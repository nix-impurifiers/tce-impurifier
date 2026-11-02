#!/usr/bin/python3
# SPDX-License-Identifier: MIT
"""Load native extensions, then report profile activation errors to the caller."""
import json
import re
from pathlib import Path
import subprocess
import sys


def main():
    args = sys.argv[1:]
    if not args:
        raise ValueError("use load ARCHIVE.tcz... or reconcile")
    if args[0] == "load":
        if len(args) < 2 or any(a.startswith("-") for a in args[1:]):
            raise ValueError("load accepts extension paths, not root/loader options")
        projected = set()
        for source in args[1:]:
            path = Path(source)
            if not path.is_file() or any(c.isspace() for c in source):
                raise ValueError("load requires local extension paths without whitespace")
            data = json.loads(Path(str(path) + ".impurifier.json").read_text())
            name = data["nativeName"]
            app = data["projectedName"]
            if data["schema"] != 1 or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9+._-]*", name) or path.name != name + ".tcz":
                raise ValueError("invalid managed extension metadata or filename")
            if Path("/usr/local/tce.installed", name).exists():
                raise ValueError("extension is already loaded; change the boot set and reboot")
            if app is not None:
                if not re.fullmatch(r"[a-z0-9][a-z0-9+.-]+", app):
                    raise ValueError("invalid projected package name")
                if app in projected or Path("/usr/share/nix-profile.d", app + ".json").exists():
                    raise ValueError("application is already selected; change the boot set and reboot")
                projected.add(app)
        status = subprocess.run(["tce-load", "-i", *args[1:]]).returncode
    elif args == ["reconcile"]:
        status = 0
    else:
        raise ValueError("use load ARCHIVE.tcz... or reconcile")
    engine = Path("/usr/sbin/nix-profile-engine")
    activation = subprocess.run(["sudo", "/usr/sbin/tce-impurifier-activate", "0"]).returncode if engine.exists() else 0
    return status or activation


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("tce-impurifier: " + str(error), file=sys.stderr)
        sys.exit(1)
