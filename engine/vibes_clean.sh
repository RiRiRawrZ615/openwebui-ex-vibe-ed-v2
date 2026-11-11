#!/usr/bin/env bash
# Open Web Vibes v2 engine wrapper. Runs either engine out of the box.
#   BACKEND=llama    llama.cpp
#   BACKEND=strata   strata
#   BACKEND=auto     strata when detected, otherwise llama.cpp (default)
# Nothing is hardcoded to this machine: every path resolves from HOME and env.
#
# Context proxy stays optional and off by default (plain runs are untouched):
#   OWV_CONTEXT_PROXY=1    route Open WebUI through billion-context
#   BILI_BIN               proxy binary (default bili, also accepts billion-context)
#   BILI_PORT              proxy port (default 8787)
#   OWV_UPSTREAM_URL       engine URL the proxy forwards to
#   OWV_PROXY_URL          URL Open WebUI uses when the proxy is on
#
set -euo pipefail

ENGINE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HOME_ROOT=${HOME}

export PYTHON=${PYTHON:-python3}
export EX_STATS_DIR=${EX_STATS_DIR:-$HOME_ROOT/.local/share/openwebvibes}
export EX_SESSION_ID=${EX_SESSION_ID:-${SESSION_ID:-${OPENWEBUI_SESSION_ID:-vibes}}}
export BILI_PORT=${BILI_PORT:-8787}
export OWV_CONTEXT_PROXY=${OWV_CONTEXT_PROXY:-0}
mkdir -p "$EX_STATS_DIR"

BACKEND=${BACKEND:-auto}
if [ "$BACKEND" = auto ]; then
  if command -v strata >/dev/null 2>&1 || [ -d "$HOME_ROOT/strata" ]; then
    BACKEND=strata
  else
    BACKEND=llama
  fi
fi

pick_launcher() {
  for candidate in "$ENGINE_DIR/$1" "$HOME_ROOT/Documents/AI_Output/ai-launchers/$1"; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

if [ "$BACKEND" = strata ]; then
  LAUNCHER=$(pick_launcher strata_openwebui_launcher.sh) || {
    echo "vibes_clean.sh: no strata launcher found" >&2
    exit 1
  }
  ENGINE_PORT=${API_PORT:-8092}
else
  LAUNCHER=$(pick_launcher openwebui_llamacpp_safe_moe_v4.sh) || {
    echo "vibes_clean.sh: no llama.cpp launcher found" >&2
    exit 1
  }
  ENGINE_PORT=${API_PORT:-8080}
fi

if [ "$OWV_CONTEXT_PROXY" = 1 ]; then
  PROXY_BIN=${BILI_BIN:-bili}
  command -v "$PROXY_BIN" >/dev/null 2>&1 || PROXY_BIN=billion-context
  if command -v "$PROXY_BIN" >/dev/null 2>&1; then
    export OWV_UPSTREAM_URL=${OWV_UPSTREAM_URL:-http://127.0.0.1:$ENGINE_PORT/v1}
    export OWV_PROXY_URL=${OWV_PROXY_URL:-http://127.0.0.1:$BILI_PORT/v1}
    "$PROXY_BIN" --provider openai --host 127.0.0.1 --port "$BILI_PORT" \
      --ttl "${BILI_TTL:-3600}" --session-id "$EX_SESSION_ID" \
      --max_context_window "${BILI_MAX_CONTEXT:-40000}" \
      --max_completion_tokens "${BILI_MAX_COMPLETION:-8192}" &
    export OPENAI_API_BASE_URL="$OWV_PROXY_URL"
    echo "proxy: $OPENAI_API_BASE_URL -> $OWV_UPSTREAM_URL"
  else
    echo "proxy: $PROXY_BIN is not installed, running direct (npm i -g billion-context)" >&2
  fi
fi

echo "engine: $BACKEND via $LAUNCHER"
exec bash "$LAUNCHER"
