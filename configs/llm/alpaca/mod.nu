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
# Speech recognition's model, fetched here so the mic works without a download prompt. Alpaca runs whisper on the cpu:
# base garbles real speech, medium transcribes a sentence in about 3 s on the desktop. stt-model indexes Alpaca's
# STT_MODELS (tiny base small medium large); whisper's url carries its sha256.
const WHISPER = {name: medium, index: 3, sha256: "345ae4da62f9b3d59415adc60127b97c714f32e89e936602e85993674d08dcb1"}
const WHISPER_URL = $"https://openaipublic.azureedge.net/main/whisper/models/($WHISPER.sha256)/($WHISPER.name).pt"
const SCHEMA = "CREATE TABLE IF NOT EXISTS instance (id TEXT NOT NULL PRIMARY KEY, pinned INTEGER NOT NULL,
    type TEXT NOT NULL, properties TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS online_instance_model_list (id TEXT NOT NULL PRIMARY KEY, list TEXT NOT NULL);"

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
    let vllm_model = if $vllm.gpu_memory_utilization? == null { "" } else { $vllm.model | default "" }
    [
        (step seed $vllm_model --done=(seeded $vllm_model))
        (fetch-file $WHISPER_URL $WHISPER.sha256 (db | path dirname | path join whisper $"($WHISPER.name).pt"))
        (ini-merge ($nu.home-dir | path join .var app $APP config glib-2.0 settings keyfile)
            {"com/jeffser/Alpaca": {stt-model: ($WHISPER.index | into string)}})
    ]
}

def ollama-instance []: nothing -> record {
    {
        name: "System Ollama", url: "http://127.0.0.1:11434", api: EMPTY, temperature: 0.7, num_ctx: $LONG_CONTEXT_TOKENS
        keep_alive: (($KEEP_ALIVE_MIN * 1min) / 1sec | into int), default_model: $LONG_CONTEXT
    }
}

# Whether the database holds every value the seed forces; read only, Alpaca may hold it open.
def seeded [vllm_model: string]: nothing -> bool {
    let query = "SELECT i.id, i.properties, l.list FROM instance i LEFT JOIN online_instance_model_list l ON l.id = i.id WHERE i.id LIKE 'dotfiles-%'"
    let found = if not (db | path exists) { null } else {
        try { ^sqlite3 -readonly -json (db) $query | from json | default [] } catch { null }
    }
    if $found == null { return false }
    let rows = $found | each {|r| $r | update properties { from json } }
    let ollama = $rows | where id == dotfiles-ollama | get --optional 0.properties
    let wanted = ollama-instance | select url api num_ctx keep_alive default_model
    let ollama_set = $ollama != null and ($ollama | select --optional url api num_ctx keep_alive default_model) == $wanted
    let vllm = $rows | where id == dotfiles-vllm | get --optional 0
    let vllm_set = if $vllm_model == "" { $vllm == null } else {
        let listed = $vllm.list? | default "[]" | from json
        $vllm != null and $vllm.properties.default_model? == $vllm_model and $vllm.properties.title_model? == $vllm_model and $vllm_model in $listed
    }
    $ollama_set and $vllm_set
}

export def seed [vllm_model: string]: nothing -> nothing {
    mkdir (db | path dirname)
    let ollama = ollama-instance
    let vllm = {name: vLLM, url: "http://127.0.0.1:8000/v1", api: EMPTY, max_tokens: 2048, override_parameters: true, temperature: 0.7, seed: 0, default_model: $vllm_model, title_model: $vllm_model}
    let rows = [["dotfiles-ollama" ollama $ollama] ["dotfiles-vllm" "openai:generic" $vllm]]
        | where {|r| $r.0 != "dotfiles-vllm" or $vllm_model != "" }
        | each {|r| $"\('($r.0)', 1, '($r.1)', json\('(sql-escape ($r.2 | to json --raw))'\)\)" } | str join ", "
    # Alpaca sends "Bearer <api>" unconditionally; an empty key makes "Bearer ", which httpx rejects
    let ollama_follow = ($" UPDATE instance SET properties = json_set\(properties, '$.url', '(sql-escape $ollama.url)',"
        + $" '$.api', '($ollama.api)', '$.num_ctx', ($ollama.num_ctx), '$.keep_alive', ($ollama.keep_alive),"
        + $" '$.default_model', '(sql-escape $ollama.default_model)'\) WHERE id = 'dotfiles-ollama';")
    let vllm_follow = if $vllm_model == "" { " DELETE FROM instance WHERE id = 'dotfiles-vllm';" } else {
        let model = sql-escape $vllm_model
        # an openai instance offers only the models in its added list (its "add" button), empty until one is added
        ($" UPDATE instance SET properties = json_set\(properties, '$.default_model', '($model)', '$.title_model', '($model)'\) WHERE id = 'dotfiles-vllm';"
            + " INSERT OR IGNORE INTO online_instance_model_list (id, list) VALUES ('dotfiles-vllm', '[]');"
            + $" UPDATE online_instance_model_list SET list = json_insert\(list, '$[#]', '($model)'\) WHERE id = 'dotfiles-vllm'"
            + $" AND NOT EXISTS \(SELECT 1 FROM json_each\(list\) WHERE value = '($model)'\);")
    }
    let insert = $"INSERT OR IGNORE INTO instance \(id, pinned, type, properties\) VALUES ($rows);"
    ^sqlite3 (db) $"($SCHEMA) ($insert)($ollama_follow)($vllm_follow)"
}
