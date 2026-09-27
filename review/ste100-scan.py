#!/usr/bin/env python3
"""Approximate the proof lint-prose-ste100 checks to enumerate all findings at once.
Flags: >25 words in descriptive fields, >20 in procedural (AC text), passive voice."""
import re, sys, yaml, pathlib

root = pathlib.Path("/private/tmp/omarchy-fix-jsonc-comma")
DESCRIPTIVE = {"description", "rationale", "story", "notes", "reason", "detail", "result"}
PROCEDURAL = {"text"}  # acceptance criteria text

PASSIVE = re.compile(r"\b(is|are|was|were|be|been|being)\s+(\w*(?:ed|en))\b", re.I)
# common adjectives that end in ed/en but are not passive verbs
ALLOW = {"unattended", "integrated", "advanced"}

def sentences(txt):
    txt = re.sub(r"\s+", " ", str(txt)).strip()
    parts = re.split(r"(?<=[.!?])\s+(?=[A-Z0-9\"'`(])", txt)
    return [p for p in parts if p.strip()]

def wc(s):
    return len(s.split())

def scan(path):
    try:
        data = yaml.safe_load(path.read_text())
    except Exception:
        return []
    out = []
    def walk(o, key=""):
        if isinstance(o, dict):
            for k, v in o.items():
                walk(v, k)
        elif isinstance(o, list):
            for v in o:
                walk(v, key)
        elif isinstance(o, str) and len(o) > 40:
            limit = 20 if key in PROCEDURAL else 25 if key in DESCRIPTIVE else None
            for s in sentences(o):
                w = wc(s)
                if limit and w > limit:
                    out.append(f"LONG({w}>{limit}) [{key}] {s[:100]}")
                m = PASSIVE.search(s)
                if m and m.group(2).lower() not in ALLOW:
                    out.append(f"PASSIVE({m.group(1)}+{m.group(2)}) [{key}] …{s[max(0,m.start()-40):m.end()+40]}…")
    walk(data)
    return out

for pat in ("specs/**/*.yaml", "proof/**/*.yaml"):
    for p in sorted(root.glob(pat)):
        findings = scan(p)
        if findings:
            print(f"### {p.relative_to(root)}")
            for f in findings:
                print("   ", f)
