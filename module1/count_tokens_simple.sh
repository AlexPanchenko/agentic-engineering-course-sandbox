#!/usr/bin/env bash
# count_tokens_simple.sh - Minimal Anthropic Token Counter

set -euo pipefail

: "${ANTHROPIC_API_KEY:?Error: ANTHROPIC_API_KEY environment variable is required}"

# 1. If JSON is piped via stdin, use it
if [ ! -t 0 ]; then
  PAYLOAD="$(cat)"
# 2. If a raw JSON string is passed as $1, use it
elif [[ "${1:-}" == \{* ]]; then
  PAYLOAD="$1"
# 3. Otherwise, use simple arguments: [PROMPT] [SYSTEM] [MODEL]
else
  PROMPT="${1:-Hello, Claude}"
  SYSTEM="${2:-You are a scientist}"
  MODEL="${3:-${ANTHROPIC_MODEL:-claude-sonnet-4-6}}"
  PAYLOAD="{\"model\":\"$MODEL\",\"system\":\"$SYSTEM\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}]}"
fi

curl -s https://api.anthropic.com/v1/messages/count_tokens \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$PAYLOAD"
echo
