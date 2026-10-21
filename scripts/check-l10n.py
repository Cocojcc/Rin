#!/usr/bin/env python3
"""Every key used in L10n.swift must exist in each Localizable.strings, and vice versa."""
import re, sys, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
used = set(re.findall(r'tr\("([^"]+)"', (root / "Rin/Core/L10n.swift").read_text()))
# Interpolated keys ("widget.name.\\(kind.rawValue)") cover every key with that prefix.
prefixes = {k.split("\\(")[0] for k in used if "\\(" in k}
used = {k for k in used if not k.endswith(".") and "\\(" not in k}
ok = True
for lang in ["zh-Hans", "en"]:
    text = (root / f"Rin/Resources/{lang}.lproj/Localizable.strings").read_text()
    have = set(re.findall(r'^"([^"]+)"\s*=', text, re.M))
    dynamic = {k for k in have if any(k.startswith(p) for p in prefixes)}
    for p in sorted(prefixes):
        if not any(k.startswith(p) for k in have): print(f"{lang}: missing {p}*"); ok = False
    have_static = have - dynamic
    for k in sorted(used - have): print(f"{lang}: missing {k}"); ok = False
    for k in sorted(have_static - used): print(f"{lang}: unused {k}")
sys.exit(0 if ok else 1)
