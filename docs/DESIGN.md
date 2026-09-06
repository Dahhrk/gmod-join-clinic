# Join Clinic design

## Caller

A player finishes connecting to a Workshop-heavy roleplay server. They need one sentence: what failed, and the Workshop ID or FastDL path. Staff need the same row without a verify-cache thread.

## Domain

One report per join. Not a live stream. Not a profiler.

```
ExpectedItem
  kind: "workshop" | "fastdl" | "asset"
  id: string          -- wsid or GAME-relative path
  label: string|nil

ItemResult
  item: ExpectedItem
  status: "ok" | "missing" | "not_downloaded" | "not_mounted" | "http_fail" | "error_texture"
  detail: string

JoinReport
  steamid64: string
  nick: string
  map: string
  started: number     -- os.time
  finished: number
  results: ItemResult[]
  counts: { ok: number, bad: number }
```

`JoinReport` is the only persisted shape. Server keeps the last report per SteamID64. Older joins are discarded.

## Shapes compared

**Manifest-diff (chosen).** Server wraps `resource.AddWorkshop` / `resource.AddFile` / `resource.AddSingleFile` and owns an expected registry. Client diffs `engine.GetAddons()`, `file.Exists(..., "GAME")`, and `Material():IsError()`. Staff see a Workshop ID.

**Probe-only (rejected).** Client hunts ERROR models after spawn. No ID. Useless for support tickets.

## Net

Expected list and reports go as compressed JSON, chunked at 60 KB. Chunks are spaced by `JoinClinic.CHUNK_GAP` (default 0.05s) so large collections do not flood one tick. A newer send on the same channel cancels in-flight staggered chunks. GMod's per-message cap is 65,533 bytes. Registry and report rows hard-cap at 8192. Oversized **reports** error on parse. Oversized **expected** sends drop from the front of the sorted list (asset/fastdl first) so Workshop IDs are kept.

## Surfaces

- Player: `joinclinic` or auto-open when `counts.bad > 0`
- Staff: `joinclinic_inspect <name|steamid>` (SuperAdmin, CAMI `JoinClinic_Inspect`, or `JoinClinic_CanInspect` hook)
- Notify: chat line when `counts.bad > 0` (SuperAdmin, CAMI `JoinClinic_Notify`, or `JoinClinic_CanNotifyStaff` hook)
- Console: last report printed as copyable text

Owner ops: [OPS.md](OPS.md).

## Layout

```
lua/autorun/aaa_join_clinic.lua        -- early boot across addons (aaa_*); AddCSLuaFile + includes only
lua/join_clinic/
  shared/report.lua                    -- JoinReport shape + helpers
  shared/net.lua                       -- chunked JSON net
  server/expected_registry.lua         -- wraps resource.Add*
  server/report_store.lua              -- last report per SteamID64
  client/mount_audit.lua               -- engine.GetAddons / file / Material
  client/panel.lua                     -- player + staff UI
  config/critical_assets.lua           -- empty {} in git; ops fill locally
```

Commands stay `joinclinic_*`. Global table stays `JoinClinic`.

## Out of scope

Reloader, EPOE rewrite, entity budget, job editor, admin sit, debugger.
