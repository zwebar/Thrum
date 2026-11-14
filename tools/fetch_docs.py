"""Copies Blizzard's generated API docs out of the local WoW Classic Forever install.

    python3 tools/fetch_docs.py [--wow "/Applications/World of Warcraft"] [--casc <path to casc.py dir>]

The docs land in tools/forever_docs (not committed: they are Blizzard's files). The test rig
uses them when present, so every API Thrum calls is checked against the build the game runs.
It reads the "wowf" (Classic Forever) row of .build.info with Chronicle's CASC reader.
"""
import builtins
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def opt(name, default):
    if "--" + name in sys.argv:
        return sys.argv[sys.argv.index("--" + name) + 1]
    return default


WOW = opt("wow", "/Applications/World of Warcraft")
CASC_DIR = opt("casc", os.path.join(HERE, "..", "..", "chronicle", "tools"))
OUT = os.path.join(HERE, "forever_docs")
DOCS = "Interface\\AddOns\\Blizzard_APIDocumentationGenerated\\"

sys.path.insert(0, CASC_DIR)
import casc  # noqa: E402

real_open = builtins.open
lines = real_open(os.path.join(WOW, ".build.info")).read().splitlines()
rows = [l for l in lines[1:] if l.split("|")[-1] == "wowf"]
if not rows:
    sys.exit("no Classic Forever (wowf) build in " + WOW)
only_forever = "\n".join([lines[0], rows[0]])


def patched_open(path, *a, **k):
    if str(path).endswith(".build.info"):
        return io.StringIO(only_forever)
    return real_open(path, *a, **k)


builtins.open = patched_open
try:
    store = casc.CASC(WOW)
finally:
    builtins.open = real_open

toc = store.read(DOCS + "Blizzard_APIDocumentationGenerated.toc").decode("utf-8", "replace")
files = [l.strip() for l in toc.splitlines() if l.strip().endswith(".lua")]
os.makedirs(OUT, exist_ok=True)
for f in files:
    with real_open(os.path.join(OUT, f), "wb") as fh:
        fh.write(store.read(DOCS + f))
with real_open(os.path.join(OUT, "VERSION"), "w") as fh:
    fh.write(store.version + "\n")
print("wrote", len(files), "doc files for build", store.version, "to", OUT)
