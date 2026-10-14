# exit 0 for --help, 1 with one "<command>: error: <why>" line on stderr, 2 with --misuse

use log.nu [log-err]

export def die [message: string, --misuse]: nothing -> nothing {
    with-env {LOG_TAG: ($env.CURRENT_FILE | path parse | get stem)} { log-err $message }
    exit (if $misuse { 2 } else { 1 })
}
