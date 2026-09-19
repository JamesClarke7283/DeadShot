#!/usr/bin/env python3
"""Export a release from a private project/cache copy without disturbing MCP."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("preset", choices=["Linux", "Windows", "Web"], nargs="?", default="Linux")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--keep", action="store_true", help="Retain the isolated build project")
    options = parser.parse_args()
    source = Path(__file__).resolve().parent.parent
    defaults = {"Linux": "builds/linux/DeadShot.x86_64", "Windows": "builds/windows/DeadShot.exe", "Web": "builds/web/index.html"}
    output = (options.output or source / defaults[options.preset]).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    mirror = Path(tempfile.mkdtemp(prefix="deadshot-release-"))
    log = source / "builds/logs" / (options.preset.lower() + "-export.log")
    log.parent.mkdir(parents=True, exist_ok=True)
    try:
        # Copy rather than symlink: editor imports must never mutate live caches.
        for name in ["assets", "data", "scripts", "scenes", ".godot"]:
            if (source / name).exists():
                shutil.copytree(source / name, mirror / name)
        for name in ["icon.svg", "icon.svg.import", "export_presets.cfg"]:
            shutil.copy2(source / name, mirror / name)
        config = (source / "project.godot").read_text()
        config = re.sub(r'^MCPRuntimeServer=.*\n', '', config, flags=re.MULTILINE)
        config = re.sub(r'\[editor_plugins\]\n.*?(?=\n\[|\Z)', '[editor_plugins]\n\nenabled=PackedStringArray()\n', config, flags=re.DOTALL)
        (mirror / "project.godot").write_text(config)
        print(f"Exporting {options.preset} from isolated project {mirror}", flush=True)
        with log.open("w") as stream:
            result = subprocess.run([options.godot, "--headless", "--path", str(mirror), "--log-file", str(mirror / "editor.log"), "--export-release", options.preset, str(output)], stdout=stream, stderr=subprocess.STDOUT, check=False)
        if result.returncode == 0:
            licenses = output.parent / "licenses"
            licenses.mkdir(exist_ok=True)
            for license_file in (source / "assets/fonts").glob("*.txt"):
                shutil.copy2(license_file, licenses / license_file.name)
            print(f"Release: {output}\nExport log: {log}")
        else:
            print(f"Export failed ({result.returncode}); see {log}")
        return result.returncode
    finally:
        if options.keep:
            print(f"Retained isolated project: {mirror}")
        else:
            shutil.rmtree(mirror)


if __name__ == "__main__":
    raise SystemExit(main())
