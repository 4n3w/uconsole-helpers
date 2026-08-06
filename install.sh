#!/usr/bin/env bash
#
# install.sh — rebuild this uConsole from a fresh Debian bullseye image.
#
#   ./install.sh --check          report what is missing; change NOTHING
#   ./install.sh                  install everything
#   ./install.sh links claude     install only the named sections
#
#   sections:  deps links claude blobs system
#
# WHY THIS EXISTS
#
# CLAUDE.md says "a fresh image loses it" about six different things, and until
# this script there was nothing that put any of them back. The knowledge was all
# written down and none of it was executable, so rebuilding meant a human reading
# 900 lines of prose and retyping commands. On a device whose entire OS lives on
# an SD card, that is the wrong place for a runbook to stop.
#
# It also keeps the docs honest. Prose drifts silently; a script that drifts
# breaks visibly the next time it is run with --check.
#
# SAFETY RULES, ALL OF THEM LEARNED THE HARD WAY
#
#   * IDEMPOTENT. Every step checks before it acts. Re-running is a no-op, which
#     is what makes --check trustworthy on a working machine.
#
#   * NEVER CLOBBER. If a real file sits where a symlink belongs, this REPORTS it
#     and moves on. dotfiles' create_symlink does the same thing silently, and
#     CLAUDE.md records that as the cause of "a config that stubbornly won't
#     update". Silence is the bug; the skip is correct.
#
#   * BACKUPS ARE WRITTEN ONCE. The .bak-pre-* files are the PRISTINE originals
#     from before this box was ever modified. Re-running must not overwrite a
#     backup with an already-modified file, or the revert commands in CLAUDE.md
#     stop being reverts.
#
#   * cmdline.txt STAYS ONE LINE. It is appended to with `sed 1s`, never with a
#     newline. A second line silently breaks boot.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
#   * No `apt upgrade`, no bookworm. The ClockworkPi kernel and panel overlays
#     are the one thing here that cannot be reinstalled from a repo.
#   * It does not install fp16 ggml-base.en or ggml-small.en-q5_1. Measured on
#     this CPU the fp16 model is strictly worse than the quantized one — slower
#     AND larger for identical output — and small.en is 15.7x real time, i.e.
#     unusable. Installing them would be reinstating a conclusion already made.
#   * It does not touch ~/.gitconfig. The email is a per-account choice, not a
#     per-machine one; see CLAUDE.md.

set -uo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CHECK=0
FAILED=0
SECTIONS=""   # space-separated; a bash array trips `set -u` when empty

### Version pins.
#
# PIPER_VER IS LOAD-BEARING, not tidiness. This release links against glibc 2.31,
# which is what bullseye has. Modern piper builds need 2.35+ and will not run
# here at all. Do not "update" it without testing on the device.
NERD_VER="v3.4.0"
PIPER_VER="2023.11.14-2"
PIPER_VOICE="en_GB-alba-medium"
PIPER_VOICE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/alba/medium"
WHISPER_MODELS="ggml-base.en-q5_1.bin ggml-tiny.en.bin"

APT_PKGS="sway foot swayidle wofi fonts-jetbrains-mono wl-clipboard wtype
          alsa-utils fzf git cmake build-essential unzip curl python3"

### Output

c_ok=$'\033[32m'; c_no=$'\033[31m'; c_wa=$'\033[33m'; c_dim=$'\033[2m'; c_z=$'\033[0m'
[ -t 1 ] || { c_ok=""; c_no=""; c_wa=""; c_dim=""; c_z=""; }

section() { printf '\n%s== %s ==%s\n' "$c_dim" "$1" "$c_z"; }
ok()      { printf '  %sok%s      %s\n'   "$c_ok" "$c_z" "$1"; }
did()     { printf '  %sdone%s    %s\n'   "$c_ok" "$c_z" "$1"; }
need()    { printf '  %smissing%s %s\n'   "$c_wa" "$c_z" "$1"; }
skip()    { printf '  %sskip%s    %s\n'   "$c_wa" "$c_z" "$1"; }
fail()    { printf '  %sFAIL%s    %s\n'   "$c_no" "$c_z" "$1"; FAILED=$((FAILED+1)); }

have()    { command -v "$1" >/dev/null 2>&1; }
wanted()  { [ -z "$SECTIONS" ] && return 0; case " $SECTIONS " in *" $1 "*) return 0 ;; esac; return 1; }

# Back up a root-owned file exactly once. See SAFETY RULES: the .bak is the
# pristine original and must never be replaced with a modified copy.
backup_once() {
    local f="$1" bak="$1.bak-pre-$2"
    [ -e "$bak" ] && return 0
    sudo cp -a "$f" "$bak" && printf '            %sbackup -> %s%s\n' "$c_dim" "$bak" "$c_z"
}

# Symlink, idempotently, refusing to destroy anything real.
link() {
    local target="$1" name="$2"
    if [ -L "$name" ]; then
        local cur; cur="$(readlink -f "$name")"
        if [ "$cur" = "$(readlink -f "$target")" ]; then ok "$name"; return 0; fi
        fail "$name is a symlink to $cur, expected $target — left alone"
        return 1
    fi
    if [ -e "$name" ]; then
        fail "$name exists as a real file — move it aside, then re-run"
        return 1
    fi
    need "$name -> $target"
    [ "$CHECK" = 1 ] && return 0
    mkdir -p "$(dirname "$name")"
    ln -s "$target" "$name" && did "$name -> $target"
}

fetch() {  # url dest
    have curl && { curl -fsSL "$1" -o "$2"; return $?; }
    have wget && { wget -qO "$2" "$1"; return $?; }
    return 1
}

### deps

do_deps() {
    section "apt packages"
    local missing=""
    for p in $APT_PKGS; do
        if dpkg -s "$p" >/dev/null 2>&1; then ok "$p"; else need "$p"; missing="$missing $p"; fi
    done
    [ -z "$missing" ] && return 0
    [ "$CHECK" = 1 ] && return 0
    sudo apt-get update -qq && sudo apt-get install -y $missing \
        && did "installed:$missing" || fail "apt install failed:$missing"
}

### links

do_links() {
    section "the ~/uconsole symlink"
    # Everything else — sway's include, ~/.profile, starship.toml in the OTHER
    # repo — refers to ~/uconsole rather than to the checkout. That indirection is
    # the whole reason the checkout can live anywhere.
    if [ "$(readlink -f "$HOME/uconsole" 2>/dev/null)" = "$REPO" ]; then
        ok "~/uconsole -> $REPO"
    else
        link "$REPO" "$HOME/uconsole"
    fi

    section "config symlinks"
    # NOTE ~/.config/sway must stay a REAL directory: config.d/ has to be local so
    # this repo's override can be dropped into it alongside the dotfiles base.
    link "$HOME/uconsole/sway/10-uconsole.conf" "$HOME/.config/sway/config.d/10-uconsole.conf"
    link "$HOME/uconsole/bin/wifi"              "$HOME/.local/bin/wifi"
    link "$HOME/uconsole/bin/ptt"               "$HOME/.local/bin/ptt"
    link "$HOME/uconsole/bin/note"              "$HOME/.local/bin/note"

    section "~/.profile hooks"
    # Order matters: the palette first, sway second — the palette is what you are
    # looking at if sway ever exits. Appending preserves that, since the palette
    # line is appended before the sway line.
    #
    # Anything sway's children must inherit has to be exported ABOVE the sway
    # hook: autostart-sway.sh runs sway WITHOUT exec and therefore blocks there.
    profile_line '[ -r ~/uconsole/tty/rose-pine-tty.sh ] && . ~/uconsole/tty/rose-pine-tty.sh' \
                 '# uConsole: repaint the VT palette to rose-pine. No-ops outside a real VT.'
    profile_line '[ -r ~/uconsole/tty/autostart-sway.sh ] && . ~/uconsole/tty/autostart-sway.sh' \
                 '# uConsole: start sway on the tty1 autologin. Must come AFTER the palette hook.'
}

profile_line() {
    local line="$1" comment="$2" p="$HOME/.profile"
    if [ -f "$p" ] && grep -Fqx "$line" "$p"; then ok "~/.profile: ${line:0:46}..."; return 0; fi
    need "~/.profile: ${line:0:46}..."
    [ "$CHECK" = 1 ] && return 0
    # ~/.bash_profile must never be created here — bash reads the FIRST of
    # .bash_profile/.bash_login/.profile, so creating one silently disables this.
    printf '\n%s\n%s\n' "$comment" "$line" >>"$p" && did "appended to ~/.profile"
}

### claude

do_claude() {
    section "Claude Code wiring"
    link "$HOME/uconsole/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"

    local s="$HOME/.claude/settings.json"
    local hook="$HOME/uconsole/hooks/speak-summary.py"
    # settings.json is a REAL file, not a symlink: it also carries personal
    # preferences (theme, tui) that are not device config. So the hook is MERGED
    # in rather than the file being replaced.
    if [ ! -f "$s" ]; then
        need "$s (creating with the Stop hook)"
        [ "$CHECK" = 1 ] && return 0
        mkdir -p "$(dirname "$s")"
        printf '{}\n' >"$s"
    fi
    # The helper prints STATUS<tab>message and bash renders it, so colour lives
    # in one place instead of leaking escape codes into a non-tty pipe.
    local out status
    out="$(python3 "$REPO/hooks/register-stop-hook.py" "$s" "$hook" "$CHECK")"
    status="${out%%	*}"
    case "$status" in
        OK)   ok   "${out#*	}" ;;
        DONE) did  "${out#*	}" ;;
        NEED) need "${out#*	}" ;;
        *)    fail "${out#*	}" ;;
    esac
    printf '            %sa running session keeps its old settings — type /hooks to reload%s\n' "$c_dim" "$c_z"
}

### blobs — hand-installed, unmanaged by dpkg

do_blobs() {
    section "JetBrainsMono Nerd Font"
    # bullseye packages only the plain family. A MISSING font does not fall back
    # to another monospace — fontconfig resolves to proportional DejaVu Sans and
    # terminal columns stop lining up, which looks like a panel fault.
    if fc-match "JetBrainsMono Nerd Font" 2>/dev/null | grep -qi nerdfont; then
        ok "JetBrainsMono Nerd Font"
    else
        need "JetBrainsMono Nerd Font"
        if [ "$CHECK" = 0 ]; then
            local tmp; tmp="$(mktemp -d)"
            if fetch "https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_VER/JetBrainsMono.zip" "$tmp/f.zip"; then
                mkdir -p "$HOME/.local/share/fonts/JetBrainsMonoNerd"
                unzip -joq "$tmp/f.zip" "*NerdFont-*.ttf" "*NerdFontMono-*.ttf" \
                    -d "$HOME/.local/share/fonts/JetBrainsMonoNerd" \
                    && fc-cache -f "$HOME/.local/share/fonts" >/dev/null && did "Nerd Font installed"
            else fail "could not download the Nerd Font"; fi
            rm -rf "$tmp"
        fi
    fi

    section "piper TTS"
    local pdir="$HOME/.local/share/piper"
    if [ -x "$pdir/piper" ]; then ok "piper binary"; else
        need "piper $PIPER_VER"
        if [ "$CHECK" = 0 ]; then
            mkdir -p "$pdir"
            local tmp; tmp="$(mktemp -d)"
            if fetch "https://github.com/rhasspy/piper/releases/download/$PIPER_VER/piper_linux_aarch64.tar.gz" "$tmp/p.tgz"; then
                tar xzf "$tmp/p.tgz" -C "$pdir" --strip-components=1 && did "piper installed"
            else fail "could not download piper"; fi
            rm -rf "$tmp"
        fi
    fi
    # The .onnx.json is NOT optional — the model cannot load without it.
    if [ -f "$pdir/voices/$PIPER_VOICE.onnx" ] && [ -f "$pdir/voices/$PIPER_VOICE.onnx.json" ]; then
        ok "voice $PIPER_VOICE"
    else
        need "voice $PIPER_VOICE (~61 MB)"
        if [ "$CHECK" = 0 ]; then
            mkdir -p "$pdir/voices"
            fetch "$PIPER_VOICE_URL/$PIPER_VOICE.onnx"      "$pdir/voices/$PIPER_VOICE.onnx" &&
            fetch "$PIPER_VOICE_URL/$PIPER_VOICE.onnx.json" "$pdir/voices/$PIPER_VOICE.onnx.json" &&
                did "voice installed" || fail "could not download the voice"
        fi
    fi

    section "whisper.cpp"
    local wdir="$HOME/.local/share/whisper.cpp"
    if [ -x "$wdir/build/bin/whisper-cli" ] || [ -x "$wdir/build/bin/main" ]; then
        ok "whisper binary"
    else
        need "whisper.cpp (clone + build, several minutes)"
        if [ "$CHECK" = 0 ]; then
            [ -d "$wdir/.git" ] || git clone --depth 1 https://github.com/ggerganov/whisper.cpp "$wdir"
            ( cd "$wdir" && cmake -B build -DCMAKE_BUILD_TYPE=Release >/dev/null \
                         && cmake --build build -j4 --config Release >/dev/null ) \
                && did "whisper.cpp built" || fail "whisper.cpp build failed"
        fi
    fi
    for m in $WHISPER_MODELS; do
        if [ -f "$wdir/models/$m" ]; then ok "model $m"; else
            need "model $m"
            if [ "$CHECK" = 0 ]; then
                mkdir -p "$wdir/models"
                fetch "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$m" "$wdir/models/$m" \
                    && did "$m" || fail "could not download $m"
            fi
        fi
    done
}

### system — root-owned, outside the sway include seam

do_system() {
    section "console rotation (/boot/cmdline.txt)"
    # The panel is mounted rotated. sway's transform 90 fixes only Wayland; the
    # TTY is drawn by the kernel and never sees it. Two independent settings that
    # happen to need the same correction.
    if grep -q 'fbcon=rotate:1' /boot/cmdline.txt; then ok "fbcon=rotate:1"; else
        need "fbcon=rotate:1"
        if [ "$CHECK" = 0 ]; then
            backup_once /boot/cmdline.txt fbcon
            # 1s appends to the END OF LINE ONE. Never `echo >>` here: a second
            # line in cmdline.txt silently breaks boot.
            sudo sed -i '1s/$/ fbcon=rotate:1/' /boot/cmdline.txt && did "fbcon=rotate:1 appended"
        fi
    fi
    [ "$(wc -l < /boot/cmdline.txt)" -le 1 ] || fail "/boot/cmdline.txt has more than one line — FIX BEFORE REBOOT"

    section "console geometry (/boot/config.txt)"
    # The firmware injects its own video= ahead of cmdline.txt and the FIRST match
    # wins, so appending video=HDMI-A-1:d to cmdline.txt cannot work. This is the
    # only lever.
    if grep -q '^disable_fw_kms_setup=1' /boot/config.txt; then ok "disable_fw_kms_setup=1"; else
        need "disable_fw_kms_setup=1"
        if [ "$CHECK" = 0 ]; then
            backup_once /boot/config.txt fwkms
            printf 'disable_fw_kms_setup=1\n' | sudo tee -a /boot/config.txt >/dev/null \
                && did "disable_fw_kms_setup=1 appended"
        fi
    fi

    section "right Alt -> Super (udev hwdb)"
    local hwdb=/etc/udev/hwdb.d/90-uconsole-keyboard.hwdb
    # Deployed as a COPY, not a symlink: it is a root-owned system path, so
    # editing the repo file does nothing until this is re-run.
    if [ -f "$hwdb" ] && cmp -s "$REPO/udev/90-uconsole-keyboard.hwdb" "$hwdb"; then
        ok "hwdb rule deployed and current"
    else
        need "hwdb rule"
        if [ "$CHECK" = 0 ]; then
            sudo install -Dm644 "$REPO/udev/90-uconsole-keyboard.hwdb" "$hwdb" \
                && sudo systemd-hwdb update \
                && sudo udevadm trigger --subsystem-match=input \
                && did "hwdb rule deployed" || fail "hwdb deploy failed"
        fi
    fi

    section "console font (Terminus 14x28)"
    # Debian names the FILE height-first (Uni2-Terminus28x14) while FONTSIZE is
    # width-first. Same font, written both ways round.
    if grep -q '^FONTFACE="Terminus"' /etc/default/console-setup \
    && grep -q '^FONTSIZE="14x28"'   /etc/default/console-setup; then
        ok "Terminus 14x28"
    else
        need "Terminus 14x28"
        if [ "$CHECK" = 0 ]; then
            backup_once /etc/default/console-setup terminus
            sudo sed -i 's/^FONTFACE=.*/FONTFACE="Terminus"/; s/^FONTSIZE=.*/FONTSIZE="14x28"/' \
                /etc/default/console-setup
            # setupcon warns "keyboard is in some unknown mode" and skips the
            # keymap half. Deliberately NOT forced with -f: only the font is
            # wanted, and this box's keymap comes from the hwdb rule above.
            sudo setupcon 2>/dev/null; did "console font set"
        fi
    fi

    section "wlan0 taken from NetworkManager"
    local nm=/etc/NetworkManager/conf.d/10-uconsole-wlan0-unmanaged.conf
    if [ -f "$nm" ]; then ok "wlan0 unmanaged"; else
        need "wlan0 unmanaged by NetworkManager"
        if [ "$CHECK" = 0 ]; then
            printf '[keyfile]\nunmanaged-devices=interface-name:wlan0\n' \
                | sudo tee "$nm" >/dev/null \
                && sudo systemctl reload NetworkManager && did "wlan0 released to wpa_supplicant"
        fi
    fi
    # wpa_supplicant.conf holds real passphrases and is deliberately NOT in this
    # repo. Nothing here can recreate it.
    [ -f /etc/wpa_supplicant/wpa_supplicant.conf ] \
        && ok "wpa_supplicant.conf present" \
        || skip "wpa_supplicant.conf absent — add networks with 'wifi add' (holds secrets, not in this repo)"
}

### main

for a in "$@"; do
    case "$a" in
        --check|-n) CHECK=1 ;;
        -h|--help)  sed -n '3,9p' "$0" | sed 's/^# \?//'; exit 0 ;;
        deps|links|claude|blobs|system) SECTIONS="$SECTIONS $a" ;;
        *) printf 'install.sh: unknown argument %s\n' "$a" >&2; exit 1 ;;
    esac
done

printf '%suconsole installer%s   repo: %s%s\n' "$c_dim" "$c_z" "$REPO" \
       "$([ "$CHECK" = 1 ] && printf '   (--check: nothing will be changed)')"

wanted deps   && do_deps
wanted links  && do_links
wanted claude && do_claude
wanted blobs  && do_blobs
wanted system && do_system

printf '\n'
if [ "$FAILED" -gt 0 ]; then
    printf '%s%d item(s) need attention.%s\n' "$c_no" "$FAILED" "$c_z"
    exit 1
fi
if [ "$CHECK" = 1 ]; then
    printf '%sCheck complete. Re-run without --check to apply.%s\n' "$c_dim" "$c_z"
else
    printf '%sDone. Boot-file changes need a reboot; hwdb and NetworkManager took effect now.%s\n' "$c_dim" "$c_z"
fi
