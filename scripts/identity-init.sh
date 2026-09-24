#!/usr/bin/env bash
# Give a repository its own customer identity, see configs/identity/envrc.

set -euo pipefail

DOTFILES_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
TEMPLATE=$DOTFILES_DIR/configs/identity/envrc
ENVRC_LINE='source_env_if_exists .identity/envrc'
USAGE="usage: identity-init [repo-dir]"

identity_env_create() {
  local env_file=$1
  install -m 600 /dev/null "$env_file"
  cat >"$env_file" <<EOF
GIT_NAME="$(git config --global user.name || true)"
GIT_EMAIL=
# gpg key id from .identity/gnupg, signs git and jj commits
GIT_SIGNING_KEY=

# TF_TOKEN_app_terraform_io=
EOF
}

envrc_line_add() {
  local envrc=$1
  touch "$envrc"
  if grep -qxF "$ENVRC_LINE" "$envrc"; then
    [[ $(grep -v '^[[:space:]]*\(#.*\)\?$' "$envrc" | tail -n 1) == "$ENVRC_LINE" ]] ||
      echo "warning: lines after '$ENVRC_LINE' in $envrc can override the identity" >&2
    return
  fi
  [[ ! -s $envrc || -z $(tail -c 1 "$envrc") ]] || echo >>"$envrc"
  echo "$ENVRC_LINE" >>"$envrc"
}

main() {
  (($# <= 1)) || { echo "$USAGE" >&2; exit 2; }
  [[ -d ${1:-.} ]] || { echo "error: ${1} is not a directory" >&2; echo "$USAGE" >&2; exit 2; }
  command -v direnv >/dev/null || { echo "error: direnv missing, install it with 'pacman -S direnv'" >&2; exit 1; }

  local repo_dir identity_dir
  repo_dir=$(cd "${1:-.}" && pwd)
  identity_dir=$repo_dir/.identity

  mkdir -p "$identity_dir"
  chmod 700 "$identity_dir"
  echo '*' >"$identity_dir/.gitignore"
  install -m 644 "$TEMPLATE" "$identity_dir/envrc"
  [[ -e $identity_dir/env ]] || { identity_env_create "$identity_dir/env"; echo "set GIT_EMAIL in $identity_dir/env"; }
  envrc_line_add "$repo_dir/.envrc"

  echo "run 'direnv allow $repo_dir'"
}

main "$@"
