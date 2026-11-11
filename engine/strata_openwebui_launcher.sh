#!/usr/bin/env bash

# Strata + Open WebUI launcher
#
# This is the Strata sibling of openwebui_llamacpp_safe_moe_v4.sh.
#
# What is identical to that launcher (by design, so your existing Open WebUI
# profile, integrations and workflows keep working unchanged):
#   - Open WebUI data dir, ports, auth, offline uvx start, persistent-config
#     environment, and the Open Terminal (bare-metal) integration: same key
#     file, same auto-registration into Open WebUI, same capability defaults.
#   - Safety rule: no broad pkill. Only PIDs this launcher started are stopped.
#
# What is different:
#   - The model backend is Strata (source install in $STRATA_DIR) instead of
#     llama.cpp. Strata is itself an OpenAI-compatible server, so there is no
#     engine.py proxy and no separate llama-server process. Open WebUI points
#     directly at Strata's /v1.
#   - Strata loads the prepared model pack, so startup is slow (minutes). The
#     startup timeout is long, and a model that is already running is reused
#     instead of restarted.
#   - Vision: Strata's IQ2_XS Flash-Next setup here is text-only
#     (--vision no). If you later enable the picture reader in Strata's setup,
#     set VISION_ENABLED=1 and the Open WebUI capability defaults below already
#     advertise vision.

set -Eeuo pipefail

# -----------------------------
# Paths
# -----------------------------
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.strata/bin"

# Strata source install (built/fetched here).
STRATA_DIR="${STRATA_DIR:-$HOME/strata}"
STRATA_VENV_PY="${STRATA_VENV_PY:-$STRATA_DIR/.venv/bin/python}"
STRATA_SERVER="${STRATA_SERVER:-$STRATA_DIR/serve/server.py}"
STRATA_CONFIG="${STRATA_CONFIG:-$STRATA_DIR/strata-iq2_xs.json}"
STRATA_LOG="${STRATA_LOG:-$HOME/Documents/strata.log}"
STRATA_PID_FILE="${STRATA_PID_FILE:-$HOME/Documents/strata.pid}"

# Model files (the two IQ2_XS shards, verified against Strata's pins).
MODEL_ROOT="${MODEL_ROOT:-$HOME/Documents/AI_Models/Qwen3.8-Flash-Next-abliterated-GSQ-RCO-IQ2_XS}"

# Ports. Open WebUI stays on 8080 (identical to the llama.cpp launcher, so the
# user's existing bookmarks and workflows are unchanged). Strata's OpenAI API
# takes the old llama.cpp port 8001, which is free now.
API_PORT="${STRATA_PORT:-8001}"          # Strata serves its OpenAI API here.
WEBUI_PORT="${WEBUI_PORT:-8080}"          # Open WebUI front end (unchanged from the llama.cpp launcher).
OPENAPI_API_BASE_URL="${OPENAPI_API_BASE_URL:-http://127.0.0.1:${API_PORT}/v1}"

BRAVE_PROFILE="${BRAVE_PROFILE:-$HOME/.config/Brave-AI-App}"
WEBUI_LOG="${WEBUI_LOG:-$HOME/Documents/strata_openwebui.log}"
WEBUI_DATA_DIR="${WEBUI_DATA_DIR:-$HOME/.open-webui-strata}"
RUNTIME_DIR="${RUNTIME_DIR:-$HOME/.cache/strata-openwebui}"
BRAVE_PID_FILE="${BRAVE_PID_FILE:-$HOME/Documents/brave-strata.pid}"
WEBUI_PID_FILE="${WEBUI_PID_FILE:-$HOME/Documents/strata_openwebui_webui.pid}"

# Open Terminal (bare-metal) integration: identical to the llama.cpp launcher.
OPEN_TERMINAL_ENABLED="${OPEN_TERMINAL_ENABLED:-1}"
OPEN_TERMINAL_HOST="${OPEN_TERMINAL_HOST:-127.0.0.1}"
OPEN_TERMINAL_PORT="${OPEN_TERMINAL_PORT:-8004}"  # 8003 belongs to the llama.cpp launcher.
OPEN_TERMINAL_OUTPUT_DIR="${OPEN_TERMINAL_OUTPUT_DIR:-$HOME/Documents/AI_Output}"
OPEN_TERMINAL_CWD="${OPEN_TERMINAL_CWD:-$OPEN_TERMINAL_OUTPUT_DIR}"
OPEN_TERMINAL_KEY_FILE="${OPEN_TERMINAL_KEY_FILE:-$HOME/.config/open-terminal/api-key-strata}"
OPEN_TERMINAL_LOG="${OPEN_TERMINAL_LOG:-$HOME/Documents/strata_open_terminal.log}"
OPEN_TERMINAL_PID_FILE="${OPEN_TERMINAL_PID_FILE:-$HOME/Documents/strata_open_terminal.pid}"
OPEN_TERMINAL_CHAT_UPLOADS="${OPEN_TERMINAL_CHAT_UPLOADS:-filesystem}"
OPEN_TERMINAL_AUTOCONFIGURE="${OPEN_TERMINAL_AUTOCONFIGURE:-1}"
OPEN_TERMINAL_STARTUP_TIMEOUT="${OPEN_TERMINAL_STARTUP_TIMEOUT:-120}"

WEBUI_AUTH="${WEBUI_AUTH:-False}"
WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY:-fixed_secret_strata_openwebui}"

# Strata model load is slow (minutes). Give it room.
STRATA_STARTUP_TIMEOUT="${STRATA_STARTUP_TIMEOUT:-1800}"
STRATA_STARTUP_TIMEOUT_MIN="${STRATA_STARTUP_TIMEOUT_MIN:-600}"

# -----------------------------
# Validate
# -----------------------------
if [[ ! -x "$STRATA_VENV_PY" ]]; then
    echo "[ERROR] Strata venv python not found: $STRATA_VENV_PY"
    echo "[HINT] Run Strata's setup in $STRATA_DIR first (./setup.sh)."
    exit 1
fi
if [[ ! -f "$STRATA_SERVER" ]]; then
    echo "[ERROR] Strata server not found: $STRATA_SERVER"
    exit 1
fi
if [[ ! -f "$STRATA_CONFIG" ]]; then
    echo "[ERROR] Strata run config not found: $STRATA_CONFIG"
    echo "[HINT] Strata's setup writes strata-<model>.json into its checkout."
    exit 1
fi
if [[ ! -d "$MODEL_ROOT" ]]; then
    echo "[ERROR] Model root not found: $MODEL_ROOT"
    exit 1
fi

case "${OPEN_TERMINAL_ENABLED,,}" in
    1|true|yes|on) OPEN_TERMINAL_ENABLED=1 ;;
    0|false|no|off) OPEN_TERMINAL_ENABLED=0 ;;
    *) echo "[ERROR] OPEN_TERMINAL_ENABLED must be true/false or 1/0."; exit 1 ;;
esac
case "${OPEN_TERMINAL_CHAT_UPLOADS,,}" in
    filesystem|default) OPEN_TERMINAL_CHAT_UPLOADS="${OPEN_TERMINAL_CHAT_UPLOADS,,}" ;;
    *) echo "[ERROR] OPEN_TERMINAL_CHAT_UPLOADS must be 'filesystem' or 'default'."; exit 1 ;;
esac

port_in_use() {
    local port="$1"
    curl -s --max-time 1 "http://127.0.0.1:${port}/health" >/dev/null 2>&1
}

# -----------------------------
# Runtime state
# -----------------------------
mkdir -p "$HOME/Documents" "$WEBUI_DATA_DIR" "$RUNTIME_DIR" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Documents" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Code" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Spreadsheets" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Presentations" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Images" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Reports" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Data" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Web" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Archives" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Uploads" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Other" \
    "$OPEN_TERMINAL_OUTPUT_DIR/tools" \
    "$OPEN_TERMINAL_CWD"

safe_kill_pid() {
    local pid="${1:-}"
    if [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ || ! -d "/proc/$pid" ]]; then return 0; fi
    kill "$pid" 2>/dev/null || true
    for _ in {1..8}; do if [[ ! -d "/proc/$pid" ]]; then return 0; fi; sleep 1; done
    kill -9 "$pid" 2>/dev/null || true
}

safe_kill_pgid() {
    local pid="${1:-}"
    if [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ || ! -d "/proc/$pid" ]]; then return 0; fi
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    for _ in {1..8}; do if [[ ! -d "/proc/$pid" ]]; then return 0; fi; sleep 1; done
    kill -9 -- "-$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
}

cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM
    echo -e "\n[STATUS] --- Shutting down AI Services ---"
    if [[ -f "$BRAVE_PID_FILE" ]]; then safe_kill_pgid "$(cat "$BRAVE_PID_FILE" 2>/dev/null)" "Brave"; fi
    if [[ -f "$WEBUI_PID_FILE" ]]; then safe_kill_pgid "$(cat "$WEBUI_PID_FILE" 2>/dev/null)" "WebUI"; fi
    if [[ -f "$OPEN_TERMINAL_PID_FILE" ]]; then safe_kill_pgid "$(cat "$OPEN_TERMINAL_PID_FILE" 2>/dev/null)" "Open Terminal"; fi
    if [[ -f "$STRATA_PID_FILE" ]]; then safe_kill_pgid "$(cat "$STRATA_PID_FILE" 2>/dev/null)" "strata"; fi
    rm -f "$BRAVE_PID_FILE" "$WEBUI_PID_FILE" "$STRATA_PID_FILE" "$OPEN_TERMINAL_PID_FILE" 2>/dev/null || true
    exit "$exit_code"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# -----------------------------
# Start Strata (the model server)
# -----------------------------
STRATA_READY=0
if port_in_use "$API_PORT"; then
    echo "[STATUS] Strata already healthy on port $API_PORT. Reusing it."
    STRATA_READY=1
else
    echo "[STATUS] Starting Strata model server on port $API_PORT (model load takes several minutes)..."
    echo "[STATUS] Log: $STRATA_LOG"
    # Same invocation Strata's own run-iq2_xs.sh uses, with the config's env and
    # library paths applied. The subshell is one process group we can stop cleanly.
    ( cd "$STRATA_DIR"
      export STRATA_ROCBLAS_TUNING="${STRATA_ROCBLAS_TUNING:-$STRATA_DIR/tools/hip}"
      export LD_LIBRARY_PATH="$STRATA_DIR/.venv/lib/python3.11/site-packages/_rocm_sdk_devel/lib:$STRATA_DIR/.venv/lib/python3.11/site-packages/_rocm_sdk_libraries_gfx103X_all/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      exec "$STRATA_VENV_PY" "$STRATA_SERVER" --engine strata --config "$STRATA_CONFIG" --port "$API_PORT"
    ) > "$STRATA_LOG" 2>&1 &
    STRATA_PID=$!
    echo "$STRATA_PID" > "$STRATA_PID_FILE"
fi

for _ in $(seq 1 "$STRATA_STARTUP_TIMEOUT"); do
    if port_in_use "$API_PORT"; then
        STRATA_READY=1
        break
    fi
    if [[ -f "$STRATA_PID_FILE" ]] && ! kill -0 "$(cat "$STRATA_PID_FILE")" 2>/dev/null; then
        echo "[ERROR] Strata exited during startup. Check: $STRATA_LOG"
        tail -n 30 "$STRATA_LOG" 2>/dev/null || true
        exit 1
    fi
    sleep 1
done

if [[ "$STRATA_READY" != 1 ]]; then
    echo "[ERROR] Strata did not become healthy within ${STRATA_STARTUP_TIMEOUT}s. Check: $STRATA_LOG"
    tail -n 30 "$STRATA_LOG" 2>/dev/null || true
    exit 1
fi

echo "[STATUS] Strata is ready: http://127.0.0.1:$API_PORT"

# -----------------------------
# Start Open Terminal (bare metal; optional)
# -----------------------------
OPEN_TERMINAL_READY=0
if [[ "$OPEN_TERMINAL_ENABLED" == 1 ]]; then
    if ! command -v uvx >/dev/null 2>&1; then
        echo "[WARNING] uvx is missing; Open Terminal will not start. Install uv, or set OPEN_TERMINAL_ENABLED=0 to silence this warning."
    else
        mkdir -p "$(dirname "$OPEN_TERMINAL_KEY_FILE")" "$OPEN_TERMINAL_CWD"
        chmod 700 "$(dirname "$OPEN_TERMINAL_KEY_FILE")"
        if [[ ! -s "$OPEN_TERMINAL_KEY_FILE" ]]; then
            if command -v openssl >/dev/null 2>&1; then
                (umask 077; openssl rand -hex 32 > "$OPEN_TERMINAL_KEY_FILE")
            else
                (umask 077; python3 -c 'import secrets; print(secrets.token_hex(32))' > "$OPEN_TERMINAL_KEY_FILE")
            fi
            echo "[STATUS] Generated persistent Open Terminal API key at $OPEN_TERMINAL_KEY_FILE"
        fi
        chmod 600 "$OPEN_TERMINAL_KEY_FILE"
        OPEN_TERMINAL_API_KEY_VALUE="$(cat "$OPEN_TERMINAL_KEY_FILE")"
        if [[ -z "$OPEN_TERMINAL_API_KEY_VALUE" ]]; then
            echo "[WARNING] Open Terminal key file is empty; Open Terminal will not start."
        else
            echo "[STATUS] Starting Open Terminal bare-metal service on http://$OPEN_TERMINAL_HOST:$OPEN_TERMINAL_PORT"
            echo "[WARNING] Bare-metal Open Terminal executes commands as user '${USER:-$(id -un)}' with that user's host permissions. It is not isolated like Docker."
            if ping -q -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
                OPEN_TERMINAL_API_KEY="$OPEN_TERMINAL_API_KEY_VALUE" setsid uvx --python 3.11 open-terminal@latest run \
                    --host "$OPEN_TERMINAL_HOST" --port "$OPEN_TERMINAL_PORT" --cwd "$OPEN_TERMINAL_CWD" \
                    > "$OPEN_TERMINAL_LOG" 2>&1 &
            else
                OPEN_TERMINAL_API_KEY="$OPEN_TERMINAL_API_KEY_VALUE" setsid uvx --offline --python 3.11 open-terminal@latest run \
                    --host "$OPEN_TERMINAL_HOST" --port "$OPEN_TERMINAL_PORT" --cwd "$OPEN_TERMINAL_CWD" \
                    > "$OPEN_TERMINAL_LOG" 2>&1 &
            fi
            OPEN_TERMINAL_PID=$!
            echo "$OPEN_TERMINAL_PID" > "$OPEN_TERMINAL_PID_FILE"
            for _ in $(seq 1 "$OPEN_TERMINAL_STARTUP_TIMEOUT"); do
                if curl -fsS --max-time 1 "http://127.0.0.1:$OPEN_TERMINAL_PORT/health" >/dev/null 2>&1; then
                    OPEN_TERMINAL_READY=1
                    break
                fi
                if ! kill -0 "$OPEN_TERMINAL_PID" 2>/dev/null; then break; fi
                sleep 1
            done
            if [[ "$OPEN_TERMINAL_READY" == 1 ]]; then
                echo "[STATUS] Open Terminal is ready. Log: $OPEN_TERMINAL_LOG"
                echo "[SETUP] One-time Open WebUI setup: Admin Settings > Integrations > Open Terminal"
                echo "[SETUP] URL: http://127.0.0.1:$OPEN_TERMINAL_PORT"
                echo "[SETUP] Bearer API key is stored in: $OPEN_TERMINAL_KEY_FILE"
            else
                echo "[WARNING] Open Terminal did not become healthy within ${OPEN_TERMINAL_STARTUP_TIMEOUT}s. Main models and Open WebUI will still start. Check $OPEN_TERMINAL_LOG"
                if ! kill -0 "$OPEN_TERMINAL_PID" 2>/dev/null; then rm -f "$OPEN_TERMINAL_PID_FILE"; fi
            fi
        fi
    fi
fi

# -----------------------------
# Preconfigure Open WebUI's built-in Open Terminal integration
# -----------------------------
if [[ "$OPEN_TERMINAL_ENABLED" == 1 && "$OPEN_TERMINAL_READY" == 1 && "$OPEN_TERMINAL_AUTOCONFIGURE" == 1 && -s "$OPEN_TERMINAL_KEY_FILE" ]]; then
    export TERMINAL_SERVER_CONNECTIONS="$(python3 - "$OPEN_TERMINAL_KEY_FILE" "$OPEN_TERMINAL_PORT" <<'PYTERMJSON'
import json
import os
import sys
from pathlib import Path

key_path = Path(sys.argv[1])
port = int(sys.argv[2])
api_key = key_path.read_text(encoding="utf-8").strip()
if not api_key:
    raise SystemExit("Open Terminal API key file is empty")
raw = os.environ.get("TERMINAL_SERVER_CONNECTIONS", "[]")
try:
    connections = json.loads(raw) if raw.strip() else []
    if not isinstance(connections, list):
        connections = []
except Exception:
    connections = []

local = {
    "id": "local-open-terminal",
    "name": "Local Open Terminal",
    "enabled": True,
    "url": f"http://127.0.0.1:{port}",
    "key": api_key,
    "auth_type": "bearer",
    "config": {
        "chat_uploads": os.environ.get("OPEN_TERMINAL_CHAT_UPLOADS", "filesystem"),
        "access_grants": [
            {"principal_type": "user", "principal_id": "*", "permission": "read"}
        ]
    },
}
local["path"] = "/openapi.json"
local["config"]["enable"] = True
local["config"]["working_directory_context"] = True
local["config"]["user_shell_tools"] = "always"
local["config"]["access_grants"].append({"principal_type": "user", "principal_id": "*", "permission": "write"})
connections = [c for c in connections if not (isinstance(c, dict) and c.get("id") == local["id"])]
connections.append(local)
print(json.dumps(connections, separators=(",", ":")))
PYTERMJSON
)"
    echo "[STATUS] Open WebUI will receive the desired terminal connection via TERMINAL_SERVER_CONNECTIONS, then the launcher will persist it via the admin API."
fi

# -----------------------------
# Start Open WebUI
# -----------------------------
export DATA_DIR="$WEBUI_DATA_DIR"
export ENABLE_PERSISTENT_CONFIG=True
export ENABLE_KB_EXEC=True
export ENABLE_CODE_INTERPRETER=True
export ENABLE_CODE_EXECUTION=True
export ENABLE_OLLAMA_API=False
export ENABLE_OPENAI_API=True
export ENABLE_TOOL_SERVERS=True
export DEFAULT_MODEL_PARAMS="${DEFAULT_MODEL_PARAMS:-{\"function_calling\":\"native\"}}"
export DEFAULT_MODEL_METADATA="${DEFAULT_MODEL_METADATA:-{\"capabilities\":{\"file_context\":true,\"vision\":true,\"file_upload\":true,\"web_search\":true,\"image_generation\":true,\"code_interpreter\":true,\"terminal\":true,\"citations\":true,\"status_updates\":true,\"usage\":true,\"builtin_tools\":true},\"terminalId\":\"local-open-terminal\"}}"
export OPENAI_API_BASE_URL="$OPENAPI_API_BASE_URL"
export OPENAI_API_KEY="${OPENAI_API_KEY:-strata-local-key}"
export WEBUI_AUTH
export WEBUI_SECRET_KEY
export PORT="$WEBUI_PORT"

echo "[STATUS] Starting Open WebUI on port $WEBUI_PORT (OpenAI base: $OPENAPI_API_BASE_URL)..."
if ping -q -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
    setsid bash -c 'exec uvx --python 3.11 open-webui@latest serve' > "$WEBUI_LOG" 2>&1 &
else
    setsid bash -c 'exec uvx --offline --python 3.11 open-webui@latest serve' > "$WEBUI_LOG" 2>&1 &
fi
WEBUI_PID=$!
echo "$WEBUI_PID" > "$WEBUI_PID_FILE"

for _ in {1..120}; do
    if curl -s "http://127.0.0.1:$WEBUI_PORT" >/dev/null; then break; fi
    if ! kill -0 "$WEBUI_PID" 2>/dev/null; then
        echo "[ERROR] Open WebUI exited during startup. Check: $WEBUI_LOG"
        exit 1
    fi
    sleep 1
done

# Persist the Open Terminal connection through Open WebUI's own admin API
# (same approach as the llama.cpp launcher: TERMINAL_SERVER_CONNECTIONS is a
# PersistentConfig variable, so an env write alone can be overridden by an old
# database value).
if [[ "$OPEN_TERMINAL_ENABLED" == 1 && "$OPEN_TERMINAL_READY" == 1 && "$OPEN_TERMINAL_AUTOCONFIGURE" == 1 && -s "$OPEN_TERMINAL_KEY_FILE" ]]; then
    python3 - "$WEBUI_DATA_DIR" "$WEBUI_SECRET_KEY" "$WEBUI_PORT" "$OPEN_TERMINAL_PORT" "$OPEN_TERMINAL_KEY_FILE" "$OPEN_TERMINAL_CHAT_UPLOADS" <<'PYWEBUI_TERMINAL_REGISTER'
import base64
import hashlib
import hmac
import json
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

webui_data = Path(sys.argv[1]).expanduser()
secret = sys.argv[2]
webui_port = int(sys.argv[3])
terminal_port = int(sys.argv[4])
key_path = Path(sys.argv[5]).expanduser()
chat_uploads = sys.argv[6].strip().lower()
if chat_uploads not in {"filesystem", "default"}:
    print(f"[WARNING] Unsupported OPEN_TERMINAL_CHAT_UPLOADS value: {chat_uploads}")
    raise SystemExit(6)
api_key = key_path.read_text(encoding="utf-8").strip()
if not api_key:
    raise SystemExit("Open Terminal API key is empty")

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

def make_admin_token(admin_id: str) -> str:
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url(json.dumps({"id": admin_id, "exp": int(time.time()) + 300}, separators=(",", ":")).encode())
    signing_input = f"{header}.{payload}".encode("ascii")
    signature = hmac.new(secret.encode("utf-8"), signing_input, hashlib.sha256).digest()
    return f"{header}.{payload}.{b64url(signature)}"

def locate_admin_id(directory: Path) -> str | None:
    candidates = []
    for pattern in ("webui.db", "*.db", "*.sqlite", "*.sqlite3"):
        candidates.extend(directory.glob(pattern))
    seen = set()
    for db_path in candidates:
        try:
            resolved = db_path.resolve()
            if resolved in seen or not db_path.is_file():
                continue
            seen.add(resolved)
            conn = sqlite3.connect(f"file:{resolved.as_posix()}?mode=ro", uri=True, timeout=3)
            try:
                tables = conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
                for (table,) in tables:
                    escaped_table = str(table).replace('"', '""')
                    columns = {row[1] for row in conn.execute(f'PRAGMA table_info("{escaped_table}")').fetchall()}
                    if not {"id", "role"}.issubset(columns):
                        continue
                    try:
                        row = conn.execute(
                            f'SELECT "id" FROM "{escaped_table}" WHERE lower("role") = ? LIMIT 1',
                            ("admin",),
                        ).fetchone()
                    except sqlite3.Error:
                        continue
                    if row and row[0]:
                        return str(row[0])
            finally:
                conn.close()
        except Exception:
            continue
    return None

admin_id = locate_admin_id(webui_data)
if not admin_id:
    try:
        _warm_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        for _warm_path in ("/api/config", "/api/v1/auths/"):
            try:
                with _warm_opener.open(f"http://127.0.0.1:{webui_port}{_warm_path}", timeout=5) as _r:
                    _ = _r.read()
            except Exception:
                pass
    except Exception:
        pass
    admin_id = locate_admin_id(webui_data)
    if not admin_id:
        for _db_path in sorted(webui_data.rglob("*.db")):
            try:
                _conn = sqlite3.connect(str(_db_path), timeout=3)
                try:
                    _row = _conn.execute('SELECT "id" FROM "user" LIMIT 1').fetchone()
                    if _row and _row[0]:
                        admin_id = str(_row[0])
                        break
                finally:
                    _conn.close()
            except Exception:
                continue
if not admin_id:
    print("[WARNING] Could not find an admin user in the Open WebUI SQLite database; automatic terminal registration was not persisted.")
    print("[WARNING] Check WEBUI_DATA_DIR and confirm an Open WebUI admin account exists.")
    raise SystemExit(2)

token = make_admin_token(admin_id)
base = f"http://127.0.0.1:{webui_port}/api/v1/configs/terminal_servers"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

def api_request(method: str, payload=None):
    data = None if payload is None else json.dumps(payload, separators=(",", ":")).encode("utf-8")
    req = urllib.request.Request(
        base,
        data=data,
        method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with opener.open(req, timeout=15) as response:
            raw = response.read()
            return response.status, json.loads(raw.decode("utf-8")) if raw else {}
    except urllib.error.HTTPError as exc:
        return exc.code, {}

status, current = api_request("GET")
if status != 200:
    print(f"[WARNING] Open WebUI terminal config API GET failed with HTTP {status}; integration was not persisted.")
    raise SystemExit(3)
connections = current.get("TERMINAL_SERVER_CONNECTIONS", [])
if not isinstance(connections, list):
    connections = []
local = {
    "id": "local-open-terminal",
    "name": "Local Open Terminal",
    "enabled": True,
    "url": f"http://127.0.0.1:{terminal_port}",
    "path": "/openapi.json",
    "key": api_key,
    "auth_type": "bearer",
    "config": {
        "chat_uploads": chat_uploads,
        "access_grants": [
            {"principal_type": "user", "principal_id": "*", "permission": "read"}
        ]
    },
}
local["config"]["enable"] = True
local["config"]["working_directory_context"] = True
local["config"]["user_shell_tools"] = "always"
local["config"]["access_grants"].append({"principal_type": "user", "principal_id": "*", "permission": "write"})
connections = [c for c in connections if not (isinstance(c, dict) and c.get("id") == local["id"])]
connections.append(local)
status, saved = api_request("POST", {"TERMINAL_SERVER_CONNECTIONS": connections})
if status != 200:
    print(f"[WARNING] Open WebUI terminal config API POST failed with HTTP {status}; integration was not persisted.")
    raise SystemExit(4)
status, check = api_request("GET")
confirmed = status == 200 and any(
    isinstance(c, dict)
    and c.get("id") == "local-open-terminal"
    and c.get("enabled", True)
    and isinstance(c.get("config", {}), dict)
    and c.get("config", {}).get("chat_uploads", "default") == chat_uploads
    for c in check.get("TERMINAL_SERVER_CONNECTIONS", [])
)
if not confirmed:
    print("[WARNING] Open WebUI accepted the terminal configuration request but verification did not find the enabled connection with the requested Chat Uploads mode.")
    raise SystemExit(5)
print("[STATUS] Local Open Terminal connection is saved in Open WebUI and verified enabled.")
PYWEBUI_TERMINAL_REGISTER
    OPEN_TERMINAL_CONFIGURED=1
else
    OPEN_TERMINAL_CONFIGURED=0
fi

echo "[STATUS] Open WebUI is ready: http://0.0.0.0:$WEBUI_PORT"
echo "[STATUS] Strata OpenAI API: http://127.0.0.1:$API_PORT/v1"
if [[ "$OPEN_TERMINAL_ENABLED" == 1 && "$OPEN_TERMINAL_READY" == 1 ]]; then
    echo "[STATUS] Open Terminal service URL: http://127.0.0.1:$OPEN_TERMINAL_PORT"
    echo "[STATUS] Agent workspace and default uploads: $OPEN_TERMINAL_CWD"
    if [[ "${OPEN_TERMINAL_CONFIGURED:-0}" == 1 ]]; then
        echo "[STATUS] Open Terminal connection is persisted in Open WebUI and verified enabled. Refresh the page, then select it from the chat terminal picker."
    fi
fi
echo "[RUNNING] AI is active. Press Ctrl+C in this terminal to stop this launcher's services."

# Keep the foreground alive until interrupted (same UX as the llama.cpp launcher).
while true; do
    sleep 3600 &
    wait $!
done
