# --------------------------------------------------------------------- config

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
        # Gate the direnv fork: skip it unless PWD changed or an .envrc is here,
        # so a plain prompt in a plain dir costs no subprocess.
        pre_prompt: [{ ||
            if (which direnv | is-empty) { return }
            let changed = (($env.DIRENV_LAST_PWD? | default "") != $env.PWD)
            if not ($changed or (".envrc" | path exists)) { return }
            $env.DIRENV_LAST_PWD = $env.PWD
            let export = (direnv export json | complete)
            if $export.exit_code != 0 or ($export.stdout | str trim | is-empty) { return }
            let vars = ($export.stdout | from json)
            let unset = ($vars | transpose key value | where value == null | get key)
            for name in $unset { hide-env -i $name }
            $vars | transpose key value | where value != null | transpose -r -d | load-env
        }]
        env_change: {
            PWD: []
        }
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
            # fzf file widget, mirrors zsh ctrl-t
            name: fzf_file
            modifier: control
            keycode: char_t
            mode: [emacs, vi_insert, vi_normal]
            event: { send: executehostcommand cmd: "commandline edit --insert (fzf | str trim)" }
        }
        {
            # fzf dir widget, mirrors zsh alt-c
            name: fzf_cd
            modifier: alt
            keycode: char_c
            mode: [emacs, vi_insert, vi_normal]
            event: { send: executehostcommand cmd: "let d = (fzf --walker=dir | str trim); if $d != '' { cd $d }" }
        }
    ]
}

$env.config.buffer_editor = "nvim"

# -------------------------------------------------------------------- aliases

alias b = bat
alias cat = bat
alias cd = z
alias cdi = zi
alias convert = magick
alias cp = cp -v
alias downgrade = sudo downgrade
alias e = eza
alias kubectl = kubecolor
alias l = eza -lh
alias la = eza -lah
alias ldocker = lazydocker
alias lgit = lazygit
alias lgithub = gh-dash
alias ljj = lazyjj
def ljournal [...args] { lazyjournal -T (date now | format date "%:z") ...$args }
alias ls = eza
alias lsql = lazysql
alias lt = eza -lah --tree
alias mkdir = mkdir -v
alias mv = mv -v
alias pacman = sudo pacman
# rm already trashes via config.rm.always_trash; trash-rm is the verbose form.
alias trash-rm = trash -v
alias sshnb = ~/projects/arch-dotfiles/scripts/sshk.sh luca@192.168.178.73
alias sshpc = ~/projects/arch-dotfiles/scripts/sshk.sh luca@192.168.178.138
alias toroff = sudo systemctl stop tor-router.service
alias toron = sudo systemctl start tor-router.service

# ------------------------------------------------------------------ functions

# git clone always pulls submodules (no native config covers the initial clone)
def --wrapped git [...rest] {
    if (($rest | length) > 0) and (($rest | first) == "clone") {
        ^git clone --recurse-submodules ...($rest | skip 1)
    } else {
        ^git ...$rest
    }
}

# Remote Control needs feature-flag eval, which DO_NOT_TRACK disables. Drop it
# for claude only, so RC works while DO_NOT_TRACK still covers everything else.
def --wrapped claude [...rest] {
    ^env -u DO_NOT_TRACK claude ...$rest
}

# tms marks the session so tmux session-init lays out the nvim/claude/zsh stack;
# clear it afterwards so a plain tmux does not inherit a stale marker.
def --wrapped tms [...rest] {
    try { tmux set-environment -g TMS_LAUNCH 1 }
    ^tms ...$rest
    try { tmux set-environment -gu TMS_LAUNCH }
}

# --------------------------------------------------------------- integrations

source ~/.cache/nushell/starship.nu
source ~/.cache/nushell/zoxide.nu
source ~/.cache/nushell/mise.nu
source ~/.cache/nushell/wal.nu

if ("TERM" in $env) and $env.TERM != "dumb" and (which fastfetch | is-not-empty) {
    fastfetch
}
