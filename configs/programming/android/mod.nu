use module.nu *

# the ndk from pacman, the sdk user-writable under XDG_DATA_HOME: arch's android-sdk is root-owned and only the
# deprecated `tools`, and sdkmanager must write into the sdk it manages. jdk21: sdkmanager and apksigner, beside the
# default jdk-openjdk that toolchains keeps
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
# cmdline-tools;latest 23.0 from https://dl.google.com/android/repository/repository2-3.xml (its sha1 e025545c...)
const CMDLINE_TOOLS_URL = "https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip"
const CMDLINE_TOOLS_SHA256 = "0877a1d048fe4a24efe2eff536ca4223f7adeb58648bb81909d33c446918cfa8"
const SYSTEM_IMAGE = "system-images;android-35;google_apis;x86_64"
const DEVICE = "pixel_6"
# sdkmanager package and the file that marks it installed, relative to the sdk
const PACKAGES = [
    [package created];
    [platform-tools platform-tools/adb]
    ["build-tools;35.0.1" build-tools/35.0.1/apksigner]
    ["platforms;android-35" platforms/android-35/android.jar]
    [emulator emulator/emulator]
    [$SYSTEM_IMAGE system-images/android-35/google_apis/x86_64/system.img]
]

# the same dirs as configs/base/xdg/app-dirs.conf sets for the session, passed explicitly: dot may run outside it.
# jdk21 once pacman has it; the cmdline-tools also run on the default jdk until then
def env-vars []: nothing -> list<string> {
    let data = $nu.home-dir | path join .local share
    [
        $"ANDROID_HOME=($data | path join android-sdk)" $"ANDROID_SDK_ROOT=($data | path join android-sdk)"
        $"ANDROID_USER_HOME=($data | path join android)" $"ANDROID_EMULATOR_HOME=($data | path join android)"
        $"ANDROID_AVD_HOME=($data | path join android avd)"
    ] ++ (if ($JAVA_HOME | path exists) { [$"JAVA_HOME=($JAVA_HOME)"] } else { [] })
}

def sdk []: nothing -> path { $nu.home-dir | path join .local share android-sdk }

export def link [cfg: record] {
    let sdk = sdk
    let sdkmanager = $sdk | path join cmdline-tools latest bin sdkmanager
    # accepting google's android sdk license: approved by the owner (2026-10-20), sdkmanager refuses without it
    let install = {|p| exec $"sdkmanager ($p.package)" [env ...(env-vars) sh -c $'yes | "$0" --licenses >/dev/null; "$0" --install "$1"' $sdkmanager $p.package] --creates ($sdk | path join $p.created) }
    let avd = $nu.home-dir | path join .local share android avd $"($cfg.avd).avd"
    let avdmanager = $sdk | path join cmdline-tools latest bin avdmanager
    [
        (fetch-file $CMDLINE_TOOLS_URL $CMDLINE_TOOLS_SHA256 ($sdk | path join cmdline-tools latest) --extract cmdline-tools)
        ($PACKAGES | each {|p| do $install $p })
        (if ($cfg.avd | is-empty) { [] } else {
            exec $"avd ($cfg.avd)" [env ...(env-vars) sh -c 'echo no | "$0" create avd --name "$1" --package "$2" --device "$3"' $avdmanager $cfg.avd $SYSTEM_IMAGE $DEVICE] --creates $avd
        })
    ] | decls-flatten
}
