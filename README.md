# glm-t3

**GLM (Z.ai Coding Plan) als Agent in [T3 Code](https://github.com/pingdotgg/t3code) — mit einem Befehl eingerichtet.**

T3 Code steuert Coding-Agents über das [Agent Client Protocol (ACP)](https://agentclientprotocol.com). Dieser Installer richtet den [glm-acp-agent](https://github.com/stefandevo/glm-acp-agent) — einen ACP-Agent für die GLM-Modelle des Z.ai Coding Plans (GLM-5.3, GLM-5.3 Flash, GLM-5 Turbo, GLM-4.7) — auf deinem Rechner ein und verdrahtet ihn als Provider-Instanz in T3 Code. Für macOS, Linux und Windows.

## Was das Script macht

| Schritt | Beschreibung |
|---|---|
| 1. Vorab-Checks | Node ≥ 18, npm ≥ 9, T3-Installation finden, **ACP-Registry-Treiber im `app.asar` nachweisen** (T3 braucht **0.0.46+**; die Stable 0.0.45 hat den Treiber noch nicht!) |
| 2. Agent installieren | `npm install -g glm-acp-agent@latest` (Version optional pinnbar) |
| 3. API-Key prüfen | Echter 1-Token-Testcall gegen `api.z.ai/api/coding/paas/v4` — **bevor** irgendwas geschrieben wird |
| 4. Credentials | `~/.config/glm-acp-agent/credentials.json` (Rechte 0600) — damit der Agent auch standalone funktioniert |
| 5. T3-Instanz | Upsert des Provider-Instance-Eintrags `glm` in `~/.t3/userdata/settings.json` — **mit Backup** und atomarem, validiertem Schreiben |
| 6. Registry-Cache | Seedet `~/.t3/caches/acp-registry/registry.json` (behebt den Fehler *„No valid cached ACP Registry index is available"*) |
| 7. Verifizieren | Echter ACP-Initialize-Handshake gegen den Agent-Binary |

## Anforderungen

- **T3 Code 0.0.46 oder neuer** (der Installer prüft das konkret im App-Bundle nach). Releases: [github.com/pingdotgg/t3code/releases](https://github.com/pingdotgg/t3code/releases) — bis die Stable 0.0.46 raus ist, den [Nightly](https://github.com/pingdotgg/t3code/releases/tag/v0.0.46-nightly.20261004.2648) nehmen.
- Node.js ≥ 18 mit npm ≥ 9
- Einen **Z.AI API-Key** (GLM Coding Plan): <https://z.ai/manage-apikey/apikey-list>

## Installation

**macOS / Linux:**

```bash
./install.sh                      # interaktiv (fragt den Key ab)
./install.sh --api-key "xxxx.yyyy"
./install.sh --dry-run            # nur Checks, nichts wird geändert
```

**Windows (PowerShell):**

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
.\install.ps1 -ApiKey "xxxx.yyyy"
.\install.ps1 -DryRun
```

### Optionen (beide Installer)

| Flag | Bedeutung |
|---|---|
| `--api-key KEY` / `-ApiKey KEY` | Key direkt übergeben (sonst `$Z_AI_API_KEY` / Prompt) |
| `--t3-home DIR` / `-T3Home DIR` | Abweichendes T3-Home (Default: `~/.t3` bzw. `$env:T3_HOME`) |
| `--agent-version V` / `-AgentVersion V` | Bestimmte glm-acp-agent-Version pinnen |
| `--no-install-agent` / `-NoInstallAgent` | npm-Paket nicht anfassen, nur T3-Config neu verdrahten |
| `--skip-key-check` / `-SkipKeyCheck` | Key-Testcall überspringen (nicht empfohlen) |
| `--dry-run` / `-DryRun` | Alles prüfen, nichts schreiben |

## Was wo landet

| Pfad | Zweck |
|---|---|
| `~/.t3/userdata/settings.json` | Provider-Instanz `glm` (`driver: acpRegistry`, `agentId: glm-acp-agent`, `commandPath`, Key als sensitive Env-Var) — Backup davor: `settings.json.bak-glm-t3-<timestamp>` |
| `~/.config/glm-acp-agent/credentials.json` | Key für den Agent (0600), auch für standalone-Nutzung |
| `~/.t3/caches/acp-registry/registry.json` | Geseedeter ACP-Registry-Index (T3 aktualisiert ihn selbst) |
| npm global | `glm-acp-agent` |

## Deinstallation

```bash
./uninstall.sh                    # Instanz + Credentials raus, npm-Paket bleibt
./uninstall.sh --remove-agent     # inkl. npm-Paket
```

```powershell
.\uninstall.ps1
.\uninstall.ps1 -RemoveAgent
```

## Troubleshooting

**„disabled" beim Provider in T3 Settings**
Deine T3-Version hat keinen ACP-Registry-Treiber. Der Treiber wurde **nach** dem 0.0.45-Release gemergt → T3 auf **0.0.46+** aktualisieren (Nightly, bis die Stable raus ist).

**„Could not inspect ACP Registry agent: No valid cached ACP Registry index is available."**
T3s Inspect-Pfad liest den Registry-Index nur aus dem Cache. Der Installer seedet ihn — falls er fehlt (z. B. nach Löschen von `~/.t3/caches`), Installer einfach nochmal laufen lassen.

**Key rotieren**
Im [Z.ai-Dashboard](https://z.ai/manage-apikey/apikey-list) einen neuen Key erzeugen und den Installer erneut ausführen — er aktualisiert Credentials-Datei und T3-Instanz (beides idempotent).

**Windows: Agent startet nicht**
Der Installer verlinkt den npm-`.cmd`-Shim. Falls T3 den Agent nicht spawnen kann, in den Provider-Settings den Executable-Override auf `glm-acp-agent.cmd` im npm-Global-Bin-Verzeichnis (`npm prefix -g`) setzen.

## Hintergrund

- Warum ACP und nicht die ZCode-CLI? T3 Code steuert Agents über definierte Treiber (Claude, Codex, OpenCode, …) und generisch über die [ACP Registry](https://agentclientprotocol.com/get-started/registry). Die ZCode-CLI spricht kein ACP — der glm-acp-agent schon, und er nutzt exakt den Coding-Plan-Endpunkt.
- Der Installer ändert ausschließlich den einen Instance-Eintrag `glm` in der T3-Settings-Datei und legt davor immer ein Backup an. Bestehende Instanzen (claude, codex, …) werden nicht angerührt.

## License

[MIT](./LICENSE) — © sayedmahmod
