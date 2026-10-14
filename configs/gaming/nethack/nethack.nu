#!/usr/bin/nu --no-config-file
# the binary without arch's wrapper: no HACKDIR, so it keeps its games gid and uses its compiled-in /var/games/nethack

def --wrapped main [...args: string]: nothing -> nothing {
    exec /usr/lib/nethack/nethack ...$args
}
