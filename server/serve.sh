#!/bin/bash
# The two LAN services the uConsole's voice stack talks to.
#
#   ./serve.sh            start both
#   ./serve.sh stop       stop both
#   ./serve.sh status     what is up
#   ./serve.sh whisper    just transcription
#   ./serve.sh llama      just the chat model
#
# The uConsole reads both addresses from ~/.config/uconsole/voice.conf and falls
# back to its own local whisper when the first is unreachable — so stopping these
# degrades the device rather than breaking it.
#
# --host 0.0.0.0 on both is required. Bound to 127.0.0.1 they answer only this
# machine, which looks identical from here and fails from everywhere else. It
# also means anything on the LAN can reach them.
set -u
DIR="$HOME/workspace/uconsole-voice"
WHISPER_MODEL="$DIR/whisper.cpp/models/ggml-large-v3-turbo.bin"
CHAT_MODEL="$DIR/models/Qwen2.5-7B-Instruct-Q4_K_M.gguf"
WHISPER_PORT=8178
LLAMA_PORT=8179

start_whisper() {
  pkill -f whisper-server 2>/dev/null; sleep 1
  cd "$DIR/whisper.cpp" || return 1
  nohup ./build/bin/whisper-server -m "$WHISPER_MODEL" \
      --host 0.0.0.0 --port "$WHISPER_PORT" -t 16 \
      >"$DIR/whisper.log" 2>&1 &
  for _ in $(seq 1 90); do
    curl -s -o /dev/null "http://127.0.0.1:$WHISPER_PORT/" && { echo "  whisper up on $WHISPER_PORT"; return 0; }
    sleep 1
  done
  echo "  whisper did not start — see $DIR/whisper.log"; return 1
}

start_llama() {
  pkill -f "llama-server" 2>/dev/null; sleep 1
  # -c 4096 is plenty for spoken turns and keeps first-token latency down; a huge
  # context costs prompt-processing time on every request for no benefit here.
  nohup /opt/homebrew/bin/llama-server -m "$CHAT_MODEL" \
      --host 0.0.0.0 --port "$LLAMA_PORT" -c 4096 -ngl 999 \
      >"$DIR/llama.log" 2>&1 &
  for _ in $(seq 1 120); do
    curl -s -o /dev/null "http://127.0.0.1:$LLAMA_PORT/health" && { echo "  llama up on $LLAMA_PORT"; return 0; }
    sleep 1
  done
  echo "  llama did not start — see $DIR/llama.log"; return 1
}

case "${1:-start}" in
  stop)    pkill -f whisper-server; pkill -f llama-server; echo "  stopped" ;;
  status)  pgrep -f whisper-server >/dev/null && echo "  whisper: up on $WHISPER_PORT" || echo "  whisper: down"
           pgrep -f llama-server   >/dev/null && echo "  llama:   up on $LLAMA_PORT"   || echo "  llama:   down" ;;
  whisper) start_whisper ;;
  llama)   start_llama ;;
  start)   start_whisper; start_llama ;;
  *) echo "usage: serve.sh [start|stop|status|whisper|llama]"; exit 2 ;;
esac
