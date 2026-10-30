use module.nu *
use ../ollama/mod.nu [KEEP_ALIVE_MIN]
use ../ollama/ollama-ensure-models.nu [LONG_CONTEXT LONG_CONTEXT_TOKENS]

export const meta = {
    deps: [llm/vllm llm/ollama]
    packages: {
        pacman: [sqlite]
        flatpak: {com.jeffser.Alpaca: ced59ceb84b2a8824c270305f413e76720ebf0b1d4fcfe224c19b4cd25ae42eb}
    }
}

const APP = "com.jeffser.Alpaca"
const OLD_OLLAMA_SEED = {num_ctx: 16384, keep_alive: 5, default_model: "llama3.1-64k"}
const SCHEMA = "CREATE TABLE IF NOT EXISTS instance (id TEXT NOT NULL PRIMARY KEY, pinned INTEGER NOT NULL,
    type TEXT NOT NULL, properties TEXT NOT NULL);"

def db []: nothing -> path {
    $nu.home-dir | path join .var app $APP data alpaca.db
}

# sqlite escapes a literal single quote by doubling it
def sql-escape [s: string]: nothing -> string {
    $s | str replace --all "'" "''"
}

export def link [cfg: record] {
    if (^flatpak info $APP | complete).exit_code != 0 { return [] }
    # without a gpu share llm/vllm installs nothing, so no instance points at its port
    let vllm = $cfg.deps."llm/vllm"
    step seed (if $vllm.gpu_memory_utilization? == null { "" } else { $vllm.model | default "" })
}

export def seed [vllm_model: string]: nothing -> nothing {
    mkdir (db | path dirname)
    let ollama = {
        name: "System Ollama", url: "http://127.0.0.1:11434", api: "", temperature: 0.7, num_ctx: $LONG_CONTEXT_TOKENS
        keep_alive: $KEEP_ALIVE_MIN, default_model: $LONG_CONTEXT
    }
    let vllm = {name: vLLM, url: "http://127.0.0.1:8000/v1", api: EMPTY, max_tokens: 2048, override_parameters: true, temperature: 0.7, seed: 0, default_model: $vllm_model, title_model: $vllm_model}
    let rows = [["dotfiles-ollama" ollama $ollama] ["dotfiles-vllm" "openai:generic" $vllm]]
        | where {|r| $r.0 != "dotfiles-vllm" or $vllm_model != "" }
        | each {|r| $"\('($r.0)', 1, '($r.1)', json\('(sql-escape ($r.2 | to json --raw))'\)\)" } | str join ", "
    let ollama_url = ($" UPDATE instance SET properties = json_set\(properties, '$.url', '(sql-escape $ollama.url)'\)"
        + " WHERE id = 'dotfiles-ollama';")
    # a field still holding an older seed moves to the new one; anything changed in the ui stays
    let ollama_reseed = $OLD_OLLAMA_SEED | transpose key old | each {|f|
        let new = $ollama | get $f.key | to json --raw
        let old = $f.old | to json --raw
        ($" UPDATE instance SET properties = json_set\(properties, '$.($f.key)', json\('(sql-escape $new)'\)\)"
            + $" WHERE id = 'dotfiles-ollama'"
            + $" AND json_extract\(properties, '$.($f.key)'\) = json_extract\('(sql-escape $old)', '$'\);")
    } | str join
    let ollama_follow = $ollama_url + $ollama_reseed
    let vllm_follow = if $vllm_model == "" { " DELETE FROM instance WHERE id = 'dotfiles-vllm';" } else {
        $" UPDATE instance SET properties = json_set\(properties, '$.default_model', '(sql-escape $vllm_model)', '$.title_model', '(sql-escape $vllm_model)'\) WHERE id = 'dotfiles-vllm';"
    }
    let insert = $"INSERT OR IGNORE INTO instance \(id, pinned, type, properties\) VALUES ($rows);"
    ^sqlite3 (db) $"($SCHEMA) ($insert)($ollama_follow)($vllm_follow)"
}
