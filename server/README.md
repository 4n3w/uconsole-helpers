# server/ — the LAN transcription host

`bin/listen` sends recordings here instead of transcribing locally, and falls back
to the local model whenever this is unreachable. Measured against a Mac Studio
M2 Ultra running `large-v3-turbo` on Metal, **including** the wifi round trip:

| audio | remote | local `base.en-q5_1` | |
|---|---|---|---|
| 3 s | 0.28 s | 3.45 s | 12.5× |
| 5 s | 0.36 s | 5.09 s | 14.3× |
| 12 s | 0.52 s | 14.56 s | 28.3× |

More accurate as well as faster: `large-v3-turbo` returns "coronal mass ejection"
where `base.en-q5_1` gives "coral mass ejection".

## Setting one up

Anything that runs `whisper.cpp`'s `whisper-server` will do — this happens to be
a Mac, but nothing here is Mac-specific beyond the build command.

```bash
mkdir -p ~/workspace/uconsole-voice && cd ~/workspace/uconsole-voice
git clone --depth 1 https://github.com/ggerganov/whisper.cpp
cd whisper.cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release -DWHISPER_BUILD_SERVER=ON
cmake --build build -j --config Release
curl -fL -o models/ggml-large-v3-turbo.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
```

Then copy `serve.sh` alongside and run `./serve.sh start`.

Metal is enabled by default on macOS — `libggml-metal.dylib` in `build/bin` is the
confirmation.

## Two things that are easy to get wrong

**`--host 0.0.0.0`, not the default.** Bound to `127.0.0.1` the server answers only
the machine it runs on, which looks identical from that machine and fails from
everywhere else. It also means anything on the LAN can reach it.

**It does not survive a reboot.** `serve.sh` uses `nohup`; a launchd agent or
systemd unit would fix that and is deliberately left to whoever runs it.

## The client side is NOT here

The server's address lives in `~/.config/uconsole/voice.conf` on the device,
untracked, because it is a private LAN address and this repo is public. See
CLAUDE.md.
