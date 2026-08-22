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

**It does not survive a reboot until you make it.** See below — and note that the
failure is silent, which is what makes it worth doing.

## Surviving a reboot — `./serve.sh install-agent`

```bash
./serve.sh install-agent      # both services
./serve.sh status             # says which manager is in charge
./serve.sh uninstall-agent    # back to hand-started
```

**Why bother, when the client falls back?** Because the fallback is the problem.
Nothing announces a server that did not come back: the uConsole keeps transcribing,
quietly at 25 s instead of 0.36 s and with worse words — `coral mass ejection` for
`coronal mass ejection`. A regression that is invisible, gradual, and gets blamed
on the microphone weeks later is worse than an outage, which at least tells you the
moment it happened.

**A LaunchAgent, not a LaunchDaemon, and the difference costs you something.** A
daemon in `/Library/LaunchDaemons` starts at boot with nobody logged in, which
sounds like what you want. It also runs as root outside any GUI session, and Metal
is the entire reason `large-v3-turbo` answers in a third of a second. So this is an
agent in `~/Library/LaunchAgents`, and **it comes up at login rather than at boot**
— a Mac sitting at the login window has no servers. Enable automatic login, or stay
logged in. There is no third option that keeps the GPU.

**The plists are generated, not committed.** `$HOME` differs per machine, so a
checked-in plist would be wrong everywhere but the machine it was written on. More
importantly, the flags live in `serve.sh` exactly once and the plist is built from
them — a committed copy would drift the moment a flag changed, and drift silently,
since both files would still look correct on their own. `install-agent` is
therefore also how you apply a flag change.

**`KeepAlive` is `SuccessfulExit: false`, not `true`.** Plain `true` restarts the
job after *any* exit, including the clean one `serve.sh stop` asks for — so the
server appears impossible to stop. This is a bad afternoon; the setting avoids it.

For the same reason `serve.sh` drives `launchctl` once an agent exists, rather than
`nohup` and `pkill`. Two managers for one process means `pkill` and launchd fight,
and launchd wins.

On anything that is not a Mac, `install-agent` refuses and points at systemd. The
hand-started path is unchanged and still works everywhere.

### Checking it actually worked

```bash
launchctl print gui/$(id -u)/local.uconsole-voice.whisper | head -20
```

Then reboot, log in, and ask **from the uConsole** rather than from the Mac —
`--host 0.0.0.0` is the setting that makes those two different answers:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://<mac>:8178/
```

## The client side is NOT here

The server's address lives in `~/.config/uconsole/voice.conf` on the device,
untracked, because it is a private LAN address and this repo is public. See
CLAUDE.md.
