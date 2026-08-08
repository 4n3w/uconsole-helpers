#!/bin/bash
# whisper-server for the uConsole, over the LAN.
#
#   ./serve.sh          start (or restart) it
#   ./serve.sh stop     stop it
#   ./serve.sh status    is it up?
#
# The uConsole reads the address from ~/.config/uconsole/voice.conf and falls
# back to its own local model whenever this is unreachable, so stopping this
# degrades dictation rather than breaking it.
#
# --host 0.0.0.0 is required: bound to 127.0.0.1 it would serve only this Mac.
# That also means it is reachable by anything on the LAN, which is the intent
# but worth knowing.
set -u
DIR="$HOME/workspace/uconsole-voice"
MODEL="$DIR/whisper.cpp/models/ggml-large-v3-turbo.bin"
PORT=8178
LOG="$DIR/server.log"

case "${1:-start}" in
  stop)   pkill -f whisper-server && echo "stopped" || echo "not running" ;;
  status) pgrep -f whisper-server >/dev/null \
            && echo "running on port $PORT" || echo "not running" ;;
  start)
    pkill -f whisper-server 2>/dev/null; sleep 1
    cd "$DIR/whisper.cpp" || exit 1
    nohup ./build/bin/whisper-server -m "$MODEL" \
        --host 0.0.0.0 --port "$PORT" -t 16 >"$LOG" 2>&1 &
    for _ in $(seq 1 60); do
      curl -s -o /dev/null "http://127.0.0.1:$PORT/" && { echo "up on port $PORT"; exit 0; }
      sleep 1
    done
    echo "did not come up — see $LOG"; exit 1 ;;
  *) echo "usage: serve.sh [start|stop|status]"; exit 2 ;;
esac
