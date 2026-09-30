# shellcheck shell=bash
# user_hook_install <hook dir> <name>: install <name>.path + <name>.service as user units, arm the path, run once now
user_hook_install() {
    local dir="$1" name="$2"
    install -Dm644 "${dir}/${name}.path" "${HOME}/.config/systemd/user/${name}.path"
    install -Dm644 "${dir}/${name}.service" "${HOME}/.config/systemd/user/${name}.service"
    systemctl --user daemon-reload
    systemctl --user enable --now "${name}.path"
    systemctl --user start --no-block "${name}.service"
}
