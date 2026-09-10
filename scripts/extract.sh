#!/usr/bin/env bash
# Safely extract a supported archive into a same-named directory.
set -euo pipefail

usage() { printf 'usage: %s ARCHIVE [DESTINATION]\n' "$0" >&2; exit 2; }
[[ $# -ge 1 && $# -le 2 ]] || usage
archive=$(readlink -f -- "$1")
[[ -f "$archive" ]] || { printf 'not a regular file: %s\n' "$1" >&2; exit 1; }

base=$(basename -- "$archive")
base=${base%.tar.gz}; base=${base%.tar.bz2}; base=${base%.tar.xz}; base=${base%.tar.zst}
base=${base%.[Tt][Gg][Zz]}; base=${base%.[Bb][Zz]2}; base=${base%.[Xx][Zz]}; base=${base%.[Zz][Ss][Tt]}
base=${base%.*}
dest_root=$(readlink -f -- "${2:-$PWD}")
dest="$dest_root/$base"
[[ ! -e "$dest" ]] || { printf 'destination already exists: %s\n' "$dest" >&2; exit 1; }

stage=$(mktemp -d "${TMPDIR:-/tmp}/extract.XXXXXX")
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT

# Python performs the complete preflight for tar/zip: reject traversal,
# links, excessive entries, and excessive declared expansion before extraction.
python3 - "$archive" "$stage" <<'PY'
import os, sys, tarfile, zipfile
p, stage = sys.argv[1:]
MAX_ENTRIES, MAX_TOTAL, MAX_FILE = 200000, 10 * 1024**3, 2 * 1024**3

def safe(n):
    n = n.replace('\\', '/')
    return n and not n.startswith('/') and not any(x == '..' for x in n.split('/'))

def check(names):
    if len(names) > MAX_ENTRIES: raise SystemExit('archive has too many entries')
    total = 0
    for n, size, link in names:
        if not safe(n) or (link and not safe(link)):
            raise SystemExit('unsafe archive path or link: ' + n)
        if size < 0 or size > MAX_FILE or total + size > MAX_TOTAL:
            raise SystemExit('archive expansion exceeds safety limit')
        if link: raise SystemExit('links are not allowed in archives: ' + n)
        total += size

try:
    if zipfile.is_zipfile(p):
        with zipfile.ZipFile(p) as z:
            check([(i.filename, i.file_size, '') for i in z.infolist()])
    elif tarfile.is_tarfile(p):
        with tarfile.open(p, 'r:*') as t:
            check([(m.name, m.size if m.isfile() else 0, m.linkname if m.issym() or m.islnk() else '') for m in t.getmembers()])
    else:
        raise ValueError
except (ValueError, tarfile.ReadError, zipfile.BadZipFile):
    # 7z/rar are preflighted by the shell's 7z listing below.
    pass
PY

if python3 - "$archive" "$stage" <<'PY'
import sys, zipfile, tarfile
p=sys.argv[1]
print('zip' if zipfile.is_zipfile(p) else ('tar' if tarfile.is_tarfile(p) else 'other'))
PY
then :; fi
kind=$(python3 - "$archive" <<'PY'
import sys, zipfile, tarfile
p=sys.argv[1]
print('zip' if zipfile.is_zipfile(p) else ('tar' if tarfile.is_tarfile(p) else 'other'))
PY
)
case "$kind" in
  zip) python3 - "$archive" "$stage" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z: z.extractall(sys.argv[2])
PY
    ;;
  tar) tar --extract --file "$archive" --directory "$stage" --no-same-owner --no-same-permissions ;;
  *)
    command -v 7z >/dev/null || { printf 'unsupported archive (install 7z): %s\n' "$archive" >&2; exit 1; }
    listing=$(7z l -slt -- "$archive")
    python3 - "$listing" <<'PY'
import sys, re
s=sys.argv[1]
size=sum(int(x) for x in re.findall(r'^Size = (\d+)$', s, re.M))
entries=len(re.findall(r'^Path = ', s, re.M))
if entries > 200000 or size > 10*1024**3: raise SystemExit('archive expansion exceeds safety limit')
for path in re.findall(r'^Path = (.*)$', s, re.M):
    path=path.replace('\\','/')
    if path.startswith('/') or '..' in path.split('/'):
        raise SystemExit('unsafe archive path: '+path)
PY
    7z x -y -o"$stage" -- "$archive" >/dev/null
    ;;
esac

mkdir -p -- "$dest"
shopt -s dotglob nullglob
entries=("$stage"/*)
if (( ${#entries[@]} == 1 )) && [[ -d ${entries[0]} ]]; then
    # A single archive root is already the requested destination root.
    mv -- "${entries[0]}"/* "$dest"/ 2>/dev/null || true
else
    ((${#entries[@]})) && mv -- "${entries[@]}" "$dest"/
fi
printf '%s\n' "$dest"
