"""Run deterministic checks against the production multi-account selection and persistence.

From the repository root: python3 tools/multi_account_tests/run.py
"""
from pathlib import Path
import subprocess
import tempfile

with tempfile.TemporaryDirectory(prefix="clashboard-multi-account-tests-") as directory:
    executable = Path(directory) / "checks"
    main = Path(directory) / "main.swift"
    main.write_text(Path("tools/multi_account_tests/checks.swift").read_text())
    subprocess.run([
        "xcrun", "swiftc", "-module-cache-path", "/tmp/clashboard-swift-module-cache",
        "clash_widgets/Models.swift", "clash_widgets/RemoteContentModels.swift",
        "clash_widgets/PlayerAccount.swift", "clash_widgets/PersistentStore.swift",
        "clash_widgets/MultiAccountUpgrades.swift", "clash_widgets/DataService+Profiles.swift",
        str(main), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)
