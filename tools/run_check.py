#!/usr/bin/env python3
"""Run a Godot check/capture without touching the live MCP registry or log.

Examples:
  python tools/run_check.py --script res://tests/weapon_parity.gd
  python tools/run_check.py --graphical --script res://tests/snapshot_match.gd
  python tools/run_check.py --timeout 180 -- --quit-after 120 -- --smoke-match

Resources and import caches are shared with the source project. This runner is
for runtime checks only: editor/import operations must use a separate checkout.
"""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import uuid


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--graphical", action="store_true", help="Keep the display enabled for rendered captures")
    parser.add_argument("--keep", action="store_true", help="Retain the temporary project and diagnostic log")
    parser.add_argument("--timeout", type=float, default=120, help="Maximum runtime in seconds (default 120)")
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    options, arguments = parser.parse_known_args()
    if arguments and arguments[0] == "--":
        arguments.pop(0)
    if any(value in arguments for value in ["--editor", "-e", "--import", "--path", "--project", "--project-manager"]) or any(value.startswith("--export") for value in arguments):
        parser.error("Editor/import/project overrides are unsupported because runtime resources share the source cache")
    source = Path(__file__).resolve().parent.parent
    temporary = Path(tempfile.mkdtemp(prefix="deadshot-check-"))
    app_name = "DeadShot-check-" + uuid.uuid4().hex
    config = (source / "project.godot").read_text()
    config = re.sub(r'^MCPRuntimeServer=.*\n', '', config, flags=re.MULTILINE)
    config = re.sub(r'^config/name=.*$', f'config/name="{app_name}"', config, flags=re.MULTILINE)
    config = re.sub(r'\[editor_plugins\]\n.*?(?=\n\[|\Z)', '[editor_plugins]\n\nenabled=PackedStringArray()\n', config, flags=re.DOTALL)
    (temporary / "project.godot").write_text(config)
    for entry in source.iterdir():
        if entry.name not in ["project.godot", ".git", ".mcp.json"]:
            (temporary / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
    command = [options.godot, "--path", str(temporary)]
    if not options.graphical and "--headless" not in arguments:
        command.append("--headless")
    if "--log-file" not in arguments:
        command.extend(["--log-file", str(temporary / "check.log")])
    command.extend(arguments)
    print(f"Isolated Godot project: {temporary} (MCP autoload disabled)", flush=True)
    try:
        return subprocess.run(command, timeout=options.timeout, check=False).returncode
    except subprocess.TimeoutExpired:
        print(f"Godot check exceeded {options.timeout:g} seconds", file=sys.stderr)
        return 124
    finally:
        if options.keep:
            print(f"Retained isolated project: {temporary}")
        else:
            shutil.rmtree(temporary)
            # This unique test application name cannot be the user's game save.
            data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
            shutil.rmtree(data_home / "godot/app_userdata" / app_name, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
