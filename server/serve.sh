#!/bin/bash
# The two LAN services the uConsole's voice stack talks to.
#
#   ./serve.sh                    start both
#   ./serve.sh stop               stop both
#   ./serve.sh status             what is up, and what is managing it
#   ./serve.sh whisper            just transcription
#   ./serve.sh llama              just the chat model
#
#   ./serve.sh install-agent      survive a reboot (macOS)
#   ./serve.sh uninstall-agent    go back to hand-started
#
# The uConsole reads both addresses from ~/.config/uconsole/voice.conf and falls
# back to its own local whisper when the first is unreachable — so stopping these
# degrades the device rather than breaking it.
#
# THAT FALLBACK IS ALSO WHY install-agent EXISTS. Nothing announces a server that
# did not come back after a reboot: dictation keeps working, silently at 25s
# instead of 0.36s and with noticeably worse words. An invisible, gradual
# regression that gets blamed on the microphone three weeks later is a worse
# failure than an outage, which at least tells you something happened.
#
# --host 0.0.0.0 on both is required. Bound to 127.0.0.1 they answer only this
# machine, which looks identical from here and fails from everywhere else. It
# also means anything on the LAN can reach them.
set -u
DIR="$HOME/workspace/uconsole-voice"
WHISPER_MODEL="$DIR/whisper.cpp/models/ggml-large-v3-turbo.bin"
CHAT_MODEL="$DIR/models/Qwen2.5-7B-Instruct-Q4_K_M.gguf"
WHISPER_BIN="$DIR/whisper.cpp/build/bin/whisper-server"
LLAMA_BIN="/opt/homebrew/bin/llama-server"
WHISPER_PORT=8178
LLAMA_PORT=8179

LABEL_PREFIX="local.uconsole-voice"
AGENT_DIR="$HOME/Library/LaunchAgents"

# ---------------------------------------------------------------- invocations
#
# ONE DEFINITION OF HOW TO RUN EACH SERVICE, used by the hand-started path and by
# the generated plist alike. The obvious alternative — a committed plist next to
# this script — drifts the moment a flag changes here, and drifts silently,
# because each file looks perfectly correct on its own. Generating the plist from
# these means `install-agent` is also how you apply a flag change.
#
# ARGV is an array rather than a string: paths come from $HOME and a machine
# whose user directory contains a space would otherwise split mid-path.

ARGV=()

set_argv() {
    case "$1" in
        whisper) ARGV=( "$WHISPER_BIN" -m "$WHISPER_MODEL"
                        --host 0.0.0.0 --port "$WHISPER_PORT" -t 16 ) ;;
        # -c 4096 is plenty for spoken turns and keeps first-token latency down;
        # a huge context costs prompt-processing on every request for no benefit.
        llama)   ARGV=( "$LLAMA_BIN" -m "$CHAT_MODEL"
                        --host 0.0.0.0 --port "$LLAMA_PORT" -c 4096 -ngl 999 ) ;;
        *) echo "unknown service: $1" >&2; return 2 ;;
    esac
}

svc_port()   { [ "$1" = whisper ] && echo "$WHISPER_PORT" || echo "$LLAMA_PORT"; }
svc_health() { [ "$1" = whisper ] && echo "/" || echo "/health"; }
svc_log()    { echo "$DIR/$1.log"; }
svc_wd()     { [ "$1" = whisper ] && echo "$DIR/whisper.cpp" || echo "$DIR"; }
# llama loads a 7B off disk and is slower to answer than whisper on a cold cache.
svc_wait()   { [ "$1" = whisper ] && echo 90 || echo 120; }

wait_for() {
    local svc="$1" n port
    n=$(svc_wait "$svc"); port=$(svc_port "$svc")
    for _ in $(seq 1 "$n"); do
        if curl -s -o /dev/null "http://127.0.0.1:$port$(svc_health "$svc")"; then
            echo "  $svc up on $port"; return 0
        fi
        sleep 1
    done
    echo "  $svc did not start — see $(svc_log "$svc")"
    return 1
}

# --------------------------------------------------------------------- launchd
#
# A LaunchAGENT, not a LaunchDaemon, and the difference is load-bearing. A daemon
# in /Library/LaunchDaemons starts at boot with nobody logged in, which sounds
# like exactly what is wanted — but it runs as root outside any GUI session, and
# Metal is the entire reason large-v3-turbo answers in a third of a second here.
#
# The cost is that these come up at LOGIN, not at boot. A Mac that reboots and
# sits at the login window has no servers. Enable automatic login, or stay logged
# in; there is no third option that keeps the GPU.

label()  { echo "$LABEL_PREFIX.$1"; }
plist()  { echo "$AGENT_DIR/$(label "$1").plist"; }
target() { echo "gui/$(id -u)/$(label "$1")"; }

have_agent()   { [ -f "$(plist "$1")" ]; }
agent_loaded() { launchctl print "$(target "$1")" >/dev/null 2>&1; }

xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

write_plist() {
    local svc="$1" out arg
    out="$(plist "$svc")"
    set_argv "$svc" || return 2
    mkdir -p "$AGENT_DIR"
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        echo '<plist version="1.0"><dict>'
        echo "  <key>Label</key><string>$(label "$svc")</string>"
        echo '  <key>ProgramArguments</key><array>'
        for arg in "${ARGV[@]}"; do
            echo "    <string>$(xml_escape "$arg")</string>"
        done
        echo '  </array>'
        # A job with no WorkingDirectory inherits launchd's "/", which turns any
        # relative path in a future flag into a landmine that works by hand and
        # fails only under the agent.
        echo "  <key>WorkingDirectory</key><string>$(xml_escape "$(svc_wd "$svc")")</string>"
        echo '  <key>RunAtLoad</key><true/>'
        # NOT <key>KeepAlive</key><true/>. That restarts the job after ANY exit,
        # the clean one `serve.sh stop` asks for included — so stopping the server
        # appears not to work at all, which is a genuinely maddening thing to
        # debug. SuccessfulExit=false restarts a crash and respects a clean exit.
        echo '  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>'
        # Otherwise macOS is entitled to throttle a mostly-idle background job,
        # and these are idle right up until the instant latency matters.
        echo '  <key>ProcessType</key><string>Interactive</string>'
        echo "  <key>StandardOutPath</key><string>$(xml_escape "$(svc_log "$svc")")</string>"
        echo "  <key>StandardErrorPath</key><string>$(xml_escape "$(svc_log "$svc")")</string>"
        echo '</dict></plist>'
    } >"$out"
    echo "  wrote $out"
}

install_agent() {
    local svc
    for svc in "$@"; do
        set_argv "$svc" || return 2
        if [ ! -x "${ARGV[0]}" ]; then
            echo "  $svc: ${ARGV[0]} is not executable — build it first"
            continue
        fi
        agent_loaded "$svc" && launchctl bootout "$(target "$svc")" 2>/dev/null
        write_plist "$svc" || continue
        if ! launchctl bootstrap "gui/$(id -u)" "$(plist "$svc")"; then
            echo "  $svc: bootstrap failed"; continue
        fi
        wait_for "$svc"
    done
}

uninstall_agent() {
    local svc
    for svc in "$@"; do
        agent_loaded "$svc" && launchctl bootout "$(target "$svc")" 2>/dev/null
        if [ -f "$(plist "$svc")" ]; then
            rm -f "$(plist "$svc")"
            echo "  $svc: agent removed and stopped"
        else
            echo "  $svc: no agent installed"
        fi
    done
}

# ----------------------------------------------------------------- start/stop
#
# ONE CONTROL SURFACE. With an agent installed, nohup/pkill and launchctl are two
# managers fighting over one process: pkill it and launchd puts it straight back,
# so `stop` looks broken. Every verb therefore asks whether an agent exists first
# and drives launchd whenever one does.

start_svc() {
    local svc="$1"
    set_argv "$svc" || return 2
    if have_agent "$svc"; then
        if agent_loaded "$svc"; then
            launchctl kickstart -k "$(target "$svc")" || return 1
        else
            launchctl bootstrap "gui/$(id -u)" "$(plist "$svc")" || return 1
        fi
        wait_for "$svc"
        return
    fi
    pkill -f "$(basename "${ARGV[0]}")" 2>/dev/null; sleep 1
    ( cd "$(svc_wd "$svc")" || exit 1
      nohup "${ARGV[@]}" >"$(svc_log "$svc")" 2>&1 & )
    wait_for "$svc"
}

stop_svc() {
    local svc="$1"
    set_argv "$svc" || return 2
    if have_agent "$svc"; then
        agent_loaded "$svc" && launchctl bootout "$(target "$svc")" 2>/dev/null
        echo "  $svc stopped — the agent stays installed and returns at next login"
        return
    fi
    pkill -f "$(basename "${ARGV[0]}")" 2>/dev/null
    echo "  $svc stopped"
}

status_svc() {
    local svc="$1" mgr="hand-started" up="down"
    have_agent "$svc" && mgr="launchd agent"
    if curl -s -o /dev/null --max-time 2 \
        "http://127.0.0.1:$(svc_port "$svc")$(svc_health "$svc")"; then
        up="up on $(svc_port "$svc")"
    fi
    # Which manager is in charge is half the answer: "down" means something very
    # different when launchd is supposed to be keeping it alive.
    printf '  %-9s %-14s (%s)\n' "$svc:" "$up" "$mgr"
}

cmd="${1:-start}"
[ $# -gt 0 ] && shift
[ $# -eq 0 ] && set -- whisper llama

case "$cmd" in
  start)   start_svc whisper; start_svc llama ;;
  stop)    stop_svc whisper;  stop_svc llama ;;
  status)  status_svc whisper; status_svc llama ;;
  whisper) start_svc whisper ;;
  llama)   start_svc llama ;;
  install-agent)
      [ "$(uname -s)" = Darwin ] || {
          echo "install-agent is macOS-only — elsewhere this wants a systemd unit"; exit 2; }
      install_agent "$@" ;;
  uninstall-agent)
      uninstall_agent "$@" ;;
  *) echo "usage: serve.sh [start|stop|status|whisper|llama|install-agent|uninstall-agent]"; exit 2 ;;
esac
