#!/usr/bin/nu --no-config-file
# qvidcap's gl setup fails on native wayland and it exits; under xwayland it runs

def --wrapped main [...args: string]: nothing -> nothing {
    with-env {QT_QPA_PLATFORM: xcb} { exec /usr/bin/qvidcap ...$args }
}
