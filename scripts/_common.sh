# shellcheck shell=bash
# Shared helpers for the Fabric Git-deployment demo setup scripts.
#
# Provides configuration loading, token acquisition (Service Principal or Azure CLI),
# a Fabric REST wrapper with long-running-operation (LRO) polling, state helpers, and
# small base64 utilities. Source this file from the numbered scripts:
#     source "$(dirname "$0")/_common.sh"
#
# Requirements: bash, curl, jq  (and 'az' if you use FABRIC_AUTH=azcli).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FABRIC_API="https://api.fabric.microsoft.com/v1"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.json}"
STATE_FILE="${STATE_FILE:-$SCRIPT_DIR/.state.json}"

# Populated by get_fabric_token.
FABRIC_TOKEN=""

# ANSI colours (no-op if not a tty).
if [[ -t 1 ]]; then
    C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'
else
    C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RESET=""
fi
info()  { printf '%s%s%s\n' "$C_CYAN"   "$*" "$C_RESET"; }
ok()    { printf '%s%s%s\n' "$C_GREEN"  "$*" "$C_RESET"; }
warn()  { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
die()   { printf '%s\n' "$*" >&2; exit 1; }

require_tools() {
    command -v curl >/dev/null 2>&1 || die "curl is required but not installed."
    command -v jq   >/dev/null 2>&1 || die "jq is required but not installed."
}

# ---------------------------------------------------------------------------
# Config & state
# ---------------------------------------------------------------------------

# cfg '.path.to.value'  -> reads a value from config.json
cfg() {
    [[ -f "$CONFIG_FILE" ]] || die "Config not found at '$CONFIG_FILE'. Copy scripts/config.sample.json to scripts/config.json and fill it in."
    jq -r "$1" "$CONFIG_FILE"
}

state_init() {
    [[ -f "$STATE_FILE" ]] || echo '{"workspaces":{}}' > "$STATE_FILE"
}

# state_get '.path'  -> reads a value from .state.json
state_get() {
    state_init
    jq -r "$1" "$STATE_FILE"
}

# state_set_field KEY VALUE  -> sets a top-level string field
state_set_field() {
    state_init
    local tmp; tmp="$(mktemp)"
    jq --arg k "$1" --arg v "$2" '.[$k] = $v' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# state_set_workspace ENV ID DISPLAYNAME BRANCH VALUESET
state_set_workspace() {
    state_init
    local tmp; tmp="$(mktemp)"
    jq --arg env "$1" --arg id "$2" --arg dn "$3" --arg br "$4" --arg vs "$5" \
        '.workspaces[$env] = {id:$id, displayName:$dn, branch:$br, valueSet:$vs}' \
        "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

# get_fabric_token  -> sets FABRIC_TOKEN
#   FABRIC_AUTH=azcli  uses 'az account get-access-token' (reuses 'az login').
#   otherwise          uses OAuth2 client credentials. Values come from the
#                      FABRIC_TENANT_ID / FABRIC_CLIENT_ID / FABRIC_CLIENT_SECRET
#                      env vars if set (CI), else from config.json.
get_fabric_token() {
    local auth="${FABRIC_AUTH:-sp}"
    if [[ "$auth" == "azcli" ]]; then
        command -v az >/dev/null 2>&1 || die "Azure CLI ('az') not found. Run 'az login' or use service principal auth."
        FABRIC_TOKEN="$(az account get-access-token --resource "https://api.fabric.microsoft.com" --query accessToken -o tsv 2>/dev/null || true)"
        [[ -n "$FABRIC_TOKEN" ]] || die "Could not get a token via Azure CLI. Run 'az login' first, or use service principal auth."
        return
    fi

    local tid cid sec
    tid="${FABRIC_TENANT_ID:-$(cfg '.tenantId')}"
    cid="${FABRIC_CLIENT_ID:-$(cfg '.clientId')}"
    sec="${FABRIC_CLIENT_SECRET:-$(cfg '.clientSecret')}"

    local resp
    resp="$(curl -sS -X POST "https://login.microsoftonline.com/${tid}/oauth2/v2.0/token" \
        --data-urlencode "client_id=${cid}" \
        --data-urlencode "client_secret=${sec}" \
        --data-urlencode "scope=https://api.fabric.microsoft.com/.default" \
        --data-urlencode "grant_type=client_credentials")"
    FABRIC_TOKEN="$(jq -r '.access_token // empty' <<<"$resp" 2>/dev/null)"
    if [[ -z "$FABRIC_TOKEN" ]]; then
        die "Failed to acquire Fabric token: $(jq -r '"\(.error // "unknown") - \(.error_description // "no detail" | .[0:200])"' <<<"$resp" 2>/dev/null)"
    fi
}

# ---------------------------------------------------------------------------
# Fabric REST wrapper (handles 202 Accepted long-running operations)
# ---------------------------------------------------------------------------

# _header_value HEADERS_FILE NAME  -> last value of a (case-insensitive) header
_header_value() {
    grep -i "^$2:" "$1" 2>/dev/null | tail -1 | sed -E "s/^[^:]+:[[:space:]]*//" | tr -d '\r'
}

# fabric_api METHOD PATH [JSON_BODY]  -> prints the final JSON result on stdout.
# PATH may be relative to /v1 (start with '/') or an absolute URL.
fabric_api() {
    local method="$1" path="$2" body="${3:-}"
    local url
    if [[ "$path" == http* ]]; then url="$path"; else url="${FABRIC_API}${path}"; fi

    local hfile bfile status
    hfile="$(mktemp)"; bfile="$(mktemp)"

    if [[ -n "$body" ]]; then
        status="$(curl -sS -D "$hfile" -o "$bfile" -w '%{http_code}' -X "$method" "$url" \
            -H "Authorization: Bearer $FABRIC_TOKEN" \
            -H "Content-Type: application/json" \
            --data "$body")"
    elif [[ "$method" == "GET" ]]; then
        status="$(curl -sS -D "$hfile" -o "$bfile" -w '%{http_code}' -X "$method" "$url" \
            -H "Authorization: Bearer $FABRIC_TOKEN")"
    else
        # Bodyless POST/PUT/PATCH/DELETE: send an explicit empty body so curl
        # emits Content-Length: 0. Without it some Fabric endpoints (e.g.
        # getDefinition) return HTTP 411 Length Required.
        status="$(curl -sS -D "$hfile" -o "$bfile" -w '%{http_code}' -X "$method" "$url" \
            -H "Authorization: Bearer $FABRIC_TOKEN" \
            -H "Content-Length: 0" \
            --data '')"
    fi

    if [[ "$status" -ge 400 ]]; then
        local content; content="$(cat "$bfile")"
        rm -f "$hfile" "$bfile"
        echo "Fabric API $method $path failed ($status): $content" >&2
        return 1
    fi

    # Long-running operation: poll until it completes.
    if [[ "$status" == "202" ]]; then
        local op_url retry
        op_url="$(_header_value "$hfile" 'Location')"
        retry="$(_header_value "$hfile" 'Retry-After')"
        [[ "$retry" =~ ^[0-9]+$ ]] || retry=5
        rm -f "$hfile" "$bfile"

        # Some 202 responses (e.g. assignToCapacity) are fire-and-forget and
        # return no operation URL to poll. Treat them as accepted.
        if [[ -z "$op_url" ]]; then
            return 0
        fi

        local attempts=0 max_attempts=120 wait_s
        wait_s="$(( retry > 3 ? retry : 3 ))"
        while (( attempts < max_attempts )); do
            sleep "$wait_s"
            attempts=$(( attempts + 1 ))
            local op_status opfile op_http
            opfile="$(mktemp)"
            op_http="$(curl -sS -o "$opfile" -w '%{http_code}' -X GET "$op_url" \
                -H "Authorization: Bearer $FABRIC_TOKEN" || echo 000)"
            op_status="$(jq -r '.status // empty' "$opfile" 2>/dev/null || true)"
            rm -f "$opfile"
            printf '    ...operation status: %s\n' "${op_status:-pending}" >&2
            case "$op_status" in
                Succeeded|Completed)
                    local rstatus rfile
                    rfile="$(mktemp)"
                    rstatus="$(curl -sS -D /dev/null -o "$rfile" -w '%{http_code}' -X GET "${op_url}/result" -H "Authorization: Bearer $FABRIC_TOKEN" || echo 000)"
                    if [[ "$rstatus" -lt 400 && -s "$rfile" ]]; then cat "$rfile"; fi
                    rm -f "$rfile"
                    return 0
                    ;;
                Failed|Cancelled)
                    echo "Fabric operation failed (status: $op_status)" >&2
                    return 1
                    ;;
            esac
            # If the status URL itself errors (e.g. 404) there is nothing to poll.
            if [[ "$op_http" == "404" || "$op_http" == "000" ]]; then
                return 0
            fi
        done
        echo "Fabric operation timed out after $max_attempts polls: $op_url" >&2
        return 1
    fi


    cat "$bfile"
    rm -f "$hfile" "$bfile"
}

# ---------------------------------------------------------------------------
# Power BI REST API (api.powerbi.com) — needed for binding a semantic model's
# data source to a cloud connection. Power BI endpoints require a token with
# the Power BI audience, which is distinct from the Fabric token.
# ---------------------------------------------------------------------------
PBI_API="https://api.powerbi.com/v1.0/myorg"

# get_powerbi_token  -> sets PBI_TOKEN (mirrors get_fabric_token's auth modes).
get_powerbi_token() {
    local auth="${FABRIC_AUTH:-sp}"
    if [[ "$auth" == "azcli" ]]; then
        command -v az >/dev/null 2>&1 || die "Azure CLI ('az') not found. Run 'az login' or use service principal auth."
        PBI_TOKEN="$(az account get-access-token --resource "https://analysis.windows.net/powerbi/api" --query accessToken -o tsv 2>/dev/null || true)"
        [[ -n "$PBI_TOKEN" ]] || die "Could not get a Power BI token via Azure CLI. Run 'az login' first, or use service principal auth."
        return
    fi

    local tid cid sec
    tid="${FABRIC_TENANT_ID:-$(cfg '.tenantId')}"
    cid="${FABRIC_CLIENT_ID:-$(cfg '.clientId')}"
    sec="${FABRIC_CLIENT_SECRET:-$(cfg '.clientSecret')}"

    PBI_TOKEN="$(curl -sS -X POST "https://login.microsoftonline.com/${tid}/oauth2/v2.0/token" \
        --data-urlencode "client_id=${cid}" \
        --data-urlencode "client_secret=${sec}" \
        --data-urlencode "scope=https://analysis.windows.net/powerbi/api/.default" \
        --data-urlencode "grant_type=client_credentials" | jq -r '.access_token')"
    [[ -n "$PBI_TOKEN" && "$PBI_TOKEN" != "null" ]] || die "Failed to acquire Power BI token (check tenant/client/secret)."
}

# pbi_api METHOD PATH [JSON_BODY]  -> prints the response body; nonzero on HTTP>=400.
pbi_api() {
    local method="$1" path="$2" body="${3:-}"
    local url; if [[ "$path" == http* ]]; then url="$path"; else url="${PBI_API}${path}"; fi

    local bfile status
    bfile="$(mktemp)"
    if [[ -n "$body" ]]; then
        status="$(curl -sS -o "$bfile" -w '%{http_code}' -X "$method" "$url" \
            -H "Authorization: Bearer $PBI_TOKEN" -H "Content-Type: application/json" --data "$body")"
    elif [[ "$method" == "GET" ]]; then
        status="$(curl -sS -o "$bfile" -w '%{http_code}' -X "$method" "$url" \
            -H "Authorization: Bearer $PBI_TOKEN")"
    else
        status="$(curl -sS -o "$bfile" -w '%{http_code}' -X "$method" "$url" \
            -H "Authorization: Bearer $PBI_TOKEN" -H "Content-Length: 0" --data '')"
    fi

    if [[ "$status" -ge 400 ]]; then
        local content; content="$(cat "$bfile")"; rm -f "$bfile"
        echo "Power BI API $method $path failed ($status): $content" >&2
        return 1
    fi
    cat "$bfile"; rm -f "$bfile"
}

# ---------------------------------------------------------------------------
# Item helpers
# ---------------------------------------------------------------------------

# get_workspace_items WORKSPACE_ID  -> prints the items array (JSON)
get_workspace_items() {
    fabric_api GET "/workspaces/$1/items" | jq '.value'
}

# get_item_definition WORKSPACE_ID ITEM_ID  -> prints the .definition object (JSON)
get_item_definition() {
    fabric_api POST "/workspaces/$1/items/$2/getDefinition" | jq '.definition'
}

# update_item_definition WORKSPACE_ID ITEM_ID DEFINITION_JSON
update_item_definition() {
    local body; body="$(jq -n --argjson def "$3" '{definition:$def}')"
    fabric_api POST "/workspaces/$1/items/$2/updateDefinition" "$body" >/dev/null
}

# b64_decode / b64_encode (UTF-8)
b64_decode() { printf '%s' "$1" | base64 -d; }
b64_encode() { printf '%s' "$1" | base64 -w0; }
