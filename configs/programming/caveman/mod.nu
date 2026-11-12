use module.nu *

# serial: claude plugin and gemini extensions rewrite their files whole, outside the json lock
export const meta = {deps: [programming/claude], serial: true}

const URL = "https://github.com/JuliusBrussee/caveman.git"
const COMMIT = "6571943370f7c9d4de1946481177ee7b306cd8e8"
const SKILLS_CLI = "skills@1.7.0"
# else the claude cli writes failed telemetry events under ~/.claude on every call
const CLAUDE = [env DISABLE_TELEMETRY=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude]
const PROBE = "skills/caveman/SKILL.md"

def has [cmd: string]: nothing -> bool {
    which $cmd | is-not-empty
}

def json-load [file: path]: nothing -> record {
    if ($file | path exists) { open $file } else { {} }
}

def same-file [a: path, b: path]: nothing -> bool {
    ($a | path exists) and ($b | path exists) and (open --raw $a | hash sha256) == (open --raw $b | hash sha256)
}

def claude-steps [dir: path, probe: path]: nothing -> list<any> {
    # the marketplace is the fetched checkout: before the fetch landed these wait instead of failing
    let plugins = $nu.home-dir | path join .claude plugins
    let installed = json-load ($plugins | path join installed_plugins.json) | get --optional plugins."caveman@caveman"
        | default [] | any { $in.gitCommitSha? == $COMMIT }
    let market = json-load ($plugins | path join known_marketplaces.json) | get --optional caveman
    let added = $market.installLocation? == $dir
    [
        (if $market != null and not $added { exec "caveman marketplace drop" [...$CLAUDE plugin marketplace remove caveman] })
        (exec "caveman marketplace" [...$CLAUDE plugin marketplace add $dir] --done=$added --requires $probe)
        # named by its commit as the gemini install; the undo calls claude bare, so with claude gone it counts as done
        (exec $"caveman claude plugin ($COMMIT | str substring 0..11)" [...$CLAUDE plugin install caveman@caveman]
            --done=$installed --undo [claude plugin uninstall caveman@caveman] --requires $probe)
    ]
}

# Named by its commit: a bump orphans the old install, whose undo uninstalls it before the new one goes in.
def gemini-step []: nothing -> record {
    let ext = $nu.home-dir | path join .gemini extensions caveman
    let ref = json-load ($ext | path join .gemini-extension-install.json) | get --optional ref
    (exec $"caveman gemini ($COMMIT | str substring 0..11)" [gemini extensions install $URL --ref $COMMIT --consent]
        --done=($ref == $COMMIT) --undo [gemini extensions uninstall caveman] --network)
}

export def link [cfg: record] {
    let dir = xdg data caveman
    let probe = $dir | path join $PROBE
    let hermes = $nu.home-dir | path join .hermes skills productivity caveman SKILL.md
    let copilot = $nu.home-dir | path join .agents skills caveman SKILL.md
    [
        (fetch-git $URL $COMMIT $dir)
        (if (has claude) { claude-steps $dir $probe })
        (if (has gemini) { gemini-step })
        (if (has node) and (has hermes) {
            (exec "caveman hermes" [node ($dir | path join bin install.js) --only hermes --non-interactive]
                --done=(same-file $probe $hermes) --requires $probe)
        })
        (if (has copilot) and (has npx) {
            (exec "caveman copilot" [npx -y $SKILLS_CLI add $dir --skill "*" -a github-copilot -g --yes]
                --done=(same-file $probe $copilot) --network --requires $probe)
        })
    ]
}
