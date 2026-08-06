#!/usr/bin/env python3
"""Speak Claude Code's closing one-line summary aloud, via bin/say.

Registered as a `Stop` hook in ~/.claude/settings.json, so it runs each time
Claude finishes a response.

WHY A MARKER LINE AND NOT THE WHOLE RESPONSE

Speaking the entire response was the obvious design and is unusable. Piper runs
at roughly real time, so a 300-word answer is two minutes of talking, and the
content is worse than the length: file paths, command flags, tables and fenced
code are all miserable heard aloud. Stripping markdown afterwards does not fix
that, because the text was still written to be read.

So the convention is inverted. Claude ends a response with a single line opening
with the marker below, written specifically to be HEARD, and this speaks only
that. The instruction lives in CLAUDE.md; if it is ever dropped, this hook simply
stays quiet, which is the correct failure.

WHY THE LAST NON-EMPTY LINE, SPECIFICALLY

Requiring the marker to be the final line, rather than searching anywhere in the
response, keeps the hook from firing on a marker that merely appears in prose or
inside a code fence — such as the documentation of this very file.

WALKING THE TRANSCRIPT

The hook receives JSON on stdin carrying `transcript_path`, a JSONL of the
session. Two things there are easy to get wrong:

  * The final `assistant` entry is usually a `tool_use`, not text. Reading "the
    last message" naively yields nothing at all most of the time; in the session
    that built this file, it did exactly that. Text blocks have to be gathered
    across the whole final turn.

  * Tool RESULTS are recorded as `type: "user"` entries. Walking back until the
    first "user" row therefore stops at a tool result rather than at the human's
    prompt, truncating the turn. Real prompts are distinguished by not carrying
    `tool_result` content blocks.

Everything here fails silently and exits 0. A hook that errors, hangs or blocks
would damage the session it is decorating; there is no summary worth that.
"""

import datetime
import json
import os
import re
import subprocess
import sys
import time

MARKER = "\N{SPEAKER WITH THREE SOUND WAVES}"

# Every run leaves a line here. THE EMPTY CASE IS THE POINT: it distinguishes "Claude
# Code never invoked the hook" from "the hook ran and chose silence", which is otherwise
# pure guesswork and cost real time once.
#
# That first failure is worth recording. A session opened after the hook was registered
# still did not speak, because Claude Code reads settings.json when a process SPAWNS but
# reads CLAUDE.md when a session is CLAIMED — and the session claimed a pre-warmed spare
# that had started before the hook existed. So it had the new instruction and the old
# settings, wrote a perfectly good summary line, and had nothing to speak it. `/hooks`
# in the affected session reloads config and fixes it.
LOG = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "say", "speak-summary.log"
)


def log(msg):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        if os.path.exists(LOG) and os.path.getsize(LOG) > 65536:
            with open(LOG) as fh:
                tail = fh.readlines()[-100:]
            with open(LOG, "w") as fh:
                fh.writelines(tail)
        stamp = datetime.datetime.now().strftime("%F %T")
        with open(LOG, "a") as fh:
            fh.write("%s %s\n" % (stamp, msg))
    except Exception:
        pass

# Long enough for a couple of sentences, short enough that a runaway line cannot
# hold the speaker for minutes. $mod+Shift+p stops it early regardless.
MAX_CHARS = 400

# How long to wait for Claude Code to flush the final message. Generous, because the
# hook is registered async: true and so cannot delay the session no matter how long it
# waits. A response that genuinely has no marker simply burns this in the background.
DEADLINE_S = 8.0
POLL_S = 0.2


def say_path():
    """bin/say, resolved through this file's real location, not the symlink."""
    here = os.path.dirname(os.path.realpath(__file__))
    return os.path.join(os.path.dirname(here), "bin", "say")


def final_turn_text(rows):
    """Concatenated assistant prose since the human's last prompt."""
    chunks = []
    for row in reversed(rows):
        kind = row.get("type")
        if kind == "user":
            content = row.get("message", {}).get("content")
            if isinstance(content, list) and any(
                isinstance(b, dict) and b.get("type") == "tool_result"
                for b in content
            ):
                continue  # a tool result, not the human — keep walking back
            break
        if kind != "assistant":
            continue
        for block in row.get("message", {}).get("content") or []:
            if isinstance(block, dict) and block.get("type") == "text":
                chunks.append(block.get("text", ""))
    chunks.reverse()
    return "\n".join(chunks)


def summary_of(text):
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    if not lines or not lines[-1].startswith(MARKER):
        return None
    spoken = lines[-1][len(MARKER):].strip()
    # Markdown emphasis and backticks are silent on the page and noisy aloud.
    spoken = re.sub(r"[*_`]+", "", spoken).strip()
    return spoken[:MAX_CHARS] or None


def read_rows(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return [json.loads(ln) for ln in fh if ln.strip()]
    except Exception:
        return None


def wait_for_summary(path, deadline_s=DEADLINE_S, interval=POLL_S):
    """Poll the transcript until the closing marker line appears, or time out.

    THE STOP HOOK CAN FIRE BEFORE THE FINAL MESSAGE IS ON DISK. This is the whole
    reason the function exists, and it is not theoretical: the log recorded "no
    marker line" at 17:11:21 for a turn whose transcript entry, timestamped that
    same second, ends with a perfectly good marker. Reading once loses that race
    intermittently — which is far more confusing than failing outright, because
    it works often enough to look configured correctly.

    Re-parsing only when mtime moves keeps this cheap; a long session transcript
    is thousands of JSON lines and polling it twenty times would not be.
    """
    end = time.time() + deadline_s
    last_mtime = None
    while True:
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            mtime = None
        if mtime != last_mtime:
            last_mtime = mtime
            rows = read_rows(path)
            if rows is not None:
                spoken = summary_of(final_turn_text(rows))
                if spoken:
                    return spoken
        if time.time() >= end:
            return None
        time.sleep(interval)


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        log("fired: unreadable payload on stdin")
        return 0

    path = payload.get("transcript_path")
    if not path or not os.path.isfile(path):
        log("fired: no usable transcript_path (%r)" % path)
        return 0

    started = time.time()
    spoken = wait_for_summary(path)
    if not spoken:
        log("fired: no marker line after %.1fs — silent" % (time.time() - started))
        return 0

    say = say_path()
    if not os.access(say, os.X_OK):
        log("fired: bin/say missing or not executable at %s" % say)
        return 0

    # Detached, so the hook returns immediately and never holds up the session.
    # bin/say stops any previous utterance itself, so responses do not overlap.
    try:
        subprocess.Popen(
            [say, spoken],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        log("speaking: %s" % spoken)
    except Exception as exc:
        log("fired: could not launch say: %s" % exc)
    return 0


if __name__ == "__main__":
    sys.exit(main())
