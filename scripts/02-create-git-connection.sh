#!/usr/bin/env bash
# Step 2 — Create a reusable Fabric "GitHub source control" connection from a PAT.
#
# GitHub + Service Principal cannot use "Automatic" Git credentials, so we create a
# ConfiguredConnection (credentialType = Key = the GitHub PAT) and reuse its
# connectionId when connecting each workspace to Git in step 3.
#
# Usage:
#   ./scripts/02-create-git-connection.sh
set -euo pipefail
source "$(dirname "$0")/_common.sh"
require_tools

get_fabric_token
state_init

owner="$(cfg '.gitHub.ownerName')"
repo="$(cfg '.gitHub.repositoryName')"
pat="$(cfg '.gitHub.personalAccessToken')"
repoUrl="https://github.com/${owner}/${repo}"
displayName="GitHub-${repo}-demo"

info "Creating GitHub source-control connection for $repoUrl ..."

body="$(jq -n --arg dn "$displayName" --arg url "$repoUrl" --arg pat "$pat" '{
    connectivityType: "ShareableCloud",
    displayName: $dn,
    connectionDetails: {
        type: "GitHubSourceControl",
        creationMethod: "GitHubSourceControl.Contents",
        parameters: [ { dataType: "Text", name: "url", value: $url } ]
    },
    credentialDetails: {
        credentials: { credentialType: "Key", key: $pat }
    }
}')"

connId="$(fabric_api POST "/connections" "$body" | jq -r '.id')"
ok "  connection created: $connId"

state_set_field "gitConnectionId" "$connId"
info "Done. connectionId saved to scripts/.state.json"
