#!/usr/bin/env -S nu --no-config-file
# runs as a transient unit: a closed reader ends it and ExecStopPost removes the test files

const PHASE_SECONDS = 8
const PARALLEL = 4
const CHUNK_MB = 4
const FILE_MB = 256
const SECTOR_BYTES = 512
const BYTES_PER_MB = 1_000_000
const STAT_FIELD = {read: 2, write: 6}

def fail [message: string] {
    print --stderr $message
    exit 1
}

def rate-format [value: float]: nothing -> string {
    if $value <= 0 { "0.0" } else if $value < 10 { $value | into string --decimals 1 } else { $value | math round | into string }
}

def disk-root [dev: string]: nothing -> string {
    let slave = glob $"/sys/class/block/($dev)/slaves/*" | sort | get --optional 0
    if $slave != null { return (disk-root ($slave | path basename)) }
    if ($"/sys/class/block/($dev)/partition" | path exists) { $"/sys/class/block/($dev)" | path expand | path dirname | path basename } else { $dev }
}

def sectors [stat: path, phase: string]: nothing -> int {
    open --raw $stat | str trim | split row --regex '\s+' | get ($STAT_FIELD | get $phase) | into int
}

def dd-pass [phase: string, chunk: path, file: path]: nothing -> bool {
    let args = if $phase == read { [$"if=($file)" of=/dev/null iflag=direct] } else { [$"if=($chunk)" $"of=($file)" oflag=direct conv=notrunc] }
    (^dd ...$args $"bs=($CHUNK_MB)M" status=none | complete).exit_code == 0
}

def phase-run [phase: string, chunk: path, files: list<path>, stat: path] {
    let workers = $files | each {|file| job spawn { while (dd-pass $phase $chunk $file) {} } }
    let deadline = (date now) + ($PHASE_SECONDS * 1sec)
    mut before = sectors $stat $phase
    mut samples = 0
    mut baseline = {sectors: 0, time: (date now)}
    mut end_time = date now
    while (date now) < $deadline and (job list | where id in $workers | is-not-empty) {
        sleep 1sec
        let after = sectors $stat $phase
        $end_time = date now
        print $"($phase) (rate-format ([0 ($after - $before)] | math max | $in * $SECTOR_BYTES / $BYTES_PER_MB))"
        $samples += 1
        if $samples == 1 { $baseline = {sectors: $after, time: $end_time} }
        $before = $after
    }
    let alive = job list | where id in $workers | length
    $workers | each { job kill $in } | ignore
    if $alive < $PARALLEL { fail $"Disk ($phase) test failed before finishing" }
    if $samples > 1 {
        let seconds = ($end_time - $baseline.time) / 1sec
        let rate = if $seconds <= 0 or $before < $baseline.sectors { 0.0 } else { ($before - $baseline.sectors) * $SECTOR_BYTES / $BYTES_PER_MB / $seconds }
        print $"($phase) (rate-format $rate)"
    }
}

def "main measure" [run_dir: path, chunk: path] {
    let target_dir = $run_dir | path dirname
    # btrfs appends the subvolume as [/name]
    let source = ^findmnt -no SOURCE --target $target_dir | complete | get stdout | str trim | split row "[" | first
    if not ($source | str starts-with /dev/) { fail $"Cannot find a disk behind ($target_dir)" }
    let dev = $source | path expand | path basename
    let stat = $"/sys/class/block/($dev)/stat"
    if not ($stat | path exists) { fail $"No I/O statistics for ($dev)" }
    let needed_mb = $PARALLEL * $FILE_MB * 2
    if (^df --output=avail -m $target_dir | lines | last | str trim | into int) < $needed_mb {
        fail $"Need at least ($needed_mb)MB free on ($target_dir)"
    }

    let disk = disk-root $dev
    let model = ^lsblk -dno MODEL $"/dev/($disk)" | complete | get stdout | str trim
    print $"disk ($model | default --empty $disk)"

    ^dd if=/dev/urandom $"of=($chunk)" $"bs=($CHUNK_MB)M" $"count=($FILE_MB // $CHUNK_MB)" status=none
    let files = 0..<$PARALLEL | each { $run_dir | path join $"($in).dat" }
    let staged = $files | par-each { dd-pass write $chunk $in } | all { $in }
    if not $staged or (ls $files.0 | get 0.size) == 0B { fail $"Direct disk I/O is not available on ($target_dir)" }

    phase-run read $chunk $files $stat
    phase-run write $chunk $files $stat
}

def main [target_dir?: path] {
    if $target_dir != null and ($target_dir | path type) != dir {
        print --stderr "Usage: disk-speedtest.nu [target-dir]"
        exit 2
    }
    let target = $target_dir | default ($env.XDG_CACHE_HOME? | default --empty ($nu.home-dir | path join .cache) | path join quickshell) | path expand
    mkdir $target
    let run_dir = mktemp --directory --tmpdir-path $target disk-speedtest-XXXXXX
    let chunk = mktemp --tmpdir-path /dev/shm --suffix .src quickshell-disk-speedtest-XXXXXX
    ^chattr +C $run_dir | complete | ignore
    (exec systemd-run --user --wait --collect --pipe --quiet $"--property=ExecStopPost=/usr/bin/rm -rf '($run_dir)' '($chunk)'"
        $nu.current-exe --no-config-file $env.CURRENT_FILE measure $run_dir $chunk)
}
