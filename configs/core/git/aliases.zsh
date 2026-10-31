git() {
  if [[ "$1" == clone ]]; then
    command git clone --recurse-submodules "${@:2}"
  else
    command git "$@"
  fi
}
