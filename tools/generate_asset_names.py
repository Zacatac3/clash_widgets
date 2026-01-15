#!/usr/bin/env python3
"""
Generates sanitized asset names from the `mapping` dictionary in DataService.swift.

Run:
  python3 tools/generate_asset_names.py

It will print JSON mapping of original names -> sanitized asset names.
"""
import re
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_SERVICE = ROOT / 'clash_widgets' / 'DataService.swift'

def sanitize(name: str) -> str:
    # Lowercase, replace non-alphanumerics with underscores, collapse underscores, trim
    s = name.lower()
    s = re.sub(r'[^a-z0-9]+', '_', s)
    s = re.sub(r'_+', '_', s)
    s = s.strip('_')
    return s

def extract_mapping(swift_text: str):
    # Find the mapping block between 'private let mapping: [Int: String] = [' and the closing ']'
    m = re.search(r'private\s+let\s+mapping:\s*\[Int:\s*String\]\s*=\s*\[', swift_text)
    if not m:
        return {}
    start = m.end()
    # Find the matching closing bracket — simple approach: find the next '\n\s*]' at column position
    rest = swift_text[start:]
    end_match = re.search(r'\n\s*\]\s*', rest)
    if not end_match:
        return {}
    block = rest[:end_match.start()]
    # Find lines like 1000008: "Cannon",
    pairs = re.findall(r"\s*(\d+)\s*:\s*\"([^\"]+)\"", block)
    return {int(k): v for k, v in pairs}

def main():
    if not DATA_SERVICE.exists():
        print('Error: DataService.swift not found at', DATA_SERVICE)
        return
    text = DATA_SERVICE.read_text(encoding='utf-8')
    mapping = extract_mapping(text)
    out = {}
    for k, v in mapping.items():
        out[v] = sanitize(v)
    print(json.dumps(out, indent=2, ensure_ascii=False))

if __name__ == '__main__':
    main()
