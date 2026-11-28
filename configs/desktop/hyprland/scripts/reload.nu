# The compositor's config-only reload, shared by the module's reload verb, the plugin loader and the power saver
# toggle. A reload drops the `hyprctl eval` state (lid.nu's panel off, the shader), which the toggles replay; the shader
# goes last, a config write or scale re-render after it drops it.

const TOGGLES = path self ../../../../scripts/toggles

# Runs every step even when one fails, so the shader is replayed after a failed reload; fails naming each failed step.
export def hyprland-reload []: nothing -> nothing {
    let steps = [
        {what: "hyprctl reload", run: [hyprctl reload config-only]}
        {what: "monitor-scale reapply", run: [nu --no-config-file ($TOGGLES | path join toggle-monitor-scale.nu) reapply]}
        {what: "shader reapply", run: [nu --no-config-file ($TOGGLES | path join toggle-shader.nu) reapply]}
    ]
    let failed = $steps | each {|step|
        let run = run-external ...$step.run | complete
        if $run.exit_code != 0 {
            let cause = $run.stderr | str trim | lines | last 1 | str join "" | if $in != "" { $in } else { $"exited ($run.exit_code)" }
            $"($step.what): ($cause)"
        }
    }
    if ($failed | is-not-empty) { error make --unspanned {msg: $"hyprland reload failed: ($failed | str join '; ')"} }
}
