# Safety net (live errors, kill switch, save rescue)

Added 26 Oct 2026. What to do when live breaks: `docs/ROLLBACK.md`.

## Modules

| Module | Side | Does |
|---|---|---|
| `src/ServerScriptService/ErrorBook.lua` | pure | Error signatures, batches, the per-day record merge, the client report rate limit |
| `src/ServerScriptService/ErrorLog.lua` | server | ScriptContext.Error + SVRemotes.ReportError into SVErrors_v1 once a minute; `read(days)` |
| `src/StarterPlayer/StarterPlayerScripts/ErrorReportClient.client.lua` | client | Sends this client's errors (once per 30 s each) |
| `src/ServerScriptService/Flags.lua` | server + Studio | The kill switch: SVFlags_v1 "live"/"studio", polled every 60 s, copied to ReplicatedStorage `Flag_<name>` |
| `src/ServerScriptService/SaveRescue.lua` | Studio (Edit) | Lists a save's 30 days of versions and restores one after a backup |

## Data

- `SVErrors_v1`, key `live/<UTC day>` (Studio: `studio/<day>`): `{ total, dropped, v, updated, sigs = { [sig] = { n, side, sample, first, last, v0, v } } }`, at most 60 kinds.
- `SVFlags_v1`, key `live` / `studio`: `{ bobScenes = false, updated = <unix> }`. Missing or broken = every flag on.
- `SVRescue_v1`, key `<userId>/<unix time>`: the save as it was just before a restore.

## Wired into

- `SiliconCore.server.lua`: `Flags.init()` and `ErrorLog.init({ remote, telemetry })`, after Feedback.
- `BobSceneClient.client.lua`: `Flag_bobScenes == false` -> no scene, state "failed" (the intro falls back to the flyover; the payoff shows a toast).

## Tests

`tests/offline/errorbook.spec.luau`, `flags.spec.luau`, `saverescue.spec.luau`.

Live (Studio, 26 Oct): `bobScenes` off on the studio key -> intro and payoff both "failed" with no scene,
"Bob paid you $120K · SERIES A CLOSED · x3" toast (held behind the Daily menu, shown 0.2 s after it closed);
back on from the running server -> picked up in 5 s. A planted server error and a planted client error each
logged once under `studio/2026-10-26`. SaveRescue on Wilz: list, peek, wrong words refused, restore with a
backup written; Wilz restored from the snapshot after (0 differs). Not tried: a real live server, PlaceVersion > 0.

**Last verified:** 2026-10-26 (safety-net branch, before its first commit)
