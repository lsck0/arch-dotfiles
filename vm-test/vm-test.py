#!/usr/bin/env python3
"""End-to-end test of the dotfiles on a fresh Arch install in a system libvirt VM.

    vm-test.py run [--iso PATH] [--reuse] [--master]
                                            fresh VM + archinstall (--reuse keeps an installed one), then what a
                                            human does: log in, clone into ~/projects, ./install.sh, answer sudo
                                            and prompts; pulls logs, reboots, exits 1 on failures. Tests the local
                                            working tree (clone, then check out a snapshot bundle) unless --master
    vm-test.py logs                         pull install.log, FAILURES and every *.log to ~/.cache/vm-test/<name>/logs
    vm-test.py shot                         screenshot to ~/.cache/vm-test/<name>/screen.png
    vm-test.py type TEXT                    type TEXT on the VM console (\\n for enter)
    vm-test.py destroy                      delete the VM and its disk

The VM has no guest agent and user-mode networking. Input goes in through qemu sendkey. State comes back as
beacons: every typed step ends in a curl to a host server (the guest's 10.0.2.2 is host loopback), which also
serves archinstall.json and receives the log tarball. Only prompts the guest cannot beacon (LUKS, sudo,
install.sh questions) are read off the screen with tesseract. Install choices and passwords: archinstall.json.
"""

import argparse
import http.server
import json
import os
import queue
import shutil
import subprocess
import sys
import tarfile
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG = HERE / "archinstall.json"
REPO_URL = "https://github.com/lsck0/arch-dotfiles.git"
CONNECT = "qemu:///system"      # gnome-boxes saves every session vm when it quits, which stalls a run
POOL = "default"
POOL_DIR = "/var/lib/libvirt/images"
ISO_VOLUME = "vm-test-archlinux.iso"
USER = "luca"
PORT = 8765                     # host loopback, the guest reaches it as 10.0.2.2
HOST = f"10.0.2.2:{PORT}"
POLL_S = 15
DISK_GIB = 200                  # archinstall.json sizes the root partition for exactly this disk
ARCHINSTALL_TIMEOUT_S = 3600
INSTALL_TIMEOUT_S = 12 * 3600   # install.sh builds a lot of AUR packages
BOOT_TIMEOUT_S = 300
LOGIN_ATTEMPTS = 3
SNAPSHOT_REF = "refs/vm-test/snapshot"
KEY_HOLD_MS = 10
KEY_GAP_S = 0.03            # a virsh call takes ~6ms, the guest console drops keys at that rate
MODIFIERS = ("shift", "shift_r", "ctrl", "ctrl_r", "alt", "alt_r")

# qemu key names per character: the iso console is us, the installed system de-latin1
KEYS_US = {' ': 'spc', '-': 'minus', '.': 'dot', '/': 'slash', ':': 'shift-semicolon', ';': 'semicolon',
           '$': 'shift-4', '(': 'shift-9', ')': 'shift-0', '*': 'shift-8', '_': 'shift-minus', '=': 'equal',
           '>': 'shift-dot', '<': 'shift-comma', "'": 'apostrophe', '"': 'shift-apostrophe', '\n': 'ret',
           ',': 'comma', '&': 'shift-7', '|': 'shift-backslash', '~': 'shift-grave_accent', '@': 'shift-2',
           '%': 'shift-5', '#': 'shift-3', '!': 'shift-1', '?': 'shift-slash', '\\': 'backslash', '+': 'shift-equal',
           '[': 'bracket_left', ']': 'bracket_right', '{': 'shift-bracket_left', '}': 'shift-bracket_right'}
KEYS_DE = {' ': 'spc', '-': 'slash', '.': 'dot', '/': 'shift-7', ':': 'shift-dot', ';': 'shift-comma',
           '$': 'shift-4', '(': 'shift-8', ')': 'shift-9', '*': 'shift-bracket_right', '_': 'shift-slash',
           '=': 'shift-0', '>': 'shift-less', '<': 'less', "'": 'shift-backslash', '"': 'shift-2', '\n': 'ret',
           ',': 'comma', '&': 'shift-6', '|': 'alt_r-less', '~': 'alt_r-bracket_right', '@': 'alt_r-q',
           '%': 'shift-5', '#': 'backslash', '!': 'shift-1', '?': 'shift-minus', '\\': 'alt_r-minus', '+': 'bracket_right',
           '[': 'alt_r-8', ']': 'alt_r-9', '{': 'alt_r-7', '}': 'alt_r-0'}


def virsh(*args: str, check: bool = True) -> str:
    return subprocess.run(["virsh", "-c", CONNECT, *args], check=check, capture_output=True, text=True).stdout


def cache_dir(name: str) -> Path:
    d = Path.home() / ".cache" / "vm-test" / name
    d.mkdir(parents=True, exist_ok=True)
    return d


# --- input ---

def key_for(ch: str, layout: str) -> str:
    table = KEYS_DE if layout == "de" else KEYS_US
    if ch in table:
        return table[ch]
    if ch.isdigit():
        return ch
    if ch.isascii() and ch.isalpha():
        if layout == "de":
            ch = {"y": "z", "z": "y", "Y": "Z", "Z": "Y"}.get(ch, ch)
        return ("shift-" if ch.isupper() else "") + ch.lower()
    sys.exit(f"vm-test: no key for {ch!r} on layout {layout}")


def type_text(name: str, text: str, layout: str) -> None:
    keys = [key_for(ch, layout) for ch in text]  # reject the whole string before typing half of it
    # the default 100ms hold outlasts one virsh call and keys overlap; without the gap the guest queue drops keys
    for k in keys:
        virsh("qemu-monitor-command", name, "--hmp", f"sendkey {k} {KEY_HOLD_MS}")
        time.sleep(KEY_GAP_S)
    for mod in MODIFIERS:
        virsh("qemu-monitor-command", name, "--hmp", f"sendkey {mod} {KEY_HOLD_MS}")


def clear_line(name: str) -> None:
    virsh("qemu-monitor-command", name, "--hmp", "sendkey ctrl-u")


# --- screen ---

def screen_text(name: str) -> str:
    ppm = cache_dir(name) / "screen.ppm"
    if subprocess.run(["virsh", "-c", CONNECT, "screenshot", name, str(ppm)], capture_output=True).returncode != 0:
        return ""
    return subprocess.run(["tesseract", str(ppm), "-"], capture_output=True, text=True).stdout


def wait_screen(name: str, needles: list[str], timeout_s: int) -> str:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        text = screen_text(name)
        for needle in needles:
            if needle in text:
                return needle
        time.sleep(POLL_S)
    sys.exit(f"vm-test: none of {needles} on screen after {timeout_s}s, see `vm-test.py shot`")


# --- host server: beacons, config, log upload ---

class Host:
    """GET /beacon/<tag> records tag, GET /step/<name> serves a step script, GET /<file> serves from vm-test/,
    PUT /logs.tgz stores the upload."""

    def __init__(self, upload_to: Path):
        self.beacons: queue.Queue[str] = queue.Queue()
        self.steps: dict[str, str] = {}
        self.files: dict[str, Path] = {}
        self.upload_to = upload_to
        self.uploaded = threading.Event()
        host = self

        class Handler(http.server.SimpleHTTPRequestHandler):
            def __init__(self, *a, **kw):
                super().__init__(*a, directory=str(HERE), **kw)

            def do_GET(self):
                if self.path.startswith("/beacon/"):
                    host.beacons.put(self.path.removeprefix("/beacon/"))
                    self.send_response(204)
                    self.end_headers()
                    return
                if self.path.startswith("/file/"):
                    path = host.files.get(self.path.removeprefix("/file/"))
                    if path is None:
                        self.send_error(404)
                        return
                    data = path.read_bytes()
                    self.send_response(200)
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                    return
                if self.path.startswith("/step/"):
                    body = host.steps.get(self.path.removeprefix("/step/"))
                    if body is None:
                        self.send_error(404)
                        return
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(body.encode())
                    return
                super().do_GET()

            def do_PUT(self):
                host.upload_to.write_bytes(self.rfile.read(int(self.headers.get("Content-Length", 0))))
                host.uploaded.set()
                self.send_response(204)
                self.end_headers()

            def log_message(self, *a):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def beacon(self, prefix: str, timeout_s: float) -> str | None:
        """Next beacon starting with prefix, dropping older unrelated ones; None on timeout."""
        deadline = time.time() + timeout_s
        while (left := deadline - time.time()) > 0:
            try:
                tag = self.beacons.get(timeout=left)
            except queue.Empty:
                return None
            if tag.startswith(prefix):
                return tag
        return None


def beacon_cmd(tag: str) -> str:
    return f"curl -s {HOST}/beacon/{tag}"


def run_step(name: str, host: Host, step: str, script: str, layout: str) -> None:
    """Serve script and type one short line that fetches and runs it; sendkey garbles long lines."""
    host.steps[step] = script
    type_text(name, f"curl -so /tmp/{step} {HOST}/step/{step} && bash /tmp/{step}\n", layout)


# --- steps ---

def pool_iso(iso: Path) -> str:
    """Upload the iso into the system pool, qemu there cannot read the home dir; returns the volume path."""
    if POOL not in virsh("pool-list", "--all", "--name").split():
        virsh("pool-define-as", POOL, "dir", "--target", POOL_DIR)
        virsh("pool-build", POOL)
        virsh("pool-autostart", POOL)
    if virsh("pool-info", POOL).find("running") == -1:
        virsh("pool-start", POOL)
    size = str(iso.stat().st_size)
    info = virsh("vol-info", "--pool", POOL, ISO_VOLUME, "--bytes", check=False)
    if size not in info:
        virsh("vol-delete", "--pool", POOL, ISO_VOLUME, check=False)
        virsh("vol-create-as", POOL, ISO_VOLUME, size, "--format", "raw")
        virsh("vol-upload", "--pool", POOL, ISO_VOLUME, str(iso))
    return virsh("vol-path", "--pool", POOL, ISO_VOLUME).strip()


def destroy(name: str) -> None:
    virsh("destroy", name, check=False)
    # only the disk: the shared iso volume stays for the next run
    virsh("undefine", name, "--nvram", "--storage", "vda", check=False)


def archinstall(name: str, iso: Path, host: Host) -> None:
    destroy(name)
    subprocess.run([
        "virt-install", "--connect", CONNECT, "--name", name, "--memory", "12288", "--vcpus", "8",
        "--cpu", "host-passthrough", "--disk", f"pool={POOL},size={DISK_GIB},format=qcow2,bus=virtio,discard=unmap",
        "--cdrom", pool_iso(iso), "--osinfo", "archlinux", "--network", "user,model=virtio",
        "--graphics", "spice", "--video", "virtio", "--noautoconsole",
        "--boot", "uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no",
    ], check=True, capture_output=True)

    wait_screen(name, ["root@archiso"], BOOT_TIMEOUT_S)
    run_step(name, host, "archinstall", f"curl -fsSo cfg.json {HOST}/{CONFIG.name}"
             f" && archinstall --config cfg.json --silent && {beacon_cmd('archinstall-ok')} || {beacon_cmd('archinstall-fail')}\n",
             "us")
    if host.beacon("archinstall-", ARCHINSTALL_TIMEOUT_S) != "archinstall-ok":
        sys.exit("vm-test: archinstall failed, see `vm-test.py shot`")

    # virt-install keeps the iso only for this first boot and turns the guest reboot into a power off
    type_text(name, "poweroff\n", "us")
    deadline = time.time() + BOOT_TIMEOUT_S
    while virsh("domstate", name, check=False).strip() != "shut off":
        if time.time() > deadline:
            sys.exit(f"vm-test: {name} did not power off")
        time.sleep(POLL_S)
    virsh("start", name)


def unlock_and_login(name: str, password: str, host: Host, reuse: bool) -> None:
    if reuse:
        clear_line(name)
        type_text(name, f"{beacon_cmd('shell')}\n", "de")
        if host.beacon("shell", 20):
            return
    if wait_screen(name, ["assphrase", "root volume", "login:"], BOOT_TIMEOUT_S) in ("assphrase", "root volume"):
        type_text(name, password + "\n", "de")
        wait_screen(name, ["login:"], BOOT_TIMEOUT_S)
    # getty clears the screen as it starts and drops input typed before that, hence the retries
    for attempt in range(LOGIN_ATTEMPTS):
        time.sleep(POLL_S)
        type_text(name, f"{USER}\n", "de")
        time.sleep(3)
        type_text(name, f"{password}\n", "de")
        time.sleep(5)
        type_text(name, f"{beacon_cmd(f'login-{attempt}')}\n", "de")
        if host.beacon(f"login-{attempt}", 30):
            return
    sys.exit(f"vm-test: login failed {LOGIN_ATTEMPTS} times, see `vm-test.py shot`")


def snapshot_bundle(name: str) -> Path:
    """Working tree (untracked included, .gitignore respected) as a commit bundle on top of origin/master."""
    repo = HERE.parent
    index = cache_dir(name) / "snapshot.index"
    index.unlink(missing_ok=True)
    env = {**os.environ, "GIT_INDEX_FILE": str(index)}
    git = lambda *a, **kw: subprocess.run(["git", "-C", str(repo), *a], check=True, capture_output=True, text=True, **kw).stdout.strip()
    git("fetch", "-q", "origin", "master")
    git("read-tree", "HEAD", env=env)
    git("add", "-A", env=env)
    commit = git("commit-tree", git("write-tree", env=env), "-p", "HEAD", "-m", "vm-test snapshot")
    git("update-ref", SNAPSHOT_REF, commit)
    bundle = cache_dir(name) / "snapshot.bundle"
    git("bundle", "create", str(bundle), SNAPSHOT_REF, "^origin/master")
    return bundle


def run_install(name: str, password: str, host: Host, bundle: Path | None) -> tuple[bool, int]:
    """Type the manual install steps, answer prompts until install.sh ends; (succeeded, sudo prompts answered)."""
    checkout = ""
    if bundle is not None:
        host.files["snapshot.bundle"] = bundle
        checkout = (f" && curl -so /tmp/snapshot.bundle {HOST}/file/snapshot.bundle"
                    f" && git fetch -q /tmp/snapshot.bundle {SNAPSHOT_REF} && git checkout -q FETCH_HEAD")
    # a no-op reboot keeps the vm up after a successful run so its logs can be pulled
    run_step(name, host, "install", f"""mkdir -p ~/projects ~/.vm-test
printf '#!/bin/sh\\n{beacon_cmd('install-ok')}\\n' > ~/.vm-test/reboot
chmod +x ~/.vm-test/reboot
cd ~/projects && git clone {REPO_URL} && cd arch-dotfiles{checkout} && PATH=~/.vm-test:$PATH ./install.sh
{beacon_cmd('install-exit')}
""", "de")
    deadline = time.time() + INSTALL_TIMEOUT_S
    answered = ""  # tail of the screen we last answered, so a prompt still showing is not answered twice
    sudo_prompts = 0
    pending = ""  # prompt screen seen once, answered only if the next poll still shows it
    while time.time() < deadline:
        tag = host.beacon("install-", POLL_S)
        if tag == "install-ok":
            return True, sudo_prompts
        if tag == "install-exit":
            return False, sudo_prompts
        lines = [line.rstrip(" _") for line in screen_text(name).splitlines() if line.strip(" _")]
        text = "\n".join(lines[-3:])
        if text == answered:
            continue
        line = lines[-1] if lines else ""
        # tesseract reads "password" as "passuord", the user name survives; parallel builds can print past the prompt
        if any(f"for {USER}" in tail_line for tail_line in lines[-3:]):
            # a sudo without a readable tty prints the prompt and fails at once; only one still waiting blocks a human
            if text != pending:
                pending = text
                continue
            type_text(name, password + "\n", "de")
            answered = text
            sudo_prompts += 1
            print(f"vm-test: sudo prompt {sudo_prompts} answered", flush=True)
        elif "Numbers to exclude" in line or "Bootloader (limine/grub)" in line or "[Y/n]" in line:
            type_text(name, "\n", "de")
            answered = text
    sys.exit(f"vm-test: install.sh still running after {INSTALL_TIMEOUT_S}s")


def pull_logs(name: str, host: Host) -> Path:
    out = cache_dir(name)
    tgz = out / "logs.tgz"
    tgz.unlink(missing_ok=True)
    host.upload_to = tgz
    host.uploaded.clear()
    clear_line(name)
    run_step(name, host, "logs", "cd ~/projects/arch-dotfiles && sudo -n journalctl -b --no-pager -o short-iso -t sudo > sudo-journal.log;"
             " tar czf /tmp/vm-test-logs.tgz install.log $(ls FAILURES 2>/dev/null) $(find . -name '*.log');"
             f" curl -sT /tmp/vm-test-logs.tgz {HOST}/logs.tgz\n", "de")
    if not host.uploaded.wait(timeout=120):
        sys.exit("vm-test: no log upload arrived, see `vm-test.py shot`")
    shutil.rmtree(out / "logs", ignore_errors=True)
    with tarfile.open(tgz) as tar:
        tar.extractall(out / "logs", filter="data")
    return out / "logs"


# --- commands ---

def cmd_run(args: argparse.Namespace) -> None:
    for tool in ("virt-install", "virsh", "tesseract", "magick"):
        if not shutil.which(tool):
            sys.exit(f"vm-test: {tool} missing")
    if not args.reuse and not args.iso.is_file():
        sys.exit(f"vm-test: no iso at {args.iso}")
    password = json.loads(CONFIG.read_text())["encryption_password"]
    name = args.name
    host = Host(cache_dir(name) / "logs.tgz")

    if not args.reuse:
        archinstall(name, args.iso, host)
    unlock_and_login(name, password, host, args.reuse)
    ok, sudo_prompts = run_install(name, password, host, None if args.master else snapshot_bundle(name))
    logs = pull_logs(name, host)
    print(f"vm-test: logs in {logs}")
    # a human types the sudo password once and walks away; a second prompt would hang the real install
    if sudo_prompts > 1:
        print(f"vm-test: install.sh asked for the sudo password {sudo_prompts} times, expected once")
        ok = False

    failures = logs / "FAILURES"
    if not ok or (failures.exists() and failures.read_text().strip()):
        print(failures.read_text() if failures.exists() else "install.sh aborted, see install.log", end="")
        sys.exit(1)

    type_text(name, f"echo {password} | sudo -S reboot\n", "de")
    wait_screen(name, ["assphrase", "root volume"], BOOT_TIMEOUT_S)
    type_text(name, password + "\n", "de")
    time.sleep(BOOT_TIMEOUT_S // 5)
    print(cmd_shot(args))
    print("vm-test: install succeeded, the screenshot shows the first boot")


def cmd_logs(args: argparse.Namespace) -> None:
    logs = pull_logs(args.name, Host(cache_dir(args.name) / "logs.tgz"))
    print(logs)
    if (logs / "FAILURES").exists():
        print((logs / "FAILURES").read_text(), end="")


def cmd_shot(args: argparse.Namespace) -> Path:
    out = cache_dir(args.name)
    virsh("screenshot", args.name, str(out / "screen.ppm"))
    subprocess.run(["magick", str(out / "screen.ppm"), str(out / "screen.png")], check=True)
    return out / "screen.png"


def cmd_type(args: argparse.Namespace) -> None:
    type_text(args.name, args.text.encode().decode("unicode_escape"), args.layout)


def cmd_destroy(args: argparse.Namespace) -> None:
    destroy(args.name)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--name", default="archlinux-test")
    sub = parser.add_subparsers(dest="cmd", required=True)
    run = sub.add_parser("run", parents=[common])
    run.add_argument("--iso", type=Path, default=Path.home() / "downloads" / "archlinux-x86_64.iso")
    run.add_argument("--reuse", action="store_true", help="skip archinstall, continue on the installed vm")
    run.add_argument("--master", action="store_true", help="test github master instead of the local working tree")
    sub.add_parser("logs", parents=[common])
    sub.add_parser("shot", parents=[common])
    typ = sub.add_parser("type", parents=[common])
    typ.add_argument("text")
    typ.add_argument("--layout", choices=["de", "us"], default="de")
    sub.add_parser("destroy", parents=[common])
    args = parser.parse_args()
    if args.cmd == "shot":
        print(cmd_shot(args))
        return
    {"run": cmd_run, "logs": cmd_logs, "type": cmd_type, "destroy": cmd_destroy}[args.cmd](args)


if __name__ == "__main__":
    main()
