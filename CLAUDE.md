# uconsole

> **Read this before acting on anything below — especially if you are an agent.**
>
> This file is auto-loaded as project instructions by Claude Code, which means a tool
> will treat it as ground truth rather than as prose to be read sceptically. That is
> correct on the machine it was written for and wrong everywhere else.
>
> It describes **one specific ClockworkPi uConsole**, as configured through 2026-08-05:
> a CM4 on Debian bullseye with the ClockworkPi kernel, a particular panel, a particular
> USB mic, and a particular set of hand-installed binaries. Statements here are written
> as flat assertions — "the panel is 720x1280", "sudo is passwordless", "card 3 is the
> mic", "there is no swaylock" — because on that machine they were **verified**, not
> assumed.
>
> On any other board, OS image, or ClockworkPi revision, several of them will simply be
> false. **Verify against the hardware in front of you before relying on any specific
> device name, node number, mode, model or measurement.** The reasoning generalises; the
> values do not.

Device-specific config for the ClockworkPi uConsole. Deliberately **not** part of
[`dotfiles`](../dotfiles) — that repo is portable config symlinked
onto every unix box, and everything here would be wrong or useless anywhere else.

## `claude/` — machine-wide Claude Code instructions

`claude/CLAUDE.md` is symlinked to `~/.claude/CLAUDE.md`, so Claude Code loads it in
**every** session on this box, from any directory. It carries the instruction to end each
response with a spoken 🔊 summary line.

**It is deliberately not in this file.** *This* CLAUDE.md loads only while working in this
repo, but the `Stop` hook that speaks the line is registered in `~/.claude/settings.json`
and therefore fires everywhere. A project-scoped instruction would have meant the hook
running in `elixir-hologram` and every other project, finding no marker, and staying
silent — looking broken while behaving exactly as designed.

Keep `claude/CLAUDE.md` short: it is paid for in context on every session on this machine.
Anything that only matters while editing the uConsole config belongs here instead.

## Rebuilding from a fresh image — `./install.sh`

```bash
./install.sh --check      # report what is missing, change nothing
./install.sh              # install everything
./install.sh links blobs  # sections: deps links claude blobs system
```

This file says *"a fresh image loses it"* about six separate things, and for a long
while nothing put any of them back: the knowledge was written down and none of it was
executable. On a device whose entire OS is one SD card, that is the wrong place for a
runbook to stop. `install.sh` covers the apt packages, every symlink, the `~/.profile`
hooks, the `~/.claude` wiring, the hand-installed blobs (Nerd Font, piper + voice,
whisper.cpp + models) and the root-owned system changes.

**`--check` is the load-bearing mode.** It changes nothing, so it is safe on a working
box, and it is what keeps this documentation honest: prose drifts silently, but a script
that has drifted fails visibly the next time anyone runs it. On a fully-installed device
it reports 35 items ok and exits 0.

Four safety properties, each verified against a throwaway `HOME` rather than assumed:

- **Idempotent** — a second run makes zero changes.
- **Never clobbers.** A real file where a symlink belongs is reported and left alone, and
  the run exits 1. `dotfiles`' `create_symlink` does the same thing *silently*, which
  this file already records as the cause of "a config that stubbornly won't update".
- **Merges `settings.json`, never replaces it** — it also holds `theme` and `tui`, which
  are personal preference rather than device config.
- **Backups are written once.** The `.bak-pre-*` files are the pristine pre-modification
  originals; overwriting one on a re-run would quietly turn every revert command in this
  file into a no-op.

`/boot/cmdline.txt` is appended to with `sed '1s/$/ .../'`, never `echo >>` — a second
line in that file silently breaks boot, and the script asserts the line count afterwards.

**What it deliberately will not do:** no `apt upgrade` or bookworm (the ClockworkPi
kernel and panel overlays are the one thing here that cannot be reinstalled from a repo);
no fp16 `ggml-base.en` or `ggml-small.en-q5_1`, both of which are conclusions this file
already rejected; and no `~/.gitconfig`, whose email is a per-account choice. Nor can it
recreate `/etc/wpa_supplicant/wpa_supplicant.conf` — that holds real passphrases and is
deliberately absent from this repo, so `wifi add` is still a manual step.

## The split

| | `dotfiles` | `uconsole` (here) |
|---|---|---|
| scope | every machine | this one board |
| sway | keybindings, colors, layout | `output`/`input`, rotation, scale, gaps |
| terminal | `foot.ini` base theme | panel-specific font size |
| owns | `~/.config/*` | `/boot/config.txt`, `/boot/cmdline.txt`, `/etc/udev/hwdb.d/`, kernel overlays, TTY setup |

The seam is sway's `include`. The base config in `dotfiles` ends with:

```
include ~/.config/sway/config.d/*.conf
```

so this repo drops `sway/10-uconsole.conf` into `~/.config/sway/config.d/` and its
settings win, without the device layer ever touching the shared config.

## Hardware

All confirmed on-device 2026-07-27 unless noted.

| | |
|---|---|
| Board | Raspberry Pi Compute Module 4 Rev 1.1 |
| OS | **Debian 11 bullseye** — old, and it constrains everything below |
| Kernel | `5.10.17-v8+` (ClockworkPi build, Jun 2023) |
| Host | `uconsole`, single non-root user with passwordless sudo |
| SSH | `ssh uconsole` from the Mac, key auth, `enabled` so it survives reboots |
| Net | `eth1`, a **USB** ethernet adapter. Onboard `eth0` is `NO-CARRIER` — see Gotchas. `wlan0` exists but is off at boot; see `bin/wifi` |
| GPU | `vc4-kms-v3d-pi4`, `cma-384` — **full KMS**, so wlroots works |
| DRM | `card1`, `renderD128`; connector `DSI-1` connected |
| Panel | native mode **`720x1280`** — portrait, because it is mounted rotated |
| Overlays | `devterm-panel-uc`, `devterm-pmu`, `devterm-misc`, `audremap` |
| Trackball | `7855:36:ClockworkPI_uConsole_Mouse`, `/dev/input/event6` — matched by `type:pointer`, confirmed. Three buttons: left, right, and **left+right together = a real `BTN_MIDDLE`** |
| Keyboard | `1EAF:0024` (LeafLabs Maple MCU), `/dev/input/event4` |
| Consumer Control | `7855:36:ClockworkPI_uConsole_Consumer_Control`, `/dev/input/event3` — a **separate HID device** from the keyboard. The Fn+`<`/`>` brightness keys emit `KEY_BRIGHTNESSDOWN`/`UP` from here, not from the keyboard node |
| Power key | `axp20x-pek` — the PMU's Power Enable Key, a real input device. Easy to miss: its name contains no "power", so grepping `/proc/bus/input/devices` for that word finds nothing |
| Currently | default target `multi-user.target`, sway launched by hand. `lightdm` is still `enabled` but never pulled in — harmless, since only `graphical.target` wants it |

### Bullseye is the binding constraint

The ClockworkPi apt repo pins this to bullseye, and that dictates package versions:

| package | situation |
|---|---|
| `sway` | **1.5-7** (Aug 2020). Works, but predates a lot of syntax. |
| `foot` | 1.6.4 |
| `swayidle` | 1.6 |
| `wofi` | 1.2.4 — the launcher, since `fuzzel`/`bemenu`/`wmenu` are all absent |
| `swaylock` | **no installation candidate at all.** No lock screen on this box. |
| `fonts-jetbrains-mono` | 2.225 — plain family only, **no Nerd Font build packaged**. The Nerd Font is installed by hand instead; see System changes |

No backports repo is enabled. Upgrading to bookworm would fix all of this but risks the
custom kernel and panel overlays, so it is not on the table casually.

## Target setup

Terminal-first. **No display manager**, no desktop environment. tty1 autologins and
starts sway; tty2–tty6 stay plain themed VTs.

```
boot → multi-user.target
        ├── tty1  autologin (agetty) → ~/.profile → sway
        │          └── foot + the i3 keybindings, ported
        └── tty2-tty6  plain themed VTs (rose-pine palette, Terminus font)
```

No greeter, because there is no good one here: `greetd`, `ly` and `emptty` are all
absent from bullseye, and `sddm` would drag a Qt stack onto this board for a login
screen that would essentially never be looked at. An autologin getty plus a `~/.profile`
hook is lighter than any of them and was already half-built.

**Sway used to be launched by hand**, on the reasoning that it saved boot time and
battery. That was reversed on 2026-08-02: in practice the GUI was wanted on essentially
every boot, so the manual step was pure friction. The escape hatch survives as
`~/.nosway` and as tty2–tty6.

## Status

**KMS is confirmed working** — the one thing that could have sunk this. `vc4-kms-v3d-pi4`
with a live `renderD128` means wlroots has everything it needs. Sway is a config
exercise here, not a kernel one.

Installed on-device: `sway foot swayidle wofi fonts-jetbrains-mono wl-clipboard wtype`.

`wtype` is the one that matters for anything new: it is how a script gets text *into* a
window under Wayland, since `xdotool type` has no meaning here. `ydotool` is also
packaged but wants a root daemon and a `uinput` device, which `wtype` avoids entirely by
using the compositor's virtual-keyboard protocol.

**Sway is confirmed running on the actual panel** (2026-07-31). `swaybg` and `swayidle`
come up with it, and `transform 90` is verified working end to end: the panel's native
mode is `720x1280` and `swaymsg -t get_outputs` reports `DSI-1` as a `1280x720` logical
rect. This repo has been edited from a Claude Code session running in `foot` under sway
on the device itself.

### The `~/uconsole` symlink

**`~/uconsole` is a symlink to this checkout** — resolve it before assuming a path.

Seven things reference the `~/uconsole` path, and one of them lives in a *different* repo:

| reference | points at |
|---|---|
| `~/.config/sway/config.d/10-uconsole.conf` | `~/uconsole/sway/10-uconsole.conf` |
| `~/.profile` (login hook) | `~/uconsole/tty/rose-pine-tty.sh` |
| `~/.local/bin/wifi` | `~/uconsole/bin/wifi` |
| `~/.local/bin/ptt` | `~/uconsole/bin/ptt` |
| `~/.claude/CLAUDE.md` | `~/uconsole/claude/CLAUDE.md` |
| `~/.claude/settings.json` (`Stop` hook) | `~/uconsole/hooks/speak-summary.py` |
| **`dotfiles/.config/starship.toml`** | `~/uconsole/bin/battery-remaining` (as both `command` and `when`) |

Note the last two are **Claude Code** config, not shell or Wayland config, and neither is
managed by `dotfiles`. `~/.claude/CLAUDE.md` is a symlink so it survives as tracked
content, but `~/.claude/settings.json` is a **real file** holding the hook registration —
a fresh image keeps `hooks/speak-summary.py` and loses the thing that runs it.

That last one is why `~/uconsole` is the canonical path and the checkout hides behind a
symlink, rather than the references being rewritten to point at the checkout directly:
`starship.toml` is portable config that syncs to every machine, so the device layer must
not require an edit there. Moving this checkout is therefore fine — **repointing the
`~/uconsole` symlink is mandatory when you do**, and it is the only thing that needs to
change.

History: until 2026-07-31 `~/uconsole` was a real directory and *not* a git repo, while
the actual checkout sat unreferenced at `~/workspace/uconsole`. The two had diverged in
both directions — `bin/` existed only in the live tree, `udev/` and `CLAUDE.md` only in
the checkout. Consolidated by copying `bin/` into the checkout and replacing the live
tree with the symlink. The old tree was kept at `~/uconsole.bak-pre-consolidate` until it
had been confirmed redundant, and has since been deleted.

### How `~/.config` is wired

Everything is a symlink now; there are no unmanaged real files left:

| on device | → |
|---|---|
| `~/.config/sway/config` | `~/dotfiles/.config/sway/config` |
| `~/.config/foot/foot.ini` | `~/dotfiles/.config/foot/foot.ini` |
| `~/.config/starship.toml` | `~/dotfiles/.config/starship.toml` |
| `~/.config/sway/config.d/10-uconsole.conf` | `~/uconsole/sway/10-uconsole.conf` |

Note `~/.config/sway/` and `~/.config/foot/` are **real directories** containing
symlinked files, not symlinked directories. For sway that is load-bearing: `config.d/`
has to stay local so this repo's override can be dropped into it. `install.sh` links
both at file level via the same single-file path `starship.toml` already used.

**History, because this was wrong for a while.** Until 2026-08-02, `~/.config/sway/config`
and `~/.config/foot/foot.ini` were **real files tracked by nothing at all**. This file
claimed both had been "written in the `dotfiles` repo", but `dotfiles` had *zero* commits
ever touching `.config/sway*` or `.config/foot*`, and its `install.sh` listed only
`.config/i3` and `.config/i3status`. The 6.3K sway base existed solely on this SD card.
Fixed in `dotfiles` — see "Written in the `dotfiles` repo" below.

A related trap survived that whole period and is worth remembering: `create_symlink`
never overwrites, so with a real file in place `install.sh` prints a skip and the symlink
is **silently** not created. Delete the real file first. Directory-level linking has a
sharper version of the same problem — `~/.config/foot` could not be linked as a directory
because a stray `foot.ini.bak-pre-cursor` was sitting in it, and the failure looked
exactly like success.

### Verified on the panel

Nothing outstanding. `tty/rose-pine-tty.sh` was **confirmed painting on a real VT**
(2026-07-31) — the palette swatches render in rose-pine, so the `~/.profile` hook, the
`/dev/tty[0-9]*` guard and the `\e]P` escapes all work as intended.

### `bin/` — on `PATH` via `~/.local/bin`

| script | what it does |
|---|---|
| `bin/battery-remaining` | prints e.g. `13% +11h31m`. Backs starship's `[custom.battery]`; exits 1 with no battery so the module self-hides elsewhere |
| `bin/wifi` | `on`/`off`/`status`/`restart`/`edit`/`add` for `wlan0`, plus an fzf menu with no args |
| `bin/backlight` | `up`/`down`/`get`/`set N`. Bound to the keyboard's brightness keys in `10-uconsole.conf`. No sudo — the sysfs node is world-writable |
| `bin/say` | speaks text aloud via piper. Reads stdin, so anything can pipe into it. `-l` lists voices, `-v` picks one, `-w` renders to WAV, `--stop` interrupts. Bound to `$mod+p` (speak selection) and `$mod+Shift+p` (stop) |
| `bin/listen` | records and transcribes with whisper.cpp. Records until Enter, or `-d N` seconds. `-f FILE` transcribes an existing wav. `-c` copies to clipboard |
| `bin/audio` | `status`/`out`/`in`/`vol`/`mute`/`mic`/`test`/`level` for PulseAudio and ALSA, plus an fzf menu with no args |
| `bin/ptt` | dictation. `toggle [--enter]`/`start`/`stop`/`cancel`/`status`. Bound in `10-uconsole.conf` to `$mod+/` (toggle) and `$mod+\` (toggle, then Return); types the transcript into the focused window |

`wifi` and `ptt` are symlinked into `~/.local/bin`. `battery-remaining` is **not** on
`PATH` — starship invokes it by absolute path, so nothing noticed. Symlink it too if you
want it by hand.

Both are 64-bit-arithmetic and `sudo`-dependent respectively; see each script's header.

### `tty/` — hooked from `~/.profile`

Both are **sourced**, not executed, and both no-op unless their guards pass. `~/.profile`
carries one line for each. Order matters: the palette first, sway second — the palette is
what you are looking at if sway ever exits.

| script | what it does |
|---|---|
| `tty/rose-pine-tty.sh` | repaints the VT's 16-colour palette. Guards on `/dev/tty[0-9]*` |
| `tty/autostart-sway.sh` | starts sway on the tty1 autologin |

`autostart-sway.sh` refuses to run unless *all* of these hold: the tty is exactly
`/dev/tty1`, `~/.nosway` does not exist, `WAYLAND_DISPLAY` and `SSH_CONNECTION` are
unset, no `sway` process already exists, and `sway` is on `PATH`.

Two of those are load-bearing and should not be "simplified":

- **tty1 only.** tty2–tty6 stay plain gettys so there is always a way in if sway breaks.
  Generalising this to all VTs removes the escape hatch.
- **plain `sway`, never `exec sway`.** With `exec`, a sway that dies takes the login
  shell with it, agetty respawns, autologin fires, and sway starts again — an instant
  crash loop on tty1. Without `exec` a sway exit just drops back to the tty1 shell.

`touch ~/.nosway` boots to a plain tty1 shell without editing anything tracked; `rm` it
to restore. Rollback of the whole feature is deleting the one line from `~/.profile`,
which leaves the repo file inert.

### Corrected during setup

Three things were wrong in the first draft, all caught before launch:

- `mode 1280x720` → **`720x1280`**. `mode` takes the physical, pre-transform mode, and
  the panel is natively portrait.
- `output * power off` → **`output * dpms off`**. `power` postdates sway 1.5; the
  binary contains only `dpms`, so the newer spelling fails silently at runtime.
- `smart_gaps inverse_outer` → **`smart_gaps on`**. `inverse_outer` is i3-gaps syntax
  that sway 1.5 does not implement.

**`sway --validate` catches none of these.** It validates directive *names* only —
`totally_bogus_directive` is rejected, but a bad *value* like `mode 1280x720` or
`smart_gaps inverse_outer` sails through and fails at runtime. Check values against
`man 5 sway` / `man 5 sway-output` and the panel's actual mode list in
`/sys/class/drm/card1-DSI-1/modes`.

Also note: `sway --validate` over SSH exits 1 with "Unable to create backend" before it
ever parses the config. Prefix with a headless backend to validate remotely:

```bash
WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 sway --validate
```

### Written in the `dotfiles` repo

All of this landed in `dotfiles` on 2026-08-02 (`9f69bd2`, `49b1dae`). Before that date
this section described work that had **never actually been done** — see the history note
under "How `~/.config` is wired".

- `.config/sway/config` — portable base, ported from `config-rose-pine`.
- `.config/foot/foot.ini` — rose-pine theme for foot.
- `.config/sway/config.d/README.md` — documents the override seam.
- `.config/starship.toml` — `[custom.battery]`, which calls this repo's
  `bin/battery-remaining`.
- `install.sh` — `.config/sway/config` and `.config/foot/foot.ini` added to
  `LINUX_CONFIG_DIRS`, both as **files**, not directories.

`dotfiles` also carries uncommitted nvim work (`lazy-lock.json`,
`lua/plugins/treesitter.lua`) belonging to the treesitter migration in the Backlog.
That was deliberately left alone.

## Next up

The original 8-item plan is **done**. sway runs and its keybindings work, rotation is
fixed in both the compositor and the console, the console fills the panel in Terminus,
the trackball rules are confirmed, right Alt is Super, foot renders in a real monospace,
the display manager is out of the boot path, and the TTY palette is hooked into
`~/.profile`. Remaining:

Nothing outstanding.

The obvious follow-on for push-to-talk was **latency**, and it has largely been dealt
with: `-ac` sizing took a five-second utterance from ~13 s to ~5 s of whisper time. Nothing in `bin/ptt` can fix that; it is
inference-bound, with no `fphp`/`asimdhp`/`dotprod` on the A72 and no caching trick
available. The levers are a smaller model (`tiny.en` gets it to ~15 s, at the accuracy
cost documented below) or different hardware.

**Chunked transcription was investigated on 2026-08-05 and rejected** — see "Two things
that sound like fixes and are not". The premise was that cost scales with audio length;
it does not, being ~90% fixed, so chunking multiplies the expensive part instead of
hiding it. The benchmark that killed it found `-ac` instead, which is now in `bin/listen`
and cuts a 5-second utterance by 2.5× for a one-line change.

**Done:** committing the repo (`ca54ed6`, pushed to its GitHub remote),
consolidating the divergent `~/uconsole` tree into it, confirming the VT palette,
folding `~/WIFI.md` in as `docs/wifi.md`, autostarting sway from the tty1 autologin,
settling the foot-override question, and binding the keyboard's brightness keys.

**The foot override question is closed.** It was posed as "where do device-specific foot
settings live", but the premise was wrong: `foot.ini` had not diverged from a `dotfiles`
original, because no original existed. There turned out to be nothing device-specific in
it either — `style=underline` is a *version* constraint (foot < 1.9), not a panel one,
and `size=12` was never actually overridden. So the whole file went to `dotfiles`
unchanged, and this repo carries no foot config at all. If a genuinely panel-specific
foot setting ever appears, foot 1.6.4 has no `include=`, so the only routes are editing
the portable file or launching foot with `--config=PATH`.

**Explicitly not doing:** fixing the starship pills on the VT. They render as U+FFFD
diamonds because the console font carries no private-use glyphs and cannot — 512 glyphs
is the Linux console's hard cap and `Uni2-Terminus28x14` is already exactly at it, so the
only fix is a second, VT-specific `STARSHIP_CONFIG` that would drift from the `dotfiles`
one. The VT is readable as-is and rarely used. Left alone on purpose; do not "fix" it.

### Git identity — global, and hand-written

`~/.gitconfig` did not exist on this box until 2026-07-31, so committing on-device failed
with "Author identity unknown"; the earlier commits were authored elsewhere and cloned
down. Now set **globally**:

```
user.name  = <your name>
user.email = <you>@users.noreply.github.com    # the GitHub noreply, deliberately
```

It is a real file, written by hand — **`dotfiles` does not manage it**. So it is
unmanaged in the same way the Nerd Font is: a fresh image loses it, and nothing will
recreate it. Placing a `.gitconfig` in `dotfiles` would fix that permanently, but it has
not been done, partly because the email is a per-account choice rather than a per-machine
one.

### Beware: this repo is pushed to from more than one machine

`b90f06e` added `bin/` from another machine while an on-device session was adding the
same two files, producing an add/add conflict with **identical blobs** and differing
modes only. Fetch before committing here. And note the modes: `b90f06e` committed both
scripts `100644`, which put a non-executable `wifi` on `PATH` for any fresh clone —
fixed in `0822a10`. If you add anything to `bin/` from a machine with a different umask,
check `git ls-files -s bin/` before pushing.

## System changes made on-device

Changes living outside `~/.config`, and therefore outside the sway `include` seam.
Each is reversible; the revert is listed with it.

Note the boot files are at **`/boot/config.txt`** and **`/boot/cmdline.txt`**. This is
bullseye — the `/boot/firmware/` layout is bookworm and later, and does not exist here.

### Console rotation — `fbcon=rotate:1`

The panel is mounted rotated, so the framebuffer console renders 90° CCW. Sway's
`transform 90` fixes only Wayland; the TTY is drawn by the kernel and never sees it.
These are two independent settings that happen to need the same correction.

The kernel has `CONFIG_FRAMEBUFFER_CONSOLE_ROTATION`, so rotation is testable at runtime
with no reboot per guess:

```bash
echo 1 | sudo tee /sys/class/graphics/fbcon/rotate_all   # 0 none, 1 90°CW, 2 180, 3 270
```

`rotate_all` is write-only (`--w-------`) — `cat`ing it returns "Permission denied", which
is expected, not a failure. Read the current value from `rotate` instead.

Made permanent by appending `fbcon=rotate:1` to `/boot/cmdline.txt`. **That file must stay
a single line** — append to it, never add a newline.

```bash
sudo cp /boot/cmdline.txt.bak-pre-fbcon /boot/cmdline.txt    # revert
```

### Right Alt → Super — `udev/90-uconsole-keyboard.hwdb`

The board has no dedicated Super key. Rationale and the captured scancodes are in the
rule file's own header comment.

Deployed as a **copy** into `/etc/udev/hwdb.d/`, not a symlink, because it is a root-owned
system path — so editing the repo copy does nothing until it is re-deployed:

```bash
sudo cp udev/90-uconsole-keyboard.hwdb /etc/udev/hwdb.d/
sudo systemd-hwdb update && sudo udevadm trigger --subsystem-match=input
```

```bash
sudo rm /etc/udev/hwdb.d/90-uconsole-keyboard.hwdb           # revert
sudo systemd-hwdb update && sudo udevadm trigger --subsystem-match=input
```

Reverting is safe. `Fn+Alt` independently emits `KEY_RIGHTMETA` — the keyboard firmware
resolves the Fn layer itself, so the kernel sees a real Super keypress, not a chord.
`$mod = Mod4` therefore keeps working with the rule removed; the remap only saves a
three-key press.

### JetBrainsMono Nerd Font — hand-installed, not from apt

`foot.ini` in `dotfiles` requests `JetBrainsMono Nerd Font`. Bullseye packages only the
plain family, so fontconfig fell back to **proportional DejaVu Sans** and terminal
columns did not line up.

Fixed by installing the real font rather than working around the request, so the
portable config stays correct here as it is everywhere else:

```bash
# from ryanoasis/nerd-fonts releases (v3.4.0 at time of install)
unzip -j JetBrainsMono.zip "*NerdFont-*.ttf" "*NerdFontMono-*.ttf" \
  -d ~/.local/share/fonts/JetBrainsMonoNerd/
fc-cache -f ~/.local/share/fonts
```

**Unmanaged by dpkg** — apt will never update or remove it, and a fresh image loses it.
The wildcards also pull the `NL` (no-ligature) variants; they register as the separate
family `JetBrainsMonoNL Nerd Font` and are harmless.

```bash
rm -rf ~/.local/share/fonts/JetBrainsMonoNerd && fc-cache -f    # revert
```

Verify with `fc-match "JetBrainsMono Nerd Font"` — it must name a `NerdFont` file, and
`fc-match -v` must report `spacing: 100`. Anything else means it is falling back again.

### Console geometry — `disable_fw_kms_setup=1`

The framebuffer console drew into a 720x720 square on a 720x1280 panel, leaving roughly
a third of the screen black. The cause was not fbcon rotation: the **firmware injects its
own `video=` parameters ahead of `cmdline.txt`**, and it was forcing
`video=HDMI-A-1:1280x720M@60` even with both HDMI ports reading `disconnected`. DRM then
sized fbdev to span a 1280x720 and a 720x1280 connector at once — a 1280x1280 virtual
buffer with the visible area clamped to 720x720.

`disable_fw_kms_setup=1` in `/boot/config.txt` stops the firmware injecting `video=` at
all, so DRM sizes to the DSI panel alone:

```
before   geometry 720  720 1280 1280 16     grid 25x51
after    geometry 720 1280  720 1280 16     grid 25x91
```

This could **not** have been fixed by appending `video=HDMI-A-1:d` to `cmdline.txt`. The
kernel's `fb_get_options()` returns the *first* match for a connector name, and the
firmware's entry is already ahead of anything `cmdline.txt` contributes.

`fbset -g 720 1280 1280 1280 16` corrects it at runtime but does not persist, and even
`setupcon` resets it — so fbset is not a viable persistence route.

```bash
sudo cp /boot/config.txt.bak-pre-fwkms /boot/config.txt    # revert
```

### Console font — Terminus 14x28

`FONTFACE` and `FONTSIZE` in `/etc/default/console-setup` were both empty, so the console
used the kernel's built-in 8x16 font. Now `Terminus` / `14x28`, a 25x91 grid that fills
the panel. Debian names these files height-first (`Uni2-Terminus28x14.psf.gz`) while
`FONTSIZE` is width-first — the same font, written both ways round.

`setupcon` warns *"The keyboard is in some unknown mode"* and skips the keymap half of its
job. That is deliberately **not** forced with `-f`: only the font was wanted, and this
box's keymap comes from a udev hwdb rule that setupcon knows nothing about.

```bash
sudo cp /etc/default/console-setup.bak-pre-terminus /etc/default/console-setup   # revert
sudo setupcon
```

### piper TTS — hand-installed, not from apt

`bin/say` speaks through [piper](https://github.com/rhasspy/piper), neural TTS that runs
comfortably on the CM4. bullseye packages only `espeak-ng`/`festival`/`flite`, all of
which sound like 1998, so piper is installed by hand:

```bash
# release 2023.11.14-2, piper_linux_aarch64.tar.gz
tar xzf piper_linux_aarch64.tar.gz -C ~/.local/share/piper --strip-components=1
# voices from huggingface.co/rhasspy/piper-voices, .onnx AND .onnx.json both required
```

Layout is `~/.local/share/piper/` for the binary and `~/.local/share/piper/voices/` for
models. **Unmanaged by dpkg** — apt will never update or remove it and a fresh image
loses it, exactly like the Nerd Font.

Two things that made this work on bullseye, and are worth not re-deriving:

- **The binary links against glibc 2.31.** This was the real risk: modern prebuilt
  binaries typically need 2.35+, and bullseye has 2.31. The 2023 release predates that
  and runs fine. A newer piper release may well not.
- **It bundles its own `libespeak-ng` and `libonnxruntime`**, so nothing is needed from
  apt and there is no system-wide dependency to conflict with. `bin/say` sets
  `LD_LIBRARY_PATH` to the install dir because the binary does not rpath them.

Voices are ~61 MB each and need their `.onnx.json` alongside the `.onnx` — the model
cannot load without it. Synthesis of a short sentence takes ~2.3 s, so roughly real time.

```bash
rm -rf ~/.local/share/piper    # revert; bin/say then exits with a clear error
```

### whisper.cpp — hand-built, not from apt

`bin/listen` transcribes through [whisper.cpp](https://github.com/ggerganov/whisper.cpp),
built from source into `~/.local/share/whisper.cpp`. Not packaged for bullseye, so
**unmanaged by dpkg** — same category as piper and the Nerd Font.

```bash
sudo apt-get install -y cmake          # bullseye has 3.18.4; whisper needs cmake now
git clone --depth 1 https://github.com/ggerganov/whisper.cpp ~/.local/share/whisper.cpp
cd ~/.local/share/whisper.cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j4 --config Release
```

The binary is `build/bin/whisper-cli`. It was called `main` for years and both names are
produced by the current tree — `bin/listen` prefers `whisper-cli` and falls back.

Models go in `models/` as `ggml-*.bin`, from
`huggingface.co/ggerganov/whisper.cpp`. **`bin/listen` defaults to the smallest
installed model**, which is deliberate; see the timings.

#### It is slower than real time on this CPU

The CM4's Cortex-A72 has `asimd` (NEON) but **no `fphp`/`asimdhp` and no `dotprod`**, so
whisper runs the baseline SIMD path.

> **The table below is ~1.8x PESSIMISTIC and is kept only for its ranking.** Every figure
> was measured from an idle box, and the `ondemand` governor spans **600 MHz to 1500 MHz**
> — so the first invocation of a burst runs at 40% clock and ramps up during the
> measurement. Re-measured warm, `tiny.en` on 5 s takes **7.5 s**, not the ~13.5 s this
> implies. See "Benchmarking anything on this board" in Gotchas. The *ranking* survives,
> since all four were biased alike.

| model | size | time (cold, pessimistic) | vs real time |
|---|---|---|---|
| `ggml-tiny.en` | 75 MB | 13.5 s | 2.9× |
| **`ggml-base.en-q5_1`** | 57 MB | **24.6 s** | 5.3× |
| `ggml-base.en` (fp16) | 142 MB | 34.3 s | 7.5× |
| `ggml-small.en-q5_1` | 182 MB | 72.4 s | 15.7× |

Warm figures, CPU pinned at 1500 MHz, best of several interleaved runs:

| audio | `tiny.en` | `base.en-q5_1` |
|---|---|---|
| 1 s | 6.3 s | — |
| 5 s | 7.5 s | 12.9 s |
| 10 s | 8.8 s | — |
| 30 s | 18.0 s | 26.1 s |

`tiny.en` fits **T ≈ 6.1 s + 0.28 × seconds** almost exactly up to ~10 s. Note what that
means: **the cost is ~90% fixed.** A one-second "yes" costs nearly as much as a
fifteen-second sentence.

**Quantized beats fp16 outright here.** `base.en-q5_1` runs 28% faster than fp16
`base.en` for identical output at 40% of the size, because whisper is memory-bandwidth
bound on this CPU rather than compute bound. There is no reason to keep an fp16 model.
`small` is word-perfect and unusable — 15.7× real time.

So `bin/listen` defaults to **`base.en-q5_1`**, overridable with `-m` or `$LISTEN_MODEL`.

**This reversed on 2026-08-05, and the reversal is the interesting part.** The default
was `tiny.en` on a pure latency argument: the table above was measured with a benchmark
phrase that *all four models got word-perfect*, so the extra ~11 s bought nothing
measurable. That was a sound reading of the evidence and still wrong, because the
evidence was too easy. Real dictated prose broke `tiny.en` immediately — it rendered
"a giant blob of plasma" as "a giant blob of plaid mode". It handles common words and
drops precisely the technical ones you are least willing to retype.

Two things also changed underneath: the mic became a RØDE VideoMic GO II, so SNR stopped
being the limiting factor, and `bin/ptt` turned this into a dictation tool rather than a
transcription toy. Against a ~14 s wait already being tolerated, ~25 s is cheap.

The lesson to keep: **a transcription benchmark that every model passes has not measured
accuracy at all.** Test with vocabulary you actually use.

Reach back for `tiny.en` with `-m` when latency matters more than words.

That default is named explicitly, and must stay that way. It used to pick the *smallest*
file, which is a trap: `ggml-base.en-q5_1` (57 MB) is smaller than `ggml-tiny.en` (75 MB)
while being the larger, slower, more accurate model — so adding a quantized file silently
changed the default.

#### `-ac` is the biggest speed lever here, and `bin/listen` sizes it automatically

Whisper's encoder processes a **fixed 30-second window** whatever the clip length, which
is where that ~90% fixed cost lives. `-ac N` shrinks it. On `base.en-q5_1` with 5 s of
audio, best of three interleaved runs:

| flags | time | |
|---|---|---|
| default (`-bs 5 -ac 1500`) | 12.9 s | — |
| `-ac 512` | **5.2 s** | **2.5×** |
| `-bs 1 -ac 512` | 3.7 s | 3.5× |

All three returned the same transcript. `bin/listen` computes `-ac` from the recording's
own duration — 50 frames per second of audio, doubled for headroom — and passes **no flag
at all** once that reaches 1500, so anything over ~15 s falls back to stock behaviour.
`$LISTEN_AUDIO_CTX=0` disables it; `=N` forces a value.

**Undersizing `-ac` is far worse than not using it, in both directions at once.** A 30 s
clip forced through `-ac 512` took **101.9 s against 26.1 s — four times SLOWER** — and
returned "the lazy easy- decay rocks" where the default got the sentence right. Whisper
retries low-confidence output through its temperature fallback, so too small a context
loses accuracy *and* pays for it repeatedly. This is why the size is computed rather than
hardcoded, and why the doubling is not timidity.

Beam search is deliberately left at the default of 5. `-bs 1` is a further 1.4× on top,
but beam search is a genuine accuracy safeguard and this box has already chosen accuracy
over speed once — see the `tiny.en` reversal above.

**Every figure in the tables above was measured on piper-synthesized speech**, because it
is repeatable and can be cut to exact lengths. That is a real caveat: synthetic speech is
cleaner than a human in a room, so it flatters both the timings and the accuracy.

**Confirmed on real speech 2026-08-06.** A 5.46 s dictated utterance through the RØDE
transcribed in ~6 s at `ac=551`, word-perfect. That is roughly real time, against the
~13 s the same utterance cost the day before — so the speedup survives contact with an
actual voice, which is the only test that counted.

#### Two things that sound like fixes and are not

**Chunked transcription does not work.** Transcribing 5-second chunks while you keep
talking is the obvious way to hide the latency, and it fails on arithmetic: cost is ~90%
fixed, so a chunk costs `6.1 + 0.28D` seconds and only keeps up if that is under `D` —
i.e. **chunks must exceed ~8.5 s**. Anything shorter falls permanently behind. At a
viable 10 s chunk the gain over one-shot is a couple of seconds, in exchange for a
streaming pipeline, a ring buffer and word-splitting at chunk boundaries. Do not build it.

**`whisper-server` is not worth a daemon.** It keeps the model resident, and the obvious
assumption is that model loading is the fixed cost. It is not: the server was serving
**0.59 s** after launch, so loading is under 10% of it. The rest is the encoder. A
resident server saves ~1.5 s per utterance and costs a background process holding 75 MB;
`-ac` beats it several times over for a one-line change.

### Speech out — `$mod+p`, and the Stop hook

The other direction from push-to-talk. Two independent routes, added 2026-08-05.

**`$mod+p` speaks the primary selection**, `$mod+Shift+p` shuts it up. Select text, press
the key. Two traps, both already documented in Gotchas and both easy to hit here:
`wl-paste -p` is the **primary selection**, a different buffer from the clipboard; and
inside a mouse-tracking client — Claude Code, vim, btop — a plain drag never reaches it
at all, so you must **hold shift while dragging**.

**Diagnosing "it did not speak."** The hook logs every run to
`$XDG_RUNTIME_DIR/say/speak-summary.log`, and **an empty log is the diagnosis**: it means
Claude Code never invoked the hook, as opposed to the hook running and choosing silence.
Without that distinction it is pure guesswork.

**The Stop hook can fire before the final message is on disk.** This produced the
second, nastier failure: it worked *sometimes*, which is far more confusing than never
working, because it looks correctly configured. The log said `no marker line` at
17:11:21 while the transcript entry timestamped that same second ended with a perfectly
good marker. The hook now polls the transcript until the marker appears, re-parsing only
when mtime moves, giving up after 8 s. It is registered `async: true`, so that wait can
never delay the session.

The first failure has happened once too, and it is not obvious. A session opened *after* the
hook was registered still did not speak. It had written a perfectly good 🔊 line, and the
hook worked when run by hand against that same transcript. The cause: **Claude Code reads
`settings.json` when a process spawns, but reads `CLAUDE.md` when a session is claimed**,
and the session had claimed a **pre-warmed spare** process started before the hook
existed. So it got the new instruction and the old settings. Typing `/hooks` in the
affected session reloads config and fixes it.

**The Stop hook speaks Claude's closing 🔊 line** — see the instruction section at the
top of this file. `hooks/speak-summary.py` is registered in `~/.claude/settings.json`,
which is **not** managed by this repo or by `dotfiles`, so a fresh image keeps the script
and loses the registration.

Speaking the *whole* response was the obvious design and is unusable: piper runs at
roughly real time, so a 300-word answer is two minutes of talking, and the content —
paths, flags, tables, fenced code — is miserable heard aloud. Stripping markdown
afterwards does not help, because the text was still written to be read. Hence a line
composed for speech instead.

Two things that bite when parsing the transcript, both found the hard way:

- **The last `assistant` entry is usually a `tool_use`, not text.** Reading "the last
  message" yields nothing most of the time. Text has to be gathered across the whole turn.
- **Tool *results* are recorded as `type: "user"` entries.** Walking back to the first
  "user" row therefore stops at a tool result, not at the human. Real prompts are the ones
  without `tool_result` content blocks.

`bin/say --stop` exists because there was previously no way to interrupt. It kills a
process **group** — playback runs under `setsid` — because killing `aplay` alone leaves
piper blocked on a broken pipe until its next write, which for a long utterance is not
"immediately". It never pkills by name: `aplay` is also how `bin/ptt` plays its beeps,
the same reasoning that stops `bin/wifi` pkilling `wpa_supplicant`.

### Dictation — `bin/ptt`, on `$mod+/` and `$mod+\`

Tap `$mod+/`, speak, tap again; `wtype` types the transcript into the focused window.
Added 2026-08-05 and **confirmed working by dictating with it**; both keys re-confirmed
on 2026-08-06 after the switch to toggles, including `$mod+\` submitting its own line.

**Two bindings, both toggles, differing only in a trailing Return.** `$mod+/` types the
transcript and leaves it for you to edit; `$mod+\` types it and presses Return, so a
dictated prompt submits itself. One flag, `toggle --enter`, and the same machinery.

**Hold-to-talk was the original design and is gone (2026-08-06).** `$mod+\` used sway's
`--release` binding to record only while held. It worked, and went essentially unused:
holding a key through a whole paragraph is tiring, and dictation is mostly paragraphs.
`start` and `stop` survive as primitives, so a hold binding is two lines away, but
nothing ships bound to them.

The submit flag is recorded **at start**, in the state file, not read from whichever key
stops the recording. The two taps are separate processes, so something has to carry it,
and "the key I pressed to begin decides" is the predictable rule — stopping a `$mod+\`
recording with `$mod+/` still submits.

`--no-repeat` is load-bearing on both bindings. Without it, holding the key autorepeats
`toggle` and flips recording on and off several times, landing on whichever state the
last repeat hit — a coin flip, and a confusing one, since every beep fires.

The Return is sent as a **separate keystroke**, `wtype -k Return`, not as a `\n` inside
the typed text. wtype types a literal newline as a character; only the keypress is what a
prompt reads as submit. The trailing space is also suppressed when submitting, since it
would just be a stray space before Enter.

A **forgotten toggle is benign**, which is worth knowing rather than assuming. `arecord`
hits its own `-d` ceiling at `MAX_SECONDS`, exits, and *nothing is transcribed and
nothing is typed* — the next tap starts a fresh recording rather than transcribing the
abandoned one. `reap_stale()` deletes the abandoned wav, which would otherwise be several
MB sitting in `$XDG_RUNTIME_DIR` until the hourly prune.

Note `ptt status` reports `idle` while a transcription is still running. That is correct
— it means "not recording" — but the state file is deleted before the slow work starts,
so there is deliberately no way to ask "is it still thinking?".

**`$mod` here is the right Alt key** — the one immediately right of the spacebar, made
Super by the hwdb rule above. Worth spelling out rather than writing `$mod`, because the
first attempt to use this failed twice over: `Fn` was pressed instead of right Alt, and
then `Fn+/` instead of `\`. The binding was fine both times. If push-to-talk appears
dead, check which key is being held before touching any config.

Three findings are worth not re-deriving.

**`Fn+\` is impossible, and that was the first choice.** Capturing the raw evdev stream
shows `Fn+\` and plain `\` emitting the **identical** scancode `70031` (HID usage
`0x07/0x31`) on `event4`, while the Consumer Control device `event3` stays silent
throughout. The firmware simply does not map Fn on that key. hwdb cannot help, because
hwdb rewrites *scancodes* and there is only one scancode to rewrite.

This makes `Fn+\` unlike the two Fn chords that *do* work here — `Fn+Alt` emits a real
`KEY_RIGHTMETA`, `Fn+<`/`>` emit real brightness keys. **The firmware resolves some
chords and passes others straight through, and which is which can only be found by
capturing the device**, never by looking at the keycaps. The only route to a literal
`Fn+\` is reflashing the LeafLabs Maple keyboard MCU (`1EAF:0024`).

```bash
sudo evtest /dev/input/event4        # keyboard
sudo evtest /dev/input/event3        # consumer control — check BOTH
```

**The press and the release are two unrelated processes.** sway fires a separate
detached `exec` for each, sharing no pipe, parent or stdin, so `ptt start` leaves a
state file in `$XDG_RUNTIME_DIR/ptt/` and `ptt stop` picks it up. `stop` deletes that
file *before* transcribing — 15 s of whisper would otherwise block the next utterance —
and each recording gets a unique wav path so a new press cannot clobber a wav still
being transcribed.

Both `--release` and `--no-repeat` **do** exist in sway 1.5; confirmed against the
binary, and a bogus flag in the same position is rejected, so the check is meaningful.
`--no-repeat` is load-bearing: without it, holding the key autorepeats `ptt start`
dozens of times a second.

`ptt start` treats an already-live recording as an orphan, kills it and starts fresh.
This mattered more under the old hold binding, where sway could drop a `--release` if
focus changed mid-hold, but it is still the right behaviour: ignoring the press instead
would leave the key dead until `arecord` hits its own `-d` ceiling.

**Whisper's non-speech tags must be filtered before typing.** This is not theoretical:
the very first test recorded three seconds of a quiet room and whisper returned
`(dramatic music)`; the next returned `[BLANK_AUDIO]`. Printing that from `listen` is
useful feedback, but *typing* it into the focused window is not, so `ptt` strips
`(...)`, `[...]` and `*...*` and treats "nothing with a letter or digit left" as silence.
Tags are stripped rather than the whole transcript rejected, so a real sentence with one
cough in it still comes through.

**That filter does not, and cannot, catch hallucination.** Whisper does not only emit
honest `[BLANK_AUDIO]` tags on silence — it sometimes emits confident, ordinary-looking
text. 1.8 seconds of room noise came back from `base.en-q5_1` as `$10,000.`, which was
duly typed into the focused window. Nothing about that string is distinguishable from
speech, so no output-side filter can reject it.

So the check has to be on the **input** side, and `ptt` now makes one before
transcribing. Measured on this board:

| | rms |
|---|---|
| quiet room, mic working | **−43.1 dBFS** |
| very quiet speech | −36.0 dBFS |
| dead mic, dithered | −87.3 dBFS |
| dead mic, true digital silence | −99.0 dBFS |

The default threshold of **−70 dBFS** sits in the ~40 dB gulf between those groups: 27 dB
below a working room, 17 dB above the loudest dead-mic case. Override with
`$PTT_SILENCE_DBFS`.

**It is a dead-mic alarm, not a speech detector, and must not be made into one.**
Separating "quiet room" (−43) from "someone talking" (~−25) is a far narrower margin, and
a threshold set slightly wrong would silently eat real dictation — a much worse failure
than the one being prevented. The wide-margin version is safe precisely because it only
answers "is the capture device producing anything at all?".

What it buys is real, because the mic can die in three documented ways that all look
healthy in every mixer reading: the physical MUTE BUTTON, PulseAudio not auto-switching
when a USB device appears or vanishes, and the mic being knocked out. Previously each
meant dictating a paragraph and getting one hallucinated sentence typed in with no clue
why. Now it is the error beep.

It measures **rms, never peak** — the quiet room above read −5.5 dBFS *peak* off a single
transient against −43.1 rms, which is the same lesson `bin/audio level` exists to teach.
It **fails open**: if `python3` is missing or the wav is not S16_LE it says nothing and
the recording is transcribed as usual, because a broken helper must never be able to
block dictation. Cost is ~210 ms, flat — long recordings are decimated 16:1, so a 120 s
clip costs the same as a 2 s one, against ~636 s of whisper for the same audio.

`wtype` (0.3-1, from bullseye) drives `zwp_virtual_keyboard_manager_v1`, which sway 1.5
does implement. Its one documented limitation is **XWayland** — X caps keycode-keysym
pairs, so typing into an XWayland client fails. Native clients including `foot` are fine.
`ptt` falls back to `wl-copy` if `wtype` fails or is missing.

Handy consequence for testing: `wtype` can **synthesise the chord itself**, so the
binding can be verified without touching the keyboard —

```bash
wtype -M logo -P backslash -s 2500 -p backslash -m logo   # hold $mod+\ for 2.5s
```

Feedback is audible only: an 880 Hz "go" tone before recording starts, 660 Hz on
release, 220 Hz when nothing usable was heard. The tones are generated by `python3`'s
`wave` module into `~/.cache/ptt/` on first use, because `sox` is not usefully packaged
here. **The start tone deliberately plays to completion *before* `arecord` starts** —
letting it bleed into the front of the recording is precisely the input that provokes
the `[beeping]` tags above. It costs ~265 ms, which is fine, since the beep *is* the
"you may speak now" signal. Remember the physical MUTE BUTTON silences all of this
invisibly.

### Audio — output only, and that is a hardware fact

| | |
|---|---|
| Playback | `card 0: bcm2835 Headphones`, via the `audremap` overlay. Works |
| Capture | **none on-board.** A USB sound card supplies one — see below |
| Mixer | one control, `Headphone` |
| Server | **PulseAudio is running** and holds `/dev/snd/controlC0`, so `aplay` routes through it |

**There is a physical MUTE BUTTON on the uConsole**, and it is invisible to software.
It silences the internal speaker while every mixer and `pactl` reading still looks
perfectly healthy. If `bin/audio status` is clean and there is still no sound, it is
either that button or the output is routed at the speaker while you are wearing a
headset. This cost real time once; `bin/audio` exists partly to make it obvious.

Note also that **PulseAudio does not switch to a USB card automatically** here — after
plugging in the sound card the default sink was still `Built-in Audio Analog Stereo`, so
everything kept playing out of the internal speaker. `audio out` moves it, and also
migrates already-playing streams, which `set-default-sink` alone does not do.

**Raspberry Pi boards have no analog audio input, ever.** The bcm2835 audio is
output-only and the 3.5mm jack cannot take a microphone. This is not something an overlay
or config unlocks. Voice *input* therefore requires a **USB microphone/headset** (there
are free ports on the Genesys hub) or a **Bluetooth headset** — `hci0` is `UP RUNNING`
with BlueZ 5.55, though mic-over-Bluetooth means HSP/HFP, which is fiddly and 8 kHz.

**A USB mic supplies capture.** Since 2026-08-05 that is a **RØDE VideoMic GO II**,
which enumerates as `card 3` (`alsa_input.usb-R__DE_R__DE_VideoMic_GO_II_...`,
`mono-fallback`) and needed no configuration — PulseAudio picked it as the default
source on its own. It offers playback as well as capture, but the default sink is
deliberately left on the built-in `bcm2835`.

It replaced a **Logitech G432 dongle with an Apple TRRS headset**, and the improvement
is a positioning one rather than an electrical one: the headset's inline mic hangs
around chest height, roughly 30 cm from your mouth, and level falls off with the square
of distance. A shotgun mic aimed at your face wins that argument before any mixer
setting is touched. The G432 notes below are kept because they are the reason to
distrust gain controls in general.

**Leave a capture device's `Auto Gain Control` OFF** — measured on the G432, but the
lesson generalises. Turning it on looks like an improvement and is not one: it lifted
the measured speech peak from −25.0 to −18.5 dBFS, but it lifted the *noise floor* by
the same ~10 dB (−27.7 → −18.4 dBFS peak). Signal-to-noise did not move, and whisper
transcribed the louder recording as `[bell ringing]`. A loud recording of mostly noise
is still mostly noise.

```bash
amixer -c 3 sset 'Auto Gain Control' off
```

**Measure SNR, never absolute level.** This is the trap the above walked into. `bin/audio
level` records the room silent, then records speech, and reports the difference. Aim for
≥20 dB; below ~12 dB whisper returns non-speech tags like `[bell ringing]` or
`[beeping]` rather than words — which is whisper being honest, not broken.

Mic *position* dominates every mixer setting: an Apple headset's inline mic sits near
your chest, roughly 30 cm from your mouth, and level falls off with the square of
distance. Getting it close is worth more than any gain control.

Debugging note: a silent-but-"successful" playback usually means PulseAudio, not the
player. Check that the sink reports `RUNNING` during playback rather than `SUSPENDED`:

```bash
( aplay -q file.wav & sleep 0.8; pactl list short sinks; wait )
```

### `wlan0` taken away from NetworkManager

Full detail in **`docs/wifi.md`** — changing networks, `wpa_passphrase` hashing, and why
`nmcli` is not the tool here. Summary:

Wifi is **off at boot** and stays down until `wifi on`. `wlan0` is driven by
`wpa_supplicant` against `/etc/wpa_supplicant/wpa_supplicant.conf`, which is the single
source of truth for networks and passphrases. `bin/wifi` only starts and stops daemons —
it never reads, copies or passes the passphrase, so it is safe to keep in a public repo.

```
/etc/NetworkManager/conf.d/10-uconsole-wlan0-unmanaged.conf
    [keyfile]
    unmanaged-devices=interface-name:wlan0
```

NetworkManager runs its own global `wpa_supplicant` (`-u -s -O /run/wpa_supplicant`).
`bin/wifi` therefore matches **only its own** daemon via a pidfile, never a `pkill`
pattern, which would take NetworkManager's down by accident. The pidfile lives in `/run`
root-owned, so `kill -0` returns EPERM for a normal user — the script tests `/proc/$pid`
instead. Do not "simplify" either of these.

```bash
sudo rm /etc/NetworkManager/conf.d/10-uconsole-wlan0-unmanaged.conf   # revert
sudo systemctl reload NetworkManager
```

## Gotchas

- **`class` vs `app_id`.** Under sway, `for_window [class=...]` matches only XWayland
  clients. Native Wayland windows need `app_id`. The base config carries both rules;
  anything new needs the same treatment.
- **No root window.** `xsetroot` does nothing under Wayland — backgrounds are set with
  `output * bg`.
- **Sway does not blank on its own.** `xset s off` has no equivalent because idling is
  entirely swayidle's job. The device layer runs one; the portable base does not.
- **The firmware injects `video=` ahead of `cmdline.txt`, and the first match wins.**
  Anything appended to `cmdline.txt` for a connector the firmware already named is dead
  syntax that fails silently. `disable_fw_kms_setup=1` in `config.txt` is the lever.
  Always diff `/proc/cmdline` against `/boot/cmdline.txt` — they are not the same.
- **foot 1.6.4 has no `beam` cursor.** Only `block` and `underline`; `beam` came later.
  The portable `foot.ini` uses `beam`, so the copy here says `underline`. Same species as
  the sway 1.5 problems above — check the installed binary, not current docs:
  `strings $(command -v foot) | grep -xE 'block|beam|underline'`. Unlike sway, foot 1.6.4
  has **no `include=`**, so there is no override seam for device-specific foot settings.
- **A missing font falls back to a *proportional* one.** `foot.ini` requests
  `JetBrainsMono Nerd Font`; bullseye packages only plain `JetBrains Mono`. Fontconfig
  does not helpfully pick another monospace — it resolves to **DejaVu Sans**, and
  terminal columns stop aligning. The symptom reads like a panel or antialiasing fault,
  which it is not. `fc-match "JetBrainsMono Nerd Font"` gives the real answer; never
  assume the requested family is the one that loaded.
- **There is no sleep on this board, at all.** Not "unproven" — *absent*.
  `/sys/power/state` is **empty**, and `/sys/power/mem_sleep` and `/sys/power/disk` do
  not exist, so this ClockworkPi kernel is built without `CONFIG_SUSPEND` and without
  `CONFIG_HIBERNATION`. There is not even `freeze`/s2idle. `systemctl suspend` cannot
  work; logind does not expose `CanSuspend` at all. Do not spend time wiring a sleep
  keybind — the only levers are the backlight and poweroff.

  The backlight is the only real lever, and it is a big one. **Measured on-device
  2026-08-02** from `axp20x-battery/current_now`, at the `/sys/class/backlight/backlight@0`
  levels (0–9):

  | brightness | draw | vs max |
  |---|---|---|
  | 9 (max) | 1168 mA | — |
  | 7 | 1043 mA | −125 mA |
  | 5 | 848 mA | −320 mA |
  | 3 | 705 mA | −463 mA |
  | 1 | 630 mA | −538 mA |
  | 0 | 627 mA | −541 mA |

  So the backlight is **~46% of total draw at maximum**. Two non-obvious results:
  level `0` is *not* off, merely minimum (627 vs 630 mA); and `output * dpms off`
  measured **599 mA**, i.e. below level 0, because it sets `bl_power=4`
  (`FB_BLANK_POWERDOWN`) rather than just dimming.

  **`output * dpms off` therefore does genuinely cut the backlight** — this was an open
  question, and the answer is yes. `bl_power` goes 0 → 4 and `actual_brightness` → 0,
  while the requested `brightness` is preserved, which is why it restores cleanly. The
  300s swayidle rule saves ~208 mA of ~807 mA, about 26%. It earns its place.

  `brightness` and `bl_power` are both mode `rw-rw-rw-`, so a keybind needs **no sudo**.
  Note `current_now` is noisy — CPU load moves it by tens of mA, so take medians.

  The keyboard's own brightness keys are now wired to this: see `bin/backlight` and the
  Backlight section of `sway/10-uconsole.conf`. They were never broken — the firmware
  emits real `KEY_BRIGHTNESSDOWN`/`UP`, just from the **Consumer Control** device rather
  than the keyboard, and nothing was bound to them.
- **sway autostart is tty1-only on purpose.** See the `tty/` section — tty2–tty6 staying
  plain gettys is the escape hatch, and `exec sway` is deliberately avoided to prevent a
  crash loop. Neither is an oversight.
- **`~/.bash_profile` does not exist here, and must not be created.** Bash reads the
  first of `.bash_profile`, `.bash_login`, `.profile` — so adding a `.bash_profile`
  silently stops `.profile` being read, losing Debian's PATH setup and `.bashrc`
  sourcing. Login-shell hooks go in `~/.profile`, in POSIX syntax.
- **Onboard `eth0` runs through the KVM.** Switching KVM inputs drops the Pi's link, and
  `raspberrypi.local` stops resolving from the Mac — the box looks dead when it is fine.
  It is on a dedicated USB adapter (`eth1`) instead. If `ssh uconsole` hangs, check
  carrier before assuming a crash, and just ask for the current IP rather than scanning.
- **`create_symlink` in `dotfiles/install.sh` never overwrites.** If a real file sits
  where a symlink should go, it prints a skip and moves on. A config that stubbornly
  won't update is usually this.
- **`~/uconsole` is a symlink to the checkout, not the checkout.** `readlink -f` it before
  reasoning about paths, and repoint it if the checkout ever moves. It was a real,
  untracked directory until 2026-07-31, so anything written before then that says
  "`~/uconsole`" may mean the old tree — the leftover is at `~/uconsole.bak-pre-consolidate`.
- **Benchmarking anything on this board requires warming the CPU first.** The governor
  is `ondemand` spanning **600 MHz to 1500 MHz**, so the first invocation of a burst runs
  at 40% clock and ramps up *during* the measurement. This silently corrupted the whisper
  timings for months: the same 5-second clip measured 23.7 s cold and 12.4 s warm, and a
  0.5 s clip appeared to take *longer* than a 2 s one — impossible as a function of
  length, and the tell that the instrument rather than the subject was being measured.

  Burn a few seconds of CPU first, interleave variants rather than running all reps of
  one before the next, and take the **minimum** rather than the mean — noise here is
  additive, so the fastest observation is the least contaminated.

  ```bash
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq   # confirm 1500000
  vcgencmd measure_temp; vcgencmd get_throttled               # 0x0 = not thermal
  ```

  Check `get_throttled` too, so thermal throttling is not mistaken for the governor.
- **Nothing after the sway hook in `~/.profile` is set while sway is running.**
  `autostart-sway.sh` runs sway *without* `exec` — deliberately, to avoid a tty1 crash
  loop — so it **blocks** at that line until sway exits. Any `export` placed below it
  therefore never reaches sway or any of its children, including everything launched by
  a `bindsym ... exec`.

  This bit once, silently: an `export LISTEN_MODEL=tiny.en` sat below the hook and did
  nothing, but `bin/listen`'s own default was *also* `tiny.en`, so the observable
  behaviour was correct and the variable looked live. Editing it would have appeared to
  do nothing at all. Removed on 2026-08-05; `bin/listen`'s `DEFAULT_MODEL` is the single
  source of truth. Environment meant for sway's children goes **above** the hook.

  Check rather than assume — the answer is one command:

  ```bash
  tr '\0' '\n' < /proc/$(pgrep -x sway)/environ | grep VAR
  ```
- **The Y/X/B/A gamepad cluster is a joystick, and `bindsym` cannot reach it.** It is a
  *separate input device* from the keyboard — `ClockworkPI uConsole`, `event5` **and
  `js0`**, exposing `EV_ABS` axes plus `BTN_*` codes rather than any `KEY_*`. Captured
  mapping, in the physical order Y X B A:

  | key | emits |
  |---|---|
  | Y | `BTN_TOP` (291) |
  | X | `BTN_TRIGGER` (288) |
  | B | `BTN_THUMB2` (290) |
  | A | `BTN_THUMB` (289) |

  sway binds xkb keysyms from *keyboard* devices, so no `bindsym` — and no `bindcode`
  either — will ever fire on these. Nor will `wtype`, which speaks the virtual-*keyboard*
  protocol. Anything driven by these buttons has to read `/dev/input/event5` directly,
  which needs membership of the `input` group but no root, and which would work on a bare
  TTY with no compositor running at all. That last property is the real attraction if a
  gamepad binding is ever wanted.
- **An Fn chord is not necessarily a distinct key, and the keycaps do not tell you.**
  The keyboard firmware resolves *some* Fn combinations into real, distinct keycodes and
  passes others straight through as the unmodified base key. `Fn+Alt` → a genuine
  `KEY_RIGHTMETA`, `Fn+<`/`>` → genuine brightness keys on a *different* HID device, but
  `Fn+\` → plain `KEY_BACKSLASH`, scancode `70031`, indistinguishable from `\` alone.

  So an Fn combo may be **unbindable**, and no amount of sway or xkb config changes that.
  hwdb cannot rescue it either: hwdb remaps scancodes, and a chord that emits the base
  key's scancode has nothing to remap. Capture the device before designing around a
  chord — `sudo evtest /dev/input/event4` for the keyboard and `event3` for Consumer
  Control, and check **both**, since brightness proves they do not all arrive on the
  same node.
- **Middle click is left+right together, and the firmware resolves it.** There is no third
  button on the trackball. Reading the raw evdev node `/dev/input/event6` — *before*
  libinput sees anything — shows a genuine `BTN_MIDDLE` on the chord, so the kernel is
  handed a real middle button. Same pattern as `Fn+Alt` emitting a real `KEY_RIGHTMETA`;
  this keyboard/trackball firmware resolves its own chords.

  Consequence: **do not set `middle_emulation enabled`.** That is libinput synthesising a
  middle click from a device that lacks one, and this device does not lack one — enabling
  it on top of a real `BTN_MIDDLE` is at best redundant. The `input type:pointer` block
  correctly says nothing about buttons.

  Note the capability bitmask is **not** evidence here. `/proc/bus/input/devices` advertises
  all eight of `BTN_LEFT` through `BTN_TASK`, because that is the generic HID descriptor.
  Only pressing the buttons and reading the event stream tells you what physically exists.
- **A client with mouse tracking on disables foot's own text selection.** This is the
  usual cause of "copy/paste is broken". From foot's README: drag-to-select "is
  **disabled** when client has enabled *mouse tracking*", and "holding `shift` enables
  selection in mouse tracking enabled clients."

  So in Claude Code, `vim`, `btop` — anything that grabs the mouse — a drag never reaches
  the primary selection, and middle-clicking in a *different* foot window then pastes
  nothing. A plain shell prompt has no mouse tracking, which is why it behaves differently
  and makes the fault look window-specific.

  **Hold `shift` to select out of a mouse-tracking app**, and `shift`+middle-click to
  paste into one. Nothing needs configuring; the bindings were never the problem.

  Related and equally confusable: `Ctrl+Shift+C` is the **clipboard**, middle-click is the
  **primary selection**. Separate buffers. Copying with one and pasting with the other
  looks exactly like a broken paste. Both protocols are present — sway 1.5 creates
  `wlr_primary_selection_v1_device_manager` and foot binds
  `zwp_primary_selection_device_manager_v1` — so cross-window primary is not the problem
  either.
- **`dotfiles` reaches into this repo.** `starship.toml`'s `[custom.battery]` calls
  `~/uconsole/bin/battery-remaining` by absolute path, as both `command` and `when`. The
  dependency is deliberate and safe — the script exits 1 with no battery, so the module
  hides on machines where this repo is absent — but it means the portable repo breaks
  quietly if `bin/battery-remaining` is renamed. Grep `dotfiles` before touching `bin/`.

## Backlog

- ~~**Battery status in the TTY.**~~ **Done** — it became a starship prompt segment.
  `bin/battery-remaining` computes the estimate the axp20x PMU will not report, and
  `[custom.battery]` in `dotfiles/.config/starship.toml` renders it.
- **nvim-treesitter migration to the `main` API.** Tracked in the `dotfiles` CLAUDE.md,
  since the config lives there. The `master` pin fixing it is still uncommitted on this
  device.
