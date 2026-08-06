#!/usr/bin/env python3
"""Register the speak-summary Stop hook in a Claude Code settings.json.

    register-stop-hook.py SETTINGS_PATH HOOK_PATH CHECK_FLAG

Prints one `STATUS<tab>message` line — OK, NEED, DONE or FAIL — which
`install.sh` renders. Keeping the formatting there rather than here means colour
is decided in one place and never leaks escape codes into a non-tty pipe.

MERGES, NEVER REPLACES. `~/.claude/settings.json` is the one piece of this setup
that is a real file rather than a symlink into the repo, because it also holds
personal preferences — theme, tui — that are not device config and have no
business being version-controlled per-machine. Overwriting it to install a hook
would take those with it.

Exits 0 even on failure. install.sh decides what a failure means; a helper that
exits non-zero mid-script is a worse citizen than one that reports.
"""

import json
import sys


def main():
    if len(sys.argv) != 4:
        print("FAIL\tregister-stop-hook.py: wrong arguments")
        return 0
    path, hook, check = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

    try:
        with open(path) as fh:
            data = json.load(fh)
    except FileNotFoundError:
        data = {}
    except Exception:
        # Refuse to touch a file we cannot parse: rewriting it would destroy
        # whatever the user has in there.
        print("FAIL\tsettings.json is not valid JSON — fix it by hand first")
        return 0

    stop = data.setdefault("hooks", {}).setdefault("Stop", [])
    if any(h.get("command") == hook
           for group in stop for h in group.get("hooks", [])):
        print("OK\tStop hook registered")
        return 0

    if check:
        print("NEED\tStop hook -> %s" % hook)
        return 0

    # async so the hook's wait for the transcript flush can never delay a
    # session; timeout comfortably clear of that wait.
    stop.append({
        "hooks": [{
            "type": "command",
            "command": hook,
            "async": True,
            "timeout": 20,
        }]
    })
    try:
        with open(path, "w") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
    except Exception as exc:
        print("FAIL\tcould not write settings.json: %s" % exc)
        return 0

    print("DONE\tStop hook added (existing settings preserved)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
