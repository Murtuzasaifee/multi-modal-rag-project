#!/usr/bin/env bash
# set_github_secrets.sh — Push .env values to GitHub Actions secrets via gh CLI
#
# Usage:
#   ./scripts/set_github_secrets.sh                        # uses .env in repo root
#   ./scripts/set_github_secrets.sh --env .env.production  # custom env file
#   ./scripts/set_github_secrets.sh --repo owner/repo      # explicit repo target
#
# Prerequisites:
#   gh auth login   (must be authenticated)
#   gh --version    (must be 2.x)

set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────
ENV_FILE=".env"
REPO_FLAG=""

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)   ENV_FILE="$2"; shift 2 ;;
    --repo)  REPO_FLAG="--repo $2"; shift 2 ;;
    *)       echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Preflight checks ─────────────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI not found. Install from https://cli.github.com" >&2
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "Error: not authenticated. Run: gh auth login" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: env file not found: $ENV_FILE" >&2
  exit 1
fi

# ── Keys to push from .env ───────────────────────────────────────────────────
GITHUB_SECRET_KEYS=(
  Z_AI_API_KEY
  OPENAI_API_KEY
  GEMINI_API_KEY
  JINA_API_KEY
  QDRANT_API_KEY
)

# ── AWS / ECS vars — prompted if not in .env ─────────────────────────────────
AWS_SECRET_KEYS=(
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  AWS_REGION
  ECR_REGISTRY
  ECS_CLUSTER
  ECS_SERVICE_APP
  ECS_SERVICE_VISUALIZER
)

# ── Parse .env into an associative array ─────────────────────────────────────
declare -A ENV_VALUES

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" || "$line" != *=* ]] && continue
  key="${line%%=*}"
  value="${line#*=}"
  value="${value#\"}" ; value="${value%\"}"
  value="${value#\'}" ; value="${value%\'}"
  ENV_VALUES["$key"]="$value"
done < "$ENV_FILE"

# ── Helper: set one secret ────────────────────────────────────────────────────
set_secret() {
  local key="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "  SKIP  $key  (empty)"
    return
  fi
  # shellcheck disable=SC2086
  if printf '%s' "$value" | gh secret set "$key" $REPO_FLAG --body -; then
    echo "  SET   $key"
  else
    echo "  FAIL  $key" >&2
  fi
}

# ── Push app secrets from .env ────────────────────────────────────────────────
echo
echo "==> Pushing app secrets from $ENV_FILE"
echo

for key in "${GITHUB_SECRET_KEYS[@]}"; do
  set_secret "$key" "${ENV_VALUES[$key]:-}"
done

# ── Push AWS/ECS secrets ──────────────────────────────────────────────────────
echo
echo "==> Pushing AWS / ECS deployment secrets"
echo "    (reads from $ENV_FILE if present, otherwise prompts)"
echo

for key in "${AWS_SECRET_KEYS[@]}"; do
  value="${ENV_VALUES[$key]:-}"
  if [[ -z "$value" ]]; then
    case "$key" in
      AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|ECR_REGISTRY)
        read -rsp "  Enter $key: " value; echo ;;
      *)
        read -rp  "  Enter $key: " value ;;
    esac
  fi
  set_secret "$key" "$value"
done

echo
echo "Done. Verify at: gh secret list $REPO_FLAG"
