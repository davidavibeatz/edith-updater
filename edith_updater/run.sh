#!/usr/bin/with-contenv bashio
set -Eeuo pipefail

POLL_SECONDS="$(bashio::config 'poll_seconds')"
SWITCH_ENTITY="input_boolean.home_ml_aggiorna"
API="http://supervisor/core/api"

set_switch_off() {
    curl -fsS -o /dev/null -X POST \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"entity_id\":\"${SWITCH_ENTITY}\"}" \
        "${API}/services/input_boolean/turn_off" || true
}

bashio::log.info "Edith Updater pronto"

while true; do
    STATE="$(curl -fsS \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        "${API}/states/${SWITCH_ENTITY}" \
        | jq -r '.state // "off"' 2>/dev/null || printf 'off')"

    if [[ "${STATE}" == "on" ]]; then
        bashio::log.info "Aggiornamento richiesto"
        /update.sh || bashio::log.error "Aggiornamento non completato"
        set_switch_off
    fi

    sleep "${POLL_SECONDS}"
done
