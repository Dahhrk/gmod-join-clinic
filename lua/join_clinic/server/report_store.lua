local last = {}

function JoinClinic.StoreReport(report)
	last[report.steamid64] = report
end

function JoinClinic.GetReport(steamid64)
	return last[steamid64]
end

function JoinClinic.NotifyStaff(report)
	if report.counts.bad < 1 then
		return
	end
	local cv = GetConVar("joinclinic_staff_notify")
	if not cv or cv:GetInt() ~= 1 then
		return
	end
	local line = "Join Clinic: " .. report.nick .. " (" .. report.steamid64 .. ") " .. tostring(report.counts.bad) .. " bad / " .. tostring(report.counts.ok) .. " ok on " .. report.map
	print(line)
	local players = player.GetAll()
	local i = 1
	while players[i] do
		local ply = players[i]
		if ply:IsSuperAdmin() then
			ply:PrintMessage(HUD_PRINTTALK, line)
		end
		i = i + 1
	end
end

local function resolveSid(arg)
	if not arg or arg == "" then
		return nil
	end
	arg = string.Trim(arg)
	if last[arg] then
		return arg
	end
	if string.sub(arg, 1, 6) == "STEAM_" then
		local sid = util.SteamIDTo64(arg)
		if sid and sid ~= "0" and sid ~= "" then
			return sid
		end
	end
	local by64 = player.GetBySteamID64(arg)
	if IsValid(by64) then
		return by64:SteamID64()
	end
	local bySteam = player.GetBySteamID(arg)
	if IsValid(bySteam) then
		return bySteam:SteamID64()
	end
	local lower = string.lower(arg)
	local players = player.GetAll()
	local i = 1
	while players[i] do
		local ply = players[i]
		if string.lower(ply:Nick()) == lower then
			return ply:SteamID64()
		end
		i = i + 1
	end
	i = 1
	while players[i] do
		local ply = players[i]
		if string.find(string.lower(ply:Nick()), lower, 1, true) then
			return ply:SteamID64()
		end
		i = i + 1
	end
	for sid, report in pairs(last) do
		if string.lower(report.nick) == lower then
			return sid
		end
	end
	for sid, report in pairs(last) do
		if string.find(string.lower(report.nick), lower, 1, true) then
			return sid
		end
	end
	return nil
end

local function canInspect(ply, target)
	if not IsValid(ply) then
		return true
	end
	if ply:IsSuperAdmin() then
		return true
	end
	return hook.Run("JoinClinic_CanInspect", ply, target) == true
end

JoinClinic.RecvChunked(JoinClinic.NET_REPORT, function(raw, ply)
	if not IsValid(ply) then
		return
	end
	local report = JoinClinic.ParseJoinReport(raw)
	report.steamid64 = ply:SteamID64()
	report.nick = ply:Nick()
	report.map = game.GetMap()
	report.counts = JoinClinic.CountResults(report.results)
	JoinClinic.StoreReport(report)
	JoinClinic.NotifyStaff(report)
end)

concommand.Add("joinclinic_inspect", function(ply, _, args)
	local arg = string.Trim(table.concat(args or {}, " "))
	if arg == "" then
		local usage = "Join Clinic: joinclinic_inspect <name|steamid>"
		print(usage)
		if IsValid(ply) then
			ply:PrintMessage(HUD_PRINTCONSOLE, usage)
		end
		return
	end
	local sid = resolveSid(arg)
	local targetPly = sid and player.GetBySteamID64(sid) or nil
	local target = IsValid(targetPly) and targetPly or (sid or arg)
	if not canInspect(ply, target) then
		if IsValid(ply) then
			ply:PrintMessage(HUD_PRINTCONSOLE, "Join Clinic: not allowed")
		end
		return
	end
	if not sid then
		local miss = "Join Clinic: no report for " .. arg
		print(miss)
		if IsValid(ply) then
			ply:PrintMessage(HUD_PRINTCONSOLE, miss)
		end
		return
	end
	local report = last[sid]
	if not report then
		local miss = "Join Clinic: no report for " .. sid
		print(miss)
		if IsValid(ply) then
			ply:PrintMessage(HUD_PRINTCONSOLE, miss)
		end
		return
	end
	if not IsValid(ply) then
		print(JoinClinic.FormatReport(report))
		return
	end
	JoinClinic.SendChunked(JoinClinic.NET_INSPECT, report, ply)
end)
