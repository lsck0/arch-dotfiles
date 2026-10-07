#!/usr/bin/env bash
# from omarchy-shell, cache dir moved to ~/.cache/quickshell
# usage: list.sh <wallpaper-list.py> [WxH]; prints "<image>\t<thumbnail or image>" per wallpaper eligible for that screen

wallpaper_list=${1:?usage: list.sh <wallpaper-list.py> [WxH]}
screen=${2:-}
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/image-selector
index_file="$cache_dir/index.tsv"

mkdir -p "$cache_dir"

# eligibility and the secrets shadowing live in wallpaper-list.py alone; nothing listed when it fails
images=$("$wallpaper_list" ${screen:+--screen "$screen"}) || exit 1

python3 - "$cache_dir" "$index_file" "$images" <<'PY' || true
import hashlib, os, sys, signal
# the consumer may close the pipe early
signal.signal(signal.SIGPIPE, signal.SIG_DFL)
cache_dir, index_file, images = sys.argv[1], sys.argv[2], sys.argv[3]

# index keeps thumbnails stable across runs
index = {}
try:
    with open(index_file) as fh:
        for line in fh:
            parts = line.rstrip('\n').split('\t')
            if len(parts) >= 3:
                index[(parts[0], parts[1])] = parts[2]
except OSError:
    pass

for image in images.splitlines():
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

# thumbnails generated after listing, detached, so opening never waits
if command -v vipsthumbnail >/dev/null 2>&1; then
  (
    while IFS= read -r image; do
      [[ -n $image ]] || continue
      signature=$(stat -Lc '%s:%Y' "$image") || continue
      hash=$(printf '%s\t%s' "$image" "$signature" | md5sum | cut -d ' ' -f 1)
      thumb="$cache_dir/$hash.jpg"
      [[ -f $thumb ]] && continue
      vipsthumbnail "$image" --size 800x800 -o "$thumb[Q=88]" >/dev/null 2>&1 \
        && printf '%s\t%s\t%s\n' "$image" "$signature" "$hash" >>"$index_file"
    done <<<"$images"
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi
