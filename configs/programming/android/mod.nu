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
const CMDLINE_TOOLS_URL = "https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip"
const CMDLINE_TOOLS_SHA256 = "0877a1d048fe4a24efe2eff536ca4223f7adeb58648bb81909d33c446918cfa8"
const SYSTEM_IMAGE = "system-images;android-35;google_apis;x86_64"
const DEVICE = "pixel_6"
const PACKAGES = [
    [package created];
    [platform-tools platform-tools/adb]
    ["build-tools;35.0.1" build-tools/35.0.1/apksigner]
    ["platforms;android-35" platforms/android-35/android.jar]
    [emulator emulator/emulator]
    [$SYSTEM_IMAGE system-images/android-35/google_apis/x86_64/system.img]
]

# the sdk tools want a jdk; the android dirs come from app-dirs.conf, which the user layer loads
def env-vars []: nothing -> list<string> {
    if ($JAVA_HOME | path exists) { [$"JAVA_HOME=($JAVA_HOME)"] } else { [] }
}

def sdk []: nothing -> path { xdg data android-sdk }

export def link [cfg: record] {
    let sdk = sdk
    let sdkmanager = $sdk | path join cmdline-tools latest bin sdkmanager
    let install = {|p| exec $"sdkmanager ($p.package)" [env ...(env-vars) sh -c $'yes | "$0" --licenses >/dev/null; "$0" --install "$1"' $sdkmanager $p.package] --creates ($sdk | path join $p.created) }
    let avd = xdg data android avd $"($cfg.avd).avd"
    let avdmanager = $sdk | path join cmdline-tools latest bin avdmanager
    # adb and the emulator on PATH for the session (systemd's environment.d) and zsh (zshenv sources the same dir)
    let path = $"PATH=${PATH}:($sdk)/platform-tools:($sdk)/emulator\n"
    [
        (file-text (xdg config environment.d android.conf) $path)
        (fetch-file $CMDLINE_TOOLS_URL $CMDLINE_TOOLS_SHA256 ($sdk | path join cmdline-tools latest) --extract cmdline-tools)
        ($PACKAGES | each {|p| do $install $p })
        (if ($cfg.avd | is-empty) { [] } else {
            exec $"avd ($cfg.avd)" [env ...(env-vars) sh -c 'echo no | "$0" create avd --name "$1" --package "$2" --device "$3"' $avdmanager $cfg.avd $SYSTEM_IMAGE $DEVICE] --creates $avd
        })
    ] | decls-flatten
}
