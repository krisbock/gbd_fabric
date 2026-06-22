#!/usr/bin/env bash
# One-time per-workspace fixup — point the HospitalOpsETL pipeline at the local HospitalETL notebook.
#
# A Data Pipeline's notebook activity stores a physical notebookId + workspaceId. After the
# items land in each workspace via Git, this script rewrites the pipeline definition so the
# activity runs the notebook that lives in the SAME workspace. Run once per workspace (the
# daily PR demo never touches this).
#
# Usage:
#   ./scripts/bind-pipeline.sh
set -euo pipefail
source "$(dirname "$0")/_common.sh"
require_tools

get_fabric_token
state_init

while IFS=$'\t' read -r env displayName branch valueSet; do
    wsId="$(state_get ".workspaces.\"$env\".id // empty")"
    [[ -n "$wsId" ]] || die "Workspace '$env' not found in state. Run 01-create-workspaces.sh first."
    info "Binding pipeline in '$displayName'..."

    items="$(get_workspace_items "$wsId")"
    pipeId="$(jq -r 'map(select(.type == "DataPipeline" and .displayName == "HospitalOpsETL")) | .[0].id // empty' <<<"$items")"
    nbId="$(jq -r 'map(select(.type == "Notebook" and .displayName == "HospitalETL")) | .[0].id // empty' <<<"$items")"
    if [[ -z "$pipeId" || -z "$nbId" ]]; then
        warn "  pipeline or notebook missing (run the Git sync first). Skipping."
        continue
    fi

    def="$(get_item_definition "$wsId" "$pipeId")"
    payload="$(jq -r '.parts[] | select(.path == "pipeline-content.json") | .payload' <<<"$def")"
    content="$(b64_decode "$payload")"

    newContent="$(jq --arg nb "$nbId" --arg ws "$wsId" '
        .properties.activities |= map(
            if .type == "TridentNotebook"
            then .typeProperties.notebookId = $nb | .typeProperties.workspaceId = $ws
            else . end)' <<<"$content")"

    newPayload="$(b64_encode "$newContent")"
    newDef="$(jq --arg payload "$newPayload" '
        .parts |= map(if .path == "pipeline-content.json" then .payload = $payload else . end)' <<<"$def")"

    update_item_definition "$wsId" "$pipeId" "$newDef"
    ok "  pipeline now runs notebook $nbId."
done < <(cfg '.workspaces[] | [.env, .displayName, .branch, .valueSet] | @tsv')

info "Done."
