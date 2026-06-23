#!/usr/bin/env bash
# Step 1 — Create the four Fabric workspaces and assign capacity.
#
# Usage:
#   ./scripts/01-create-workspaces.sh              # Service Principal auth (default)
#   FABRIC_AUTH=azcli ./scripts/01-create-workspaces.sh   # use 'az login' instead
set -euo pipefail
source "$(dirname "$0")/_common.sh"
require_tools

get_fabric_token
state_init

info "Creating workspaces..."
existing="$(fabric_api GET "/workspaces" | jq '.value')"

# Iterate workspaces defined in config.json.
while IFS=$'\t' read -r env displayName branch valueSet; do
    found_id="$(jq -r --arg dn "$displayName" 'map(select(.displayName == $dn)) | .[0].id // empty' <<<"$existing")"
    if [[ -n "$found_id" ]]; then
        warn "  '$displayName' already exists ($found_id)."
        wsId="$found_id"
    else
        body="$(jq -n --arg dn "$displayName" --arg env "$env" \
            '{displayName:$dn, description:("Healthcare Git-deployment demo (" + $env + ")")}')"
        wsId="$(fabric_api POST "/workspaces" "$body" | jq -r '.id')"
        ok "  created '$displayName' ($wsId)."
    fi

    # Assign capacity (idempotent). assignToCapacity returns 202 fire-and-forget.
    capBody="$(jq -n --arg cap "$(cfg '.capacityId')" '{capacityId:$cap}')"
    if fabric_api POST "/workspaces/$wsId/assignToCapacity" "$capBody" >/dev/null; then
        echo "    capacity assigned."
    else
        warn "    capacity assignment skipped (already assigned or insufficient permission)."
    fi

    # Grant an Entra ID group Contributor on the workspace. Workspaces created by
    # a Service Principal aren't visible to users (even tenant Fabric admins)
    # until a workspace role is assigned, so add the group here.
    groupId="$(cfg '.contributorGroupId // empty')"
    if [[ -n "$groupId" && "$groupId" != 00000000-0000-0000-0000-000000000000 ]]; then
        roleBody="$(jq -n --arg id "$groupId" '{principal:{id:$id, type:"Group"}, role:"Admin"}')"
        if roleOut="$(fabric_api POST "/workspaces/$wsId/roleAssignments" "$roleBody" 2>&1)"; then
            echo "    group $groupId added as Admin."
        elif grep -qiE 'already|PrincipalAlreadyHasRoleAssignment' <<<"$roleOut"; then
            echo "    group already has a role assignment."
        else
            echo "$roleOut" >&2
            warn "    could not assign group role (continuing)."
        fi
    else
        warn "    no contributorGroupId set in config.json - skipping group role assignment."
    fi

    state_set_workspace "$env" "$wsId" "$displayName" "$branch" "$valueSet"
done < <(cfg '.workspaces[] | [.env, .displayName, .branch, .valueSet] | @tsv')

info "Done. Workspace IDs saved to scripts/.state.json"
