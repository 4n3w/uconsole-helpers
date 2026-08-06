#!/usr/bin/env python3
"""Stop a bin/ptt recording once it has been quiet for a while.

    ptt-silence-watch.py WAV STATE PTT WINDOW_S THRESH_DBFS LOG

Spawned detached by `ptt start` so you do not have to tap the key a second
time. Runs as ONE long-lived process rather than a shell loop re-invoking a
helper every poll — at 0.4 s intervals that would be dozens of interpreter
startups per utterance, which is real load on this CPU.

READS RAW BYTES, NOT THE `wave` MODULE. arecord only finalises the header's
frame count when the file is closed, so `wave` cannot read a recording that is
still being written. Samples start at a fixed 44-byte offset for the S16_LE mono
format bin/ptt records in.

WILL NOT FIRE UNTIL IT HAS HEARD SOMETHING. Otherwise toggling on and saying
nothing would stop instantly on the silence that was there from the start.
Instead that case records to arecord's own -d ceiling, exactly as before.

EXITS WHEN THE RECORDING IS NO LONGER OURS. The state file names the wav, so a
manual toggle, a cancel or an orphan recovery all shut this down within one poll
without its pid needing to be tracked anywhere.

THE THRESHOLD ERRS LOW, and that asymmetry is the design. Too high and quiet
speech reads as silence, cutting you off mid-sentence. Too low and room noise
never reads as silence, so this simply never fires and you tap twice as before.
One failure is disruptive, the other is invisible, so the default sits just
above the noisiest observed room floor rather than midway to speech.
"""

import array
import math
import os
import subprocess
import sys
import time

RATE, WIDTH, HDR = 16000, 2, 44
POLL_S = 0.4


def main():
    # --trace WAV WINDOW THRESH: print the live level instead of acting on it.
    # Exists because a threshold guessed from someone else's room is worthless,
    # and because loudspeaker playback turned out to be a poor stand-in for a
    # voice at the mic — it barely cleared the threshold, which invalidated a
    # test rather than the code.
    if sys.argv[1] == "--trace":
        wav, window, thresh = sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
        globals()["wav"] = wav
        return trace(wav, window, thresh)
    if len(sys.argv) != 7:
        return 0
    wav, state, ptt = sys.argv[1], sys.argv[2], sys.argv[3]
    window, thresh, logfile = float(sys.argv[4]), float(sys.argv[5]), sys.argv[6]

    def note(msg):
        try:
            with open(logfile, "a") as fh:
                fh.write("%s %s\n" % (time.strftime("%F %T"), msg))
        except Exception:
            pass

    def trailing_peak_block(secs):
        """Loudest 0.5 s block in the trailing window, not its mean.

        AVERAGING IS THE WRONG MEASURE HERE and this was caught in testing: a
        3 s window holding 0.9 s of speech and 2.1 s of quiet averaged -40.3
        dBFS and tripped a -40.0 threshold, ending the recording while the
        speaker was still mid-sentence. Energy diluted over the window hides in
        the mean.

        Taking the loudest block instead asks the right question — "was anything
        said at any point in the last N seconds?" — and restores real margin: a
        quiet block reads about -45 dBFS here and one containing speech about
        -25, so the threshold sits between two well-separated populations rather
        than on a continuum.
        """
        try:
            size = os.path.getsize(wav)
        except OSError:
            return None
        want = int(RATE * secs) * WIDTH
        if size - HDR < want:
            return None
        try:
            with open(wav, "rb") as fh:
                fh.seek(size - want)
                raw = fh.read(want)
        except OSError:
            return None
        a = array.array("h")
        a.frombytes(raw[: len(raw) // 2 * 2])
        if not len(a):
            return None
        block = int(RATE * 0.5)
        loudest = -99.0
        for start in range(0, len(a) - block + 1, block):
            chunk = a[start:start + block][::4]   # decimated within the block
            acc = 0
            for v in chunk:
                acc += v * v
            rms = math.sqrt(acc / len(chunk)) if chunk else 0.0
            db = 20 * math.log10(rms / 32768.0) if rms > 0 else -99.0
            if db > loudest:
                loudest = db
        return loudest

    def still_ours():
        try:
            with open(state) as fh:
                return wav in fh.read()
        except OSError:
            return False

    heard = False
    while still_ours():
        time.sleep(POLL_S)
        level = trailing_peak_block(window)
        if level is None:
            continue
        if level > thresh:
            heard = True
            continue
        if not heard:
            continue
        note("auto-stop: loudest 0.5s block in the last %.1fs was %.1f dBFS, "
             "below %.1f" % (window, level, thresh))
        try:
            subprocess.Popen(
                [ptt, "stop"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception as exc:
            note("auto-stop: could not invoke ptt stop: %s" % exc)
        break
    return 0


def trace(wav, window, thresh):
    """Print the trailing loudest-block level once a second, with a bar."""
    import builtins
    end = time.time() + 600
    while time.time() < end:
        time.sleep(1.0)
        lvl = _peak(wav, window)
        if lvl is None:
            continue
        verdict = "SILENT" if lvl <= thresh else "sound"
        bar = "#" * max(0, min(40, int((lvl + 60) / 1.2)))
        builtins.print("  %7.1f dBFS  %-6s %s" % (lvl, verdict, bar), flush=True)
    return 0


def _peak(wav, secs):
    RATE, WIDTH, HDR = 16000, 2, 44
    try:
        size = os.path.getsize(wav)
    except OSError:
        return None
    want = int(RATE * secs) * WIDTH
    if size - HDR < want:
        return None
    try:
        with open(wav, "rb") as fh:
            fh.seek(size - want)
            raw = fh.read(want)
    except OSError:
        return None
    a = array.array("h")
    a.frombytes(raw[: len(raw) // 2 * 2])
    block = int(RATE * 0.5)
    loudest = -99.0
    for st in range(0, len(a) - block + 1, block):
        c = a[st:st + block][::4]
        acc = 0
        for v in c:
            acc += v * v
        r = math.sqrt(acc / len(c)) if c else 0.0
        db = 20 * math.log10(r / 32768.0) if r > 0 else -99.0
        if db > loudest:
            loudest = db
    return loudest


if __name__ == "__main__":
    sys.exit(main())
