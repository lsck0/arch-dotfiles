#!/bin/bash
# Verbatim from omarchy-shell except cache dir `~/.cache/omarchy/image-selector` -> `~/.cache/quickshell/image-selector`.

image_dirs=${1:-}
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/image-selector
index_file="$cache_dir/index.tsv"

mkdir -p "$cache_dir"

# Was: for every image WITHOUT a cached thumbnail, md5sum the entire file to look for a "legacy" thumbnail keyed by content hash.
python3 - "$cache_dir" "$index_file" "$image_dirs" <<'PY' || true
import hashlib, os, sys, signal
# The consumer may close the pipe early (a `head`, or the picker being
# dismissed mid-scan); die quietly rather than dumping a BrokenPipeError.
signal.signal(signal.SIGPIPE, signal.SIG_DFL)
cache_dir, index_file, image_dirs = sys.argv[1], sys.argv[2], sys.argv[3]
EXT = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'}

# The index maps path+signature -> hash, so an unchanged file keeps its
# thumbnail across runs even though the hash is derived, not stored per file.
index = {}
try:
    with open(index_file) as fh:
        for line in fh:
            parts = line.rstrip('\n').split('\t')
            if len(parts) >= 3:
                index[(parts[0], parts[1])] = parts[2]
except OSError:
    pass

files = []
for d in image_dirs.splitlines():
    d = d.strip()
    if not d or not os.path.isdir(d):
        continue
    for name in os.listdir(d):
        if os.path.splitext(name)[1].lower() in EXT:
            full = os.path.join(d, name)
            if os.path.isfile(full):
                files.append(full)

for image in sorted(files):
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

# Generate any missing thumbnails AFTER the listing is complete, detached, so it never delays the picker opening.
if command -v vipsthumbnail >/dev/null 2>&1; then
  (
    while IFS= read -r dir; do
      [[ -n $dir && -d $dir ]] || continue
      find -L "$dir" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \) \
        -print0 2>/dev/null
    done <<<"$image_dirs" | while IFS= read -r -d '' image; do
      signature=$(stat -Lc '%s:%Y' "$image") || continue
      hash=$(printf '%s\t%s' "$image" "$signature" | md5sum | cut -d ' ' -f 1)
      thumb="$cache_dir/$hash.jpg"
      [[ -f $thumb ]] && continue
      # 800px / Q=88, not 400px / Q=80.
      vipsthumbnail "$image" --size 800x800 -o "$thumb[Q=88]" >/dev/null 2>&1 \
        && printf '%s\t%s\t%s\n' "$image" "$signature" "$hash" >>"$index_file"
    done
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi
