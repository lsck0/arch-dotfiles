#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# alpaca is a flatpak; skip until it is installed, and skip without sqlite3 to seed its db
flatpak info com.jeffser.Alpaca >/dev/null 2>&1 || exit 0
command -v sqlite3 >/dev/null 2>&1 || exit 0

set -e

# alpaca keeps its instances in this sqlite db (constants.data_dir + alpaca.db), the flatpak data dir
db="${HOME}/.var/app/com.jeffser.Alpaca/data/alpaca.db"
mkdir -p "$(dirname "$db")"

# alpaca creates this table on launch with the same schema; make it first so the backends are seeded
sqlite3 "$db" "CREATE TABLE IF NOT EXISTS instance (id TEXT NOT NULL PRIMARY KEY, pinned INTEGER NOT NULL, type TEXT NOT NULL, properties TEXT NOT NULL);"

# the system ollama (socket-activated on 11434) and vllm (openai-compatible proxy on 8000)
# insert or ignore so a later edit in the gui is kept
sqlite3 "$db" <<'SQL'
INSERT OR IGNORE INTO instance (id, pinned, type, properties) VALUES
 ('dotfiles-ollama', 1, 'ollama', json('{"name":"System Ollama","url":"http://localhost:11434","api":"","temperature":0.7,"num_ctx":16384,"keep_alive":5,"default_model":"llama3.1-64k"}')),
 ('dotfiles-vllm', 1, 'openai:generic', json('{"name":"vLLM","url":"http://127.0.0.1:8000/v1","api":"EMPTY","max_tokens":2048,"override_parameters":true,"temperature":0.7,"seed":0,"default_model":"mattbucci/gemma-4-12B-AWQ","title_model":"mattbucci/gemma-4-12B-AWQ"}'));
SQL
