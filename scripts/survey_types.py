#!/usr/bin/env python3
"""One-shot census: which QML object types does the tree actually use,
and which of them fall outside BASE_PROPS / QT_BASE / local files /
REQUIRED_MODULE (i.e. property-assignments there are validated NOWHERE)."""
import os
import re
import sys
import collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
#  check_hyprnotch.py runs main()/sys.exit at import time (module bottom),
#  so exec only its definition prefix (everything before `def tokenize`)
#  to grab the whitelist dicts without triggering a full validation run.
_src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "check_hyprnotch.py"), encoding="utf-8").read()
_prefix = _src[:_src.index("def tokenize")]
_ns: dict = {"__file__": os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                      "check_hyprnotch.py")}
exec(compile(_prefix, "check_hyprnotch_prefix", "exec"), _ns)
BASE_PROPS = _ns["BASE_PROPS"]
QT_BASE = _ns["QT_BASE"]
REQUIRED_MODULE = _ns["REQUIRED_MODULE"]
QT_BUILTIN_NAMES = _ns["QT_BUILTIN_NAMES"]

local_files = set()
for base, _, fs in os.walk(ROOT):
    for f in fs:
        if f.endswith(".qml"):
            local_files.add(f[:-4])
            if f == "qmldir":
                local_files.add(os.path.basename(base))

types = collections.Counter()   # type -> usage count
per_type_files = collections.defaultdict(set)
for base, _, fs in os.walk(ROOT):
    for f in sorted(fs):
        if not f.endswith(".qml"):
            continue
        p = os.path.join(base, f)
        raw = open(p, encoding="utf-8").read()
        for m in re.finditer(r"(?m)^\s*([A-Z]\w*)\s*(?:on[A-Z]\w*\s+[\w.]+\s*)?\{", raw):
            types[m.group(1)] += 1
            per_type_files[m.group(1)].add(os.path.relpath(p, ROOT))

uncovered = []
for t, n in sorted(types.items()):
    if t in local_files or t in BASE_PROPS or t in QT_BASE \
       or t in REQUIRED_MODULE or t in QT_BUILTIN_NAMES:
        continue
    uncovered.append((t, n))

print("== uncovered types (assignments on these are validated NOWHERE) ==")
for t, n in uncovered:
    print(f"  {t} x{n}  -> {sorted(per_type_files[t])[:4]}")

print("\n== covered-by-BASE_PROPS usage counts ==")
for t, n in sorted(types.items()):
    if t in BASE_PROPS and t not in local_files:
        print(f"  {t} x{n}")
