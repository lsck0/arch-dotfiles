# pacman.conf's NoExtract keeps nemo's FileManager1 and plasma's KSplash service files from the next install or
# upgrade on; the copies already extracted go now, so the session bus stops logging their names as duplicates.

export const layer = "system"

const SERVICES = [
    /usr/share/dbus-1/services/nemo.FileManager1.service
    /usr/share/dbus-1/services/org.kde.KSplash.service
]

export def up []: nothing -> nothing {
    rm --force ...$SERVICES
}
