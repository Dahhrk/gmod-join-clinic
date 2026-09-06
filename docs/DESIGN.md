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

Expected list and reports go as compressed JSON, chunked at 60 KB. GMod's per-message cap is 65,533 bytes. Large collections are large enough to hit it.

## Surfaces

- Player: `joinclinic` or auto-open when `counts.bad > 0`
- Staff: `joinclinic_inspect <name|steamid>`
- Console: last report printed as copyable text

## Out of scope

Reloader, EPOE rewrite, entity budget, job editor, admin sit, debugger.
