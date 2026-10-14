use module.nu *

export const meta = {inputs: [/etc/vconsole.conf /etc/localtime]}

export const options = {
    lang: {
        type: string?
        default: null
        doc: "LANG in /etc/locale.conf; detected: the one bootstrap set"
        label: "Language"
        apply: relogin
        scope: machine
    }
    formats: {
        type: string?
        default: null
        doc: "Locale for dates, numbers, money, units, paper and addresses (every LC_ but messages and collation); unset follows the language"
        label: "Formats"
        apply: relogin
        scope: machine
    }
    keyboard_layout: {
        type: string?
        default: null
        doc: "xkb layout of the console, X11 and the compositor; detected: the one bootstrap set"
        label: "Keyboard layout"
        group: input
        apply: relogin
        scope: machine
    }
    keyboard_variant: {
        type: string?
        default: null
        doc: "xkb variant, e.g. nodeadkeys"
        label: "Keyboard variant"
        group: input
        apply: relogin
        scope: machine
    }
    keyboard_options: {
        type: list<string>?
        default: null
        doc: "xkb options, e.g. ctrl:nocaps"
        label: "Keyboard options"
        group: input
        apply: relogin
        scope: machine
    }
    wifi_country: {
        type: string?
        default: null
        doc: "Wi-Fi regulatory domain (ISO 3166 alpha-2); detected: the country of the timezone, else the world domain"
        label: "Wi-Fi country"
        apply: reboot
        scope: machine
    }
}

const LOCALE_CONF = "/etc/locale.conf"
const VCONSOLE = "/etc/vconsole.conf"
const REGDOM = "/etc/conf.d/wireless-regdom"
const ZONES = "/usr/share/zoneinfo/zone1970.tab"
const XKB_MODEL = "pc105"
# besides lang and formats: what tools without a translation fall back to
const LOCALE_BASE = "en_US.UTF-8"
const FORMAT_CATEGORIES = [LC_TIME LC_NUMERIC LC_MONETARY LC_PAPER LC_MEASUREMENT LC_ADDRESS LC_TELEPHONE LC_NAME]

def env-file [file: path]: nothing -> record {
    if not ($file | path exists) { return {} }
    open --raw $file | lines | parse --regex '^(?<k>[A-Z_]+)="?(?<v>[^"]*)"?$' | reduce --fold {} {|e, acc| $acc | upsert $e.k $e.v }
}

def zone-country []: nothing -> any {
    let zone = try { ^readlink /etc/localtime | str replace --regex '^.*zoneinfo/' '' } catch { return null }
    if not ($ZONES | path exists) { return null }
    open --raw $ZONES | lines | where not ($it | str starts-with "#") | split column "\t" codes coord zone
    | where zone == $zone | get --optional 0.codes | default "" | split row "," | get --optional 0
}

export def detect [cfg: record]: nothing -> record {
    let locale = env-file $LOCALE_CONF
    let console = env-file $VCONSOLE
    let regdom = env-file $REGDOM
    {
        lang: ($locale.LANG? | default null)
        formats: ($locale.LC_TIME? | default null)
        keyboard_layout: ($console.XKBLAYOUT? | default null)
        keyboard_variant: ($console.XKBVARIANT? | default "")
        keyboard_options: ($console.XKBOPTIONS? | default "" | split row "," | where $it != "")
        wifi_country: ($regdom.WIRELESS_REGDOM? | default (zone-country))
    }
}

def charmap [locale: string]: nothing -> string {
    $locale | split row "." | get --optional 1 | default "UTF-8"
}

export def system [cfg: record] {
    let locales = [$cfg.lang $cfg.formats $LOCALE_BASE] | compact | uniq
    let formats = if $cfg.formats == null { [] } else { $FORMAT_CATEGORIES | each {|c| [$c $cfg.formats] } }
    let conf = [[LANG $cfg.lang]] ++ $formats | where $it.1 != null | each { $"($in.0)=($in.1)" }
    let console = env-file $VCONSOLE
    let keyboard = [$cfg.keyboard_layout ($cfg.keyboard_variant | default "") ($cfg.keyboard_options | default [] | str join ",")]
    let current = [$console.XKBLAYOUT? ($console.XKBVARIANT? | default "") ($console.XKBOPTIONS? | default "")]
    [
        (file-text /etc/locale.gen ($locales | each { $"($in) (charmap $in)\n" } | str join) --generated --then [locale-gen])
        (if ($conf | is-empty) { [] } else { file-text $LOCALE_CONF ($conf | str join "\n" | $"($in)\n") --generated })
        # localectl also converts it to the nearest console keymap; wsl has neither
        (if $cfg.keyboard_layout == null or $env.FORM_FACTOR? == "wsl" or $keyboard == $current { [] } else {
            exec keymap ([localectl set-x11-keymap $cfg.keyboard_layout $XKB_MODEL] ++ ($keyboard | skip 1))
        })
        # wireless-regdb ships every country commented out, so wifi would stay on the restrictive world domain
        (if $cfg.wifi_country == null or not ($REGDOM | path exists) { [] } else {
            file-text $REGDOM $"WIRELESS_REGDOM=\"($cfg.wifi_country)\"\n" --generated
        })
    ]
}
