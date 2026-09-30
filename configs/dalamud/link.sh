#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

BACKUP="$(readlink -f ../secrets/dalamud)"
XLCORE="${HOME}/.xlcore"
# what dalamud writes as InstalledFromUrl for its own repo
MAIN_REPO_URL=https://kamori.goats.dev/Plugin/PluginMaster

if [ ! -f "${BACKUP}/dalamudConfig.json" ]; then
    exit 0
fi

set -e

# copies, not links: dalamud rewrites these files in place of a symlink. only a fresh ~/.xlcore is seeded
if [ ! -f "${XLCORE}/dalamudConfig.json" ]; then
    mkdir -p "${XLCORE}"
    cp "${BACKUP}/dalamudConfig.json" "${BACKUP}/dalamudUI.ini" "${XLCORE}/"
    cp -r "${BACKUP}/pluginConfigs" "${XLCORE}/pluginConfigs"
fi

# dalamud never installs a plugin its collection names, so a fresh install fetches each one the way the
# installer would: newest build from the repo it came from, manifest carrying the old collection id
[ -d "${XLCORE}/installedPlugins" ] && exit 0
[ -d "${BACKUP}/manifests" ] || exit 0

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/repos"

plugin_restore() {
    local manifest=$1 name from url repo entry version link dir
    name=$(jq -r .InternalName "${manifest}")
    from=$(jq -r .InstalledFromUrl "${manifest}")
    url=${from}
    [ "${from}" = OFFICIAL ] && url=${MAIN_REPO_URL}
    repo="${work}/repos/$(md5sum <<<"${url}" | cut -d' ' -f1).json"
    [ -f "${repo}" ] || curl -fsSL -m 60 -o "${repo}" "${url}" || return 1
    entry=$(jq -c --arg name "${name}" 'first(.[] | select(.InternalName == $name)) // empty' "${repo}")
    [ -n "${entry}" ] || return 1
    if [ "$(jq -r .Testing "${manifest}")" = true ] && [ "$(jq -r '.TestingAssemblyVersion // empty' <<<"${entry}")" != "" ]; then
        version=$(jq -r .TestingAssemblyVersion <<<"${entry}")
        link=$(jq -r .DownloadLinkTesting <<<"${entry}")
    else
        version=$(jq -r .AssemblyVersion <<<"${entry}")
        link=$(jq -r .DownloadLinkInstall <<<"${entry}")
    fi
    dir="${work}/${name}/${version}"
    mkdir -p "${dir}"
    curl -fsSL -m 300 -o "${work}/${name}.zip" "${link}" || return 1
    bsdtar -xf "${work}/${name}.zip" -C "${dir}" || return 1
    # the backed up manifest with the repo's data for this version; fields dalamud keeps local stay local
    jq -n --slurpfile local "${manifest}" --argjson entry "${entry}" --arg version "${version}" '
        $local[0] as $old
        | ["Disabled", "Testing", "InstalledFromUrl", "WorkingPluginId", "IsThirdParty", "IsHide",
           "DownloadLinkInstall", "DownloadLinkTesting", "DownloadLinkUpdate", "DownloadCount", "LastUpdate",
           "TestingAssemblyVersion", "TestingDalamudApiLevel"] as $kept
        | $old + ($entry | with_entries(select((.key | in($old)) and (.key | IN($kept[]) | not))))
        + { AssemblyVersion: $version, ScheduledForDeletion: false }
        | .DalamudApiLevel |= (tonumber? // .)' \
        >"${dir}/${name}.json" || return 1
    mkdir -p "${XLCORE}/installedPlugins"
    mv "${work}/${name}" "${XLCORE}/installedPlugins/${name}"
}

for manifest in "${BACKUP}"/manifests/*.json; do
    plugin_restore "${manifest}" || echo "dalamud: could not restore $(basename "${manifest}" .json)" >&2
done
