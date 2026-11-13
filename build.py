#!/usr/bin/env python3
"""Stitch src/*.lua -> dist/retromud.{lua,xml,mpackage}, with sanity checks."""
import glob, os, re, shutil, subprocess, sys, zipfile
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.abspath(__file__))
DIST = os.path.join(ROOT, "dist")

# comments and strings, in scan order, so banned tokens inside them are ignored
STRIP = re.compile(
    r"--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]"
    r'|"(?:\\.|[^"\\\n])*"' r"|'(?:\\.|[^'\\\n])*'", re.S)
BANNED = [
    (r"\bgoto\b", "goto"), (r"//", "// integer division"),
    (r"<<|>>", "bit shift"), (r"[&|]", "bitwise & or |"),
    (r"~(?!=)", "bitwise ~"), (r"\btable\.unpack\b", "table.unpack"),
    (r"\butf8\b", "utf8"),
    (r"<(?:const|close)>", "<const>/<close> attrib"), (r"::\w+::", "label"),
    (r"\b(?:math\.(?:type|tointeger|ult)|table\.(?:pack|move)"
     r"|string\.(?:pack|unpack|packsize)|rawlen|warn)\b", "5.2+ library"),
    (r"\bload\s*\(", "load"), (r"\b0[xX][0-9a-fA-F.]*[pP]", "hex float"),
]
# string escapes are invisible after STRIP, so check the raw body
ESCAPE = re.compile(r"(?<!\\)\\[xzu]")

def lint(body):
    code = STRIP.sub(" ", body)
    found = ["line %d: banned %s" % (code[:m.start()].count("\n") + 1, what)
             for pat, what in BANNED for m in re.finditer(pat, code)]
    return found + ["line %d: banned \\x/\\z/\\u escape" % (body[:m.start()].count("\n") + 1)
                    for m in ESCAPE.finditer(body)]

def find_lua():
    lua = os.environ.get("LUA") or shutil.which("lua")
    if not lua:
        sys.exit("build: no lua binary (set LUA=/path/to/lua)")
    return lua

def lua_check(path):
    r = subprocess.run([find_lua(), os.path.join(ROOT, "test", "check_body.lua"), path],
                       capture_output=True, text=True)
    return [] if r.returncode == 0 else [(r.stdout + r.stderr).strip()]

def lua_value(file, name):
    m = re.search(name + r'\s*=\s*(?:\[\[|")([^\]"]+)', open(file).read())
    return m and m.group(1)

def main():
    files = sorted(glob.glob(os.path.join(ROOT, "src", "*.lua")))
    body = "\n".join(open(f).read() for f in files)
    os.makedirs(DIST, exist_ok=True)
    body_path = os.path.join(DIST, "retromud.lua")
    open(body_path, "w").write(body)

    problems = lint(body) + lua_check(body_path)
    cfg = os.path.join(ROOT, "config.lua")
    m = re.search(r'rm\.version\s*=\s*"([^"]+)"', body)
    if not m or m.group(1) != lua_value(cfg, "version"):
        problems.append("rm.version does not match config.lua version")
    if problems:
        print("build FAILED:\n  " + "\n  ".join(problems))
        sys.exit(1)

    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE MudletPackage>\n'
           '<MudletPackage version="1.001">\n<ScriptPackage>\n'
           '<Script isActive="yes" isFolder="no">\n<name>retromud</name>\n'
           '<packageName></packageName>\n<script>%s</script>\n'
           '<eventHandlerList />\n</Script>\n</ScriptPackage>\n</MudletPackage>\n'
           % escape(body))
    open(os.path.join(DIST, "retromud.xml"), "w").write(xml)
    out = os.path.join(DIST, "retromud.mpackage")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(os.path.join(DIST, "retromud.xml"), "retromud.xml")
        z.write(cfg, "config.lua")
    print("built %s (%d modules, checks passed)" % (out, len(files)))

if __name__ == "__main__":
    main()
