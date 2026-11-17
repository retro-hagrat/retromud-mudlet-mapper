#!/usr/bin/env python3
"""Build, then replay each capture and compare ROOM lines to <capture>.expect.
Exit 0 all match, 1 mismatch or missing .expect, 2 harness error."""
import difflib, glob, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CAP = os.path.join(HERE, "captures")

def lua():
    import shutil
    return os.environ.get("LUA") or shutil.which("lua") or sys.exit("no lua binary")

def main():
    b = subprocess.run([sys.executable, os.path.join(ROOT, "build.py")])
    if b.returncode:
        return 2
    body = os.path.join(ROOT, "dist", "retromud.lua")
    s = subprocess.run([lua(), os.path.join(HERE, "smoke.lua"), body],
                       capture_output=True, text=True)
    if s.returncode:
        print("smoke FAILED:\n" + s.stdout + s.stderr)
        return 2
    u = subprocess.run([lua(), os.path.join(HERE, "capture_test.lua"), body],
                       capture_output=True, text=True)
    print((u.stdout + u.stderr).strip())
    if u.returncode:
        return 2
    t = subprocess.run([lua(), os.path.join(HERE, "tracker_test.lua"), body, CAP],
                       capture_output=True, text=True)
    print((t.stdout + t.stderr).strip())
    if t.returncode:
        return 2
    sd = subprocess.run([lua(), os.path.join(HERE, "seed_test.lua"), body],
                        capture_output=True, text=True)
    print((sd.stdout + sd.stderr).strip())
    if sd.returncode:
        return 2
    j = subprocess.run([lua(), os.path.join(HERE, "jobs_test.lua"), body, CAP],
                       capture_output=True, text=True)
    print((j.stdout + j.stderr).strip())
    if j.returncode:
        return 2
    caps = sorted(p for p in glob.glob(os.path.join(CAP, "*"))
                  if not p.endswith((".expect", "README.md")))
    failed = 0
    for cap in caps:
        name = os.path.basename(cap)
        r = subprocess.run([lua(), os.path.join(HERE, "replay.lua"), body, cap, cap + ".expect"],
                           capture_output=True, text=True)
        if r.returncode:
            print("ERROR  %s\n%s" % (name, r.stderr))
            return 2
        got = [l for l in r.stdout.splitlines() if l.startswith("ROOM|")]
        exp_path = cap + ".expect"
        if not os.path.exists(exp_path):
            print("FAIL   %s: no .expect file (got %d ROOM lines)" % (name, len(got)))
            failed += 1
            continue
        exp = [l.rstrip("\n") for l in open(exp_path, encoding="utf-8")
               if l.startswith("ROOM|")]
        if got == exp:
            print("PASS   %s (%d rooms)" % (name, len(exp)))
            continue
        failed += 1
        print("FAIL   %s: expected %d ROOM lines, got %d" % (name, len(exp), len(got)))
        for l in list(difflib.unified_diff(exp, got, "expected", "got", lineterm="", n=0))[:12]:
            print("   " + l)
    print("%d/%d captures match" % (len(caps) - failed, len(caps)))
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
