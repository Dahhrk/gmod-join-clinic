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

local function findAddon(wsid)
	wsid = tostring(wsid)
	local addons = engine.GetAddons()
	local i = 1
	while addons[i] do
		if tostring(addons[i].wsid) == wsid then
			return addons[i]
		end
		i = i + 1
	end
	return nil
end

local function auditWorkshop(item)
	local addon = findAddon(item.id)
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
	if not file.Exists(item.id, "GAME") then
		return JoinClinic.MakeResult(item, "missing", "GAME")
	end
	if JoinClinic.IsMaterialPath(item.id) then
		local mat = Material(JoinClinic.MaterialName(item.id))
		if not mat or mat:IsError() then
			return JoinClinic.MakeResult(item, "error_texture", "Material:IsError")
		end
		return JoinClinic.MakeResult(item, "ok", "material")
	end
	return JoinClinic.MakeResult(item, "ok", "GAME")
end

function JoinClinic.SendOwnReport(results)
	local ply = LocalPlayer()
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

	local function probeFastdl(index, item, exists, base)
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
				local detail = "GAME " .. (exists and "exists" or "missing") .. "; HTTP " .. table.concat(notes, " ")
				if not saw200 then
					finish("http_fail", detail)
					return
				end
				if exists then
					finish("ok", detail)
					return
				end
				finish("missing", detail)
			end

			local url = fastdlUrl(base, item.id)
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

			-- http.Fetch can stall without calling success or failure.
			timer.Simple(HTTP_WAIT, function()
				if finished then
					return
				end
				local detail = "GAME " .. (exists and "exists" or "missing") .. "; HTTP " .. table.concat(notes, " ") .. " timeout"
				if saw200 then
					if exists then
						finish("ok", detail)
						return
					end
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
		local item = JoinClinic.ParseExpectedItem(items[i])
		local kind = item.kind
		if kind == "workshop" then
			results[i] = auditWorkshop(item)
		elseif kind == "fastdl" then
			local exists = file.Exists(item.id, "GAME")
			local probe, base = shouldHttp()
			if probe then
				pending = pending + 1
				probeFastdl(i, item, exists, base)
			elseif exists then
				results[i] = JoinClinic.MakeResult(item, "ok", "GAME")
			else
				results[i] = JoinClinic.MakeResult(item, "missing", "GAME")
			end
		elseif kind == "asset" then
			results[i] = auditAsset(item)
		else
			error("JoinClinic: unknown kind " .. tostring(kind))
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
end)
