#!/usr/bin/env bash
#
# glm-t3 installer for macOS & Linux.
#
# Installs the GLM ACP agent (glm-acp-agent, Z.ai GLM Coding Plan) and wires it
# up as a provider instance inside T3 Code (https://github.com/pingdotgg/t3code).
#
# Everything it touches is backed up first; nothing is deleted. Run with
# --dry-run to see every planned action without changing anything.
#
# Repo: https://github.com/sayedmahmod/glm-t3
#
set -euo pipefail

SCRIPT_VERSION="1.0.0"
INSTANCE_ID="glm"
DISPLAY_NAME="GLM Agent (Z.ai Coding Plan)"
AGENT_ID="glm-acp-agent"
NPM_PACKAGE="glm-acp-agent"
AUTH_METHOD_ID="z_ai_api_key"
ENV_VAR_NAME="Z_AI_API_KEY"
REGISTRY_URL="https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json"
CODING_API_BASE="https://api.z.ai/api/coding/paas/v4"
T3_DRIVER_MIN_HINT="0.0.46"

# ---------------------------------------------------------------------------
# pretty output
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; DIM=""; RESET=""
fi
info()  { printf '%s\n' "  ${DIM}[info]${RESET}  $*"; }
ok()    { printf '%s\n' "  ${GREEN}[ ok ]${RESET}  $*"; }
warn()  { printf '%s\n' "  ${YELLOW}[warn]${RESET}  $*" >&2; }
die()   { printf '%s\n' "  ${RED}[fail]${RESET}  $*" >&2; exit 1; }
step()  { printf '\n%s\n' "${BOLD}==> $*${RESET}"; }

mask_key() { local k="$1"; printf '%s…%s' "${k:0:6}" "${k: -4}"; }

usage() {
  cat <<EOF
glm-t3 installer v${SCRIPT_VERSION} (macOS / Linux)

Installs the glm-acp-agent (Z.ai GLM Coding Plan) globally via npm and
registers it as an ACP Registry provider instance inside T3 Code.

Usage:
  ./install.sh [options]

Options:
  --api-key KEY       Z.AI Coding Plan API key (else \$Z_AI_API_KEY env or
                      interactive prompt). Get one: https://z.ai/manage-apikey/apikey-list
  --t3-home DIR       T3 home directory (default: \$T3_HOME or ~/.t3)
  --agent-version V   Pin a specific glm-acp-agent version (default: latest)
  --no-install-agent  Do not touch the npm package; only (re)wire T3 config
  --skip-key-check    Skip the live API key validation call
  --dry-run           Run all checks, change nothing
  -h, --help          Show this help
EOF
}

# ---------------------------------------------------------------------------
# arguments
# ---------------------------------------------------------------------------
API_KEY="${Z_AI_API_KEY:-}"
T3_HOME="${T3_HOME:-$HOME/.t3}"
AGENT_VERSION=""
NO_INSTALL_AGENT=0
SKIP_KEY_CHECK=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-key)          API_KEY="$2"; shift 2 ;;
    --t3-home)          T3_HOME="$2"; shift 2 ;;
    --agent-version)    AGENT_VERSION="$2"; shift 2 ;;
    --no-install-agent) NO_INSTALL_AGENT=1; shift ;;
    --skip-key-check)   SKIP_KEY_CHECK=1; shift ;;
    --dry-run)          DRY_RUN=1; shift ;;
    -h|--help)          usage; exit 0 ;;
    *)                  die "Unknown option: $1 (see --help)" ;;
  esac
done

step "glm-t3 installer v${SCRIPT_VERSION}"
[[ $DRY_RUN -eq 1 ]] && warn "DRY RUN - no changes will be made"

# ---------------------------------------------------------------------------
# 1. platform & toolchain
# ---------------------------------------------------------------------------
step "Checking platform & toolchain"

OS="$(uname -s)"
case "$OS" in
  Darwin) OS_NAME="macOS" ;;
  Linux)  OS_NAME="Linux" ;;
  *) die "Unsupported platform '$OS'. For Windows use install.ps1 (PowerShell)." ;;
esac
ok "Platform: $OS_NAME ($(uname -m))"

command -v node >/dev/null 2>&1 || die "node not found in PATH. Install Node.js 18+ (https://nodejs.org)."
NODE_MAJOR="$(node -p 'parseInt(process.versions.node, 10)')"
[[ "$NODE_MAJOR" -ge 18 ]] || die "node $(node --version) is too old. glm-acp-agent needs Node.js 18+."
ok "node $(node --version)"

command -v npm >/dev/null 2>&1 || die "npm not found in PATH (comes with Node.js)."
NPM_VERSION="$(npm --version)"
NPM_OK="$(printf '%s\n' 9.0.0 "$NPM_VERSION" | sort -V | head -1)"
[[ "$NPM_OK" == "9.0.0" ]] || die "npm $NPM_VERSION is too old (need >= 9). Update: npm install -g npm@latest"
ok "npm $NPM_VERSION"

# ---------------------------------------------------------------------------
# 2. locate T3 Code & verify it can run ACP Registry agents
# ---------------------------------------------------------------------------
step "Locating T3 Code installation"

T3_APP=""
T3_ASAR=""
find_t3_macos() {
  local candidates=(
    "$HOME/Applications/T3 Code (Nightly).app"
    "/Applications/T3 Code (Nightly).app"
    "$HOME/Applications/T3 Code (Alpha).app"
    "/Applications/T3 Code (Alpha).app"
    "$HOME/Applications/T3 Code.app"
    "/Applications/T3 Code.app"
  )
  local app
  for app in "${candidates[@]}"; do
    if [[ -d "$app" ]]; then
      T3_APP="$app"
      T3_ASAR="$app/Contents/Resources/app.asar"
      return 0
    fi
  done
  return 1
}
find_t3_linux() {
  local asar="" candidate
  shopt -s nullglob
  for candidate in /opt/*T3*/resources/app.asar /usr/lib/*T3*/resources/app.asar /usr/lib/*t3*/resources/app.asar; do
    if [[ -f "$candidate" ]]; then asar="$candidate"; break; fi
  done
  shopt -u nullglob
  if [[ -n "$asar" ]]; then
    T3_ASAR="$asar"
    T3_APP="$(dirname "$(dirname "$asar")")"
    return 0
  fi
  return 1
}

T3_FOUND=0
if [[ "$OS" == "Darwin" ]]; then find_t3_macos && T3_FOUND=1; else find_t3_linux && T3_FOUND=1; fi

if [[ $T3_FOUND -eq 1 ]]; then
  T3_VERSION="(unknown)"
  if [[ "$OS" == "Darwin" ]]; then
    T3_VERSION="$(defaults read "$T3_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "(unknown)")"
  else
    T3_VERSION="$(grep -aom1 '"version":"[^"]*"' "$T3_ASAR" 2>/dev/null | head -1 | cut -d'"' -f4 || echo "(unknown)")"
  fi
  ok "T3 Code found: $T3_APP (version $T3_VERSION)"

  if [[ -f "$T3_ASAR" ]]; then
    if grep -aq "AcpRegistry" "$T3_ASAR" 2>/dev/null; then
      ok "ACP Registry driver present in this T3 build"
    else
      die "This T3 build ($T3_VERSION) has NO ACP Registry driver.
         The driver ships with T3 0.0.46+ (stable was 0.0.45 = too old).
         Update T3 Code, then re-run this script.
         Latest releases: https://github.com/pingdotgg/t3code/releases"
    fi
  fi
else
  warn "T3 Code installation not found in the usual locations."
  warn "Continuing with the T3 home config only - make sure T3 Code $T3_DRIVER_MIN_HINT or newer is installed!"
  warn "Releases: https://github.com/pingdotgg/t3code/releases"
fi

# ---------------------------------------------------------------------------
# 3. validate T3 home
# ---------------------------------------------------------------------------
step "Validating T3 home: $T3_HOME"

[[ -d "$T3_HOME" ]] || die "T3 home not found at $T3_HOME.
   Start T3 Code once (it creates the home directory), then re-run this script.
   (Or point at the right home with --t3-home / \$T3_HOME.)"
[[ -d "$T3_HOME/userdata" ]] || die "$T3_HOME exists but has no 'userdata' directory - not a valid T3 home."
SETTINGS_FILE="$T3_HOME/userdata/settings.json"
if [[ -f "$SETTINGS_FILE" ]]; then
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$SETTINGS_FILE" \
    || die "$SETTINGS_FILE is not valid JSON - refusing to touch it."
  ok "settings.json found and valid"
else
  die "$SETTINGS_FILE not found. Start T3 Code once so it creates its settings, then re-run."
fi

# ---------------------------------------------------------------------------
# 4. install glm-acp-agent
# ---------------------------------------------------------------------------
step "Installing $NPM_PACKAGE (npm global)"

command -v glm-acp-agent >/dev/null 2>&1 && HAVE_AGENT=1 || HAVE_AGENT=0
SPEC="$NPM_PACKAGE${AGENT_VERSION:+@$AGENT_VERSION}"

if [[ $DRY_RUN -eq 1 ]]; then
  info "[dry-run] would run: npm install -g $SPEC"
  BIN_PATH="$(command -v glm-acp-agent 2>/dev/null || true)"
  [[ -z "$BIN_PATH" ]] && BIN_PATH="$(npm prefix -g)/bin/glm-acp-agent"
elif [[ $NO_INSTALL_AGENT -eq 1 ]]; then
  [[ $HAVE_AGENT -eq 1 ]] || die "--no-install-agent set but glm-acp-agent is not installed."
  info "Skipping npm install (--no-install-agent)"
  BIN_PATH="$(command -v glm-acp-agent)"
else
  npm install -g "$SPEC" >/dev/null
  ok "npm package installed: $SPEC"
  BIN_PATH="$(command -v glm-acp-agent)" || die "glm-acp-agent binary not on PATH after npm install."
fi
[[ -x "$BIN_PATH" ]] || die "Agent binary not executable: $BIN_PATH"
ok "Agent binary: $BIN_PATH"

# ---------------------------------------------------------------------------
# 5. obtain & validate the Z.AI API key
# ---------------------------------------------------------------------------
step "Z.AI API key"

if [[ -z "$API_KEY" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    warn "No API key provided (via --api-key or \$Z_AI_API_KEY). Dry-run continues without key validation."
  else
    printf '  Enter your Z.AI API key (%s): ' "https://z.ai/manage-apikey/apikey-list"
    read -rs API_KEY
    printf '\n'
    [[ -n "$API_KEY" ]] || die "No API key entered."
  fi
fi

if [[ -n "$API_KEY" && $SKIP_KEY_CHECK -eq 0 ]]; then
  info "Validating key ${BOLD}$(mask_key "$API_KEY")${RESET} against the Coding Plan endpoint (1-token call)..."
  HTTP_CODE="$(curl -sS -m 30 -o /tmp/glm-t3-keycheck.json -w '%{http_code}' \
    -X POST "$CODING_API_BASE/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"model":"glm-5.3-flash","messages":[{"role":"user","content":"ping"}],"max_tokens":1}' \
    2>/dev/null || echo "000")"
  if [[ "$HTTP_CODE" == "200" ]]; then
    ok "API key is valid"
  else
    BODY="$(head -c 200 /tmp/glm-t3-keycheck.json 2>/dev/null || echo '')"
    rm -f /tmp/glm-t3-keycheck.json
    die "API key validation failed (HTTP $HTTP_CODE). $BODY
   - Key from https://z.ai/manage-apikey/apikey-list ?
   - Copy it completely (format: xxxxxxxx.xxxxxxxx)?
   - Skip this check with --skip-key-check (not recommended)."
  fi
  rm -f /tmp/glm-t3-keycheck.json
elif [[ $SKIP_KEY_CHECK -eq 1 ]]; then
  warn "Key validation skipped (--skip-key-check)"
fi

# ---------------------------------------------------------------------------
# 6. write agent credentials file
# ---------------------------------------------------------------------------
step "Agent credentials file"

CRED_DIR="$HOME/.config/glm-acp-agent"
CRED_FILE="$CRED_DIR/credentials.json"
if [[ $DRY_RUN -eq 1 ]]; then
  info "[dry-run] would write $CRED_FILE ({\"z_ai_api_key\": \"...\"}, chmod 0600)"
else
  mkdir -p "$CRED_DIR"
  chmod 700 "$CRED_DIR"
  # shellcheck disable=SC2016  # the JS must stay unexpanded, args pass values
  node -e '
    const fs = require("fs");
    // NOTE: with `node -e`, user args start at process.argv[1] (no script-name slot).
    const [file, key] = process.argv.slice(1);
    fs.writeFileSync(file, JSON.stringify({ z_ai_api_key: key }, null, 2) + "\n");
  ' "$CRED_FILE" "$API_KEY"
  chmod 600 "$CRED_FILE"
  ok "Written: $CRED_FILE (0600)"
fi

# ---------------------------------------------------------------------------
# 7. register provider instance in T3 settings (with backup)
# ---------------------------------------------------------------------------
step "T3 provider instance ($INSTANCE_ID) in $SETTINGS_FILE"

BACKUP_FILE="${SETTINGS_FILE}.bak-glm-t3-$(date +%Y%m%d-%H%M%S)"

if [[ $DRY_RUN -eq 1 ]]; then
  info "[dry-run] would back up to: $BACKUP_FILE"
  info "[dry-run] would upsert instance '$INSTANCE_ID' (driver: acpRegistry, agentId: $AGENT_ID)"
  info "[dry-run] would set commandPath: $BIN_PATH"
  [[ -n "$API_KEY" ]] && info "[dry-run] would store $ENV_VAR_NAME as sensitive env var on the instance"
else
  # shellcheck disable=SC2016  # the JS must stay unexpanded, args pass values
  node -e '
    const fs = require("fs");
    // NOTE: with `node -e`, user args start at process.argv[1] (no script-name slot).
    const [file, backup, instanceId, displayName, agentId, commandPath, authMethodId, envVarName, apiKey] = process.argv.slice(1);
    const data = JSON.parse(fs.readFileSync(file, "utf8"));
    fs.copyFileSync(file, backup);
    data.providerInstances = data.providerInstances || {};
    const prev = data.providerInstances[instanceId] || {};
    const prevConfig = prev.config || {};
    const inst = {
      driver: "acpRegistry",
      displayName,
      enabled: true,
      environment: Array.isArray(prev.environment) ? prev.environment : [],
      config: {
        agentId,
        commandPath,
        authMethodId,
        distribution: prevConfig.distribution || "auto",
        customModels: Array.isArray(prevConfig.customModels) ? prevConfig.customModels : [],
      },
    };
    if (apiKey) {
      inst.environment = inst.environment.filter((e) => e && e.name !== envVarName);
      inst.environment.push({ name: envVarName, value: apiKey, sensitive: true });
    }
    data.providerInstances[instanceId] = inst;
    const tmp = file + ".tmp-glm-t3";
    fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + "\n");
    JSON.parse(fs.readFileSync(tmp, "utf8")); // verify before replacing
    fs.renameSync(tmp, file);
    console.log("  instance upserted, backup: " + backup);
  ' "$SETTINGS_FILE" "$BACKUP_FILE" "$INSTANCE_ID" "$DISPLAY_NAME" "$AGENT_ID" "$BIN_PATH" "$AUTH_METHOD_ID" "$ENV_VAR_NAME" "$API_KEY"
  ok "Provider instance written (backup: $BACKUP_FILE)"
fi

# ---------------------------------------------------------------------------
# 8. seed the ACP Registry index cache
# ---------------------------------------------------------------------------
step "ACP Registry index cache"

CACHE_DIR="$T3_HOME/caches/acp-registry"
CACHE_FILE="$CACHE_DIR/registry.json"

info "Downloading registry index from the official CDN..."
if curl -fsSL -m 30 "$REGISTRY_URL" -o /tmp/glm-t3-registry.json 2>/dev/null; then
  if node -e '
    const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (typeof d.version !== "string" || !Array.isArray(d.agents)) process.exit(2);
    const glm = d.agents.find((a) => a && a.id === "glm-acp-agent");
    if (!glm || !glm.distribution) process.exit(3);
  ' /tmp/glm-t3-registry.json 2>/dev/null; then
    if [[ $DRY_RUN -eq 1 ]]; then
      info "[dry-run] would write $CACHE_FILE (validated: version + glm-acp-agent entry present)"
    else
      mkdir -p "$CACHE_DIR"
      mv /tmp/glm-t3-registry.json "$CACHE_FILE"
      ok "Registry index cached: $CACHE_FILE"
    fi
  else
    warn "Downloaded registry index failed validation - not writing it. T3 will fetch it itself."
  fi
else
  warn "Could not download the registry index (offline?). T3 will try itself on next start."
fi
rm -f /tmp/glm-t3-registry.json

# ---------------------------------------------------------------------------
# 9. end-to-end handshake test
# ---------------------------------------------------------------------------
step "Verifying agent speaks ACP"

if [[ $DRY_RUN -eq 1 ]]; then
  info "[dry-run] would run an ACP initialize handshake against $BIN_PATH"
else
  # shellcheck disable=SC2016  # the JS must stay unexpanded, args pass values
  if node -e '
    const { spawn } = require("child_process");
    const bin = process.argv[1]; // with `node -e`, user args start at argv[1]
    const child = spawn(bin, [], { stdio: ["pipe", "pipe", "pipe"] });
    let done = false;
    const finish = (ok, msg) => { if (!done) { done = true; child.kill(); process.exit(ok ? 0 : 1); } };
    const timer = setTimeout(() => finish(false), 15000);
    child.stdout.on("data", (d) => {
      if (String(d).includes("authMethods")) { clearTimeout(timer); finish(true); }
    });
    child.on("error", () => { clearTimeout(timer); finish(false); });
    child.on("exit", () => { clearTimeout(timer); finish(false); });
    child.stdin.write(JSON.stringify({
      jsonrpc: "2.0", id: 1, method: "initialize",
      params: { protocolVersion: 1, clientCapabilities: { fs: { readTextFile: false, writeTextFile: false } } },
    }) + "\n");
  ' "$BIN_PATH"; then
    ok "Agent answered the ACP initialize handshake"
  else
    die "Agent did not answer the ACP handshake - check: node version, npm install, $BIN_PATH"
  fi
fi

# ---------------------------------------------------------------------------
# 10. wrap up
# ---------------------------------------------------------------------------
step "Done"

if pgrep -f "T3 Code" >/dev/null 2>&1; then
  warn "T3 Code is currently running. Restart it so the provider is picked up cleanly."
fi

cat <<EOF

  ${GREEN}${BOLD}GLM is wired up for T3 Code.${RESET}

    Provider instance : $INSTANCE_ID ($DISPLAY_NAME)
    Agent             : $AGENT_ID -> $BIN_PATH
    Credentials       : $CRED_FILE
    T3 settings       : $SETTINGS_FILE
    Registry cache    : $CACHE_FILE

  Next steps:
    1. (Re)start T3 Code.
    2. Settings -> Providers -> "$DISPLAY_NAME" should be listed & active.
    3. Open a chat and pick a GLM model (glm-5.3, glm-5.3-flash, ...).

  Rotate your key later? Update it and simply re-run this script.
EOF
