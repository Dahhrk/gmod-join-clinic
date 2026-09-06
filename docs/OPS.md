# Ops — Join Clinic for server owners

For DarkRP / community networks (Icefuse-style hosted dedicated, Workshop-heavy collections, FastDL). This addon does not replace your admin mod or content pipeline. It names the Workshop ID or path that failed after join.

## Install (dedicated)

1. Put the addon folder in `garrysmod/addons/gmod-join-clinic` (or Workshop-subscribe it once published).
2. Keep `lua/autorun/aaa_join_clinic.lua` — the `aaa_` prefix must load **before** other addons call `resource.AddWorkshop`.
3. Restart the map (or the server process).
4. As SuperAdmin (or CAMI-allowed staff): `joinclinic_expected` — confirm your collection IDs appear.
5. Join as a client. Unsubscribe one Workshop addon, rejoin, confirm `not_downloaded`.

Hosted panels (Icefuse, Pingperfect, etc.): upload the addon via FTP/SFTP into `garrysmod/addons/`, or use their “addons” upload. Do not strip `aaa_` from the autorun filename.

## Collection / load order

Join Clinic **wraps** `resource.AddWorkshop` / `AddFile` / `AddSingleFile` when it loads. Anything that ran those calls earlier is invisible to the registry.

- Prefer one early collection Lua that only calls `resource.Add*`.
- If another addon boots before `aaa_join_clinic.lua`, rename *that* addon’s autorun later, or call `JoinClinic.AddExpected("workshop", wsid)` yourself after the fact.
- Folder-only content (not in `engine.GetAddons()`) goes in `lua/join_clinic/config/critical_assets.lua` on the **server copy** (keep git empty):

```lua
return {
  { kind = "asset", id = "models/player/group01/male_01.mdl", label = "citizen male 01" },
  { kind = "workshop", id = "123456789", label = "optional named pack" },
  { kind = "fastdl", id = "materials/myui/logo.vmt" },
}
```

## Staff access (ULX / SAM / CAMI)

Defaults: SuperAdmin only for notify + inspect.

**Hooks** (any admin stack):

```lua
-- lua/autorun/server/joinclinic_staff.lua (your network addon)
hook.Add("JoinClinic_CanNotifyStaff", "MyNetwork", function(ply)
  return ply:IsUserGroup("admin") or ply:IsUserGroup("moderator")
end)

hook.Add("JoinClinic_CanInspect", "MyNetwork", function(ply, target)
  return ply:IsAdmin()
end)
```

**CAMI** (SAM, etc.): privileges `JoinClinic_Notify` and `JoinClinic_Inspect` register at boot (`MinAccess = superadmin`). Grant them in your CAMI UI to moderator groups.

ConVar: `joinclinic_staff_notify 0` disables chat spam; inspect still works.

## Ticket workflow

1. Player joins with missing content → panel auto-opens (`joinclinic_auto 1`) or they run `joinclinic`.
2. Staff: `joinclinic_inspect <nick>` → Copy → paste into Discord/ticket with the Workshop ID.
3. Do not tell them “verify cache” until the report says `ok`.

## FastDL

`joinclinic_http 1` (client) probes `sv_downloadurl` **only** when the file is missing on disk. It is not a downloader for files you already have.

## Limits owners hit

- Engine download list ~8192 files — cut the collection; Join Clinic will warn/truncate expected sends.
- Empty registry → wrappers loaded too late. Fix load order, not the panel.
- Last report is per map session (memory). Map change clears it.

## What not to ask this addon to do

No ULX menu, no auto-Workshop subscribe, no sit tool, no profiler. Name the hole; your existing tools fix it.
