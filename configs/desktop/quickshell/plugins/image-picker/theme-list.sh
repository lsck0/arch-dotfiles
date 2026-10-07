#!/usr/bin/env bash
# lists theme wallpapers for image-picker's themes mode
# usage: theme-list.sh <theme-dir> <wallpaper-list.py>; prints "<image>\t<thumbnail or image>\t<theme>"

theme_dir=${1:-}
wallpaper_list=${2:?usage: theme-list.sh <theme-dir> <wallpaper-list.py>}
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/image-selector
index_file="$cache_dir/index.tsv"

mkdir -p "$cache_dir"

rows=$(python3 - "$cache_dir" "$index_file" "$theme_dir" "$wallpaper_list" <<'PY'
import hashlib, importlib.util, json, os, sys
cache_dir, index_file, theme_dir, wallpaper_list = sys.argv[1:5]

# themes name their wallpaper by file name; one in-process resolver, not one process per theme
sys.dont_write_bytecode = True  # no __pycache__ in the repo's scripts/
spec = importlib.util.spec_from_file_location("wallpaper_list", wallpaper_list)
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)

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

# (wallpaper, theme name) pairs, first theme to claim a wallpaper wins
files = []
seen = set()
for name in sorted(os.listdir(theme_dir)):
    if not name.endswith('.json'):
        continue
    try:
        with open(os.path.join(theme_dir, name)) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        continue
    wallpaper = data.get('wallpaper')
    if not isinstance(wallpaper, str) or not wallpaper or '/' in wallpaper:
        continue
    wallpaper = resolver.resolve(wallpaper)
    if not wallpaper or wallpaper in seen:
        continue
    seen.add(wallpaper)
    files.append((str(wallpaper), name[:-len('.json')]))

for image, theme_name in files:
    try:
        st = os.stat(image)
    except OSError:
        continue
    sig = f"{st.st_size}:{int(st.st_mtime)}"
    h = index.get((image, sig)) or hashlib.md5(f"{image}\t{sig}".encode()).hexdigest()
    thumb = os.path.join(cache_dir, h + '.jpg')
    print(f"{image}\t{thumb if os.path.exists(thumb) else image}\t{theme_name}")
PY
) || exit 1
[[ -n $rows ]] && printf '%s\n' "$rows"

# thumbnails generated after listing, detached
if command -v vipsthumbnail >/dev/null 2>&1; then
  (
    while IFS=$'\t' read -r wp _; do
      [[ -f "$wp" ]] || continue
      signature=$(stat -Lc '%s:%Y' "$wp") || continue
      hash=$(printf '%s\t%s' "$wp" "$signature" | md5sum | cut -d ' ' -f 1)
      thumb="$cache_dir/$hash.jpg"
      [[ -f $thumb ]] && continue
      vipsthumbnail "$wp" --size 800x800 -o "$thumb[Q=88]" >/dev/null 2>&1 \
        && printf '%s\t%s\t%s\n' "$wp" "$signature" "$hash" >>"$index_file"
    done <<<"$rows"
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi
