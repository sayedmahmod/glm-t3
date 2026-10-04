# glm-t3

**GLM (Z.ai Coding Plan) as an agent in [T3 Code](https://github.com/pingdotgg/t3code) — set up with a single command.**

T3 Code drives coding agents over the [Agent Client Protocol (ACP)](https://agentclientprotocol.com). This installer sets up the [glm-acp-agent](https://github.com/stefandevo/glm-acp-agent) — an ACP agent for the GLM models of the Z.ai Coding Plan (GLM-5.3, GLM-5.3 Flash, GLM-5 Turbo, GLM-4.7) — on your machine and wires it up as a provider instance inside T3 Code. For macOS, Linux and Windows.

## What the script does

| Step | Description |
|---|---|
| 1. Pre-flight checks | Node ≥ 18, npm ≥ 9, locate the T3 installation, **verify the ACP Registry driver inside `app.asar`** (T3 needs **0.0.46+**; stable 0.0.45 does not ship the driver yet!) |
| 2. Install the agent | `npm install -g glm-acp-agent@latest` (version can be pinned) |
| 3. Validate the API key | Real 1-token test call against `api.z.ai/api/coding/paas/v4` — **before** anything is written |
| 4. Credentials | `~/.config/glm-acp-agent/credentials.json` (mode 0600) — so the agent also works standalone |
| 5. T3 instance | Upsert of the provider instance entry `glm` in `~/.t3/userdata/settings.json` — **with backup** and atomic, validated writes |
| 6. Registry cache | Seeds `~/.t3/caches/acp-registry/registry.json` (fixes the error *“No valid cached ACP Registry index is available”*) |
| 7. Verify | Real ACP initialize handshake against the agent binary |

## Requirements

- **T3 Code 0.0.46 or newer** (the installer verifies this directly in the app bundle). Releases: [github.com/pingdotgg/t3code/releases](https://github.com/pingdotgg/t3code/releases) — until stable 0.0.46 ships, use the [Nightly](https://github.com/pingdotgg/t3code/releases/tag/v0.0.46-nightly.20261004.2648).
- Node.js ≥ 18 with npm ≥ 9
- A **Z.AI API key** (GLM Coding Plan): <https://z.ai/manage-apikey/apikey-list>

## Installation

**macOS / Linux:**

```bash
./install.sh                      # interactive (asks for the key)
./install.sh --api-key "xxxx.yyyy"
./install.sh --dry-run            # checks only, changes nothing
```

**Windows (PowerShell):**

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
.\install.ps1 -ApiKey "xxxx.yyyy"
.\install.ps1 -DryRun
```

### Options (both installers)

| Flag | Meaning |
|---|---|
| `--api-key KEY` / `-ApiKey KEY` | Pass the key directly (otherwise `$Z_AI_API_KEY` / interactive prompt) |
| `--t3-home DIR` / `-T3Home DIR` | Non-default T3 home (default: `~/.t3` or `$env:T3_HOME`) |
| `--agent-version V` / `-AgentVersion V` | Pin a specific glm-acp-agent version |
| `--no-install-agent` / `-NoInstallAgent` | Don't touch the npm package, only (re)wire the T3 config |
| `--skip-key-check` / `-SkipKeyCheck` | Skip the key test call (not recommended) |
| `--dry-run` / `-DryRun` | Run all checks, write nothing |

## What ends up where

| Path | Purpose |
|---|---|
| `~/.t3/userdata/settings.json` | Provider instance `glm` (`driver: acpRegistry`, `agentId: glm-acp-agent`, `commandPath`, key as a sensitive env var) — backed up first: `settings.json.bak-glm-t3-<timestamp>` |
| `~/.config/glm-acp-agent/credentials.json` | Key for the agent (0600), also used for standalone runs |
| `~/.t3/caches/acp-registry/registry.json` | Seeded ACP Registry index (T3 refreshes it itself) |
| npm global | `glm-acp-agent` |

## Uninstall

```bash
./uninstall.sh                    # removes instance + credentials, keeps the npm package
./uninstall.sh --remove-agent     # including the npm package
```

```powershell
.\uninstall.ps1
.\uninstall.ps1 -RemoveAgent
```

## Troubleshooting

**Provider shows “disabled” in T3 settings**
Your T3 version has no ACP Registry driver. The driver was merged **after** the 0.0.45 release → update T3 to **0.0.46+** (Nightly, until stable ships).

**“Could not inspect ACP Registry agent: No valid cached ACP Registry index is available.”**
T3's inspect path reads the registry index only from its cache. The installer seeds it — if it goes missing (e.g. after deleting `~/.t3/caches`), just run the installer again.

**Rotating the key**
Create a new key in the [Z.ai dashboard](https://z.ai/manage-apikey/apikey-list) and simply run the installer again — it updates both the credentials file and the T3 instance (idempotent).

**Windows: agent won't start**
The installer links the npm `.cmd` shim. If T3 can't spawn the agent, set the Executable Override in the provider settings to `glm-acp-agent.cmd` inside the npm global bin directory (`npm prefix -g`).

## Background

- Why ACP and not the ZCode CLI? T3 Code drives agents through defined drivers (Claude, Codex, OpenCode, …) and generically through the [ACP Registry](https://agentclientprotocol.com/get-started/registry). The ZCode CLI does not speak ACP — the glm-acp-agent does, and it uses exactly the Coding Plan endpoint.
- The installer only ever touches the single `glm` instance entry in the T3 settings file and always creates a backup first. Existing instances (claude, codex, …) are left untouched.

## License

[MIT](./LICENSE) — © sayedmahmod
