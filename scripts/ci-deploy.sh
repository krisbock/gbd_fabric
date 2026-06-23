#!/usr/bin/env bash
# CI deployment step run by GitHub Actions — sync ONE workspace to its branch and set its environment.
#
# Designed to run in GitHub Actions (no config.json / state file). All inputs come from
# environment variables / secrets:
#     FABRIC_CLIENT_ID, FABRIC_CLIENT_SECRET, FABRIC_TENANT_ID   (service principal)
#     WORKSPACE_ID                                               (target workspace)
#     VALUE_SET                                                  (Dev | Test | Prod)
#     RUN_ETL  (optional, "true" to run the notebook + refresh the model)
# Steps: initializeConnection -> updateFromGit (LRO) -> set active value set -> optional ETL + refresh.
set -euo pipefail
source "$(dirname "$0")/_common.sh"
require_tools

for v in FABRIC_CLIENT_ID FABRIC_CLIENT_SECRET FABRIC_TENANT_ID WORKSPACE_ID VALUE_SET; do
    [[ -n "${!v:-}" ]] || die "Missing required env var: $v"
done

# Strip any stray whitespace/carriage returns (a trailing \r from a CRLF-sourced
# secret would otherwise corrupt every Fabric REST URL and yield HTTP 400).
trim() { printf '%s' "$1" | tr -d '[:space:]'; }
wsId="$(trim "$WORKSPACE_ID")"
valueSet="$(trim "$VALUE_SET")"
get_fabric_token   # uses FABRIC_* env vars

echo "::group::Update workspace $wsId from Git"
# The workspace was connected to Git once during setup (03-connect-git.sh), so its
# connection is already initialized. initializeConnection only succeeds the first
# time; on later runs it returns 400/AlreadyInitialized. Try it, and on any failure
# fall back to git/status to read the commit hashes and decide whether to sync.
requiredAction=""
remoteCommitHash=""
workspaceHead=""
if init="$(fabric_api POST "/workspaces/$wsId/git/initializeConnection" '{"initializationStrategy":"PreferRemote"}' 2>&1)"; then
    requiredAction="$(jq -r '.requiredAction // empty' <<<"$init")"
    remoteCommitHash="$(jq -r '.remoteCommitHash // empty' <<<"$init")"
    workspaceHead="$(jq -r '.workspaceHead // empty' <<<"$init")"
else
    echo "initializeConnection unavailable (likely already initialized); using git/status."
    if status="$(fabric_api GET "/workspaces/$wsId/git/status" 2>&1)"; then
        remoteCommitHash="$(jq -r '.remoteCommitHash // empty' <<<"$status")"
        workspaceHead="$(jq -r '.workspaceHead // empty' <<<"$status")"
        if [[ -n "$remoteCommitHash" && "$remoteCommitHash" != "$workspaceHead" ]]; then
            requiredAction="UpdateFromGit"
        else
            requiredAction="None"
        fi
    else
        echo "$init" >&2
        echo "$status" >&2
        die "Could not initialize or read Git status for workspace $wsId. Ensure it is connected to Git (run scripts/03-connect-git.sh once)."
    fi
fi
echo "RequiredAction = ${requiredAction:-none}"

if [[ "$requiredAction" == "UpdateFromGit" ]]; then
    updBody="$(jq -n \
        --arg rc "$remoteCommitHash" \
        --arg wh "$workspaceHead" '{
            remoteCommitHash: $rc,
            workspaceHead: $wh,
            conflictResolution: { conflictResolutionType: "Workspace", conflictResolutionPolicy: "PreferRemote" },
            options: { allowOverrideItems: true }
        }')"
    fabric_api POST "/workspaces/$wsId/git/updateFromGit" "$updBody" >/dev/null
    echo "Workspace synced."
else
    echo "Already up to date."
fi
echo "::endgroup::"

echo "::group::Set active value set = $valueSet"
libId="$(fabric_api GET "/workspaces/$wsId/VariableLibraries" \
    | jq -r '.value | map(select(.displayName == "EnvConfig")) | .[0].id // empty')"
if [[ -n "$libId" ]]; then
    patchBody="$(jq -n --arg vs "$valueSet" '{properties: {activeValueSetName: $vs}}')"
    fabric_api PATCH "/workspaces/$wsId/VariableLibraries/$libId" "$patchBody" >/dev/null
    echo "Active value set = $valueSet"
else
    echo "EnvConfig variable library not found; skipping value set."
fi
echo "::endgroup::"

if [[ "${RUN_ETL:-}" == "true" ]]; then
    echo "::group::Run ETL + refresh model"
    items="$(get_workspace_items "$wsId")"
    nbId="$(jq -r 'map(select(.type == "Notebook" and .displayName == "HospitalETL")) | .[0].id // empty' <<<"$items")"
    if [[ -n "$nbId" ]]; then
        fabric_api POST "/workspaces/$wsId/items/$nbId/jobs/instances?jobType=RunNotebook" '{"executionData":{}}' >/dev/null
        echo "Notebook run completed."
    fi
    modelId="$(jq -r 'map(select(.type == "SemanticModel" and .displayName == "HospitalOps")) | .[0].id // empty' <<<"$items")"
    if [[ -n "$modelId" ]]; then
        if fabric_api POST "/workspaces/$wsId/semanticModels/$modelId/refreshes" '{"type":"Full"}' >/dev/null 2>&1; then
            echo "Model refresh started."
        else
            echo "Model refresh skipped."
        fi
    fi
    echo "::endgroup::"
fi

ok "Deployment to workspace $wsId ($valueSet) complete."
