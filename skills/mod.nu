use module.nu *

# The skills for this repo. They name the owner's machine, so another login gets none; the owner's style, personas and
# workflows are configs/secrets/skills.
export def link [cfg: record] {
    if not (profile-has secrets) { return [] }
    skills-link .
}
