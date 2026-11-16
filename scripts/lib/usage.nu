use log.nu [log-err]

# Logs "<command>: error: <message>" to stderr and exits 1, or 2 with --misuse.
export def die [message: string, --misuse]: nothing -> nothing {
    with-env {LOG_TAG: ($env.CURRENT_FILE | path parse | get stem)} { log-err $message }
    exit (if $misuse { 2 } else { 1 })
}

# "1 file", "3 files": a count with its noun, which takes an s unless the count is one.
export def counted [count: int, noun: string]: nothing -> string {
    $"($count) ($noun)(if $count == 1 { '' } else { 's' })"
}
