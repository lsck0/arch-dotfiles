#!/usr/bin/env -S nu --no-config-file
# profile-mode on the profile lines apparmor.d and the own profiles carry, with and without flags; text-mode on a file.

use profile-flags.nu [profile-mode text-mode]

const CASES = [
    [line mode want];
    ["profile x /usr/bin/x {" complain "profile x /usr/bin/x flags=(complain) {"]
    ["profile x /usr/bin/x flags=(attach_disconnected) {" complain "profile x /usr/bin/x flags=(complain,attach_disconnected) {"]
    ["profile x /usr/bin/x flags=(complain,attach_disconnected) {" enforce "profile x /usr/bin/x flags=(attach_disconnected) {"]
    ["profile x /usr/bin/x flags=(complain) {" enforce "profile x /usr/bin/x {"]
    ["profile x /usr/bin/x flags=(complain) {" unconfined "profile x /usr/bin/x flags=(unconfined) {"]
    ["profile x /usr/bin/x flags=(unconfined,mediate_deleted) {" complain "profile x /usr/bin/x flags=(complain,mediate_deleted) {"]
    ["profile x /usr/bin/x {" enforce "profile x /usr/bin/x {"]
]
# only top-level profile lines: a nested profile keeps its own flags
const FILE = "# marker\nprofile x /usr/bin/x {\n  profile y flags=(complain) {\n  }\n}"
const FILE_COMPLAIN = "# marker\nprofile x /usr/bin/x flags=(complain) {\n  profile y flags=(complain) {\n  }\n}\n"

def main [] {
    let failed = $CASES | where {|c| ($c.line | profile-mode $c.mode) != $c.want }
    for c in $failed { print --stderr $"profile-flags.test: ($c.line) ($c.mode): got ($c.line | profile-mode $c.mode)" }
    if ($failed | is-not-empty) { error make {msg: $"profile-flags.test: ($failed | length) of ($CASES | length) cases failed"} }
    let got = $FILE | text-mode complain
    if $got != $FILE_COMPLAIN { error make {msg: $"profile-flags.test: text-mode complain: got ($got)"} }
}
