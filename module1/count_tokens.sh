#!/usr/bin/env bash
# count_tokens.sh - Count tokens for Anthropic Claude API requests
# Supports all inputs, formats, and parameters of /v1/messages/count_tokens

set -euo pipefail

API_URL="${ANTHROPIC_COUNT_TOKENS_URL:-https://api.anthropic.com/v1/messages/count_tokens}"
API_VERSION="${ANTHROPIC_API_VERSION:-2023-06-01}"
API_KEY="${ANTHROPIC_API_KEY:-}"

# Parse options
JSON_INPUT=""
FILE_INPUT=""
USE_STDIN=0
DEFAULT_FALLBACK_MODEL="claude-sonnet-4-6"
MODEL="${ANTHROPIC_MODEL:-$DEFAULT_FALLBACK_MODEL}"
MODEL_EXPLICIT=0
SYSTEM_TEXT=""
SYSTEM_FILE=""
SYSTEM_JSON=""
PROMPT_TEXT=""
PROMPT_FILE=""
MESSAGES_JSON=""
MESSAGES_FILE=""
TOOLS_INPUT=""
TOOL_CHOICE_INPUT=""
THINKING_BUDGET=""
THINKING_JSON=""
VERBOSE=0
RAW_OUTPUT=0
DRY_RUN=0
BETA_HEADERS=()
CONVERSATION_EVENTS=() # Encoded user/assistant/media events in order

usage() {
  cat << 'EOF'
Usage: count_tokens.sh [OPTIONS]

A comprehensive CLI script for Anthropic's /v1/messages/count_tokens API.
Calculates token counts for text, images, documents, tools, and thinking configurations.

INPUT MODES (Direct JSON Payload):
  -j, --json JSON_STRING      Complete request JSON payload as a string
  -f, --file FILE             Read complete request JSON payload from a file
  -                           Read complete request JSON payload from stdin (or pipe)

MODULAR PARAMETERS (Builds request JSON automatically):
  -m, --model MODEL           Model ID (e.g. claude-sonnet-4-6, claude-opus-5-5)
                              [Default: $ANTHROPIC_MODEL or claude-sonnet-4-6]
  -s, --system TEXT           System prompt as a text string
      --system-file FILE      Read system prompt from a text file
      --system-json JSON      System prompt as JSON array (for cached/structured blocks)
  -p, --prompt TEXT           Quick single user prompt
      --prompt-file FILE      Read single user prompt from file
  -u, --user TEXT             Add a user text message (can be repeated for multi-turn)
  -a, --assistant TEXT        Add an assistant text message (can be repeated for multi-turn)
      --image FILE            Attach an image (PNG, JPEG, GIF, WEBP) to current user message
      --document FILE         Attach a PDF document to current user message
      --messages JSON         Full messages array JSON string
      --messages-file FILE    Read messages array from JSON file
  -t, --tools JSON_OR_FILE    Tools definitions (JSON array string or JSON file path)
  -c, --tool-choice CHOICE    Tool choice ('auto', 'any', 'none', tool name, or JSON object)
      --thinking-budget NUM   Enable extended thinking with token budget (integer)
      --thinking JSON         Full thinking configuration JSON object

API CONFIGURATION:
  -k, --api-key KEY           Anthropic API key (defaults to $ANTHROPIC_API_KEY)
      --api-version VER       Anthropic API version header [Default: 2023-06-01]
  -b, --beta FEATURE          Anthropic beta header (can be repeated, e.g. prompt-caching-2024-07-31)
      --endpoint URL          API endpoint URL [Default: https://api.anthropic.com/v1/messages/count_tokens]

OUTPUT & DEBUGGING:
  -v, --verbose               Show curl command details and HTTP headers
  -r, --raw                   Output raw JSON response (skip jq pretty-print)
      --dry-run               Print the generated JSON payload and exit without calling the API
  -h, --help                  Show this help message

EXAMPLES:
  # 1. Quick token count with draft parameters:
  ./count_tokens.sh -m claude-opus-5-5 -s "You are a scientist" -p "Hello, Claude"

  # 2. Piping full JSON from stdin:
  curl ... | ./count_tokens.sh -
  echo '{"model":"claude-3-5-sonnet-20241022","messages":[{"role":"user","content":"Hi"}]}' | ./count_tokens.sh

  # 3. Reading complete JSON from a file:
  ./count_tokens.sh -f request.json

  # 4. Multi-turn conversation with image attachment:
  ./count_tokens.sh -m claude-3-5-sonnet-20241022 \
    -u "Here is a screenshot" --image screenshot.png \
    -a "I see the screenshot. What would you like to know?" \
    -u "What is the error on screen?"

  # 5. Token count with PDF document:
  ./count_tokens.sh --document paper.pdf -p "Summarize this paper"

  # 6. With tools and tool_choice:
  ./count_tokens.sh -p "What's the weather in Tokyo?" \
    --tools '[{"name":"get_weather","description":"Get current weather","input_schema":{"type":"object","properties":{"location":{"type":"string"}},"required":["location"]}}]' \
    --tool-choice auto

  # 7. With extended thinking budget:
  ./count_tokens.sh -m claude-3-7-sonnet-20250219 -p "Solve this puzzle" --thinking-budget 2048
EOF
}

# Collect arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -j|--json)
      JSON_INPUT="$2"
      shift 2
      ;;
    -f|--file)
      FILE_INPUT="$2"
      shift 2
      ;;
    -)
      USE_STDIN=1
      shift
      ;;
    -m|--model)
      MODEL="$2"
      MODEL_EXPLICIT=1
      shift 2
      ;;
    -s|--system)
      SYSTEM_TEXT="$2"
      shift 2
      ;;
    --system-file)
      SYSTEM_FILE="$2"
      shift 2
      ;;
    --system-json)
      SYSTEM_JSON="$2"
      shift 2
      ;;
    -p|--prompt)
      PROMPT_TEXT="$2"
      shift 2
      ;;
    --prompt-file)
      PROMPT_FILE="$2"
      shift 2
      ;;
    -u|--user)
      CONVERSATION_EVENTS+=("user:$2")
      shift 2
      ;;
    -a|--assistant)
      CONVERSATION_EVENTS+=("assistant:$2")
      shift 2
      ;;
    --image)
      CONVERSATION_EVENTS+=("image:$2")
      shift 2
      ;;
    --document)
      CONVERSATION_EVENTS+=("document:$2")
      shift 2
      ;;
    --messages)
      MESSAGES_JSON="$2"
      shift 2
      ;;
    --messages-file)
      MESSAGES_FILE="$2"
      shift 2
      ;;
    -t|--tools)
      TOOLS_INPUT="$2"
      shift 2
      ;;
    -c|--tool-choice)
      TOOL_CHOICE_INPUT="$2"
      shift 2
      ;;
    --thinking-budget)
      THINKING_BUDGET="$2"
      shift 2
      ;;
    --thinking)
      THINKING_JSON="$2"
      shift 2
      ;;
    -k|--api-key)
      API_KEY="$2"
      shift 2
      ;;
    --api-version)
      API_VERSION="$2"
      shift 2
      ;;
    -b|--beta)
      BETA_HEADERS+=("$2")
      shift 2
      ;;
    --endpoint)
      API_URL="$2"
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=1
      shift
      ;;
    -r|--raw)
      RAW_OUTPUT=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    *)
      echo "Error: Unknown option '$1'" >&2
      echo "Use -h or --help for usage details." >&2
      exit 1
      ;;
  esac
done

# If no arguments provided and stdin is a pipe/redirect, read from stdin
if [[ $# -eq 0 && -z "$JSON_INPUT" && -z "$FILE_INPUT" && -z "$PROMPT_TEXT" && -z "$PROMPT_FILE" && -z "$MESSAGES_JSON" && -z "$MESSAGES_FILE" && ${#CONVERSATION_EVENTS[@]} -eq 0 && ! -t 0 ]]; then
  USE_STDIN=1
fi

STDIN_DATA=""
if [[ "$USE_STDIN" -eq 1 ]]; then
  STDIN_DATA="$(cat)"
fi

# Build payload using python3
PAYLOAD=$(JSON_INPUT="$JSON_INPUT" \
  FILE_INPUT="$FILE_INPUT" \
  USE_STDIN="$USE_STDIN" \
  STDIN_DATA="$STDIN_DATA" \
  MODEL="$MODEL" \
  MODEL_EXPLICIT="$MODEL_EXPLICIT" \
  DEFAULT_FALLBACK_MODEL="$DEFAULT_FALLBACK_MODEL" \
  SYSTEM_TEXT="$SYSTEM_TEXT" \
  SYSTEM_FILE="$SYSTEM_FILE" \
  SYSTEM_JSON="$SYSTEM_JSON" \
  PROMPT_TEXT="$PROMPT_TEXT" \
  PROMPT_FILE="$PROMPT_FILE" \
  MESSAGES_JSON="$MESSAGES_JSON" \
  MESSAGES_FILE="$MESSAGES_FILE" \
  TOOLS_INPUT="$TOOLS_INPUT" \
  TOOL_CHOICE_INPUT="$TOOL_CHOICE_INPUT" \
  THINKING_BUDGET="$THINKING_BUDGET" \
  THINKING_JSON="$THINKING_JSON" \
  CONV_EVENTS="$(python3 -c 'import json, sys; print(json.dumps([x for x in sys.argv[1:] if x]))' "${CONVERSATION_EVENTS[@]-}")" \
  python3 - << 'PYEOF'
import sys
import os
import json
import base64
import mimetypes

def main():
    json_input = os.environ.get("JSON_INPUT", "")
    file_input = os.environ.get("FILE_INPUT", "")
    use_stdin = os.environ.get("USE_STDIN", "0") == "1"
    stdin_data = os.environ.get("STDIN_DATA", "")

    model = os.environ.get("MODEL", "").strip()
    default_fallback_model = os.environ.get("DEFAULT_FALLBACK_MODEL", "claude-sonnet-4-6").strip()
    model_explicit = os.environ.get("MODEL_EXPLICIT", "0") == "1"
    effective_model = model if model else default_fallback_model

    system_text = os.environ.get("SYSTEM_TEXT", "")
    system_file = os.environ.get("SYSTEM_FILE", "")
    system_json = os.environ.get("SYSTEM_JSON", "")
    prompt_text = os.environ.get("PROMPT_TEXT", "")
    prompt_file = os.environ.get("PROMPT_FILE", "")
    messages_json = os.environ.get("MESSAGES_JSON", "")
    messages_file = os.environ.get("MESSAGES_FILE", "")
    tools_input = os.environ.get("TOOLS_INPUT", "")
    tool_choice_input = os.environ.get("TOOL_CHOICE_INPUT", "")
    thinking_budget = os.environ.get("THINKING_BUDGET", "")
    thinking_json = os.environ.get("THINKING_JSON", "")

    conv_raw = os.environ.get("CONV_EVENTS", "")
    conv_events = json.loads(conv_raw) if conv_raw else []

    payload = {}

    # 1. Direct JSON payload modes
    if use_stdin:
        try:
            payload = json.loads(stdin_data)
        except Exception as e:
            sys.stderr.write(f"Error parsing JSON from stdin: {e}\n")
            sys.exit(1)
    elif file_input:
        try:
            with open(file_input, "r", encoding="utf-8") as f:
                payload = json.load(f)
        except Exception as e:
            sys.stderr.write(f"Error reading/parsing file '{file_input}': {e}\n")
            sys.exit(1)
    elif json_input:
        try:
            payload = json.loads(json_input)
        except Exception as e:
            sys.stderr.write(f"Error parsing JSON string: {e}\n")
            sys.exit(1)

    # If full payload was provided directly
    if payload:
        if model_explicit:
            payload["model"] = effective_model
        elif "model" not in payload or not payload["model"]:
            payload["model"] = effective_model
        if "messages" not in payload:
            sys.stderr.write("Error: Request payload must include a 'messages' array.\n")
            sys.exit(1)
        print(json.dumps(payload))
        return

    # 2. Modular construction mode
    payload["model"] = effective_model

    # System prompt
    if system_json:
        try:
            payload["system"] = json.loads(system_json)
        except Exception as e:
            sys.stderr.write(f"Error parsing --system-json: {e}\n")
            sys.exit(1)
    elif system_file:
        try:
            with open(system_file, "r", encoding="utf-8") as f:
                payload["system"] = f.read().strip()
        except Exception as e:
            sys.stderr.write(f"Error reading system file '{system_file}': {e}\n")
            sys.exit(1)
    elif system_text:
        payload["system"] = system_text

    # Messages
    messages = []

    def make_media_block(filepath, media_category):
        if not os.path.exists(filepath):
            sys.stderr.write(f"Error: File not found: {filepath}\n")
            sys.exit(1)
        with open(filepath, "rb") as f:
            data_b64 = base64.b64encode(f.read()).decode("utf-8")
        
        mime, _ = mimetypes.guess_type(filepath)
        if media_category == "image":
            if not mime or not mime.startswith("image/"):
                ext = os.path.splitext(filepath)[1].lower()
                ext_map = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp"}
                mime = ext_map.get(ext, "image/jpeg")
            return {
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": mime,
                    "data": data_b64
                }
            }
        elif media_category == "document":
            if not mime or mime != "application/pdf":
                mime = "application/pdf"
            return {
                "type": "document",
                "source": {
                    "type": "base64",
                    "media_type": mime,
                    "data": data_b64
                }
            }
        raise ValueError(f"Unknown media category: {media_category}")

    if messages_file:
        try:
            with open(messages_file, "r", encoding="utf-8") as f:
                messages = json.load(f)
        except Exception as e:
            sys.stderr.write(f"Error reading messages file '{messages_file}': {e}\n")
            sys.exit(1)
    elif messages_json:
        try:
            messages = json.loads(messages_json)
        except Exception as e:
            sys.stderr.write(f"Error parsing --messages JSON: {e}\n")
            sys.exit(1)
    elif conv_events or prompt_text or prompt_file:
        current_role = None
        current_content = []

        def flush_turn():
            nonlocal current_role, current_content
            if current_role and current_content:
                if len(current_content) == 1 and current_content[0].get("type") == "text":
                    messages.append({"role": current_role, "content": current_content[0]["text"]})
                else:
                    messages.append({"role": current_role, "content": current_content})
                current_role = None
                current_content = []

        if prompt_file:
            try:
                with open(prompt_file, "r", encoding="utf-8") as f:
                    prompt_text = f.read().strip()
            except Exception as e:
                sys.stderr.write(f"Error reading prompt file '{prompt_file}': {e}\n")
                sys.exit(1)

        if prompt_text:
            current_role = "user"
            current_content.append({"type": "text", "text": prompt_text})

        for ev in conv_events:
            kind, val = ev.split(":", 1)
            if kind == "user":
                if current_role != "user":
                    flush_turn()
                    current_role = "user"
                current_content.append({"type": "text", "text": val})
            elif kind == "assistant":
                if current_role != "assistant":
                    flush_turn()
                    current_role = "assistant"
                current_content.append({"type": "text", "text": val})
            elif kind in ("image", "document"):
                if current_role != "user":
                    flush_turn()
                    current_role = "user"
                current_content.append(make_media_block(val, kind))
        flush_turn()

    if not messages:
        sys.stderr.write("Error: No messages provided. Specify --prompt, --user, --messages, or pipe request JSON.\n")
        sys.exit(1)

    payload["messages"] = messages

    # Tools
    if tools_input:
        if os.path.exists(tools_input):
            try:
                with open(tools_input, "r", encoding="utf-8") as f:
                    payload["tools"] = json.load(f)
            except Exception as e:
                sys.stderr.write(f"Error reading tools file '{tools_input}': {e}\n")
                sys.exit(1)
        else:
            try:
                payload["tools"] = json.loads(tools_input)
            except Exception as e:
                sys.stderr.write(f"Error parsing --tools JSON: {e}\n")
                sys.exit(1)

    # Tool Choice
    if tool_choice_input:
        val = tool_choice_input.strip()
        if val in ("auto", "any", "none"):
            payload["tool_choice"] = {"type": val}
        else:
            try:
                payload["tool_choice"] = json.loads(val)
            except Exception:
                payload["tool_choice"] = {"type": "tool", "name": val}

    # Thinking
    if thinking_budget:
        try:
            payload["thinking"] = {"type": "enabled", "budget_tokens": int(thinking_budget)}
        except ValueError:
            sys.stderr.write(f"Error: --thinking-budget must be an integer, got: {thinking_budget}\n")
            sys.exit(1)
    elif thinking_json:
        try:
            payload["thinking"] = json.loads(thinking_json)
        except Exception as e:
            sys.stderr.write(f"Error parsing --thinking JSON: {e}\n")
            sys.exit(1)

    print(json.dumps(payload))

if __name__ == "__main__":
    main()
PYEOF
)

if [[ "$DRY_RUN" -eq 1 ]]; then
  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "=== Dry Run: Target Request ===" >&2
    echo "POST $API_URL" >&2
    echo "Headers:" >&2
    echo "  x-api-key: ${API_KEY:+"[CONFIGURED]"}" >&2
    echo "  anthropic-version: $API_VERSION" >&2
    echo "  content-type: application/json" >&2
    for beta in "${BETA_HEADERS[@]-}"; do
      if [[ -n "$beta" ]]; then
        echo "  anthropic-beta: $beta" >&2
      fi
    done
    echo "Payload:" >&2
  else
    echo "--- Constructed Payload (Dry Run) ---"
  fi
  if command -v jq >/dev/null 2>&1; then
    echo "$PAYLOAD" | jq .
  else
    echo "$PAYLOAD"
  fi
  exit 0
fi

# Check API key
if [[ -z "$API_KEY" ]]; then
  echo "Error: Anthropic API key not found." >&2
  echo "Please set ANTHROPIC_API_KEY environment variable or pass --api-key <key>." >&2
  exit 1
fi

# Prepare curl headers
CURL_ARGS=(
  -s -S
  -X POST "$API_URL"
  -H "x-api-key: $API_KEY"
  -H "anthropic-version: $API_VERSION"
  -H "content-type: application/json"
)

# Append any beta headers
for beta in "${BETA_HEADERS[@]-}"; do
  if [[ -n "$beta" ]]; then
    CURL_ARGS+=(-H "anthropic-beta: $beta")
  fi
done

if [[ "$VERBOSE" -eq 1 ]]; then
  echo "=== Request Details ===" >&2
  echo "POST $API_URL" >&2
  echo "Headers:" >&2
  echo "  x-api-key: [REDACTED]" >&2
  echo "  anthropic-version: $API_VERSION" >&2
  echo "  content-type: application/json" >&2
  for beta in "${BETA_HEADERS[@]-}"; do
    if [[ -n "$beta" ]]; then
      echo "  anthropic-beta: $beta" >&2
    fi
  done
  echo "Payload:" >&2
  if command -v jq >/dev/null 2>&1; then
    echo "$PAYLOAD" | jq . >&2
  else
    echo "$PAYLOAD" >&2
  fi
  echo "=======================" >&2
  CURL_ARGS+=(-w "\nHTTP Status: %{http_code}\n")
fi

# Call Anthropic API
RESPONSE=$(curl "${CURL_ARGS[@]}" -d "$PAYLOAD")

# Output response
if [[ "$RAW_OUTPUT" -eq 1 ]] || ! command -v jq >/dev/null 2>&1; then
  echo "$RESPONSE"
else
  # Pretty print JSON if jq is available and output is valid JSON
  if echo "$RESPONSE" | jq . >/dev/null 2>&1; then
    echo "$RESPONSE" | jq .
  else
    echo "$RESPONSE"
  fi
fi
