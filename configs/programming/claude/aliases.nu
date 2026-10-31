# Claude without DO_NOT_TRACK, under which remote control breaks.
def --wrapped claude [...rest] {
    ^env -u DO_NOT_TRACK claude ...$rest
}
