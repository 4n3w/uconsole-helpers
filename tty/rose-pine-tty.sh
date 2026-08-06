#!/usr/bin/env bash
#
# Rose Pine palette for the Linux virtual console.
#
# The bare TTY defaults to a harsh 16-color palette that looks nothing like the
# sway/foot theme. This repaints it to match, so the machine looks consistent from
# boot through to the compositor.
#
# Source this on console login. On THIS box that means ~/.profile, NOT ~/.bash_profile:
# no ~/.bash_profile exists here, and creating one would shadow ~/.profile, which
# Debian uses to set PATH and to source ~/.bashrc.
#
#     [ -r ~/uconsole/tty/rose-pine-tty.sh ] && . ~/uconsole/tty/rose-pine-tty.sh
#
# POSIX `[` rather than bash `[[` on purpose — ~/.profile is not guaranteed to be read
# by bash.
#
# Safe to source unconditionally — it no-ops outside a real VT.

# Only meaningful on a Linux virtual console. Inside a terminal emulator (foot,
# ghostty, an SSH session) the \e]P escape either does nothing or corrupts output,
# so bail out early.
case "$(tty 2>/dev/null)" in
    /dev/tty[0-9]*) ;;
    *) return 0 2>/dev/null || exit 0 ;;
esac

# \e]P<index><rrggbb> sets one palette entry. Index is a single hex digit, and the
# color takes NO leading '#'.
_rp_set() { printf '\033]P%s%s' "$1" "$2"; }

_rp_set 0 26233a  # black         overlay
_rp_set 1 eb6f92  # red           love
_rp_set 2 31748f  # green         pine
_rp_set 3 f6c177  # yellow        gold
_rp_set 4 9ccfd8  # blue          foam
_rp_set 5 c4a7e7  # magenta       iris
_rp_set 6 ebbcba  # cyan          rose
_rp_set 7 e0def4  # white         text
_rp_set 8 6e6a86  # br black      muted
_rp_set 9 eb6f92  # br red
_rp_set a 31748f  # br green
_rp_set b f6c177  # br yellow
_rp_set c 9ccfd8  # br blue
_rp_set d c4a7e7  # br magenta
_rp_set e ebbcba  # br cyan
_rp_set f e0def4  # br white

unset -f _rp_set

# Repainting the palette leaves already-drawn cells in the old colors. Clear so the
# screen is uniformly themed.
clear
