#!/usr/bin/env -S nu --no-config-file

const REPO = path self | path expand | path dirname | path dirname | path dirname
const LIB = $REPO | path join scripts lib
use ($LIB | path join log.nu) *
use ($LIB | path join cli.nu) [concat jobs guarded]
use ($LIB | path join complete.nu) [command-table complete-run completions-run module-ids]
use ($LIB | path join platform.nu) [platform-env]
use ($LIB | path join options.nu) [options-events-file]
use ($LIB | path join modules.nu) [modules-packages modules-eval]
use ($LIB | path join pipeline.nu) [pipeline-load pipeline-plan pipeline-apply]
use ($LIB | path join secrets.nu) [secret-is-plaintext secrets-wanted]
use ($LIB | path join written.nu) [preserve-prune]
use ($LIB | path join migrate.nu) [migrations-run]
use ($LIB | path join fetch.nu) [fetch-file-run fetch-git-run]
use ($LIB | path join bootstrap.nu) [bootstrap-run]
use ($LIB | path join stage.nu) [stage-run]
use ($LIB | path join audit.nu) [audit-remind]
use ($LIB | path join drift.nu) [drift-report drift-publish]
use ($LIB | path join wallpaper.nu) [wallpaper-get wallpaper-list]
use ($LIB | path join iso.nu) [iso-build]

const DOT = $REPO | path join scripts dot.nu
const MIRROR_LIST = "mirror/packages.txt"
# what a switch waits for, in order: discord recolours from spotify's palette
const THEME_FOREGROUND = [socials/spotify socials/discord]

# dot internal <command> --help for each
def main []: nothing -> nothing { help main }

def commands-all []: nothing -> table {
    let dot = $env.DOT_COMMANDS? | default "[]" | from nuon
    $dot ++ (command-table "internal " | where name != "internal complete")
}

# candidates for the last of <words> (the words after `dot`), one `value<tab>description` per line
def --wrapped "main complete" [...words: string]: nothing -> nothing {
    complete-run (commands-all) $words
}

# the shell side of `dot internal complete`: zsh's _dot, or nushell externs generated from the command table
def "main completions" [shell: string@[zsh nu]]: nothing -> nothing {
    completions-run (commands-all) $shell
}

# download a pinned file, verify its sha256, put it in place; --extract <member> or .
def "main fetch file" [url: string, sha256: string, dest: path, --mode: string = "644", --extract: string]: nothing -> nothing {
    guarded fetch { fetch-file-run $url $sha256 $dest --mode $mode --extract=$extract }
}

# <dir> checked out at exactly <commit>, submodules too
def "main fetch git" [url: string, commit: string, dir: path]: nothing -> nothing {
    guarded fetch { fetch-git-run $url $commit $dir }
}

# install a machine from the Arch ISO or set up a fresh WSL distro
def "main bootstrap" [platform: string = ""]: nothing -> nothing {
    guarded bootstrap { bootstrap-run $REPO $platform }
}

# one stage of the unattended install chain (dotfiles-stage.service)
def "main stage" []: nothing -> nothing {
    guarded stage { stage-run $REPO }
}

def mirror-list []: nothing -> string {
    let ctx = pipeline-load $REPO system
    let all = $ctx.modules | update selected true | update cfg { upsert enable true }
    let extras = glob ($REPO | path join platforms *.nuon) | where not ($it | str ends-with ".options.nuon") | each { open $in | get --optional extra_packages | default [] } | flatten
    let variants = $all | where {|m| "packages" in $m.native } | each {|m|
        $m.options | items {|name, spec| $spec.choices? | default [] | each {|c| {m: $m, cfg: ($m.cfg | upsert $name $c)} } } | flatten
    } | flatten
    let candidates = $variants | each {|v| modules-eval [$v.m] packages {$v.m.id: $v.cfg} [] | get 0.decls | get --optional 0 | default {} | select --optional pacman native | values | flatten } | flatten
    let platform = $ctx.platform | update form_factor desktop | update extra_packages ($extras ++ $candidates)
    modules-packages $REPO $all $platform | get pacman | str join "\n" | $"($in)\n"
}

# regenerate mirror/packages.txt; --check fails when it is stale
def "main gen" [--check]: nothing -> nothing {
    guarded gen {
        if $check {
            if (open --raw ($REPO | path join $MIRROR_LIST)) != (mirror-list) { error make {msg: $"($MIRROR_LIST) is stale, run dot internal gen"} }
            return
        }
        mirror-list | save --force ($REPO | path join $MIRROR_LIST)
    }
}

# build the lsck0 install iso (needs root for mkarchiso); --work or DOT_ISO_WORK, default ~/.cache/dotfiles-iso
def "main iso" [--out: path, --work: path, --mirror: string, --sign: string, --keep: int = 3]: nothing -> nothing {
    guarded iso { iso-build $out $work $mirror $sign $keep }
}

# declared packages of a kind, one per line; --groups/--form-factor for another machine
def "main packages" [kind: string@[pacman flatpak nix] = "pacman", --groups: string, --form-factor: string]: nothing -> nothing {
    guarded packages {
        let ctx = pipeline-load $REPO system
        let chosen = $groups | default "" | split row --regex '[ ,]+' | where $it != ""
        let mods = if ($chosen | is-empty) { $ctx.modules } else { $ctx.modules | update selected {|m| $m.group in $chosen or $m.group == "" } }
        let platform = if ($chosen | is-empty) { $ctx.platform } else { $ctx.platform | update extra_packages [] | update form_factor ($form_factor | default $ctx.platform.form_factor) }
        let out = modules-packages $REPO $mods $platform | get $kind
        print (if $kind == "flatpak" { $out | items {|app, commit| $"($app) ($commit)" } } else { $out } | str join "\n")
    }
}

# pending one-time migrations (--system: root's); --baseline marks them run on a fresh install
def "main migrate" [--baseline, --system]: nothing -> nothing {
    guarded migrate {
        let done = migrations-run $REPO (if $system { "system" } else { "user" }) --baseline=$baseline
        if ($done | is-not-empty) { log-info $"migrations (if $baseline { 'marked' } else { 'applied' }): ($done | str join ' ')" }
    }
}

# preserved copies older than <days>, after a yes
def "main prune" [days: int]: nothing -> nothing {
    guarded prune { preserve-prune $days }
}

# every option and live state change as json lines {key, value, source, runtime}
def "main watch" []: nothing -> nothing {
    let file = options-events-file
    mkdir ($file | path dirname)
    if not ($file | path exists) { "" | save $file }
    ^tail --follow=name --retry --lines=0 $file
}

# this machine's drift report
def "main drift report" []: nothing -> nothing { guarded drift { drift-report | print -n } }
# publish this machine's report into secrets/drift/<host> when it changed
def "main drift publish" []: nothing -> nothing { guarded drift { drift-publish } }

# a notification when the recovery drill is due
def "main audit remind" []: nothing -> nothing { guarded audit { audit-remind } }

# the current wallpaper
def "main theme get" []: nothing -> nothing { guarded theme { print (wallpaper-get) } }
# the wallpapers for the largest monitor
def "main theme list" []: nothing -> nothing { guarded theme { print (wallpaper-list | str join "\n") } }

# every module's theme verb for this wallpaper (--only foreground|background)
def "main theme apply" [wallpaper: path, ...mods: string@module-ids, --only: string@[foreground background]]: nothing -> nothing {
    guarded theme {
        let ctx = pipeline-load $REPO user
        let ids = if ($mods | is-not-empty) { $mods } else {
            match $only {
                "foreground" => $THEME_FOREGROUND
                "background" => ($ctx.modules | where {|m| "theme" in $m.verbs and $m.id not-in $THEME_FOREGROUND } | get id)
                _ => []
            }
        }
        let planned = pipeline-plan $ctx theme $ids true [$wallpaper]
        let results = if $only != "foreground" {
            pipeline-apply $ctx ($planned | where id not-in $THEME_FOREGROUND) theme (jobs) [$wallpaper]
        } else { [] }
        let ordered = if $only != "background" {
            let foreground = $THEME_FOREGROUND | each {|id| $planned | where id == $id } | concat | update after []
            pipeline-apply $ctx $foreground theme 1 [$wallpaper]
        } else { [] }
        $results ++ $ordered | where not ok | each { log-err $"theme: ($in.id) failed" } | ignore
    }
}

def module-hash [dir: path]: nothing -> string {
    glob $"($dir)/**/*" --no-dir | where not ($it | str ends-with ".log") | sort | each {|f| $"($f) (open --raw $f | hash sha256)" } | str join "\n" | hash sha256
}

def backup-native [ctx: record, m: record]: nothing -> record {
    let r = modules-eval [$m] backup {$m.id: $m.cfg} [] --private=($m.meta.backup?.secrets? | default false) | first
    if not $r.ok { log-warn $"backup: ($m.id) failed, its state is from an older run: ($r.error)" }
    $r
}

# copy live app state into the repo; --roundtrip backs up, restores, backs up and compares
def "main backup" [--roundtrip]: nothing -> nothing {
    guarded backup {
        let ctx = pipeline-load $REPO user
        let wanted = secrets-wanted
        let locked = not $wanted or not (secret-is-plaintext ($REPO | path join secrets pgp_privatekey.asc))
        let mods = $ctx.modules | where {|m| "backup" in $m.native and $m.cfg.enable }
        let secret = {|m| $m.meta.backup?.secrets? | default false }
        if not $roundtrip {
            let skipped = $mods | where {|m| (do $secret $m) and $locked }
            with-env (platform-env $ctx.platform) { $mods | where id not-in $skipped.id | each {|m| backup-native $ctx $m } | ignore }
            if $wanted and ($skipped | is-not-empty) { log-warn $"backup: secrets is locked, skipped ($skipped.id | str join ' ')" }
            return
        }
        for m in ($mods | where {|m| not (do $secret $m) }) {
            backup-native $ctx $m | ignore
            let before = module-hash $m.dir
            let home = mktemp --directory
            let env_home = {HOME: $home, XDG_CONFIG_HOME: $"($home)/.config", XDG_DATA_HOME: $"($home)/.local/share", XDG_STATE_HOME: $"($home)/.local/state", XDG_CACHE_HOME: $"($home)/.cache"}
            let restored = with-env $env_home {
                let step = if "restore" in $m.native { [module restore $m.id] } else { [apply --user $m.id] }
                (^nu --no-config-file $DOT ...$step | complete).exit_code == 0
            }
            let again = with-env $env_home { backup-native $ctx $m }
            rm --recursive --force $home
            if not ($restored and $again.ok and (module-hash $m.dir) == $before) { error make {msg: $"backup: ($m.id) round trip changed the module or failed"} }
            log-info $"backup: ($m.id) round trip ok"
        }
    }
}
