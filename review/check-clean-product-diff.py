#!/usr/bin/env python3
"""Prove quattro-clean's product files equal upstream except behaviour-neutral annotations.

Usage: review/check-clean-product-diff.py [UPSTREAM_REF] [CLEAN_REF]
       (defaults: e332dc97 HEAD)

Product = every path the two refs differ on, except the proof layer
(proof/, specs/, pocs/, review/, test/, proof.yaml, the fork front page
.github/README.md, and the fork's own docs under docs/proof/, new files
upstream does not have). For each product file the
line diff is classified; every changed line must be one of:
  blank            an added/removed empty line
  comment          a full-line comment in the file's language
                   (# for shell/.gitignore, // for .js/.qml/.jsonc)
  qml-id           an added `id: name` line in a .qml file
  qml-inline-id    a line whose only change is an inserted `id: name;`
  gitignore-proof  the `.proof/` ignore entry
Anything else is reported as NON-NEUTRAL and the script exits 1.
Caveat: a `#`/`//` line inside a heredoc or multi-line string would be data,
not a comment; the script flags any added comment line that sits between a
heredoc opener (<<) and its terminator so it cannot pass silently.
"""
import difflib, re, subprocess, sys

up = sys.argv[1] if len(sys.argv) > 1 else "e332dc97"
cl = sys.argv[2] if len(sys.argv) > 2 else "HEAD"
NONPRODUCT = ("proof/", "specs/", "pocs/", "review/", "test/", "docs/proof/")

def git(*a):
    return subprocess.run(["git", *a], check=True, capture_output=True, text=True).stdout

def show(ref, path):
    r = subprocess.run(["git", "show", f"{ref}:{path}"], capture_output=True, text=True)
    return r.stdout.splitlines() if r.returncode == 0 else []

def lang(path):
    if path.endswith((".js", ".qml", ".jsonc", ".mjs")): return "c"
    return "sh"  # bin/* scripts, .gitignore

def is_comment(line, l):
    s = line.strip()
    return s.startswith("//") if l == "c" else s.startswith("#")

def heredoc_ranges(lines):
    inside, term, out = False, None, set()
    for i, ln in enumerate(lines):
        if inside:
            out.add(i)
            if ln.strip() == term: inside = False
            continue
        m = re.search(r"<<-?\s*['\"]?(\w+)['\"]?", ln)
        if m and not ln.lstrip().startswith("#"): inside, term = True, m.group(1)
    return out

files = [f for f in git("diff", "--name-only", up, cl).split("\n") if f]
NONPRODUCT_FILES = ("proof.yaml", ".github/README.md")
product = [f for f in files if not f.startswith(NONPRODUCT) and f not in NONPRODUCT_FILES]
bad, tally = [], {}
for f in product:
    a, b = show(up, f), show(cl, f)
    l = lang(f)
    hd = heredoc_ranges(b) if l == "sh" and f != ".gitignore" else set()
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if op == "equal": continue
        rem, add = a[i1:i2], b[j1:j2]
        # a modified line whose only change is an inserted `id: name;`
        if op == "replace" and len(rem) == len(add) and all(
                re.sub(r"\bid:\s*\w+;\s*", "", y, count=1) == x for x, y in zip(rem, add)) and f.endswith(".qml"):
            tally["qml-inline-id"] = tally.get("qml-inline-id", 0) + len(add); continue
        for k, ln in [("-", x) for x in rem] + [("+", y) for y in add]:
            idx = None
            if k == "+": idx = j1 + add.index(ln)
            if not ln.strip(): cls = "blank"
            elif f == ".gitignore" and ln.strip() == ".proof/": cls = "gitignore-proof"
            elif is_comment(ln, l) and not (idx is not None and idx in hd): cls = "comment"
            elif f.endswith(".qml") and k == "+" and re.fullmatch(r"\s*id:\s*\w+\s*", ln): cls = "qml-id"
            else:
                bad.append(f"{f}: {k} {ln!r}"); continue
            tally[cls] = tally.get(cls, 0) + 1
print(f"upstream {git('rev-parse', '--short=12', up).strip()}  clean {git('rev-parse', '--short=12', cl).strip()}")
print(f"product files differing: {len(product)}")
for f in product: print("  " + f)
print("neutral changed lines by class: " + ", ".join(f"{k}={v}" for k, v in sorted(tally.items())))
if bad:
    print(f"NON-NEUTRAL lines: {len(bad)}")
    for x in bad: print("  " + x)
    sys.exit(1)
print("RESULT: every product difference is a behaviour-neutral annotation")
