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
get_powerbi_token
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

    # --- Bind the model to a Service Principal cloud connection so refresh works ---
    # Without an explicit connection the SQL endpoint defaults to single sign-on,
    # which the owning Service Principal cannot use non-interactively (refresh
    # fails: "default data connection without explicit connection credentials").
    # We create a shareable cloud connection authenticated as the SP and bind the
    # model's SQL data source to it.
    connName="HospitalOps-SQL-$env"
    connId="$(fabric_api GET "/connections" \
        | jq -r --arg n "$connName" '.value | map(select(.displayName == $n)) | .[0].id // empty')"
    if [[ -z "$connId" ]]; then
        connBody="$(jq -n \
            --arg n "$connName" --arg srv "$sqlEndpoint" --arg db "Healthcare" \
            --arg tid "$(cfg '.tenantId')" --arg cid "$(cfg '.clientId')" --arg sec "$(cfg '.clientSecret')" '{
            connectivityType: "ShareableCloud",
            displayName: $n,
            connectionDetails: {
                type: "SQL",
                creationMethod: "SQL",
                parameters: [
                    { dataType: "Text", name: "server",   value: $srv },
                    { dataType: "Text", name: "database", value: $db }
                ]
            },
            credentialDetails: {
                singleSignOnType: "None",
                connectionEncryption: "NotEncrypted",
                skipTestConnection: false,
                credentials: {
                    credentialType: "ServicePrincipal",
                    tenantId: $tid,
                    servicePrincipalClientId: $cid,
                    servicePrincipalSecret: $sec
                }
            }
        }')"
        if connOut="$(fabric_api POST "/connections" "$connBody" 2>&1)"; then
            connId="$(jq -r '.id // empty' <<<"$connOut")"
            ok "  created SP cloud connection '$connName' ($connId)."
        else
            echo "$connOut" >&2
            warn "  could not create cloud connection; skipping bind (refresh may fail)."
        fi
    else
        echo "  reusing cloud connection '$connName' ($connId)."
    fi

    # Grant the contributor Entra group access to the connection so humans can
    # see and manage it in the portal (e.g. to remap the model's data source).
    groupId="$(cfg '.contributorGroupId // empty')"
    if [[ -n "$connId" && -n "$groupId" && "$groupId" != 00000000-0000-0000-0000-000000000000 ]]; then
        craBody="$(jq -n --arg gid "$groupId" '{principal:{id:$gid, type:"Group"}, role:"Owner"}')"
        if craOut="$(fabric_api POST "/connections/$connId/roleAssignments" "$craBody" 2>&1)"; then
            echo "    connection shared with group as Owner."
        elif grep -qiE 'already|exists|PrincipalAlready' <<<"$craOut"; then
            echo "    group already has access to the connection."
        else
            echo "$craOut" >&2
            warn "    could not share connection with group."
        fi
    fi

    if [[ -n "$connId" ]]; then
        # Take ownership as the SP, locate the model's cloud gateway, then bind the
        # SQL data source to our Service Principal connection.
        pbi_api POST "/groups/$wsId/datasets/$modelId/Default.TakeOver" >/dev/null 2>&1 || true
        gwId="$(pbi_api GET "/groups/$wsId/datasets/$modelId/datasources" 2>/dev/null \
            | jq -r '.value | map(select(.gatewayId != null)) | .[0].gatewayId // empty')"
        if [[ -z "$gwId" ]]; then
            gwId="$(pbi_api GET "/groups/$wsId/datasets/$modelId/Default.DiscoverGateways" 2>/dev/null \
                | jq -r '.value[0].id // empty')"
        fi
        if [[ -n "$gwId" ]]; then
            bindBody="$(jq -n --arg gw "$gwId" --arg ds "$connId" \
                '{gatewayObjectId: $gw, datasourceObjectIds: [$ds]}')"
            if pbi_api POST "/groups/$wsId/datasets/$modelId/Default.BindToGateway" "$bindBody" >/dev/null 2>&1; then
                ok "  model bound to SP connection."
            else
                warn "  bind call failed. In the model's Settings > Gateway and cloud connections, set 'Maps to' = '$connName'."
            fi
        else
            warn "  no bindable gateway found. In model Settings, set 'Maps to' = '$connName'."
        fi
    fi

    # Kick off a refresh so the model picks up data.
    if fabric_api POST "/workspaces/$wsId/semanticModels/$modelId/refreshes" '{"type":"Full"}' >/dev/null 2>&1; then
        echo "  refresh started."
    else
        warn "  refresh skipped (model may not be bound to a gateway/credentials yet)."
    fi
done < <(cfg '.workspaces[] | [.env, .displayName, .branch, .valueSet] | @tsv')

info "Done."
