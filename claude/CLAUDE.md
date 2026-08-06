# uConsole — machine-wide instructions

Loaded in **every** Claude Code session on this box, from any directory. Kept in the
`uconsole` repo at `claude/CLAUDE.md` and symlinked to `~/.claude/CLAUDE.md`, so it is
tracked rather than a loose untracked file — the same pattern as `sway/10-uconsole.conf`.

**Keep this file short.** It costs context in every session on this machine. Anything
that only matters while working *on* the uConsole config belongs in the repo's own
`CLAUDE.md`, not here.

## End each response with a spoken summary

This machine reads your closing line out loud. A `Stop` hook,
`~/uconsole/hooks/speak-summary.py`, speaks it through piper.

> End every response with a final line beginning with 🔊 followed by **one sentence**
> saying what happened or what is needed next.

- **The last non-empty line, always.** The hook takes the final line and no other, so a
  marker anywhere else — mid-answer, or inside a code fence — is correctly ignored.
- **Write it to be HEARD, not read.** No file paths, flags, commit hashes, code or
  markdown. "Pushed the fix and the tests pass" is right; "`a1b2c3d` updates
  `src/foo.rs:42`" is not. Backticks and asterisks are stripped anyway.
- **One sentence, under ~400 characters.** Piper speaks at roughly real time, so that is
  about ten seconds aloud. Longer is truncated.
- **Omit it when nothing needs saying aloud.** No marker means silence, which is the
  right outcome for a one-line factual reply.

The summary must be *composed for speech*, not scraped from prose written for a screen.
Speaking whole responses was tried and is unusable — a 300-word answer is two minutes of
talking, and paths, flags and fenced code are miserable heard aloud.

Two notes. Sessions started over `ssh uconsole` speak too, out of the uConsole's own
speaker rather than wherever you are sitting — PulseAudio is reachable without Wayland.
And if piper is ever removed the hook fails silently, so this instruction stays harmless.
