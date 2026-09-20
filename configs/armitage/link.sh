#!/usr/bin/env bash

cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v msfconsole >/dev/null 2>&1; then
    exit 0
fi
if ! command -v mise >/dev/null 2>&1 || ! command -v yay >/dev/null 2>&1; then
    exit 0
fi

set -e

if ! command -v armitage >/dev/null 2>&1; then
    set -x
    mise install java@11 gradle@7
    mise exec java@11 gradle@7 -- yay -S --needed --noconfirm armitage-git
    set +x
fi


db_yml=$HOME/.msf4/database.yml
socket=/tmp/.s.PGSQL.5433

if [[ ! -f "$db_yml" ]]; then
    exit 0
fi
if [[ ! -S "$socket" ]]; then
    exit 0
fi

read -r msf_pw msftest_pw < <(python3 - "$db_yml" <<'PY'
import re
import sys

text = open(sys.argv[1]).read()
sections = re.split(r'^(?=\S)', text, flags=re.MULTILINE)


def password_of(database):
    for block in sections:
        if re.search(r'^\s*database:\s*%s\s*$' % re.escape(database), block, re.MULTILINE):
            match = re.search(r'^\s*password:\s*(.+?)\s*$', block, re.MULTILINE)
            if match:
                return match.group(1)
    return ''


print(password_of('msf'), password_of('msftest'))
PY
)

if [[ -z "$msf_pw" ]]; then
    echo "armitage: could not read the msf password from $db_yml" >&2
    exit 1
fi

hashes=$(psql -h /tmp -p 5433 -U postgres -d postgres -tAc \
    "SELECT rolname || '=' || left(rolpassword, 3) FROM pg_authid WHERE rolname IN ('msf','msftest')" 2>/dev/null || true)

if [[ "$hashes" == *"msf=md5"* ]]; then
    exit 0
fi

psql -h /tmp -p 5433 -U postgres -d postgres -v ON_ERROR_STOP=1 \
    -v msf_pw="$msf_pw" -v msftest_pw="${msftest_pw:-$msf_pw}" <<'SQL'
SET password_encryption = 'md5';
ALTER ROLE msf     WITH PASSWORD :'msf_pw';
ALTER ROLE msftest WITH PASSWORD :'msftest_pw';
SQL
