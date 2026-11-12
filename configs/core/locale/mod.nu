use module.nu *

export const meta = {inputs: [/etc/vconsole.conf /etc/localtime]}

export const options = {
    lang: {
        type: string?
        default: null
        doc: "LANG in /etc/locale.conf; detected: the one bootstrap set"
        label: "Language"
        apply: relogin
    }
    formats: {
        type: string?
        default: null
        doc: "Locale for dates, numbers, money, units, paper and addresses (every LC_ except CTYPE, MESSAGES, COLLATE and IDENTIFICATION); unset follows the language"
        apply: relogin
    }
    keyboard_layout: {
        type: string?
        default: null
        doc: "xkb layout of the console, X11 and the compositor; detected: the one bootstrap set"
        group: input
        apply: relogin
    }
    keyboard_variant: {
        type: string?
        default: null
        doc: "xkb variant, e.g. nodeadkeys"
        group: input
        apply: relogin
    }
    keyboard_options: {
        type: list<string>?
        default: null
        doc: "xkb options, e.g. ctrl:nocaps"
        group: input
        apply: relogin
    }
    wifi_country: {
        type: string?
        default: null
        doc: "Wi-Fi regulatory domain (ISO 3166 alpha-2); detected: the country of the timezone, else the world domain"
        label: "Wi-Fi country"
        apply: reboot
    }
}

const LOCALE_CONF = "/etc/locale.conf"
const VCONSOLE = "/etc/vconsole.conf"
const REGDOM = "/etc/conf.d/wireless-regdom"
const ZONES = "/usr/share/zoneinfo/zone1970.tab"
const XKB_MODEL = "pc105"
const LOCALE_BASE = "en_US.UTF-8"
const FORMAT_CATEGORIES = [LC_TIME LC_NUMERIC LC_MONETARY LC_PAPER LC_MEASUREMENT LC_ADDRESS LC_TELEPHONE LC_NAME]

def zone-country []: nothing -> any {
    let zone = try { ^readlink /etc/localtime | str replace --regex '^.*zoneinfo/' '' } catch { return null }
    if not ($ZONES | path exists) { return null }
    open --raw $ZONES | lines | where not ($it | str starts-with "#") | split column "\t" codes coord zone
    | where zone == $zone | get --optional 0.codes | default "" | split row "," | get --optional 0
}

export def detect [cfg: record]: nothing -> record {
    let locale = env-file-load $LOCALE_CONF
    let console = env-file-load $VCONSOLE
    let regdom = env-file-load $REGDOM
    {
        lang: ($locale.LANG? | default null)
        formats: ($locale.LC_TIME? | default null)
        keyboard_layout: ($console.XKBLAYOUT? | default null)
        keyboard_variant: ($console.XKBVARIANT? | default "")
        keyboard_options: ($console.XKBOPTIONS? | default "" | split row "," | where $it != "")
        wifi_country: ($regdom.WIRELESS_REGDOM? | default (zone-country))
    }
}

export def system [cfg: record] {
    # WSL skips the install's locale question and its image may ship no LANG at all
    let lang = $cfg.lang | default (if $env.FORM_FACTOR? == "wsl" { $LOCALE_BASE } else { null })
    let locales = [$lang $cfg.formats $LOCALE_BASE] | compact | uniq
    let locale_gen = $locales | each { $"($in) ($in | split row '.' | get --optional 1 | default 'UTF-8')\n" } | str join
    let formats = if $cfg.formats == null { [] } else { $FORMAT_CATEGORIES | each {|c| [$c $cfg.formats] } }
    let conf = [[LANG $lang]] ++ $formats | where $it.1 != null | each { $"($in.0)=($in.1)" }
    let console = env-file-load $VCONSOLE
    let keyboard = [$cfg.keyboard_layout ($cfg.keyboard_variant | default "") ($cfg.keyboard_options | default [] | str join ",")]
    let current = [$console.XKBLAYOUT? ($console.XKBVARIANT? | default "") ($console.XKBOPTIONS? | default "")]
    [
        (file-text /etc/locale.gen $locale_gen --generated --then [locale-gen])
        (if ($conf | is-not-empty) { file-text $LOCALE_CONF ($conf | str join "\n" | $"($in)\n") --generated })
        (if $cfg.keyboard_layout != null and $env.FORM_FACTOR? != "wsl" and $keyboard != $current {
            exec keymap ([localectl set-x11-keymap $cfg.keyboard_layout $XKB_MODEL] ++ ($keyboard | skip 1))
        })
        (if $cfg.wifi_country != null and ($REGDOM | path exists) {
            file-text $REGDOM $"WIRELESS_REGDOM=\"($cfg.wifi_country)\"\n" --generated
        })
    ]
}
