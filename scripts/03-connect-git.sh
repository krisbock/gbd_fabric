#!/usr/bin/env bash
# Step 3 — Connect each workspace to its branch with Git folder = "fabric", then sync.
#
# For each workspace: git/connect (directoryName = fabric, using the configured
# connection) -> git/initializeConnection -> if the workspace needs content,
# git/updateFromGit (polled as a long-running operation).
#
# Usage:
#   ./scripts/03-connect-git.sh
set -euo pipefail
source "$(dirname "$0")/_common.sh"
require_tools

get_fabric_token
state_init

connId="$(state_get '.gitConnectionId // empty')"
[[ -n "$connId" ]] || die "No gitConnectionId in state. Run 02-create-git-connection.sh first."

owner="$(cfg '.gitHub.ownerName')"
repo="$(cfg '.gitHub.repositoryName')"
directory="$(cfg '.directoryName')"

while IFS=$'\t' read -r env displayName branch valueSet; do
    wsId="$(state_get ".workspaces.\"$env\".id // empty")"
    [[ -n "$wsId" ]] || die "Workspace '$env' not found in state. Run 01-create-workspaces.sh first."
    info "Connecting '$displayName' to branch '$branch' (folder '$directory')..."

    # 3a. Connect.
    connectBody="$(jq -n --arg owner "$owner" --arg repo "$repo" --arg branch "$branch" \
        --arg dir "$directory" --arg conn "$connId" '{
            gitProviderDetails: {
                gitProviderType: "GitHub",
                ownerName: $owner,
                repositoryName: $repo,
                branchName: $branch,
                directoryName: $dir
            },
            myGitCredentials: { source: "ConfiguredConnection", connectionId: $conn }
        }')"
    # 3a. Connect. Capture the response so a genuine failure is surfaced
    # instead of being silently treated as "already connected".
    connectOut=""
    if connectOut="$(fabric_api POST "/workspaces/$wsId/git/connect" "$connectBody" 2>&1)"; then
        echo "  connected."
    elif grep -qiE 'already connected|AlreadyConnected|WorkspaceAlreadyConnectedToGit' <<<"$connectOut"; then
        warn "  already connected."
    else
        echo "$connectOut" >&2
        die "  git/connect failed for '$displayName'. Check the GitHub PAT/connection (run 02-create-git-connection.sh) and that the repo + branch '$branch' exist."
    fi

    # 3b. Initialize the connection (decide direction).
    initBody='{"initializationStrategy":"PreferRemote"}'
    init="$(fabric_api POST "/workspaces/$wsId/git/initializeConnection" "$initBody")"
    requiredAction="$(jq -r '.requiredAction // empty' <<<"$init")"
    echo "  initialize: RequiredAction = ${requiredAction:-none}"

    # 3c. Pull the branch content into the workspace if needed.
    if [[ "$requiredAction" == "UpdateFromGit" ]]; then
        echo "  updating workspace from Git..."
        updBody="$(jq -n \
            --arg rc "$(jq -r '.remoteCommitHash // empty' <<<"$init")" \
            --arg wh "$(jq -r '.workspaceHead // empty' <<<"$init")" '{
                remoteCommitHash: $rc,
                workspaceHead: $wh,
                conflictResolution: { conflictResolutionType: "Workspace", conflictResolutionPolicy: "PreferRemote" },
                options: { allowOverrideItems: true }
            }')"
        fabric_api POST "/workspaces/$wsId/git/updateFromGit" "$updBody" >/dev/null
        ok "  workspace synced to '$branch'."
    else
        ok "  nothing to sync."
    fi
done < <(cfg '.workspaces[] | [.env, .displayName, .branch, .valueSet] | @tsv')

info "Done. All workspaces connected and synced."
info "Next: run 04-set-active-valueset.sh then bind-pipeline.sh / bind-semanticmodel.sh."
