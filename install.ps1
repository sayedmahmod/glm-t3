<#
.SYNOPSIS
    glm-t3 installer for Windows.

.DESCRIPTION
    Installs the GLM ACP agent (glm-acp-agent, Z.ai GLM Coding Plan) globally
    via npm and registers it as an ACP Registry provider instance inside
    T3 Code (https://github.com/pingdotgg/t3code).

    Everything it touches is backed up first; nothing is deleted. Run with
    -DryRun to see every planned action without changing anything.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -ApiKey "xxxxxxxx.yyyyyyyy"
    .\install.ps1 -DryRun
    .\install.ps1 -T3Home "$HOME\.t3" -AgentVersion "1.14.0"

.NOTES
    Run with PowerShell 5.1 or later. If script execution is blocked:
    powershell -ExecutionPolicy Bypass -File .\install.ps1
#>
[CmdletBinding()]
param(
    [string]$ApiKey = $env:Z_AI_API_KEY,
    [string]$T3Home = $(if ($env:T3_HOME) { $env:T3_HOME } else { Join-Path $HOME ".t3" }),
    [string]$AgentVersion = "",
    [switch]$NoInstallAgent,
    [switch]$SkipKeyCheck,
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072

$ScriptVersion   = "1.0.0"
$InstanceId      = "glm"
$DisplayName     = "GLM Agent (Z.ai Coding Plan)"
$AgentId         = "glm-acp-agent"
$NpmPackage      = "glm-acp-agent"
$AuthMethodId    = "z_ai_api_key"
$EnvVarName      = "Z_AI_API_KEY"
$RegistryUrl     = "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json"
$CodingApiBase   = "https://api.z.ai/api/coding/paas/v4"
$T3DriverMinHint = "0.0.46"

function Info([string]$m) { Write-Host "  [info]  $m" }
function Ok([string]$m)   { Write-Host "  [ ok ]  $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Warning $m }
function MaskKey([string]$k) {
    if ($k.Length -le 10) { return "*" * $k.Length }
    return $k.Substring(0, 6) + "..." + $k.Substring($k.Length - 4)
}

if ($Help) {
    Write-Host @"
glm-t3 installer v$ScriptVersion (Windows)

Installs the glm-acp-agent (Z.ai GLM Coding Plan) globally via npm and
registers it as an ACP Registry provider instance inside T3 Code.

Usage:
  .\install.ps1 [options]

Options:
  -ApiKey KEY          Z.AI Coding Plan API key (else `$env:Z_AI_API_KEY or
                       interactive prompt). Get one: https://z.ai/manage-apikey/apikey-list
  -T3Home DIR          T3 home directory (default: `$env:T3_HOME or ~\.t3)
  -AgentVersion V      Pin a specific glm-acp-agent version (default: latest)
  -NoInstallAgent      Do not touch the npm package; only (re)wire T3 config
  -SkipKeyCheck        Skip the live API key validation call
  -DryRun              Run all checks, change nothing
  -Help                Show this help
"@
    exit 0
}

Write-Host ""
Write-Host "==> glm-t3 installer v$ScriptVersion"
if ($DryRun) { Write-Warning "DRY RUN - no changes will be made" }

# ---------------------------------------------------------------------------
# 1. toolchain
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Checking toolchain"

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw "node not found in PATH. Install Node.js 18+ (https://nodejs.org)." }
$nodeVersion = (& node --version) -replace "^v", ""
$nodeMajor = [int]($nodeVersion.Split(".")[0])
if ($nodeMajor -lt 18) { throw "node $nodeVersion is too old. glm-acp-agent needs Node.js 18+." }
Ok "node v$nodeVersion"

$npm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npm) { throw "npm not found in PATH (comes with Node.js)." }
$npmVersion = (& npm --version)
$npmMajor = [int]($npmVersion.Split(".")[0])
if ($npmMajor -lt 9) { throw "npm $npmVersion is too old (need >= 9). Update: npm install -g npm@latest" }
Ok "npm $npmVersion"

# ---------------------------------------------------------------------------
# 2. locate T3 Code & verify it can run ACP Registry agents
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Locating T3 Code installation"

$t3Asar = $null
$t3Root = $null
$searchRoots = @(
    (Join-Path $env:LOCALAPPDATA "Programs"),
    $env:ProgramFiles,
    ${env:ProgramFiles(x86)}
) | Where-Object { $_ -and (Test-Path $_) }

foreach ($root in $searchRoots) {
    $hit = Get-ChildItem -Path $root -Filter "app.asar" -Recurse -Depth 3 -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "T3" -and $_.FullName -match "resources" } |
        Select-Object -First 1
    if ($hit) { $t3Asar = $hit.FullName; $t3Root = Split-Path (Split-Path $t3Asar); break }
}

if ($t3Asar) {
    $t3Version = "(unknown)"
    $exe = Get-ChildItem -Path $t3Root -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe) { $t3Version = $exe.VersionInfo.ProductVersion }
    Ok "T3 Code found: $t3Root (version $t3Version)"

    $driverHit = $false
    try {
        $bytes = [System.IO.File]::ReadAllBytes($t3Asar)
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        $driverHit = $text.Contains("AcpRegistry")
    } catch {
        Warn "Could not scan app.asar for the ACP driver ($($_.Exception.Message))."
    }
    if ($driverHit) {
        Ok "ACP Registry driver present in this T3 build"
    } else {
        throw "This T3 build ($t3Version) has NO ACP Registry driver.`nThe driver ships with T3 $T3DriverMinHint+ (stable 0.0.45 = too old).`nUpdate T3 Code, then re-run this script.`nReleases: https://github.com/pingdotgg/t3code/releases"
    }
} else {
    Warn "T3 Code installation not found in the usual locations."
    Warn "Continuing with the T3 home config only - make sure T3 Code $T3DriverMinHint or newer is installed!"
}

# ---------------------------------------------------------------------------
# 3. validate T3 home
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Validating T3 home: $T3Home"

if (-not (Test-Path $T3Home)) {
    throw "T3 home not found at $T3Home.`nStart T3 Code once (it creates the home directory), then re-run this script."
}
$userdata = Join-Path $T3Home "userdata"
if (-not (Test-Path $userdata)) { throw "$T3Home exists but has no 'userdata' directory - not a valid T3 home." }
$settingsFile = Join-Path $userdata "settings.json"
if (-not (Test-Path $settingsFile)) {
    throw "$settingsFile not found. Start T3 Code once so it creates its settings, then re-run."
}
try {
    $null = Get-Content $settingsFile -Raw | ConvertFrom-Json
} catch {
    throw "$settingsFile is not valid JSON - refusing to touch it."
}
Ok "settings.json found and valid"

# ---------------------------------------------------------------------------
# 4. install glm-acp-agent
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Installing $NpmPackage (npm global)"

$spec = if ($AgentVersion) { "$NpmPackage@$AgentVersion" } else { $NpmPackage }
$existing = Get-Command glm-acp-agent -ErrorAction SilentlyContinue

if ($DryRun) {
    Info "[dry-run] would run: npm install -g $spec"
    $npmPrefix = if ($existing) { (Split-Path $existing.Source) } else { (& npm prefix -g) }
    $commandPath = Join-Path $npmPrefix "glm-acp-agent.cmd"
} elseif ($NoInstallAgent) {
    if (-not $existing) { throw "-NoInstallAgent set but glm-acp-agent is not installed." }
    Info "Skipping npm install (-NoInstallAgent)"
    $commandPath = $existing.Source
} else {
    Write-Host "  npm install -g $spec ..."
    & npm install -g $spec 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "npm install -g $spec failed." }
    Ok "npm package installed: $spec"
    $existing = Get-Command glm-acp-agent -ErrorAction SilentlyContinue
    if (-not $existing) { throw "glm-acp-agent not on PATH after npm install (open a new shell and re-run)." }
    $commandPath = $existing.Source
    # Prefer the .cmd shim next to the resolved command (npm global bin).
    $cmdShim = Join-Path (Split-Path $commandPath) "glm-acp-agent.cmd"
    if (Test-Path $cmdShim) { $commandPath = $cmdShim }
}
Ok "Agent binary: $commandPath"

# ---------------------------------------------------------------------------
# 5. obtain & validate the Z.AI API key
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Z.AI API key"

if (-not $ApiKey -and -not $DryRun) {
    $secure = Read-Host "  Enter your Z.AI API key (https://z.ai/manage-apikey/apikey-list)" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $ApiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    if (-not $ApiKey) { throw "No API key entered." }
}

if ($ApiKey -and -not $SkipKeyCheck) {
    Info "Validating key $(MaskKey $ApiKey) against the Coding Plan endpoint (1-token call)..."
    $body = @{ model = "glm-5.3-flash"; max_tokens = 1; messages = @(@{ role = "user"; content = "ping" }) } | ConvertTo-Json -Depth 5
    try {
        $null = Invoke-RestMethod -Method Post -Uri "$CodingApiBase/chat/completions" `
            -Headers @{ Authorization = "Bearer $ApiKey" } `
            -ContentType "application/json" -Body $body -TimeoutSec 30
        Ok "API key is valid"
    } catch {
        $status = ""
        try { $status = "HTTP " + [int]$_.Exception.Response.StatusCode } catch {}
        throw "API key validation failed ($status).`n - Key from https://z.ai/manage-apikey/apikey-list ?`n - Copy it completely (format: xxxxxxxx.xxxxxxxx)?`n - Skip this check with -SkipKeyCheck (not recommended)."
    }
} elseif ($SkipKeyCheck) {
    Warn "Key validation skipped (-SkipKeyCheck)"
}

# ---------------------------------------------------------------------------
# 6. write agent credentials file
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Agent credentials file"

$credDir = Join-Path $HOME ".config\glm-acp-agent"
$credFile = Join-Path $credDir "credentials.json"
if ($DryRun) {
    Info "[dry-run] would write $credFile ({`"z_ai_api_key`": `"...`"})"
} else {
    New-Item -ItemType Directory -Force -Path $credDir | Out-Null
    & node -e "const fs=require('fs');const[f,k]=process.argv.slice(1);fs.writeFileSync(f,JSON.stringify({z_ai_api_key:k},null,2)+'\n');" $credFile $ApiKey
    if ($LASTEXITCODE -ne 0) { throw "Could not write credentials file." }
    Ok "Written: $credFile"
}

# ---------------------------------------------------------------------------
# 7. register provider instance in T3 settings (with backup)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> T3 provider instance ($InstanceId) in $settingsFile"

$backupFile = "$settingsFile.bak-glm-t3-" + (Get-Date -Format "yyyyMMdd-HHmmss")

if ($DryRun) {
    Info "[dry-run] would back up to: $backupFile"
    Info "[dry-run] would upsert instance '$InstanceId' (driver: acpRegistry, agentId: $AgentId)"
    Info "[dry-run] would set commandPath: $commandPath"
    if ($ApiKey) { Info "[dry-run] would store $EnvVarName as sensitive env var on the instance" }
} else {
    & node -e @'
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
'@ $settingsFile $backupFile $InstanceId $DisplayName $AgentId $commandPath $AuthMethodId $EnvVarName $ApiKey
    if ($LASTEXITCODE -ne 0) { throw "Could not update T3 settings." }
    Ok "Provider instance written (backup: $backupFile)"
}

# ---------------------------------------------------------------------------
# 8. seed the ACP Registry index cache
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> ACP Registry index cache"

$cacheDir = Join-Path $T3Home "caches\acp-registry"
$cacheFile = Join-Path $cacheDir "registry.json"

Info "Downloading registry index from the official CDN..."
$tmpRegistry = Join-Path $env:TEMP "glm-t3-registry.json"
try {
    Invoke-WebRequest -UseBasicParsing -Uri $RegistryUrl -OutFile $tmpRegistry -TimeoutSec 30
    $indexOk = $false
    & node -e "const d=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));const ok=typeof d.version==='string'&&Array.isArray(d.agents)&&d.agents.some(a=>a&&a.id==='glm-acp-agent'&&a.distribution);process.exit(ok?0:2);" $tmpRegistry
    if ($LASTEXITCODE -eq 0) { $indexOk = $true }

    if ($indexOk) {
        if ($DryRun) {
            Info "[dry-run] would write $cacheFile (validated: version + glm-acp-agent entry present)"
        } else {
            New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
            Move-Item -Force -Path $tmpRegistry -Destination $cacheFile
            Ok "Registry index cached: $cacheFile"
        }
    } else {
        Warn "Downloaded registry index failed validation - not writing it. T3 will fetch it itself."
    }
} catch {
    Warn "Could not download the registry index (offline?). T3 will try itself on next start."
}
if (Test-Path $tmpRegistry) { Remove-Item $tmpRegistry -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------------------
# 9. end-to-end handshake test
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Verifying agent speaks ACP"

if ($DryRun) {
    Info "[dry-run] would run an ACP initialize handshake against $commandPath"
} else {
    & node -e @'
const { spawn } = require("child_process");
const bin = process.argv[1]; // with `node -e`, user args start at argv[1]
const child = spawn(bin, [], { shell: process.platform === "win32", stdio: ["pipe", "pipe", "pipe"] });
let done = false;
const finish = (ok) => { if (!done) { done = true; try { child.kill(); } catch (e) {} process.exit(ok ? 0 : 1); } };
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
'@ $commandPath
    if ($LASTEXITCODE -eq 0) {
        Ok "Agent answered the ACP initialize handshake"
    } else {
        throw "Agent did not answer the ACP handshake - check: node version, npm install, $commandPath"
    }
}

# ---------------------------------------------------------------------------
# 10. wrap up
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Done"

$t3Running = Get-Process -Name "T3 Code*" -ErrorAction SilentlyContinue
if ($t3Running) { Warn "T3 Code is currently running. Restart it so the provider is picked up cleanly." }

Write-Host ""
Write-Host "  GLM is wired up for T3 Code." -ForegroundColor Green
Write-Host ""
Write-Host "    Provider instance : $InstanceId ($DisplayName)"
Write-Host "    Agent             : $AgentId -> $commandPath"
Write-Host "    Credentials       : $credFile"
Write-Host "    T3 settings       : $settingsFile"
Write-Host "    Registry cache    : $cacheFile"
Write-Host ""
Write-Host "  Next steps:"
Write-Host "    1. (Re)start T3 Code."
Write-Host "    2. Settings -> Providers -> '$DisplayName' should be listed & active."
Write-Host "    3. Open a chat and pick a GLM model (glm-5.3, glm-5.3-flash, ...)."
Write-Host ""
Write-Host "  Rotate your key later? Update it and simply re-run this script."
