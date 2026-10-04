<#
.SYNOPSIS
    glm-t3 uninstaller for Windows.

.DESCRIPTION
    Removes the GLM provider instance from T3 Code (with backup) and deletes
    the agent credentials file. The npm package is only removed with
    -RemoveAgent.

.EXAMPLE
    .\uninstall.ps1
    .\uninstall.ps1 -RemoveAgent
#>
[CmdletBinding()]
param(
    [string]$T3Home = $(if ($env:T3_HOME) { $env:T3_HOME } else { Join-Path $HOME ".t3" }),
    [switch]$RemoveAgent,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$InstanceId = "glm"

function Info([string]$m) { Write-Host "  [info]  $m" }
function Ok([string]$m)   { Write-Host "  [ ok ]  $m" -ForegroundColor Green }

$settingsFile = Join-Path $T3Home "userdata\settings.json"
if (-not (Test-Path $settingsFile)) { throw "T3 settings not found: $settingsFile" }

Write-Host ""
Write-Host "==> Removing provider instance '$InstanceId' from T3"

$backupFile = "$settingsFile.bak-glm-t3-uninstall-" + (Get-Date -Format "yyyyMMdd-HHmmss")
if ($DryRun) {
    Info "[dry-run] would back up to: $backupFile"
    Info "[dry-run] would remove providerInstances.$InstanceId"
} else {
    & node -e @'
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
'@ $settingsFile $backupFile $InstanceId
    if ($LASTEXITCODE -ne 0) { throw "Could not update T3 settings." }
    Ok "T3 settings updated"
}

Write-Host ""
Write-Host "==> Agent credentials file"
$credFile = Join-Path $HOME ".config\glm-acp-agent\credentials.json"
if (Test-Path $credFile) {
    if ($DryRun) {
        Info "[dry-run] would delete $credFile"
    } else {
        Remove-Item $credFile -Force
        Ok "Deleted: $credFile"
    }
} else {
    Info "No credentials file found - nothing to do"
}

Write-Host ""
Write-Host "==> npm package"
if ($RemoveAgent) {
    if ($DryRun) {
        Info "[dry-run] would run: npm uninstall -g glm-acp-agent"
    } else {
        & npm uninstall -g glm-acp-agent
        Ok "npm package removed"
    }
} else {
    Info "Left installed. Remove with: npm uninstall -g glm-acp-agent (or re-run with -RemoveAgent)"
}

Write-Host ""
Write-Host "==> Done"
Info "Restart T3 Code. The seeded ACP registry cache was left in place - T3 refreshes it itself."
