alias downgrade="sudo-at-terminal downgrade"

# pacman under sudo only for what changes the system, so queries need no fido touch; same letters as aliases.nu's pacman
function pacman {
  local arg ops=
  for arg; do
    case $arg in
      --) break ;;
      --query) ops+=Q ;; --deptest) ops+=T ;; --version) ops+=V ;; --help) ops+=h ;;
      --sync) ops+=S ;; --files) ops+=F ;; --search) ops+=s ;; --info) ops+=i ;; --groups) ops+=g ;; --list) ops+=l ;;
      --print) ops+=p ;; --refresh) ops+=y ;; --sysupgrade) ops+=u ;; --clean) ops+=c ;; --downloadonly) ops+=w ;;
      --*) ;;
      -?*) ops+=${arg#-} ;;
    esac
  done
  if [[ $ops == *[QTVh]* || ( $ops == *F* && $ops != *y* ) || ( $ops == *S* && $ops == *[siglp]* && $ops != *[yucw]* ) ]]; then
    command pacman "$@"
  else
    sudo-at-terminal pacman "$@"
  fi
}
