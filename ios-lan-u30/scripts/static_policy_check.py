#!/usr/bin/env python3
"""Reject network endpoints and impersonation markers in the LAN client sources."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
needles = [
    "remotepilot",
    "github.com",
    "notion.so",
    "api.github",
    "NSAllowsArbitraryLoads",
    "com.eric3u",
    "AirSIMPushRelayURL",
]
allowed_port_mentions = {"LanU30App/ContentView.swift"}
port_needles = ("2333", "8080", "8443")
failures = []
files = [path for path in root.rglob("*") if path.suffix in {".swift", ".plist", ".xcconfig", ".pbxproj"}]
for path in files:
    text = path.read_text(encoding="utf-8")
    relative = path.relative_to(root).as_posix()
    for needle in needles:
        if needle in text:
            failures.append(f"{relative} contains {needle}")
    if any(port in text for port in port_needles) and relative not in allowed_port_mentions:
        failures.append(f"{relative} mentions a stock admin port outside the warning copy")
if failures:
    print("\n".join(failures))
    sys.exit(1)
print(f"static policy check passed ({len(files)} files)")
