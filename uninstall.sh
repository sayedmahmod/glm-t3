#!/usr/bin/env bash
#
# glm-t3 uninstaller for macOS & Linux.
#
# Removes the GLM provider instance from T3 Code (with backup) and deletes the
# agent credentials file. The npm package is only removed with --remove-agent.
#
set -euo pipefail

INSTANCE_ID="glm"

T3_HOME="${T3_HOME:-$HOME/.t3}"
REMOVE_AGENT=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --t3-home)      T3_HOME="$2"; shift 2 ;;
    --remove-agent) REMOVE_AGENT=1; shift ;;
    --dry-run)      DRY_RUN=1; shift ;;
    -h|--help)
      echo "Usage: ./uninstall.sh [--t3-home DIR] [--remove-agent] [--dry-run]"
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

step() { printf '\n%s\n' "==> $*"; }
info() { printf '%s\n' "  [info]  $*"; }
ok()   { printf '%s\n' "  [ ok ]  $*"; }
die()  { printf '%s\n' "  [fail]  $*" >&2; exit 1; }

SETTINGS_FILE="$T3_HOME/userdata/settings.json"
[[ -f "$SETTINGS_FILE" ]] || die "T3 settings not found: $SETTINGS_FILE"

step "Removing provider instance '$INSTANCE_ID' from T3"

BACKUP_FILE="${SETTINGS_FILE}.bak-glm-t3-uninstall-$(date +%Y%m%d-%H%M%S)"
if [[ $DRY_RUN -eq 1 ]]; then
  info "[dry-run] would back up to: $BACKUP_FILE"
  info "[dry-run] would remove providerInstances.$INSTANCE_ID"
else
  # shellcheck disable=SC2016  # the JS must stay unexpanded, args pass values
  node -e '
    const fs = require("fs");
    // NOTE: with `node -e`, user args start at process.argv[1] (no script-name slot).
    const [file, backup, instanceId] = process.argv.slice(1);
    const data = JSON.parse(fs.readFileSync(file, "utf8"));
    if (data.providerInstances && data.providerInstances[instanceId]) {
      fs.copyFileSync(file, backup);
      delete data.providerInstances[instanceId];
      const tmp = file + ".tmp-glm-t3";
      fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + "\n");
      JSON.parse(fs.readFileSync(tmp, "utf8"));
      fs.renameSync(tmp, file);
      console.log("  removed, backup: " + backup);
    } else {
      console.log("  instance not present - nothing to do");
    }
  ' "$SETTINGS_FILE" "$BACKUP_FILE" "$INSTANCE_ID"
  ok "T3 settings updated"
fi

step "Agent credentials file"
CRED_FILE="$HOME/.config/glm-acp-agent/credentials.json"
if [[ -f "$CRED_FILE" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    info "[dry-run] would delete $CRED_FILE"
  else
    rm -f "$CRED_FILE"
    rmdir "$HOME/.config/glm-acp-agent" 2>/dev/null || true
    ok "Deleted: $CRED_FILE"
  fi
else
  info "No credentials file found - nothing to do"
fi

if [[ $REMOVE_AGENT -eq 1 ]]; then
  step "Removing npm package"
  if [[ $DRY_RUN -eq 1 ]]; then
    info "[dry-run] would run: npm uninstall -g glm-acp-agent"
  else
    npm uninstall -g glm-acp-agent
    ok "npm package removed"
  fi
else
  step "npm package"
  info "Left installed. Remove with: npm uninstall -g glm-acp-agent (or re-run with --remove-agent)"
fi

step "Done"
info "Restart T3 Code. The seeded ACP registry cache ($T3_HOME/caches/acp-registry) was left in place - T3 refreshes it itself."
