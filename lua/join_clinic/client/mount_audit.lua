JoinClinic.ClientReady = false
JoinClinic.Started = 0

local HTTP_MAX = 8
local HTTP_WAIT = 20

local function shouldHttp()
	local cv = GetConVar("joinclinic_http")
	if not cv or cv:GetInt() ~= 1 then
		return false
	end
	local urlCv = GetConVar("sv_downloadurl")
	if not urlCv then
		return false
	end
	local base = urlCv:GetString()
	if not base or base == "" then
		return false
	end
	return true, base
end

local function fastdlUrl(base, path)
	base = string.gsub(base, "/+$", "")
	path = string.gsub(tostring(path), "^/+", "")
	path = string.gsub(path, "\\", "/")
	path = string.gsub(path, " ", "%%20")
	return base .. "/" .. path
end

local function gamePath(id)
	return string.gsub(tostring(id), "\\", "/")
end

local function buildAddonIndex()
	local byWsid = {}
	local addons = engine.GetAddons()
	local i = 1
	while addons[i] do
		local addon = addons[i]
		byWsid[tostring(addon.wsid)] = addon
		i = i + 1
	end
	return byWsid
end

local function auditWorkshop(item, byWsid)
	local addon = byWsid[tostring(item.id)]
	if not addon then
		return JoinClinic.MakeResult(item, "not_downloaded", "not in engine.GetAddons()")
	end
	-- Require an explicit downloaded flag. nil is not success.
	if addon.downloaded ~= true and addon.downloaded ~= 1 then
		return JoinClinic.MakeResult(item, "not_downloaded", "downloaded=" .. tostring(addon.downloaded))
	end
	-- mounted nil stays ok (GMod sometimes omits the field when mounted).
	if addon.mounted == false or addon.mounted == 0 then
		return JoinClinic.MakeResult(item, "not_mounted", "downloaded, not mounted")
	end
	return JoinClinic.MakeResult(item, "ok", addon.title or "")
end

local function auditAsset(item)
	local path = gamePath(item.id)
	if not file.Exists(path, "GAME") then
		return JoinClinic.MakeResult(item, "missing", "GAME")
	end
	if JoinClinic.IsMaterialPath(path) then
		local mat = Material(JoinClinic.MaterialName(path))
		if not mat or mat:IsError() then
			return JoinClinic.MakeResult(item, "error_texture", "Material:IsError")
		end
		return JoinClinic.MakeResult(item, "ok", "material")
	end
	return JoinClinic.MakeResult(item, "ok", "GAME")
end

function JoinClinic.SendOwnReport(results)
	local ply = LocalPlayer()
	if not IsValid(ply) then
		ErrorNoHalt("[JoinClinic] SendOwnReport without LocalPlayer\n")
		return
	end
	local report = {
		steamid64 = ply:SteamID64(),
		nick = ply:Nick(),
		map = game.GetMap(),
		started = JoinClinic.Started,
		finished = os.time(),
		results = results,
		counts = JoinClinic.CountResults(results)
	}
	JoinClinic.LastReport = report
	print(JoinClinic.FormatReport(report))
	if #results == 0 then
		print("Join Clinic: expected registry is empty. Wrappers may have loaded after resource.Add*.")
	end
	JoinClinic.SendChunked(JoinClinic.NET_REPORT, report)
	local auto = GetConVar("joinclinic_auto")
	if report.counts.bad > 0 and auto and auto:GetInt() == 1 then
		JoinClinic.OpenPanel(report)
	end
end

local function runAudit(items)
	local n = #items
	local results = {}
	local pending = 1
	local sent = false
	local httpQueue = {}
	local httpInflight = 0
	local byWsid = buildAddonIndex()

	local function trySend()
		pending = pending - 1
		if pending > 0 or sent then
			return
		end
		sent = true
		JoinClinic.SendOwnReport(results)
	end

	local function httpPump()
		while httpInflight < HTTP_MAX and httpQueue[1] do
			local job = table.remove(httpQueue, 1)
			httpInflight = httpInflight + 1
			job(function()
				httpInflight = httpInflight - 1
				httpPump()
			end)
		end
	end

	-- Only used when the file is missing locally. Never download a body we already have.
	local function probeFastdl(index, item, base)
		httpQueue[#httpQueue + 1] = function(done)
			local left = 2
			local finished = false
			local saw200 = false
			local notes = {}

			local function finish(status, detail)
				if finished then
					return
				end
				finished = true
				results[index] = JoinClinic.MakeResult(item, status, detail)
				done()
				trySend()
			end

			local function one(label, code)
				if finished then
					return
				end
				notes[#notes + 1] = label .. "=" .. tostring(code)
				if tonumber(code) == 200 then
					saw200 = true
				end
				left = left - 1
				if left > 0 then
					return
				end
				local detail = "GAME missing; HTTP " .. table.concat(notes, " ")
				if saw200 then
					finish("missing", detail)
					return
				end
				finish("http_fail", detail)
			end

			local url = fastdlUrl(base, gamePath(item.id))
			local function fetch(u, label)
				local ok = pcall(function()
					http.Fetch(u, function(_, _, _, code)
						one(label, code)
					end, function(err)
						one(label, err or "fail")
					end)
				end)
				if not ok then
					one(label, "error")
				end
			end
			fetch(url, "file")
			fetch(url .. ".bz2", "bz2")

			timer.Simple(HTTP_WAIT, function()
				if finished then
					return
				end
				local detail = "GAME missing; HTTP " .. table.concat(notes, " ") .. " timeout"
				if saw200 then
					finish("missing", detail)
					return
				end
				finish("http_fail", detail)
			end)
		end
		httpPump()
	end

	local i = 1
	while i <= n do
		local index = i
		local ok, err = pcall(function()
			local item = JoinClinic.ParseExpectedItem(items[index])
			local kind = item.kind
			if kind == "workshop" then
				results[index] = auditWorkshop(item, byWsid)
			elseif kind == "fastdl" then
				local path = gamePath(item.id)
				local exists = file.Exists(path, "GAME")
				if exists then
					results[index] = JoinClinic.MakeResult(item, "ok", "GAME")
				else
					local probe, base = shouldHttp()
					if probe then
						pending = pending + 1
						probeFastdl(index, item, base)
					else
						results[index] = JoinClinic.MakeResult(item, "missing", "GAME")
					end
				end
			elseif kind == "asset" then
				results[index] = auditAsset(item)
			else
				error("JoinClinic: unknown kind " .. tostring(kind))
			end
		end)
		if not ok then
			ErrorNoHalt("[JoinClinic] audit row " .. tostring(index) .. ": " .. tostring(err) .. "\n")
			results[index] = JoinClinic.MakeResult({
				kind = "asset",
				id = "invalid_row_" .. tostring(index)
			}, "missing", tostring(err))
		end
		i = i + 1
	end

	trySend()
end

local function requestExpected()
	net.Start(JoinClinic.NET_REQUEST)
	net.SendToServer()
end

JoinClinic.RecvChunked(JoinClinic.NET_EXPECTED, function(raw)
	if not JoinClinic.ClientReady then
		return
	end
	local items = {}
	if type(raw) == "table" and type(raw.items) == "table" then
		local i = 1
		while raw.items[i] ~= nil do
			if i > 8192 then
				ErrorNoHalt("[JoinClinic] expected list exceeds 8192; truncating audit\n")
				break
			end
			items[i] = raw.items[i]
			i = i + 1
		end
	end
	runAudit(items)
end)

hook.Add("InitPostEntity", "JoinClinic", function()
	if JoinClinic.ClientReady then
		return
	end
	JoinClinic.ClientReady = true
	JoinClinic.Started = os.time()
	requestExpected()
	timer.Simple(5, function()
		if not JoinClinic.LastReport then
			requestExpected()
		end
	end)
	timer.Simple(12, function()
		if not JoinClinic.LastReport then
			requestExpected()
		end
	end)
end)
