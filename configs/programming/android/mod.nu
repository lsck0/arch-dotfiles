use module.nu *

export const meta = {packages: {pacman: [android-ndk jdk21-openjdk]}}

export const options = {
    avd: {
        type: string
        default: "nya35"
        doc: "Name of the emulator image made from the system image; empty makes none"
        label: "Emulator AVD"
        apply: relink
        scope: user
    }
}

const JAVA_HOME = "/usr/lib/jvm/java-21-openjdk"
# 22.0, the last with the java sdkmanager: 23.0's is a shim fetching an unpinned android-cli from a floating
# dl.google.com/android/cli/latest url, which a VM run off home got a 404 for
const CMDLINE_TOOLS_URL = "https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip"
const CMDLINE_TOOLS_SHA256 = "4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583"
# off home under lockdown-tor, tor-router carries everything, and dl.google.com answers tor exits with 404
const TOR_ROUTER = "tor-router.service"
const SYSTEM_IMAGE = "system-images;android-35;google_apis;x86_64"
const SYSTEM_IMAGE_FILE = "system-images/android-35/google_apis/x86_64/system.img"
const DEVICE = "pixel_6"
const PACKAGES = [
    [package created];
    [platform-tools platform-tools/adb]
    ["build-tools;35.0.1" build-tools/35.0.1/apksigner]
    ["platforms;android-35" platforms/android-35/android.jar]
    [emulator emulator/emulator]
    [$SYSTEM_IMAGE $SYSTEM_IMAGE_FILE]
]

export def link [cfg: record] {
    let sdk = xdg data android-sdk
    let bin = $sdk | path join cmdline-tools latest bin
    let sdkmanager = $bin | path join sdkmanager
    let avdmanager = $bin | path join avdmanager
    # the sdk tools want a jdk; the android dirs come from app-dirs.conf, which the user layer loads
    let env_vars = if ($JAVA_HOME | path exists) { [$"JAVA_HOME=($JAVA_HOME)"] } else { [] }
    let avd = xdg data android avd $"($cfg.avd).avd"
    # adb and the emulator on PATH for the session (systemd's environment.d) and zsh (zshenv sources the same dir)
    let path = $"PATH=${PATH}:($sdk)/platform-tools:($sdk)/emulator\n"
    let tor = (^systemctl is-active --quiet $TOR_ROUTER | complete).exit_code == 0
    if $tor { log-note "android: the sdk downloads wait for a network off tor, dl.google.com refuses tor exits" }
    [
        (file-text (xdg config environment.d android.conf) $path)
        (if not $tor {
            [
                (fetch-file $CMDLINE_TOOLS_URL $CMDLINE_TOOLS_SHA256 ($sdk | path join cmdline-tools latest) --extract cmdline-tools)
                ($PACKAGES | each {|p|
                    (exec $"sdkmanager ($p.package)" [env ...$env_vars sh -c $'yes | "$0" --licenses >/dev/null; "$0" --install "$1"' $sdkmanager $p.package]
                        --creates ($sdk | path join $p.created) --requires $sdkmanager --network)
                })
            ]
        })
        (if ($cfg.avd | is-not-empty) {
            # the image is sdkmanager's download: offline or failed, the avd waits for it instead of failing on it
            (exec $"avd ($cfg.avd)" [env ...$env_vars sh -c 'echo no | "$0" create avd --name "$1" --package "$2" --device "$3"' $avdmanager $cfg.avd $SYSTEM_IMAGE $DEVICE] --creates $avd --requires ($sdk | path join $SYSTEM_IMAGE_FILE)
                --undo [$avdmanager delete avd --name $cfg.avd])
        })
    ]
}
