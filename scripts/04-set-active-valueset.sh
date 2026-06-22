#!/usr/bin/env bash
# Step 4 — Set the active Variable Library value set for each workspace.
#
# The active value set is workspace *state* (it is not stored in the Git definition),
# so each environment selects its own: Feature/Dev -> Dev, Test -> Test, Prod -> Prod.
#
# Usage:
#   ./scripts/04-set-active-valueset.sh
set -euo pipefail
source "$(dirname "$0")/_common.sh"
require_tools

get_fabric_token
state_init

while IFS=$'\t' read -r env displayName branch valueSet; do
    wsId="$(state_get ".workspaces.\"$env\".id // empty")"
    [[ -n "$wsId" ]] || die "Workspace '$env' not found in state. Run 01-create-workspaces.sh first."
    info "Setting active value set '$valueSet' on '$displayName'..."

    libId="$(fabric_api GET "/workspaces/$wsId/VariableLibraries" \
        | jq -r '.value | map(select(.displayName == "EnvConfig")) | .[0].id // empty')"
    if [[ -z "$libId" ]]; then
        warn "  EnvConfig not found yet (did the Git sync run?). Skipping."
        continue
    fi

    patchBody="$(jq -n --arg vs "$valueSet" '{properties: {activeValueSetName: $vs}}')"
    fabric_api PATCH "/workspaces/$wsId/VariableLibraries/$libId" "$patchBody" >/dev/null
    ok "  active value set = $valueSet."
done < <(cfg '.workspaces[] | [.env, .displayName, .branch, .valueSet] | @tsv')

info "Done."
