#!/usr/bin/env bash
# Step 5 — Populate every workspace by running the HospitalETL notebook.
#
# Runs the notebook on-demand in each workspace. The notebook reads that workspace's active
# Variable Library value set, so each environment gets data at its own scale and writes its
# own env_banner row. No file upload required.
#
# Usage:
#   ./scripts/05-load-data.sh
set -euo pipefail
source "$(dirname "$0")/_common.sh"
require_tools

get_fabric_token
state_init

while IFS=$'\t' read -r env displayName branch valueSet; do
    wsId="$(state_get ".workspaces.\"$env\".id // empty")"
    [[ -n "$wsId" ]] || die "Workspace '$env' not found in state. Run 01-create-workspaces.sh first."
    info "Running HospitalETL in '$displayName'..."

    nbId="$(get_workspace_items "$wsId" \
        | jq -r 'map(select(.type == "Notebook" and .displayName == "HospitalETL")) | .[0].id // empty')"
    if [[ -z "$nbId" ]]; then
        warn "  HospitalETL missing. Skipping."
        continue
    fi

    fabric_api POST "/workspaces/$wsId/items/$nbId/jobs/instances?jobType=RunNotebook" '{"executionData":{}}' >/dev/null
    ok "  notebook run completed; env_banner written for '$valueSet'."
done < <(cfg '.workspaces[] | [.env, .displayName, .branch, .valueSet] | @tsv')

info "Done. Refresh the HospitalOps model (bind-semanticmodel.sh does this) to see the data."
