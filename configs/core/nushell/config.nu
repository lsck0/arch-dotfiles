$env.config = {
    show_banner: false
    edit_mode: emacs

    history: {
        file_format: "sqlite"
        max_size: 100_000
        sync_on_enter: true
        isolation: false
    }

    completions: {
        case_sensitive: false
        quick: true
        partial: true
        algorithm: "fuzzy"
        external: {
            enable: true
            max_results: 100
        }
    }

    filesize: { unit: "metric" }
    rm: { always_trash: true }
    table: {
        mode: "rounded"
        index_mode: "always"
        header_on_separator: false
    }
    ls: { use_ls_colors: true }
    cursor_shape: {
        emacs: "line"
        vi_insert: "line"
        vi_normal: "block"
    }

    hooks: {
        pre_prompt: [{ ||
            if (which direnv | is-empty) { return }
            let changed = (($env.DIRENV_LAST_PWD? | default "") != $env.PWD)
            if not ($changed or (".envrc" | path exists)) { return }
            $env.DIRENV_LAST_PWD = $env.PWD
            let export = (direnv export json | complete)
            if $export.exit_code != 0 or ($export.stdout | str trim | is-empty) { return }
            let vars = ($export.stdout | from json)
            let pairs = ($vars | transpose key value)
            for name in ($pairs | where value == null | get key) { hide-env -i $name }
            let set = ($pairs | where value != null)
            # load-env errors on an empty record
            if ($set | is-not-empty) { $set | transpose -r -d | load-env }
        }]
    }

    keybindings: [
        {
            name: edit_command_line
            modifier: control
            keycode: char_e
            mode: [emacs, vi_insert, vi_normal]
            event: { send: openeditor }
        }
        {
            name: fuzzy_history
            modifier: control
            keycode: char_r
            mode: [emacs, vi_insert, vi_normal]
            event: {
                send: menu
                name: history_menu
            }
        }
        {
            name: fzf_file
            modifier: control
            keycode: char_t
            mode: [emacs, vi_insert, vi_normal]
            event: { send: executehostcommand cmd: "commandline edit --insert (fzf | str trim)" }
        }
        {
            name: fzf_cd
            modifier: alt
            keycode: char_c
            mode: [emacs, vi_insert, vi_normal]
            event: { send: executehostcommand cmd: "let d = (fzf --walker=dir | str trim); if $d != '' { cd $d }" }
        }
    ]
}

$env.config.buffer_editor = "nvim"

# a tool's aliases and defs are its module's, dropped into the autoload dir (shell-aliases)
alias cp = cp -v
alias downgrade = sudo-at-terminal downgrade
alias ldocker = sudo-at-terminal lazydocker
alias mkdir = mkdir -v
alias mv = mv -v

const AGENT_MARKERS = [CLAUDECODE AI_AGENT GEMINI_CLI COPILOT_CLI_BINARY_VERSION]

# Root for this shell's defs and aliases, only at a person's terminal: an agent (its marker variable) or a process
# without one is refused instead of raising a YubiKey request nobody sees. Lint keeps every rc escalation behind it.
def --wrapped sudo-at-terminal [...rest] {
    let agent = $AGENT_MARKERS | any {|name| $env | get --optional $name | is-not-empty }
    if $agent or not (is-terminal --stdin) or not (is-terminal --stderr) {
        error make --unspanned {msg: $"($rest | get --optional 0 | default sudo): needs root, run it at your own terminal"}
    }
    ^sudo ...$rest
}

# Pacman under sudo only for what changes the system, so queries need no fido touch; same letters as zsh's pacman.
def --wrapped pacman [...rest] {
    let long = {
        --query: Q --deptest: T --version: V --help: h --sync: S --files: F --search: s --info: i --groups: g
        --list: l --print: p --refresh: y --sysupgrade: u --clean: c --downloadonly: w
    }
    let ops = ($rest | take until {|a| $a == "--" } | each {|a|
        if ($a | str starts-with "--") { $long | get -o $a | default "" } else if ($a =~ '^-.') { $a | str substring 1.. } else { "" }
    } | str join)
    let unprivileged = ($ops =~ '[QTVh]') or ($ops =~ 'F' and $ops !~ 'y') or ($ops =~ 'S' and $ops =~ '[siglp]' and $ops !~ '[yucw]')
    if $unprivileged { ^pacman ...$rest } else { sudo-at-terminal pacman ...$rest }
}

const STARSHIP_INIT = $nu.cache-dir | path join starship.nu
const ZOXIDE_INIT = $nu.cache-dir | path join zoxide.nu
const WAL_COLORS = $nu.cache-dir | path dirname | path join wal colors-nushell.nu
const STARSHIP = if ($STARSHIP_INIT | path exists) { $STARSHIP_INIT }
const ZOXIDE = if ($ZOXIDE_INIT | path exists) { $ZOXIDE_INIT }
const WAL = if ($WAL_COLORS | path exists) { $WAL_COLORS }
source $STARSHIP
source $ZOXIDE
source $WAL

# config.nu also loads for `nu -l -c`, whose stdout a caller reads
let fetch = $nu.is-interactive and (is-terminal --stdout) and ("TERM" in $env) and $env.TERM != "dumb"
if $fetch and (which fastfetch | is-not-empty) {
    fastfetch
}
