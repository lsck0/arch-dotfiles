use module.nu *

export const meta = {
    deps: [llm/vllm]
    packages: {flatpak: {com.jeffser.Alpaca: ced59ceb84b2a8824c270305f413e76720ebf0b1d4fcfe224c19b4cd25ae42eb}}
}

const APP = "com.jeffser.Alpaca"
# alpaca creates this table on launch with the same schema; made first so the backends can be seeded
const SCHEMA = "CREATE TABLE IF NOT EXISTS instance (id TEXT NOT NULL PRIMARY KEY, pinned INTEGER NOT NULL,
    type TEXT NOT NULL, properties TEXT NOT NULL);"

# its instances live in this sqlite db, the flatpak's data dir
def db []: nothing -> path {
    $nu.home-dir | path join .var app $APP data alpaca.db
}

export def link [cfg: record] {
    if (^flatpak info $APP | complete).exit_code != 0 or (which sqlite3 | is-empty) { return [] }
    step seed ($cfg.deps."llm/vllm".model | default "")
}

# the system ollama (socket-activated on 11434) and vllm (openai-compatible proxy on 8000); insert or ignore, so a
# later edit in the gui is kept
export def seed [vllm_model: string]: nothing -> nothing {
    mkdir (db | path dirname)
    let ollama = {name: "System Ollama", url: "http://localhost:11434", api: "", temperature: 0.7, num_ctx: 16384, keep_alive: 5, default_model: "llama3.1-64k"}
    let vllm = {name: vLLM, url: "http://127.0.0.1:8000/v1", api: EMPTY, max_tokens: 2048, override_parameters: true, temperature: 0.7, seed: 0, default_model: $vllm_model, title_model: $vllm_model}
    let rows = [["dotfiles-ollama" ollama $ollama] ["dotfiles-vllm" "openai:generic" $vllm]]
        | where {|r| $r.0 != "dotfiles-vllm" or $vllm_model != "" }
        | each {|r| $"\('($r.0)', 1, '($r.1)', json\('($r.2 | to json --raw)'\)\)" } | str join ", "
    ^sqlite3 (db) $"($SCHEMA) INSERT OR IGNORE INTO instance \(id, pinned, type, properties\) VALUES ($rows);"
}
