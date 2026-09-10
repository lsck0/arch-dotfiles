#!/bin/bash
# Verbatim from omarchy-shell except cache dir `~/.cache/omarchy/image-selector`
# -> `~/.cache/quickshell/image-selector`. Looks up a content-hash-cached
# thumbnail for each image found under $1 (newline-separated directories);
# falls back to the full image path when no cached thumbnail exists yet
# (this repo has no separate thumbnail-pregeneration step the way Omarchy's
# theme-install flow does -- ImagePicker.qml's Image loads full-size in that
# case, same as it would for any image directory that was never pre-warmed).

image_dirs=${1:-}
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/image-selector
index_file="$cache_dir/index.tsv"

mkdir -p "$cache_dir"

# Was: for every image WITHOUT a cached thumbnail, md5sum the entire file to
# look for a "legacy" thumbnail keyed by content hash. That cost 10.4s per
# open here — it content-hashed 616MB of wallpapers on every single launch —
# to find thumbnails from "older on-demand picker code" that this repo never
# ran. The legacy cache dir is empty and always has been.
#
# Now: the cheap signature hash only (path + size + mtime, hashing the
# STRING not the file), and the legacy lookup happens only if legacy files
# actually exist.
# The listing itself is ONE python pass, not a shell loop.
#
# The loop this replaces spawned `stat`, `awk` and `md5sum` per image — about
# 800 processes for 262 wallpapers — which cost ~6s even after the far worse
# full-file hashing was removed. Same output contract: one
# "<image>\t<thumbnail-or-original>" line per file, printed as it is
# resolved so the picker can stream them in.
# dirs passed as an ARGUMENT, not stdin: the heredoc already occupies
# stdin, and adding `<<<"$image_dirs"` made the here-string win, so python
# read the directory list as its own source and died on a SyntaxError.
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

# Generate any missing thumbnails AFTER the listing is complete, detached, so
# it never delays the picker opening. Next open finds them cached and renders
# small images instead of full-size originals.
#
# The subshell above runs in a pipeline, so missing_list is not visible here;
# re-derive cheaply instead of restructuring the pipeline.
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
      # 800px / Q=88, not 400px / Q=80. The carousel slices are 432px tall and
      # the images are PreserveAspectCrop'd into them, so a 400px thumbnail
      # was already being upscaled even in the small strip.
      vipsthumbnail "$image" --size 800x800 -o "$thumb[Q=88]" >/dev/null 2>&1 \
        && printf '%s\t%s\t%s\n' "$image" "$signature" "$hash" >>"$index_file"
    done
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi
