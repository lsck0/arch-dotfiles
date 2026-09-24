#!/usr/bin/env python3

import re
import subprocess
from pathlib import Path
from urllib.parse import urlparse

HOME = str(Path.home())
ERROR_MSG = """
Invalid format: {0}.
Expected `<url>` or `<url> as <name>`.
Name has to match /^[a-zA-Z0-9-_]+$/.
"""

with open("./links.txt", "r") as file:
    for line in file:
        line = line.strip()
        parts = [p.strip() for p in line.split(" ") if p.strip()]

        # two cases: url url as name
        if len(parts) == 1:
            url = parts[0]

            try:
                exec_name = urlparse(url).hostname
            except ValueError as err:
                raise Exception(ERROR_MSG.format(line)) from err
            if exec_name is None:
                raise Exception(ERROR_MSG.format(line))

            exec_name = re.sub(r".\w+(?=$)", "", exec_name)
        elif len(parts) == 3:
            url = parts[0]
            exec_name = parts[2]

            try:
                urlparse(url)
            except ValueError as err:
                raise Exception(ERROR_MSG.format(line)) from err

            if parts[1] != "as":
                raise Exception(ERROR_MSG.format(line))

            if not re.match(r"^[a-zA-Z0-9-_]+$", exec_name):
                raise Exception(ERROR_MSG.format(line))
        else:
            raise Exception(ERROR_MSG.format(line))

        # exec_name lands in a filesystem path and a symlink target, so keep it to the same charset the `as name` branch already enforces.
        if not re.match(r"^[a-zA-Z0-9-_]+$", exec_name):
            raise Exception(ERROR_MSG.format(line))

        script = Path("./collection") / f"{exec_name}.sh"
        script.write_text(f"#!/bin/sh\nxdg-open {url}\nexit 0\n")
        script.chmod(0o755)
        subprocess.run(
            ["sudo", "ln", "-sfn", str(script.resolve()), f"/usr/local/bin/{exec_name}"],
            check=True,
        )

        print(f"Created executable {exec_name} for {url}.")
