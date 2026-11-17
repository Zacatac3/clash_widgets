"""Verify the production remote-content clock does no work while idle.

Run: python3 tools/performance_tests/run.py
Optional baseline: add --service-source /path/to/old/RemoteContentService.swift --baseline
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--service-source", default="clash_widgets/RemoteContentService.swift")
parser.add_argument("--baseline", action="store_true")
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="clashboard-performance-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run([
        "xcrun", "swiftc", "-parse-as-library", "-module-cache-path", "/tmp/clashboard-swift-module-cache",
        "clash_widgets/Models.swift", "clash_widgets/RemoteContentModels.swift", args.service_source,
        "tools/performance_tests/main.swift", "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)] + (["--baseline"] if args.baseline else []), check=True)
