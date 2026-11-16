#!/usr/bin/env -S nu --no-config-file
# wallpapers/quotes.json, the quotes bound to a wallpaper: every key names a wallpaper, every quote has its author and
# its source, and its text is within the length the desktop's quote is laid out for

const WALLPAPERS = path self ../../../../../wallpapers
const KEYS = [text author cite source]
const TEXT_CHARS_MAX = 300

def quote-problems [file: string, quote: record]: nothing -> list<string> {
    [
        (if not ($WALLPAPERS | path join $file | path exists) { "no such wallpaper" })
        (if ($quote | columns | any { $in not-in $KEYS }) { $"keys other than ($KEYS | str join ', ')" })
        (if ($quote.text? | default "" | str length --grapheme-clusters) not-in 1..$TEXT_CHARS_MAX { $"text not within 1..($TEXT_CHARS_MAX) characters" })
        (if ($quote.author? | default "" | is-empty) { "no author" })
        (if ($quote.source? | default "") !~ '^https://' { "source is not an https URL" })
    ] | compact | each { $"($file): ($in)" }
}

def main [] {
    let problems = open ($WALLPAPERS | path join quotes.json) | items {|file, quote| quote-problems $file $quote } | flatten
    if ($problems | is-not-empty) { error make {msg: ($problems | str join "\n")} }
}
