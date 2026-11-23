# gaming/dalamud's seed marker took the shared name from secret-seed-mark: without the rename its backup refuses
# ~/.xlcore as never seeded, and the seed step never runs again to set the new one
export def up []: nothing -> nothing {
    let xl = $nu.home-dir | path join .xlcore
    let old = $xl | path join .dalamud-from-secrets
    let new = $xl | path join .from-secrets
    if ($old | path exists) and not ($new | path exists) { mv $old $new }
}
