#!/usr/bin/env python3

import os
import re
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

        # two cases:
        # url
        # url as name
        if len(parts) == 1:
            url = parts[0]

            exec_name = None
            try:
                exec_name = urlparse(url).hostname
            except:
                raise Exception(ERROR_MSG.format(line))
            finally:
                if exec_name is None:
                    raise Exception(ERROR_MSG.format(line))

            exec_name = re.sub(r".\w+(?=$)", "", exec_name)
        elif len(parts) == 3:
            url = parts[0]
            exec_name = parts[2]

            try:
                urlparse(url)
            except:
                raise Exception(ERROR_MSG.format(line))

            if parts[1] != "as":
                raise Exception(ERROR_MSG.format(line))

            if not re.match(r"^[a-zA-Z0-9-_]+$", exec_name):
                raise Exception(ERROR_MSG.format(line))
        else:
            raise Exception(ERROR_MSG.format(line))

        with open(f"./collection/{exec_name}.sh", "w") as file:
            file.write(f"#!/bin/sh\n")
            file.write(f"xdg-open {url}\n")
            file.write(f"exit 0\n")

        os.system(f"chmod +x ./collection/{exec_name}.sh")
        os.system(
            f"sudo ln -sf {HOME}/code/arch-dotfiles/weblinks/collection/{exec_name}.sh /usr/local/bin/{exec_name}"
        )

        print(f"Created executable {exec_name} for {url}.")
