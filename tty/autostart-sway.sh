#!/usr/bin/env bash
#
# Start sway automatically on the tty1 autologin.
#
# Boot lands in a logged-in shell on tty1 via
# /etc/systemd/system/getty@tty1.service.d/autologin.conf. This turns that into a
# sway session, so the box boots to the compositor without a display manager.
# (greetd/ly/emptty are not packaged for bullseye, and sddm would pull in a Qt
# stack for a greeter that would almost never be looked at.)
#
# Source this on console login. On THIS box that means ~/.profile, NOT
# ~/.bash_profile: no ~/.bash_profile exists here, and creating one would shadow
# ~/.profile, which Debian uses to set PATH and to source ~/.bashrc.
#
#     [ -r ~/uconsole/tty/autostart-sway.sh ] && . ~/uconsole/tty/autostart-sway.sh
#
# Put it AFTER the rose-pine-tty.sh hook: the palette should be applied to the VT
# first, because that is what you are looking at if sway ever exits.
#
# POSIX `[` rather than bash `[[` on purpose — ~/.profile is not guaranteed to be
# read by bash.
#
# Safe to source unconditionally — every path below returns without doing anything
# unless all of the guards pass.

# ---------------------------------------------------------------------------
# Guard 1: tty1 only.
#
# This is a SAFETY property, not a cosmetic one. tty2-tty6 stay plain gettys, so
# if sway ever fails to start there is always another VT to log in on. Do not
# "helpfully" generalise this to all VTs — that removes the escape hatch.
# ---------------------------------------------------------------------------
[ "$(tty 2>/dev/null)" = /dev/tty1 ] || return 0 2>/dev/null || exit 0

# ---------------------------------------------------------------------------
# Guard 2: manual override.
#
# Recovery valve. If a bad sway config lands and tty1 becomes unpleasant, this
# boots straight to a shell without having to edit a tracked file.
#
#     touch ~/.nosway     # boot to a plain tty1 shell
#     rm ~/.nosway        # back to autostarting
# ---------------------------------------------------------------------------
[ -e "$HOME/.nosway" ] && return 0 2>/dev/null

# ---------------------------------------------------------------------------
# Guard 3: never a second compositor.
#
# The real case this catches: sway is already up on another VT, and tty1 then
# logs in (or is logged into again). pgrep is system-wide, so it sees a sway
# started from anywhere.
#
# WAYLAND_DISPLAY covers the other direction — a login shell started INSIDE sway,
# e.g. `bash -l` in foot, which would otherwise recurse.
# ---------------------------------------------------------------------------
[ -n "${WAYLAND_DISPLAY:-}" ] && return 0 2>/dev/null
[ -n "${SSH_CONNECTION:-}" ] && return 0 2>/dev/null
pgrep -x sway >/dev/null 2>&1 && return 0 2>/dev/null

# ---------------------------------------------------------------------------
# Guard 4: don't wedge login if sway is missing.
# ---------------------------------------------------------------------------
command -v sway >/dev/null 2>&1 || return 0 2>/dev/null

# ---------------------------------------------------------------------------
# Launch.
#
# Plain `sway`, deliberately NOT `exec sway`.
#
# With exec, sway exiting would terminate the login shell, agetty would respawn,
# autologin would fire, this would run again, and sway would start again — an
# instant crash loop on tty1 if the config is ever broken. Without exec, a sway
# exit just drops back to the tty1 shell. The cost is one lingering parent shell,
# which is cheap insurance on a box whose only interface this is.
# ---------------------------------------------------------------------------
sway
