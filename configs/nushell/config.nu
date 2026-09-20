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
        pre_prompt: [{ ||
            if (which direnv | is-empty) { return }
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
    ]
}

$env.config.buffer_editor = "nvim"

# -------------------------------------------------------------------- aliases

alias b = bat
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
alias ljournal = lazyjournal
alias lsql = lazysql
alias lt = eza -lah --tree
alias mkdir = mkdir -v
alias mv = mv -v
alias pacman = sudo pacman
alias trash-rm = trash -v
alias sshnb = ssh luca@192.168.178.73
alias sshpc = ssh luca@192.168.178.138
alias toroff = sudo systemctl stop tor-router.service
alias toron = sudo systemctl start tor-router.service

# --------------------------------------------------------------- integrations

source ~/.cache/nushell/starship.nu
source ~/.cache/nushell/zoxide.nu
source ~/.cache/nushell/mise.nu
source ~/.cache/nushell/wal.nu

if ("TERM" in $env) and $env.TERM != "dumb" and (which fastfetch | is-not-empty) {
    fastfetch
}
