# Join Clinic

A Garry's Mod addon for **server owners** and **staff**. After a player connects, it says what failed to mount and names the Workshop ID or FastDL path.

It is not an admin mod, not an IDE, and not a content downloader. It tells the truth about the join.

## Who it is for

Players who spawn into purple and black after a long download.

Staff who currently answer that with "verify cache".

Owners who already called `resource.AddWorkshop` and still cannot see which ID the client missed.

## What you get

1. A player panel (`joinclinic`) listing each expected item and its status.
2. Auto-open when anything failed (`joinclinic_auto 1`).
3. Staff inspect: `joinclinic_inspect <name or steamid>`.
4. A copyable report for tickets.

Statuses:

| Status | Meaning |
|---|---|
| `ok` | Present and mounted |
| `not_downloaded` | Workshop ID in the expected list, GMA not on disk |
| `not_mounted` | Downloaded, not mounted |
| `missing` | `file.Exists` failed on the GAME path |
| `error_texture` | Material loaded as `___error` |
| `http_fail` | FastDL URL did not return 200 |

## Install

1. Clone or copy this folder into `garrysmod/addons/gmod-join-clinic`.
2. Restart the map (or the server).
3. Join. Run `joinclinic` if the panel did not open.

Workshop upload: pack with [gmpublisher](https://github.com/WilliamVenner/gmpublisher). `addon.json` already ignores docs and Cursor files. Do not put this README inside the GMA.

## Roleplay / community servers

Drop this addon on any server that already uses `resource.AddWorkshop` / FastDL. After a bad join, staff run `joinclinic_inspect <nick>` and paste the report into the support thread. The row names the Workshop ID or FastDL file.

Optional: list critical models in `lua/join_clinic/config/critical_assets.lua` (keep the git copy empty; fill on the server) so a missing playermodel is a named asset, not a lucky ERROR.

Server-specific ops notes stay in gitignored `local/` — do not commit collection IDs or staff SOPs.

## How it works

The server wraps `resource.AddWorkshop`, `resource.AddFile`, and `resource.AddSingleFile`. Whatever your collection Lua already calls becomes the expected list. The client diffs that list against `engine.GetAddons()` and disk.

See [docs/DESIGN.md](docs/DESIGN.md) for the `JoinReport` shape and why probe-only was rejected.

## Config

| ConVar | Default | Who |
|---|---|---|
| `joinclinic_auto` | `1` | Client. Open the panel when the report has failures. |
| `joinclinic_staff_notify` | `1` | Server. Print a one-line miss to SuperAdmins. |
| `joinclinic_http` | `1` | Client. Probe `sv_downloadurl` for FastDL items. |

`lua/join_clinic/config/critical_assets.lua` returns extra `asset` rows (playermodels, HUD materials). Workshop IDs do not belong there — those come from `resource.AddWorkshop`.

## Commands

| Command | Realm | Who |
|---|---|---|
| `joinclinic` | client | Anyone. Own report. |
| `joinclinic_copy` | client | Anyone. Copy last report text. |
| `joinclinic_inspect <ply>` | server | SuperAdmin. Their last report. |
| `joinclinic_expected` | server | SuperAdmin. Dump the expected registry. |

## Limits (engine, not us)

- One net message is 65,533 bytes. Large collections are compressed and chunked. We do not raise the cap.
- `resource.Add*` shares an 8192-file download list with the engine. If you are over that, the clinic will show the overflow as missing. Cut the collection.
- `file.Write` cannot fix `addons/`. This addon does not download content. It names the hole.
- FastDL HTTP probes fail if `sv_downloadurl` is empty, private, or blocks the client.
- `engine.GetAddons()` does not list folder addons. Folder content is checked only via `critical_assets.lua` paths.

## Repo layout

```
lua/autorun/00_join_clinic.lua         -- early boot (00_* before other autorun)
lua/join_clinic/
  shared/   report.lua, net.lua
  server/   expected_registry.lua, report_store.lua
  client/   mount_audit.lua, panel.lua
  config/   critical_assets.lua        -- empty {} in git
docs/DESIGN.md
addon.json
```

Player-facing commands stay `joinclinic_*`. Agent kit (`.cursor/`, `tools/`, …) is local-only / gitignored.

## Development

Requires a Garry's Mod client and a listen or dedicated server. There is no headless test for mount state.

1. Symlink or copy this folder into `garrysmod/addons/`.
2. `joinclinic_expected` after your workshop Lua runs. Confirm IDs you expect.
3. Unsubscribe one addon, rejoin, confirm `not_downloaded`.
4. Delete or rename one critical model path, confirm `missing` or `error_texture`.

## License

MIT. See [LICENSE](LICENSE).
