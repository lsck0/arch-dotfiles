use module.nu *

export const meta = {packages: {native: [v4l2loopback-dkms v4l2loopback-utils]}}

export const options = {
    video_nr: {
        type: int?
        default: null
        doc: "/dev/video<n> of the OBS virtual camera; null: a loaded one's, else the first free from 10, past webcams"
        label: "Virtual camera device"
        min: 0
        max: 255
        apply: reboot
        scope: machine
    }
}

const LABEL = "OBS Virtual Camera"
const FIRST_FREE = 10

export def detect [cfg: record]: nothing -> record {
    let devices = glob /sys/class/video4linux/video* | each {|d|
        let name = try { open --raw ($d | path join name) | str trim } catch { "" }
        {nr: ($d | path basename | str replace video "" | into int), name: $name}
    }
    let loaded = $devices | where name == $LABEL | get --optional 0.nr
    {video_nr: ($loaded | default ($FIRST_FREE.. | where $it not-in $devices.nr | first))}
}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    [
        (file-copy v4l2loopback.conf /etc/modules-load.d/v4l2loopback.conf)
        (file-render v4l2loopback-options.conf /etc/modprobe.d/v4l2loopback.conf {VIDEO_NR: $cfg.video_nr})
    ]
}

# read at pipewire and wireplumber start only; restarting either would drop live audio and video
export def link [cfg: record] {
    # wsl has pipewire as a portal dependency, but windows owns the cameras
    if (which pipewire | is-empty) or $env.FORM_FACTOR? == "wsl" { return [] }
    let config = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config)
    [
        (file-render virtcam-pipewire.conf ($config | path join pipewire pipewire.conf.d virtcam.conf)
            {VIDEO_NR: $cfg.video_nr})
        (file-copy virtcam-wireplumber.conf ($config | path join wireplumber wireplumber.conf.d virtcam.conf))
    ]
}
