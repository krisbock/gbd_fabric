#!/usr/bin/env bash
# One-time per-workspace fixup — point the HospitalOps semantic model at the local lakehouse SQL endpoint.
#
# The import-mode model reads through two parameters (SqlEndpoint, SqlDatabase). This script
# reads the Healthcare lakehouse's SQL analytics endpoint in each workspace and writes it into
# the model's expressions.tmdl, then refreshes the model. Run once per workspace.
#
# Usage:
#   ./scripts/bind-semanticmodel.sh
set -euo pipefail
source "$(dirname "$0")/_common.sh"
require_tools

get_fabric_token
state_init

while IFS=$'\t' read -r env displayName branch valueSet; do
    wsId="$(state_get ".workspaces.\"$env\".id // empty")"
    [[ -n "$wsId" ]] || die "Workspace '$env' not found in state. Run 01-create-workspaces.sh first."
    info "Binding semantic model in '$displayName'..."

    # Resolve the lakehouse SQL analytics endpoint connection string.
    sqlEndpoint="$(fabric_api GET "/workspaces/$wsId/lakehouses" \
        | jq -r '.value | map(select(.displayName == "Healthcare")) | .[0].properties.sqlEndpointProperties.connectionString // empty')"
    if [[ -z "$sqlEndpoint" ]]; then
        warn "  Healthcare lakehouse / SQL endpoint not provisioned yet (it can take a minute after first sync). Skipping."
        continue
    fi

    modelId="$(get_workspace_items "$wsId" \
        | jq -r 'map(select(.type == "SemanticModel" and .displayName == "HospitalOps")) | .[0].id // empty')"
    if [[ -z "$modelId" ]]; then
        warn "  HospitalOps model missing. Skipping."
        continue
    fi

    def="$(get_item_definition "$wsId" "$modelId")"
    payload="$(jq -r '.parts[] | select(.path == "definition/expressions.tmdl") | .payload' <<<"$def")"
    if [[ -z "$payload" ]]; then
        warn "  expressions.tmdl not found in model definition. Skipping."
        continue
    fi

    tmdl="$(b64_decode "$payload")"
    tmdl="$(sed -E "s|expression SqlEndpoint = \".*\" meta|expression SqlEndpoint = \"${sqlEndpoint}\" meta|" <<<"$tmdl")"
    tmdl="$(sed -E 's|expression SqlDatabase = ".*" meta|expression SqlDatabase = "Healthcare" meta|' <<<"$tmdl")"

    newPayload="$(b64_encode "$tmdl")"
    newDef="$(jq --arg payload "$newPayload" '
        .parts |= map(if .path == "definition/expressions.tmdl" then .payload = $payload else . end)' <<<"$def")"

    update_item_definition "$wsId" "$modelId" "$newDef"
    ok "  SqlEndpoint set to $sqlEndpoint."

    # Kick off a refresh so the model picks up data.
    if fabric_api POST "/workspaces/$wsId/semanticModels/$modelId/refreshes" '{"type":"Full"}' >/dev/null 2>&1; then
        echo "  refresh started."
    else
        warn "  refresh skipped (model may not be bound to a gateway/credentials yet)."
    fi
done < <(cfg '.workspaces[] | [.env, .displayName, .branch, .valueSet] | @tsv')

info "Done."
