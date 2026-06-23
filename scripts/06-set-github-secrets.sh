#!/usr/bin/env bash
# Push the GitHub Actions secrets that the deploy-*.yml workflows consume.
#
# The CI workflows (.github/workflows/deploy-dev|test|prod.yml) read their inputs
# from repository secrets. Run this once after config.json is filled in and the
# workspaces exist in .state.json (i.e. after 01-create-workspaces.sh), so the
# Actions runs have the service principal credentials and workspace IDs they need.
#
# Sets these repository secrets:
#     FABRIC_CLIENT_ID, FABRIC_CLIENT_SECRET, FABRIC_TENANT_ID   (service principal)
#     DEV_WORKSPACE_ID, TEST_WORKSPACE_ID, PROD_WORKSPACE_ID     (target workspaces)
#
# Auth: uses the GitHub PAT from config.json (.gitHub.personalAccessToken) via the
# GitHub CLI, which seals each value with the repo public key before uploading.
set -euo pipefail
source "$(dirname "$0")/_common.sh"
require_tools
command -v gh >/dev/null 2>&1 || die "GitHub CLI ('gh') is required but not installed. See https://cli.github.com/."

owner="$(cfg '.gitHub.ownerName')"
repo="$(cfg '.gitHub.repositoryName')"
pat="$(cfg '.gitHub.personalAccessToken')"
[[ -n "$owner" && "$owner" != "null" ]] || die "config.json: .gitHub.ownerName is not set."
[[ -n "$repo"  && "$repo"  != "null" ]] || die "config.json: .gitHub.repositoryName is not set."
[[ -n "$pat"   && "$pat"   != "null" && "$pat" != "REPLACE_WITH_GITHUB_PAT" ]] \
    || die "config.json: .gitHub.personalAccessToken is not set."

# Authenticate the gh CLI with the PAT (repo + secrets scopes required).
export GH_TOKEN="$pat"
slug="$owner/$repo"

# set_secret NAME VALUE  -> uploads a repo secret unless the value is empty/placeholder.
set_secret() {
    local name="$1" value="$2"
    # Strip stray whitespace/carriage returns so a CRLF-sourced value never leaks
    # a trailing \r into the secret (which would corrupt Fabric REST URLs in CI).
    value="$(printf '%s' "$value" | tr -d '[:space:]')"
    if [[ -z "$value" || "$value" == "null" \
        || "$value" == "REPLACE_OR_USE_AZ_CLI" \
        || "$value" == "00000000-0000-0000-0000-000000000000" ]]; then
        warn "  skipping $name (value not set in config.json/.state.json)."
        return
    fi
    if printf '%s' "$value" | gh secret set "$name" --repo "$slug" --body - >/dev/null 2>&1; then
        ok "  set $name."
    else
        die "  failed to set $name on $slug (check the PAT has 'repo' + secrets access)."
    fi
}

info "Setting GitHub Actions secrets on $slug ..."

# Service principal credentials (shared by all environments).
set_secret FABRIC_CLIENT_ID     "$(cfg '.clientId')"
set_secret FABRIC_CLIENT_SECRET "$(cfg '.clientSecret')"
set_secret FABRIC_TENANT_ID     "$(cfg '.tenantId')"

# Per-environment workspace IDs (from .state.json, written by 01-create-workspaces.sh).
set_secret DEV_WORKSPACE_ID  "$(state_get '.workspaces.Dev.id  // empty')"
set_secret TEST_WORKSPACE_ID "$(state_get '.workspaces.Test.id // empty')"
set_secret PROD_WORKSPACE_ID "$(state_get '.workspaces.Prod.id // empty')"

ok "GitHub Actions secrets updated on $slug."
