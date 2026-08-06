# uconsole-helpers

A voice-driven, terminal-first setup for the
[ClockworkPi uConsole](https://www.clockworkpi.com/uconsole) — CM4, Debian bullseye,
sway with no display manager — plus the hardware findings that make it work.

**Everything runs on the device.** Speech recognition and synthesis are local; nothing
is sent anywhere, which also means none of it needs a network.

`$mod` below is **right Alt** — the uConsole has no Super key, so a udev rule remaps it.

## What you get

| | |
|---|---|
| **Dictation into any window** | Tap `$mod+/`, speak, tap again — the transcript types itself wherever the cursor is. `$mod+\` also presses Return, so a dictated prompt submits itself. whisper.cpp locally; a 5.5 s utterance comes back in ~6 s. |
| **A spoken notebook** | `$mod+n` dictates straight into a dated notes file — no window, no cursor, no editor, and it works on a bare TTY. `note read` speaks recent entries back at you. |
| **Text to speech** | Select anything, press `$mod+p`, hear it read in a neural voice (piper). `$mod+Shift+p` shuts it up. |
| **A voice loop with an AI agent** | Dictate a prompt, get a one-line summary spoken back. A Claude Code `Stop` hook plus a convention — the pattern transfers to any agent that can run a command when it finishes. |
| **Battery time remaining** | The axp20x PMU reports charge but not time left. `bin/battery-remaining` computes it and feeds a prompt segment. |
| **Brightness keys that work** | `Fn+<`/`>` are dead out of the box — not broken, just unbound, and they emit from a *different* HID device than you'd expect. |
| **Wifi without NetworkManager** | `wifi on/off/status/add`, driving `wpa_supplicant` directly. The script never reads, copies or passes your passphrase. |
| **Audio you can reason about** | `audio status/out/in/level` for a board whose audio is genuinely confusing — including an SNR measurement, because absolute level lies to you. |
| **A panel that isn't sideways** | Correct rotation in *both* Wayland and the framebuffer console — two independent settings that need the same fix — plus autologin straight into sway on tty1. |
| **One-command rebuild** | `./install.sh` restores the whole machine from a fresh image, with a `--check` mode that changes nothing. |

Useful even if you want none of that: the findings below are things about this board that
are **not** in the ClockworkPi documentation, each confirmed on the device rather than
inferred. Several of them cost an afternoon to discover.

## Hardware findings

**Not every `Fn` chord is a distinct key, and the keycaps don't tell you.** The keyboard
firmware resolves *some* Fn combinations into real keycodes and passes others straight
through. `Fn+Alt` emits a genuine `KEY_RIGHTMETA`; `Fn+<`/`>` emit real brightness keys —
but from a *separate* HID device (`event3`, Consumer Control), not the keyboard. Whereas
`Fn+\` emits plain `KEY_BACKSLASH`, scancode `70031`, indistinguishable from `\` alone, so
it **cannot be bound at all** — and no hwdb rule can fix it, because hwdb remaps
scancodes and there is only one scancode. Capture the device before designing around a
chord; check `event3` *and* `event4`.

**The Y/X/B/A cluster is a joystick, and `bindsym` cannot reach it.** It is a separate
device (`ClockworkPI uConsole`, `event5` **and `js0`**) emitting `EV_ABS` axes plus
`BTN_TOP` / `BTN_TRIGGER` / `BTN_THUMB2` / `BTN_THUMB` — no `KEY_*` codes. Sway binds xkb
keysyms from *keyboard* devices, so no `bindsym` or `bindcode` will ever fire on these.
Reading `/dev/input/event5` directly needs the `input` group but no root, and works with
no compositor running.

**The firmware injects `video=` ahead of `cmdline.txt`, and the first match wins.** The
console drew into a 720x720 square on a 720x1280 panel because the firmware forced
`video=HDMI-A-1:1280x720M@60` with both HDMI ports disconnected. Appending
`video=HDMI-A-1:d` to `cmdline.txt` **cannot** fix this. `disable_fw_kms_setup=1` in
`config.txt` is the only lever. Always diff `/proc/cmdline` against `/boot/cmdline.txt`.

**There is no sleep on this board — not unproven, absent.** `/sys/power/state` is empty
and `/sys/power/{mem_sleep,disk}` do not exist: the ClockworkPi kernel is built without
`CONFIG_SUSPEND` and without `CONFIG_HIBERNATION`, not even s2idle. Don't wire a suspend
keybind.

**The backlight is ~46% of total draw**, which makes it the only real power lever.
Measured from `axp20x-battery/current_now`:

| brightness | draw | | |
|---|---|---|---|
| 9 (max) | 1168 mA | 3 | 705 mA |
| 7 | 1043 mA | 1 | 630 mA |
| 5 | 848 mA | 0 | 627 mA |

Level `0` is *minimum, not off*. `output * dpms off` measures **599 mA** — below level 0 —
because it sets `bl_power=4` rather than merely dimming.

**Raspberry Pi boards have no analog audio input, ever.** The bcm2835 audio is
output-only and the 3.5mm jack cannot take a microphone. No overlay unlocks one; voice
input needs USB or Bluetooth. Also: there is a **physical mute button** on the uConsole
that is invisible to software — every mixer reads healthy while the speaker is silent.

**Middle click is left+right together, and the firmware resolves it.** Reading the raw
evdev node shows a genuine `BTN_MIDDLE` on the chord, so do **not** set
`middle_emulation enabled` — the device does not lack a middle button.

**whisper.cpp: quantized beats fp16 on this CPU.** The A72 has NEON but no `fphp`,
`asimdhp` or `dotprod`, so whisper runs the baseline SIMD path and is memory-bandwidth
bound. `base.en-q5_1` (57 MB) is both **faster and smaller** than fp16 `base.en`
(142 MB) for identical output — 24.6 s against 34.3 s on the same clip. There is no
reason to keep an fp16 model on this board. `small.en-q5_1` is word-perfect and unusable
at 15.7× real time.

**Whisper's cost here is ~90% fixed, not proportional to audio length.** Warm, at
1500 MHz, `tiny.en` fits **T ≈ 6.1 s + 0.28 × seconds** almost exactly up to ~10 s — so a
one-second "yes" costs nearly as much as a fifteen-second sentence. The fixed part is the
encoder's 30-second window, which runs whatever the clip length.

Two consequences worth having before you build anything:

*Chunked transcription does not work.* Transcribing 5 s chunks while the user keeps
talking is the obvious latency fix, and it fails on arithmetic: a chunk costs
`6.1 + 0.28D` and only keeps up if that is under `D`, so **chunks must exceed ~8.5 s**.
Shorter ones fall permanently behind.

*`-ac N` is the real lever.* Shrinking the encoder's audio context cut a 5 s clip on
`base.en-q5_1` from **12.9 s to 5.2 s (2.5×)** with an identical transcript — `-bs 1` on
top gives 3.5×. Confirmed on real dictation, not just the synthesized clips used for the
timings: a 5.5 s utterance transcribes in ~6 s, roughly real time. But **undersizing it is four times SLOWER than not using it**: a 30 s clip
forced through `-ac 512` took 101.9 s against 26.1 s and garbled the text, because
whisper retries low-confidence output through its temperature fallback. Size it from the
audio duration — 50 frames per second, with headroom — never hardcode it. `bin/listen`
does this automatically.

*`whisper-server` is not the answer either.* The obvious assumption is that model loading
dominates the fixed cost. It does not: the server was serving **0.59 s** after launch.

**Benchmarking this board requires warming the CPU first.** The governor is `ondemand`
spanning **600 MHz to 1500 MHz**, so the first invocation of a burst runs at 40% clock and
ramps up *during* the measurement. This quietly corrupted the whisper numbers here for
months — the same 5 s clip measured 23.7 s cold and 12.4 s warm. The tell was a 0.5 s clip
appearing to take *longer* than a 2 s one, which is impossible as a function of length and
means the instrument is being measured rather than the subject. Burn a few seconds of CPU
first, interleave variants instead of running all reps of one before the next, take
minima rather than means, and check `vcgencmd get_throttled` so thermal throttling is not
mistaken for the governor.

**bullseye is the binding constraint.** The ClockworkPi apt repo pins it, which means
sway **1.5** (Aug 2020), foot 1.6.4, and **no `swaylock` at all**. `sway --validate`
checks directive *names* only — a bad *value* like `mode 1280x720` or
`smart_gaps inverse_outer` sails through and fails silently at runtime.

## What's here

| | |
|---|---|
| `bin/` | `ptt` (dictation), `note` (spoken notebook), `say` (piper TTS), `listen` (whisper), `audio`, `wifi`, `backlight`, `battery-remaining` |
| `sway/` | the device layer — `output`/`input`, rotation, scale, gaps, keybindings |
| `tty/` | rose-pine VT palette, sway autostart on the tty1 autologin |
| `udev/` | right Alt → Super, since the board has no Super key |
| `hooks/` | Claude Code Stop hook that speaks a one-line summary aloud |
| `claude/` | machine-wide Claude Code instructions |
| `docs/` | wifi, in detail |

Portable config lives in a separate `dotfiles` repo
and is joined to this one through sway's `include`. This repo owns only what would be
wrong or useless on any other machine.

## Quickstart

```bash
git clone <this-repo> ~/workspace/uconsole
cd ~/workspace/uconsole
./install.sh --check      # report what's missing, change nothing
./install.sh              # apt packages, symlinks, blobs, system changes
```

`--check` is safe on a working machine. The installer is idempotent, never overwrites a
real file where a symlink belongs, merges rather than replaces `~/.claude/settings.json`,
and writes each `.bak-pre-*` backup exactly once.

## The detail

**[`CLAUDE.md`](CLAUDE.md)** is the real documentation: every system change with its
revert command, why each decision was made, and the traps that cost time. It is written
for [Claude Code](https://claude.com/claude-code), which does most of the work on this
box, but it reads fine as prose.
