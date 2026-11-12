# invariants.txt as rows, for dot status (live), the chain's report (stage-report.nu) and the vm test's verdict.

const INVARIANTS = path self invariants.txt

# Each row: key, the value wanted, where it is checked (live or vm) and its bash probe.
export def invariants-load []: nothing -> table<key: string, want: string, where: string, probe: string> {
    open --raw $INVARIANTS | lines | where {|l| ($l | str trim | is-not-empty) and not ($l | str starts-with "#") }
    | parse --regex '^(?<key>\S+)\s+(?<want>\S+)\s+(?<where>\S+)\s+(?<probe>.*)$'
}
