#!/usr/bin/env python3
"""End-to-end test of the dotfiles: bootstrap from a bare Arch ISO in a system libvirt VM, then the chain.

    test.py [run] [--iso PATH] [--master] [--platform NAME]
                                            fresh VM with Secure Boot in Setup Mode, boots the iso and runs
                                            bootstrap.sh like a human would, then waits while stage.sh runs
                                            install.sh and config.sh on their own boots. Once the chain has
                                            disarmed: unlock, log in on tty3, verify, pull logs, exit 1 on
                                            failures. Tests the local working tree (snapshot bundle) unless --master
    test.py logs                            pull the stage logs, FAILURES.* and every *.log to ~/.cache/vm-test/<name>/logs
    test.py shot                            screenshot to ~/.cache/vm-test/<name>/screen.png
    test.py type TEXT                       type TEXT on the VM console (\\n for enter)
    test.py destroy                         delete the VM and its disk

The VM has no guest agent and user-mode networking. Input goes in through qemu sendkey. State comes back as
beacons: every typed step ends in a curl to a host server (the guest's 10.0.2.2 is host loopback), which also
serves the snapshot bundle and receives the log tarball. The chain itself runs unattended, so the only screen
reads (tesseract) are the iso prompt, the passphrase prompt that marks the end of the chain, and logins.
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
REPO_URL = "https://github.com/lsck0/arch-dotfiles.git"
CONNECT = "qemu:///system"      # gnome-boxes saves every session vm when it quits, which stalls a run
POOL = "default"
POOL_DIR = "/var/lib/libvirt/images"
ISO_VOLUME = "vm-test-archlinux.iso"
USER = "luca"
PASSWORD = "admin"              # BOOTSTRAP_PASSWORD, LUKS and user alike
PLATFORM = "test-vm"            # platforms/test-vm.sh, HOSTNAME=test-vm
DISK = "/dev/vda"
PORT = 8765                     # host loopback, the guest reaches it as 10.0.2.2
HOST = f"10.0.2.2:{PORT}"
POLL_S = 15
DISK_GIB = 200
BOOTSTRAP_TIMEOUT_S = 3600
CHAIN_TIMEOUT_S = 12 * 3600     # install.sh plus config.sh, longer when the mirror is down and everything compiles
BOOT_TIMEOUT_S = 300
LOGIN_ATTEMPTS = 3
LOGIN_TTY = 3                   # tty1 carries the chain's console, ly sits on tty2
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
    sys.exit(f"vm-test: none of {needles} on screen after {timeout_s}s, see `test.py shot`")


# --- host server: beacons, config, log upload ---

class Host:
    """GET /beacon/<tag> records tag, GET /step/<name> serves a step script, GET /<file> serves from the repo root,
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


def snapshot_bundle(name: str) -> Path:
    """Working tree (untracked included, .gitignore respected) as a commit bundle on top of origin/master."""
    repo = HERE
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


def bootstrap(name: str, iso: Path, host: Host, bundle: Path | None, platform: str, user: str) -> None:
    """Fresh VM, Secure Boot firmware without enrolled keys (Setup Mode), bootstrap.sh from the iso."""
    destroy(name)
    subprocess.run([
        "virt-install", "--connect", CONNECT, "--name", name, "--memory", "12288", "--vcpus", "8",
        "--cpu", "host-passthrough", "--disk", f"pool={POOL},size={DISK_GIB},format=qcow2,bus=virtio,discard=unmap",
        "--cdrom", pool_iso(iso), "--osinfo", "archlinux", "--network", "user,model=virtio",
        "--graphics", "spice", "--video", "virtio", "--noautoconsole", "--features", "smm.state=on",
        "--boot", "uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,"
                  "firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=no",
    ], check=True, capture_output=True)

    wait_screen(name, ["root@archiso"], BOOT_TIMEOUT_S)
    checkout = ""
    if bundle is not None:
        host.files["snapshot.bundle"] = bundle
        checkout = (f" && curl -so /tmp/snapshot.bundle {HOST}/file/snapshot.bundle"
                    f" && git fetch -q /tmp/snapshot.bundle {SNAPSHOT_REF} && git checkout -q FETCH_HEAD")
    # success ends in bootstrap.sh's reboot, which virt-install turns into a power off on this first boot
    host.upload_to = cache_dir(name) / "bootstrap.log"
    run_step(name, host, "bootstrap", f"""set -o pipefail
pacman -Sy --noconfirm --needed git
cd /tmp && git clone {REPO_URL} && cd arch-dotfiles{checkout} \\
    && BOOTSTRAP_DISK={DISK} BOOTSTRAP_PASSWORD={PASSWORD} BOOTSTRAP_USERNAME={user} BOOTSTRAP_ASSUME_YES=1 ./bootstrap.sh {platform} 2>&1 \\
    | tee /tmp/bootstrap.log \\
    || {{ curl -sT /tmp/bootstrap.log {HOST}/bootstrap.log; {beacon_cmd('bootstrap-fail')}; }}
""", "us")
    deadline = time.time() + BOOTSTRAP_TIMEOUT_S
    while virsh("domstate", name, check=False).strip() != "shut off":
        if host.beacon("bootstrap-fail", POLL_S):
            sys.exit(f"vm-test: bootstrap.sh failed, see {host.upload_to}")
        if time.time() > deadline:
            sys.exit(f"vm-test: bootstrap.sh still running after {BOOTSTRAP_TIMEOUT_S}s")
    virsh("start", name)


def await_chain(name: str) -> None:
    """The chain boots without a passphrase; the first prompt is the boot after stage.sh disarmed."""
    start = time.time()
    wait_screen(name, ["assphrase", "root volume"], CHAIN_TIMEOUT_S)
    print(f"vm-test: chain done after {(time.time() - start) / 3600:.1f}h", flush=True)
    type_text(name, PASSWORD + "\n", "de")


def login_tty(name: str, host: Host, user: str) -> None:
    # getty clears the screen as it starts and drops input typed before that, hence the retries
    for attempt in range(LOGIN_ATTEMPTS):
        time.sleep(POLL_S)
        virsh("qemu-monitor-command", name, "--hmp", f"sendkey ctrl-alt-f{LOGIN_TTY}")
        time.sleep(3)
        type_text(name, f"{user}\n", "de")
        time.sleep(3)
        type_text(name, f"{PASSWORD}\n", "de")
        time.sleep(5)
        type_text(name, f"{beacon_cmd(f'login-{attempt}')}\n", "de")
        if host.beacon(f"login-{attempt}", 30):
            return
    sys.exit(f"vm-test: login failed {LOGIN_ATTEMPTS} times, see `test.py shot`")


def pull_logs(name: str, host: Host) -> Path:
    """Stage logs plus the chain's end state as verify.log key=value lines; needs a shell on the guest."""
    out = cache_dir(name)
    tgz = out / "logs.tgz"
    tgz.unlink(missing_ok=True)
    host.upload_to = tgz
    host.uploaded.clear()
    clear_line(name)
    run_step(name, host, "logs", f"""cd ~/projects/arch-dotfiles
sudo -k
{{
    echo "stage_armed=$(test -e /var/lib/dotfiles-stage/next && echo yes || echo no)"
    echo "sudo_passwordless=$(sudo -n true 2>/dev/null && echo yes || echo no)"
    echo "keyfile_present=$(test -e /etc/cryptsetup-keys.d/root.key && echo yes || echo no)"
    echo "luks_keyslots=$(echo {PASSWORD} | sudo -S cryptsetup luksDump {DISK}2 2>/dev/null | grep -cE '^  [0-9]+: luks2')"
    echo "secure_boot=$(od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c | awk '{{print $NF}}')"
}} > verify.log
cp /var/lib/dotfiles-stage/log stage.log
echo {PASSWORD} | sudo -S journalctl -u dotfiles-stage.service --no-pager -o short-iso > stage-journal.log
tar czf /tmp/vm-test-logs.tgz $(ls FAILURES.* 2>/dev/null) $(find . -name '*.log')
curl -sT /tmp/vm-test-logs.tgz {HOST}/logs.tgz
""", "de")
    if not host.uploaded.wait(timeout=120):
        sys.exit("vm-test: no log upload arrived, see `test.py shot`")
    shutil.rmtree(out / "logs", ignore_errors=True)
    with tarfile.open(tgz) as tar:
        tar.extractall(out / "logs", filter="data")
    return out / "logs"


# the chain's end state, anything else means stage.sh left the machine armed or half set up
EXPECTED = {"stage_armed": "no", "sudo_passwordless": "no", "keyfile_present": "no", "luks_keyslots": "1",
            "secure_boot": "1"}


def verify(logs: Path) -> list[str]:
    problems = []
    state = dict(line.split("=", 1) for line in (logs / "verify.log").read_text().splitlines() if "=" in line)
    for key, want in EXPECTED.items():
        if state.get(key) != want:
            problems.append(f"{key}={state.get(key)}, expected {want}")
    for failures in sorted(logs.glob("FAILURES.*")):
        if failures.read_text().strip():
            problems.append(f"{failures.name}:\n{failures.read_text().rstrip()}")
    stage_log = (logs / "stage.log").read_text() if (logs / "stage.log").exists() else ""
    for stage in ("install", "config"):
        if f"{stage}: ok" not in stage_log:
            problems.append(f"stage {stage} did not finish ok, see {stage}.log")
    return problems


def lint_modules() -> list[str]:
    """static module checks, all fatal. a PKG_GROUPS entry, a dependencies.txt line or a ../../<x>/ ref
    must name a real module or (for refs) a repo-root dir, so a typo or dropped module is caught. a
    module's config reaching into another module (not base, not itself) must declare it in that module's
    dependencies.txt, so unexpected coupling (programming needing gaming) cannot slip in undeclared."""
    import re
    configs, root = HERE / "configs", {"scripts", "skills", "platforms", "wallpapers", "patches"}
    modules = {p.parent.name for p in configs.glob("*/packages.txt")}
    names = lambda f: [ln.split("#", 1)[0].split()[0] for ln in f.read_text().splitlines() if ln.split("#", 1)[0].strip()]
    deps = {m: set(names(configs / m / "dependencies.txt")) for m in modules if (configs / m / "dependencies.txt").is_file()}
    ref = re.compile(r"\.\./\.\./([a-z0-9_-]+)/")
    problems = []
    for m, ds in deps.items():
        for d in ds - modules:
            problems.append(f"configs/{m}/dependencies.txt: '{d}' is not a module")
    for name in ("link.sh", "link.py", "common.sh"):
        for script in configs.rglob(name):
            src = script.relative_to(configs).parts[0]
            for tgt in ref.findall(script.read_text(errors="ignore")):
                if tgt in modules:
                    if tgt not in (src, "base") and tgt not in deps.get(src, set()):
                        problems.append(f"{script.relative_to(HERE)}: undeclared dep on '{tgt}', add it to configs/{src}/dependencies.txt")
                elif tgt not in root:
                    problems.append(f"{script.relative_to(HERE)}: ../../{tgt}/ is no module or root dir")
    for pf in (HERE / "platforms").glob("*.sh"):
        for grp in re.findall(r"PKG_GROUPS=\(([^)]*)\)", pf.read_text()):
            for g in grp.split():
                if g not in modules:
                    problems.append(f"{pf.relative_to(HERE)}: PKG_GROUPS has '{g}', not a module")
    return problems


# --- commands ---

def cmd_lint(args: argparse.Namespace) -> None:
    problems = lint_modules()
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print("vm-test: modules lint clean")


def cmd_run(args: argparse.Namespace) -> None:
    if (problems := lint_modules()):
        sys.exit("\n".join(problems))
    for tool in ("virt-install", "virsh", "tesseract", "magick"):
        if not shutil.which(tool):
            sys.exit(f"vm-test: {tool} missing")
    if not args.iso.is_file():
        sys.exit(f"vm-test: no iso at {args.iso}")
    name = args.name
    host = Host(cache_dir(name) / "logs.tgz")

    bootstrap(name, args.iso, host, None if args.master else snapshot_bundle(name), args.platform, args.user)
    await_chain(name)
    login_tty(name, host, args.user)
    logs = pull_logs(name, host)
    print(f"vm-test: logs in {logs}")
    problems = verify(logs)
    virsh("qemu-monitor-command", name, "--hmp", "sendkey ctrl-alt-f2")
    time.sleep(5)
    print(cmd_shot(args))
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print("vm-test: chain succeeded, the screenshot shows the login manager")


def cmd_logs(args: argparse.Namespace) -> None:
    logs = pull_logs(args.name, Host(cache_dir(args.name) / "logs.tgz"))
    print(logs)
    print("\n".join(verify(logs)))


def cmd_shot(args: argparse.Namespace) -> Path:
    out = cache_dir(args.name)
    virsh("screenshot", args.name, str(out / "screen.ppm"))
    subprocess.run(["magick", str(out / "screen.ppm"), str(out / "screen.png")], check=True)
    return out / "screen.png"


def cmd_type(args: argparse.Namespace) -> None:
    type_text(args.name, args.text.encode().decode("unicode_escape"), args.layout)


def cmd_destroy(args: argparse.Namespace) -> None:
    destroy(args.name)


SUBCOMMANDS = ("run", "logs", "shot", "type", "destroy", "lint")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--name", default="archlinux-test")
    sub = parser.add_subparsers(dest="cmd", required=True)
    run = sub.add_parser("run", parents=[common])
    run.add_argument("--iso", type=Path, default=Path.home() / "downloads" / "archlinux-x86_64.iso")
    run.add_argument("--platform", default=PLATFORM, help="platforms/<name>.sh for bootstrap.sh")
    run.add_argument("--user", default=USER, help="BOOTSTRAP_USERNAME; non-luca exercises the guest path")
    run.add_argument("--master", action="store_true", help="test github master instead of the local working tree")
    sub.add_parser("logs", parents=[common])
    sub.add_parser("shot", parents=[common])
    typ = sub.add_parser("type", parents=[common])
    typ.add_argument("text")
    typ.add_argument("--layout", choices=["de", "us"], default="de")
    sub.add_parser("destroy", parents=[common])
    sub.add_parser("lint", parents=[common])
    # run is the default, so ./test.py and ./test.py run behave alike
    argv = sys.argv[1:]
    if not argv or (argv[0] not in SUBCOMMANDS and argv[0] not in ("-h", "--help")):
        argv = ["run", *argv]
    args = parser.parse_args(argv)
    if args.cmd == "shot":
        print(cmd_shot(args))
        return
    {"run": cmd_run, "logs": cmd_logs, "type": cmd_type, "destroy": cmd_destroy, "lint": cmd_lint}[args.cmd](args)


if __name__ == "__main__":
    main()
