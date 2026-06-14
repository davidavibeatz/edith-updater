#!/usr/bin/with-contenv bashio
set -Eeuo pipefail

API_ROOT="${EDITH_API_ROOT:-https://api.github.com}"
CONFIG_ROOT="${EDITH_CONFIG_ROOT:-/homeassistant}"
ADDON_CONFIG_ROOT="${EDITH_ADDON_CONFIG_ROOT:-/addon_configs}"
BACKUP_ROOT="${EDITH_BACKUP_ROOT:-/backup/edith-updater}"
WORK_ROOT="${EDITH_WORK_ROOT:-/tmp/edith-updater}"

if [[ -n "${EDITH_TEST_OPTIONS:-}" ]]; then
    OPTIONS="${EDITH_TEST_OPTIONS}"
else
    OPTIONS="$(bashio::config)"
fi

REPOSITORY="$(jq -r '.repository' <<<"${OPTIONS}")"
GITHUB_TOKEN="$(jq -r '.github_token // ""' <<<"${OPTIONS}")"
APPDAEMON_SLUG="$(jq -r '.appdaemon_slug' <<<"${OPTIONS}")"
APPDAEMON_CONFIG_DIR="$(jq -r '.appdaemon_config_dir' <<<"${OPTIONS}")"
AUTH_HEADER=()

if [[ -n "${GITHUB_TOKEN}" ]]; then
    AUTH_HEADER=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"
}

set_status() {
    local state="$1"
    local message="$2"
    log "${state}: ${message}"
    if [[ -n "${SUPERVISOR_TOKEN:-}" && -z "${EDITH_TEST_MODE:-}" ]]; then
        curl -fsS -o /dev/null -X POST \
            -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "$(jq -nc \
                --arg state "${state}" \
                --arg message "${message}" \
                '{state:$state,attributes:{friendly_name:"Edith aggiornamento",message:$message}}'
            )" \
            http://supervisor/core/api/states/sensor.edith_aggiornamento || true
    fi
}

fail() {
    set_status "errore" "$1"
    exit 1
}

api_get() {
    curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${AUTH_HEADER[@]}" \
        "$1"
}

download_asset() {
    local asset_id="$1"
    local destination="$2"
    curl -fsSL \
        -H "Accept: application/octet-stream" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${AUTH_HEADER[@]}" \
        "${API_ROOT}/repos/${REPOSITORY}/releases/assets/${asset_id}" \
        -o "${destination}"
}

install_file() {
    local source="$1"
    local destination="$2"
    local backup_dir="$3"
    local relative_backup="${destination#/}"

    mkdir -p "$(dirname "${destination}")"
    if [[ -f "${destination}" ]]; then
        mkdir -p "${backup_dir}/$(dirname "${relative_backup}")"
        cp -p "${destination}" "${backup_dir}/${relative_backup}"
    fi
    cp "${source}" "${destination}.edith-new"
    chmod --reference="${destination}" "${destination}.edith-new" 2>/dev/null || true
    mv -f "${destination}.edith-new" "${destination}"
}

target_destination() {
    local target="$1"
    case "${target}" in
        appdaemon/*)
            printf '%s/%s\n' \
                "${ADDON_CONFIG_ROOT}/${APPDAEMON_CONFIG_DIR}" \
                "${target#appdaemon/}"
            ;;
        homeassistant/*)
            printf '%s/%s\n' "${CONFIG_ROOT}" "${target#homeassistant/}"
            ;;
        *)
            return 1
            ;;
    esac
}

rollback() {
    local target destination backup_file
    while IFS= read -r target; do
        destination="$(target_destination "${target}")" || continue
        backup_file="${BACKUP_DIR}/${destination#/}"
        if [[ -f "${backup_file}" ]]; then
            cp -p "${backup_file}" "${destination}"
        else
            rm -f "${destination}"
        fi
    done < <(jq -r '.files[].target' "${MANIFEST}")
    printf '%s\n' "${CURRENT_VERSION}" > "${CURRENT_VERSION_FILE}"
    set_status "rollback" "Aggiornamento annullato; ripristinato ${CURRENT_VERSION:-stato precedente}"
}

rm -rf "${WORK_ROOT}"
mkdir -p "${WORK_ROOT}" "${BACKUP_ROOT}"
set_status "controllo" "Ricerca aggiornamenti"

if [[ -n "${EDITH_TEST_RELEASE_DIR:-}" ]]; then
    cp "${EDITH_TEST_RELEASE_DIR}/edith-update.zip" \
        "${WORK_ROOT}/edith-update.zip"
    cp "${EDITH_TEST_RELEASE_DIR}/edith-update.zip.sha256" \
        "${WORK_ROOT}/edith-update.zip.sha256"
    VERSION="$(unzip -p "${WORK_ROOT}/edith-update.zip" manifest.json \
        | jq -r '.version')"
else
    RELEASE_JSON="$(api_get "${API_ROOT}/repos/${REPOSITORY}/releases/latest")" \
        || fail "Release GitHub non raggiungibile"
    VERSION="$(jq -r '.tag_name // empty' <<<"${RELEASE_JSON}")"
    ZIP_ID="$(jq -r '.assets[] | select(.name == "edith-update.zip") | .id' \
        <<<"${RELEASE_JSON}")"
    SHA_ID="$(jq -r '.assets[] | select(.name == "edith-update.zip.sha256") | .id' \
        <<<"${RELEASE_JSON}")"

    [[ -n "${VERSION}" && -n "${ZIP_ID}" && -n "${SHA_ID}" ]] \
        || fail "Release incompleta"

    download_asset "${ZIP_ID}" "${WORK_ROOT}/edith-update.zip" \
        || fail "Download pacchetto fallito"
    download_asset "${SHA_ID}" "${WORK_ROOT}/edith-update.zip.sha256" \
        || fail "Download checksum fallito"
fi

EXPECTED_SHA="$(awk '{print $1}' "${WORK_ROOT}/edith-update.zip.sha256")"
ACTUAL_SHA="$(sha256sum "${WORK_ROOT}/edith-update.zip" | awk '{print $1}')"
[[ "${EXPECTED_SHA}" == "${ACTUAL_SHA}" ]] || fail "Checksum pacchetto non valido"

unzip -q "${WORK_ROOT}/edith-update.zip" -d "${WORK_ROOT}/release"
MANIFEST="${WORK_ROOT}/release/manifest.json"
[[ -f "${MANIFEST}" ]] || fail "Manifest assente"
[[ "$(jq -r '.version' "${MANIFEST}")" == "${VERSION}" ]] \
    || fail "Versione manifest non coerente"

while IFS=$'\t' read -r relative expected; do
    source_file="${WORK_ROOT}/release/${relative}"
    [[ -f "${source_file}" ]] || fail "File mancante: ${relative}"
    actual="$(sha256sum "${source_file}" | awk '{print $1}')"
    [[ "${actual}" == "${expected}" ]] || fail "Checksum file non valido: ${relative}"
done < <(jq -r '.files[] | [.source, .sha256] | @tsv' "${MANIFEST}")

CURRENT_VERSION_FILE="${ADDON_CONFIG_ROOT}/${APPDAEMON_CONFIG_DIR}/edith_ml_data/version"
CURRENT_VERSION="$(cat "${CURRENT_VERSION_FILE}" 2>/dev/null || true)"
if [[ "${CURRENT_VERSION}" == "${VERSION}" ]]; then
    set_status "aggiornato" "Edith ${VERSION} e gia installato"
    exit 0
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${STAMP}-${CURRENT_VERSION:-senza-versione}"
mkdir -p "${BACKUP_DIR}"

while IFS=$'\t' read -r relative target; do
    destination="$(target_destination "${target}")" \
        || fail "Destinazione non consentita: ${target}"
    install_file "${WORK_ROOT}/release/${relative}" "${destination}" "${BACKUP_DIR}"
done < <(jq -r '.files[] | [.source, .target] | @tsv' "${MANIFEST}")

mkdir -p "$(dirname "${CURRENT_VERSION_FILE}")"
printf '%s\n' "${VERSION}" > "${CURRENT_VERSION_FILE}"
set_status "installato" "Edith ${VERSION} installato; backup ${STAMP}"

if [[ -n "${EDITH_TEST_MODE:-}" ]]; then
    exit 0
fi

CHECK_RESULT="$(curl -fsS -X POST \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    -H "Content-Type: application/json" \
    http://supervisor/core/api/config/core/check_config)" \
    || {
        rollback
        fail "Controllo configurazione Home Assistant fallito"
    }

if [[ "$(jq -r '.result // empty' <<<"${CHECK_RESULT}")" != "valid" ]]; then
    rollback
    fail "Configurazione Home Assistant non valida"
fi

curl -fsS -o /dev/null -X POST \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    "http://supervisor/addons/${APPDAEMON_SLUG}/restart" \
    || {
        rollback
        fail "Riavvio AppDaemon fallito"
    }

curl -fsS -o /dev/null -X POST \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    -H "Content-Type: application/json" \
    --data '{}' \
    http://supervisor/core/api/services/homeassistant/restart \
    || fail "Riavvio Home Assistant fallito"

set_status "completato" "Edith ${VERSION} aggiornato con successo"
