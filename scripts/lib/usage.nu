# the contract of every command in scripts/: nu's generated --help exits 0, a failure is one
# "<command>: error: <why>" line on stderr and exit 1, or exit 2 with --misuse for a bad argument

use log.nu [log-err]

export def die [message: string, --misuse]: nothing -> nothing {
    with-env {LOG_TAG: ($env.CURRENT_FILE | path parse | get stem)} { log-err $message }
    exit (if $misuse { 2 } else { 1 })
}
