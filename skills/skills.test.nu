#!/usr/bin/env -S nu --no-config-file
# Every skill's frontmatter is strict YAML with its directory's name and a description: Copilot and Gemini drop a skill
# whose frontmatter does not parse (an unquoted ": " in a description), Claude Code loads it anyway.

const SKILLS = path self .

def main []: nothing -> nothing {
    let bad = glob ($SKILLS | path join "l-*" SKILL.md) | sort | each {|file|
        let dir = $file | path dirname | path basename
        let parts = open --raw $file | split row --regex '(?m)^---\s*$'
        let front = try { $parts | get 1 | from yaml } catch { null }
        if $front == null {
            $"($dir): frontmatter is not valid YAML \(quote a description holding ': '\)"
        } else if $front.name? != $dir {
            $"($dir): name is ($front.name? | default 'missing')"
        } else if ($front.description? | default "" | is-empty) {
            $"($dir): no description"
        }
    } | compact
    if ($bad | is-not-empty) { error make {msg: $"skills.test:\n($bad | str join "\n")"} }
    print "skills.test: ok"
}
