#!/usr/bin/env python3
"""Every key used in L10n.swift must exist in each Localizable.strings, and vice versa."""
import re, sys, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
used = set(re.findall(r'tr\("([^"]+)"', (root / "Hum/Core/L10n.swift").read_text()))
used = {k for k in used if not k.endswith(".")}
used |= {f"settings.palette.{p}" for p in ["system", "green", "teal", "indigo", "orange", "graphite"]}
ok = True
for lang in ["zh-Hans", "en"]:
    text = (root / f"Hum/Resources/{lang}.lproj/Localizable.strings").read_text()
    have = set(re.findall(r'^"([^"]+)"\s*=', text, re.M))
    for k in sorted(used - have): print(f"{lang}: missing {k}"); ok = False
    for k in sorted(have - used): print(f"{lang}: unused {k}")
sys.exit(0 if ok else 1)
