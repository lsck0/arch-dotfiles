use module.nu *

# One MACHINE.md rule in every harness's global instructions.
# after hermes, whose orchestrator clone must not find its dir; an input so a fresh install re-plans
export const meta = {
    deps: [programming/claude programming/rtk programming/hermes]
    inputs: [~/.hermes/profiles/orchestrator ~/.hermes/profiles/system]
}

const RULES = "MACHINE.md"
# hermes' stock identity line, kept in front of the rule since SOUL.md replaces it whole
const HERMES_SOUL = "You are Hermes Agent, built by Nous Research. Be direct: match the length of your reply to the weight of the ask: a one-line question gets a one-line answer, and finished work gets a short report of what changed, what's verified, and what's left, never a replay of the process. No filler (\"Great question,\" \"I'd be happy to\"), no restating the request back, no re-summarizing what you already said, no narrating tool calls the user can see. Plain claims over adjectives; when unsure, say so plainly. Agree because it's right, not because the user said it. Depth is earned: give it when the user asks for detail, teaches, or the stakes demand it, not by default."

export def link [cfg: record] {
    let rules = open --raw $RULES
    let profiles = [orchestrator system] | each {|p| $nu.home-dir | path join .hermes profiles $p } | where ($it | path exists)
    [
        # claude: imported by configs/programming/claude/CLAUDE.md
        (files-into ($nu.home-dir | path join .claude) $RULES)
        # gemini: a second context file next to rtk's GEMINI.md
        (files-into ($nu.home-dir | path join .gemini) $RULES)
        (json-merge ($nu.home-dir | path join .gemini settings.json) [(json-set [context fileName] [GEMINI.md $RULES])])
        # copilot's one global file, which rtk init also wrote: the rule plus the same rtk note claude reads
        (file-text ($nu.home-dir | path join .copilot copilot-instructions.md) $"($rules)\n(open --raw ../claude/RTK.md)")
        (file-text ($nu.home-dir | path join .hermes SOUL.md) $"($HERMES_SOUL)\n\n($rules)")
        # the orchestrator and system profiles are clones made once, so each gets its own copy
        ($profiles | each {|dir| file-text ($dir | path join SOUL.md) $"($HERMES_SOUL)\n\n($rules)" })
    ] | decls-flatten
}
