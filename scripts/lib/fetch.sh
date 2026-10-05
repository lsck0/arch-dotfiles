# shellcheck shell=bash
# third-party code fetched at link time, pinned by content: a moved tag or a compromised upstream fails here instead of running

# fetch_pinned <url> <sha256> <file>: download, verify, then rename into place; a mismatch leaves <file> untouched
fetch_pinned() {
    local url="$1" sha256="$2" file="$3"
    mkdir -p "$(dirname "$file")"
    curl -fsSL --retry 3 -o "$file.tmp" "$url" || return 1
    if ! sha256sum --quiet -c - <<<"$sha256  $file.tmp"; then
        rm -f "$file.tmp"
        echo "fetch: $url does not match its pinned sha256 $sha256" >&2
        return 1
    fi
    mv -f "$file.tmp" "$file"
}

# fetch_git_pinned <url> <commit> <dir>: <dir> checked out at exactly <commit>, submodules at its gitlinks; a no-op once there
fetch_git_pinned() {
    local url="$1" commit="$2" dir="$3"
    # absent or not a checkout yet: rev-parse fails, the fetch below creates it
    [[ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" == "$commit" ]] && return 0
    git init -q "$dir" \
        && git -C "$dir" fetch -q --depth 1 "$url" "$commit" \
        && git -C "$dir" -c advice.detachedHead=false checkout -q "$commit" \
        && git -C "$dir" submodule -q update --init --recursive --depth 1
}
