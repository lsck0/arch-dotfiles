#!/usr/bin/env -S nu --no-config-file
# pairing-read sees a device, an address or a folder member change, and nothing of what syncthing or api-config rewrite.

use pairing.nu [pairing-read]

const NAS = '<device id="NAS" name="lab-nas"><address>tcp://10.0.0.1:22000</address><paused>false</paused></device>'
const PHONE = '<device id="PHONE" name="phone"><address>dynamic</address></device>'

def config [devices: list<string>, members: list<string>, versioning: string = "", options: string = ""]: nothing -> string {
    let shared = $members | each {|id| $'<device id="($id)" introducedBy=""></device>' } | str join
    $'<configuration version="51">
    <folder id="sync" label="sync" path="/home/user/sync" type="sendreceive">($shared)($versioning)</folder>
    ($devices | str join "\n    ")
    <options><reconnectionIntervalS>60</reconnectionIntervalS>($options)</options>
</configuration>'
}

def main [] {
    let base = config [$NAS $PHONE] [NAS PHONE] | pairing-read
    let cases = [
        [what config same];
        ["device order" (config [$PHONE $NAS] [PHONE NAS]) true]
        ["versioning and options" (config [$NAS $PHONE] [NAS PHONE] '<versioning type="staggered"><param key="maxAge" val="1"></param></versioning>' "<natEnabled>false</natEnabled>") true]
        ["a device removed" (config [$NAS] [NAS PHONE]) false]
        ["a folder member removed" (config [$NAS $PHONE] [NAS]) false]
        ["an address changed" (config [($NAS | str replace "10.0.0.1" "10.0.0.2") $PHONE] [NAS PHONE]) false]
        ["a device renamed" (config [$NAS ($PHONE | str replace "phone" "tablet")] [NAS PHONE]) false]
    ]
    let failed = $cases | where {|c| (($c.config | pairing-read) == $base) != $c.same } | get what
    if ($base.devices | get id) != [NAS PHONE] or ($base.folders.0.devices) != [NAS PHONE] or ($base.devices.0.addresses) != ["tcp://10.0.0.1:22000"] {
        error make {msg: $"pairing.test: the base config read as ($base | to nuon)"}
    }
    if ($failed | is-not-empty) { error make {msg: $"pairing.test: ($failed | str join ', ')"} }
}
