#!/bin/bash
# Lists premade-theme wallpapers for image-picker's Themes mode (mode 1).
#
# Sourced from each themes/*.json's own "wallpaper" field — the JSON is
# authoritative, not the filename. Theme wallpapers point directly at their
# source image in wallpapers/ (no separate themes/wallpapers/ copy). Same
# tsv contract as list.sh ("<image>\t<thumbnail-or-original>" per line) so
# ImagePickerModel.loadRows needs no changes, and the same thumbnail cache
# dir/index so a file already thumbnailed via list.sh (or vice versa) is
# never redecoded.

theme_dir=${1:-}
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/image-selector
index_file="$cache_dir/index.tsv"

mkdir -p "$cache_dir"

python3 - "$cache_dir" "$index_file" "$theme_dir" <<'PY' || true
import hashlib, json, os, sys, signal
signal.signal(signal.SIGPIPE, signal.SIG_DFL)
cache_dir, index_file, theme_dir = sys.argv[1], sys.argv[2], sys.argv[3]

index = {}
try:
    with open(index_file) as fh:
        for line in fh:
            parts = line.rstrip('\n').split('\t')
            if len(parts) >= 3:
                index[(parts[0], parts[1])] = parts[2]
except OSError:
    pass

if not os.path.isdir(theme_dir):
    sys.exit(0)

files = []
for name in sorted(os.listdir(theme_dir)):
    if not name.endswith('.json'):
        continue
    try:
        with open(os.path.join(theme_dir, name)) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        continue
    wallpaper = data.get('wallpaper')
    if not wallpaper:
        continue
    wallpaper = os.path.realpath(os.path.expanduser(wallpaper))
    if os.path.isfile(wallpaper) and wallpaper not in files:
        files.append(wallpaper)

for image in files:
    try:
        st = os.stat(image)
    except OSError:
        continue
    sig = f"{st.st_size}:{int(st.st_mtime)}"
    h = index.get((image, sig)) or hashlib.md5(f"{image}\t{sig}".encode()).hexdigest()
    thumb = os.path.join(cache_dir, h + '.jpg')
    sys.stdout.write(f"{image}\t{thumb if os.path.exists(thumb) else image}\n")
    sys.stdout.flush()
PY

# Generate any missing thumbnails after the listing, detached — mirrors
# list.sh's own background pass so the picker never waits on vipsthumbnail.
if command -v vipsthumbnail >/dev/null 2>&1; then
  (
    python3 -c '
import json, os, sys
theme_dir = sys.argv[1]
if os.path.isdir(theme_dir):
    for name in sorted(os.listdir(theme_dir)):
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(theme_dir, name)) as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            continue
        wallpaper = data.get("wallpaper")
        if wallpaper:
            print(os.path.realpath(os.path.expanduser(wallpaper)))
' "$theme_dir" | while IFS= read -r wp; do
      [[ -f "$wp" ]] || continue
      signature=$(stat -Lc '%s:%Y' "$wp") || continue
      hash=$(printf '%s\t%s' "$wp" "$signature" | md5sum | cut -d ' ' -f 1)
      thumb="$cache_dir/$hash.jpg"
      [[ -f $thumb ]] && continue
      vipsthumbnail "$wp" --size 800x800 -o "$thumb[Q=88]" >/dev/null 2>&1 \
        && printf '%s\t%s\t%s\n' "$wp" "$signature" "$hash" >>"$index_file"
    done
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi
