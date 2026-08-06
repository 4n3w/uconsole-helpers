#!/usr/bin/env python3
"""Triage the capture log: walk untriaged entries and decide what each is worth.

    note-triage.py DIR inbox
    note-triage.py DIR triage [--oldest]
    note-triage.py DIR dismiss-before YYYY-MM-DD

DESIGNED FOR THE BACKLOG, NOT THE DILIGENT CASE

The obvious design is a watermark — "triaged through here" — and it is wrong for
the way this actually gets used. Come back from two weeks away and a watermark
forces you through 200 entries IN ORDER before it will move. That is how an
inbox becomes permanent guilt and the whole system gets abandoned.

So state is PER ENTRY, held in .triage/done.tsv. You can skip freely, do the
three you remember caring about, and leave the rest indefinitely. And
`dismiss-before` exists so that writing off a fortnight you will never process
is one command rather than an act of will. Nothing expires on its own and
nothing is ever deleted — dismissing marks the entry handled, it does not touch
the log.

THE STATE FILE IS APPEND-ONLY, which is not incidental. It gets `merge=union`
alongside the daily logs, so triaging from two machines merges without conflict.
A duplicate line for the same entry is harmless: this reads it as a set.

NOTHING HERE EVER WRITES TO daily/. That is the whole premise — the log is an
immutable record of what was captured, and triage produces notes elsewhere.
"""

import os
import re
import subprocess
import sys

ENTRY_RE = re.compile(r"^##\s+(\d{2}:\d{2}(?::\d{2})?)\s*(.*)$")
DAY_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})\.md$")


def load_entries(dir_):
    """Every entry in daily/, oldest first, as (id, date, time, tags, text)."""
    daily = os.path.join(dir_, "daily")
    if not os.path.isdir(daily):
        return []
    out = []
    # Two entries can share a timestamp — legacy entries predate the seconds fix,
    # and even with seconds two captures could in principle land in the same one.
    # Identical IDs would make triaging one silently mark the other, so repeats
    # get an occurrence suffix. Done HERE rather than by rewriting the log,
    # because daily/ is immutable and a parser can be fixed forever.
    seen = {}
    for name in sorted(os.listdir(daily)):
        m = DAY_RE.match(name)
        if not m:
            continue
        day = m.group(1)
        try:
            with open(os.path.join(daily, name), encoding="utf-8") as fh:
                lines = fh.read().splitlines()
        except OSError:
            continue
        cur = None
        for line in lines:
            em = ENTRY_RE.match(line)
            if em:
                if cur:
                    out.append(cur)
                t = em.group(1)
                if len(t) == 5:          # legacy HH:MM entries predate seconds
                    t += ":00"
                base = "%sT%s" % (day, t)
                seen[base] = seen.get(base, 0) + 1
                uid = base if seen[base] == 1 else "%s#%d" % (base, seen[base])
                cur = {
                    "id": uid,
                    "date": day,
                    "time": t,
                    "tags": em.group(2).strip(),
                    "body": [],
                }
            elif cur is not None and not line.startswith("---") \
                    and not line.startswith("# "):
                cur["body"].append(line)
        if cur:
            out.append(cur)
    for e in out:
        e["text"] = "\n".join(e["body"]).strip()
    return [e for e in out if e["text"]]


def state_path(dir_):
    return os.path.join(dir_, ".triage", "done.tsv")


def load_done(dir_):
    p = state_path(dir_)
    done = set()
    try:
        with open(p, encoding="utf-8") as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if parts and parts[0]:
                    done.add(parts[0])
    except OSError:
        pass
    return done


def mark_done(dir_, entry_id, action):
    p = state_path(dir_)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    from datetime import datetime
    with open(p, "a", encoding="utf-8") as fh:
        fh.write("%s\t%s\t%s\n" % (entry_id, action,
                                   datetime.now().strftime("%Y-%m-%dT%H:%M:%S")))


def pending(dir_):
    done = load_done(dir_)
    return [e for e in load_entries(dir_) if e["id"] not in done]


def cmd_inbox(dir_):
    p = pending(dir_)
    if not p:
        print("  inbox empty")
        return 0
    days = sorted({e["date"] for e in p})
    print("  %d untriaged entr%s across %d day%s"
          % (len(p), "y" if len(p) == 1 else "ies",
             len(days), "" if len(days) == 1 else "s"))
    print("  oldest %s, newest %s" % (days[0], days[-1]))
    if len(p) > 20:
        print("  (a backlog is fine — `note triage` skips freely, and")
        print("   `note dismiss-before %s` writes off anything you won't process)" % days[-1])
    return 0


def slugify(title):
    s = re.sub(r"[^\w\s-]", "", title.strip().lower())
    s = re.sub(r"[\s_]+", "-", s).strip("-")
    return s or "untitled"


def promote(dir_, entry):
    """Append the entry to a note at the vault root, creating it if needed."""
    try:
        title = input("    note title: ").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        return False
    if not title:
        print("    (no title — skipped)")
        return False
    # topics/, not the vault root. daily/ answers "when", topics/ answers "what",
    # and the root stays for vault-level files. Flat inside — no folder taxonomy,
    # because categorising up front is how these systems stall. Links and tags do
    # the organising, and this is one `git mv` from any other choice.
    topics = os.path.join(dir_, "topics")
    os.makedirs(topics, exist_ok=True)
    path = os.path.join(topics, slugify(title) + ".md")
    new = not os.path.exists(path)
    with open(path, "a", encoding="utf-8") as fh:
        if new:
            fh.write("---\ntags: [note]\n---\n\n# %s\n" % title)
        # The backlink points at the log rather than copying blindly, so the
        # original wording stays findable even after you rewrite it here.
        fh.write("\n%s\n\n<sub>from daily/%s.md at %s</sub>\n"
                 % (entry["text"], entry["date"], entry["time"]))
    print("    %s %s" % ("created" if new else "appended to",
                         os.path.relpath(path, dir_)))
    ed = os.environ.get("EDITOR")
    if ed:
        try:
            ans = input("    open in %s? [y/N] " % ed).strip().lower()
            if ans == "y":
                subprocess.call([ed, path])
        except (EOFError, KeyboardInterrupt):
            print()
    return True


def cmd_triage(dir_, oldest_first):
    items = pending(dir_)
    if not items:
        print("  inbox empty")
        return 0
    if not oldest_first:
        items = list(reversed(items))     # recent first: more actionable
    print("  %d to triage.  [d]one  [p]romote  [s]kip  [q]uit\n" % len(items))
    for i, e in enumerate(items, 1):
        print("  %s %s   (%d of %d)" % (e["date"], e["time"], i, len(items)))
        if e["tags"]:
            print("  %s" % e["tags"])
        for line in e["text"].splitlines():
            print("      %s" % line)
        while True:
            try:
                ans = input("    > ").strip().lower()
            except (EOFError, KeyboardInterrupt):
                print("\n  stopped — nothing lost, the rest stay in the inbox")
                return 0
            if ans in ("d", ""):
                mark_done(dir_, e["id"], "done")
                break
            if ans == "s":
                break
            if ans == "q":
                print("  stopped — the rest stay in the inbox")
                return 0
            if ans == "p":
                if promote(dir_, e):
                    mark_done(dir_, e["id"], "promoted")
                    break
                continue
            print("    d=done  p=promote  s=skip  q=quit")
        print()
    print("  done — inbox has %d left" % len(pending(dir_)))
    return 0


def cmd_dismiss_before(dir_, date):
    items = [e for e in pending(dir_) if e["date"] < date]
    if not items:
        print("  nothing before %s is pending" % date)
        return 0
    for e in items:
        mark_done(dir_, e["id"], "dismissed")
    print("  dismissed %d entr%s before %s (the log is untouched)"
          % (len(items), "y" if len(items) == 1 else "ies", date))
    return 0


def main():
    if len(sys.argv) < 3:
        print("usage: note-triage.py DIR {inbox|triage|dismiss-before DATE}",
              file=sys.stderr)
        return 2
    dir_, cmd = sys.argv[1], sys.argv[2]
    if cmd == "inbox":
        return cmd_inbox(dir_)
    if cmd == "triage":
        return cmd_triage(dir_, "--oldest" in sys.argv[3:])
    if cmd == "dismiss-before":
        if len(sys.argv) < 4:
            print("dismiss-before needs a YYYY-MM-DD date", file=sys.stderr)
            return 2
        return cmd_dismiss_before(dir_, sys.argv[3])
    print("unknown command %r" % cmd, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
