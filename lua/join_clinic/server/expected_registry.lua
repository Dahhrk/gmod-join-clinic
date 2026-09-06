local expected = {}

function JoinClinic.AddExpected(kind, id, label)
	if id == nil or id == "" then
		return
	end
	JoinClinic.AssertKind(kind)
	id = tostring(id)
	if kind == "fastdl" or kind == "asset" then
		id = string.gsub(id, "\\", "/")
	end
	local key = JoinClinic.ExpectedKey(kind, id)
	local existing = expected[key]
	if existing then
		if label and label ~= "" and not existing.label then
			existing.label = tostring(label)
		end
		return
	end
	local item = { kind = kind, id = id }
	if label ~= nil and label ~= "" then
		item.label = tostring(label)
	end
	expected[key] = item
end

function JoinClinic.IngestCritical(rows)
	if type(rows) ~= "table" then
		return
	end
	-- Single-row map form: { kind = "...", id = "..." }
	if rows.kind ~= nil or rows.id ~= nil then
		local ok, err = pcall(JoinClinic.AddExpected, rows.kind, rows.id, rows.label)
		if not ok then
			ErrorNoHalt("[JoinClinic] critical_assets: " .. tostring(err) .. "\n")
		end
		return
	end
	if rows[1] == nil and next(rows) ~= nil then
		ErrorNoHalt("[JoinClinic] critical_assets must be an array of rows, not a string-keyed map\n")
		return
	end
	local i = 1
	while rows[i] do
		local row = rows[i]
		if type(row) ~= "table" then
			ErrorNoHalt("[JoinClinic] critical_assets row " .. tostring(i) .. ": expected table\n")
		else
			local kind = row.kind
			local id = row.id
			local label = row.label
			if kind == nil and row[1] ~= nil then
				kind = row[1]
				id = row[2]
				label = row[3]
			end
			local ok, err = pcall(JoinClinic.AddExpected, kind, id, label)
			if not ok then
				ErrorNoHalt("[JoinClinic] critical_assets row " .. tostring(i) .. ": " .. tostring(err) .. "\n")
			end
		end
		i = i + 1
	end
end

function JoinClinic.ListExpected()
	local list = {}
	for _, item in pairs(expected) do
		list[#list + 1] = item
	end
	table.sort(list, function(a, b)
		if a.kind == b.kind then
			return a.id < b.id
		end
		return a.kind < b.kind
	end)
	return list
end

function JoinClinic.SendExpected(ply)
	local list = JoinClinic.ListExpected()
	if #list > 8192 then
		-- List is sorted asset < fastdl < workshop. Keep the last 8192 (workshop-heavy).
		ErrorNoHalt("[JoinClinic] expected registry has " .. tostring(#list) .. " rows; keeping last 8192 (workshop-heavy)\n")
		local keep = {}
		local startAt = #list - 8192 + 1
		local j = 1
		while startAt <= #list do
			keep[j] = list[startAt]
			j = j + 1
			startAt = startAt + 1
		end
		list = keep
	end
	JoinClinic.SendChunked(JoinClinic.NET_EXPECTED, { items = list }, ply)
end

local addWorkshop = resource.AddWorkshop
function resource.AddWorkshop(wsid)
	JoinClinic.AddExpected("workshop", wsid)
	return addWorkshop(wsid)
end

local addFile = resource.AddFile
function resource.AddFile(path)
	JoinClinic.AddExpected("fastdl", path)
	return addFile(path)
end

local addSingleFile = resource.AddSingleFile
function resource.AddSingleFile(path)
	JoinClinic.AddExpected("fastdl", path)
	return addSingleFile(path)
end

local function dumpLine(ply, line)
	print(line)
	if IsValid(ply) then
		ply:PrintMessage(HUD_PRINTCONSOLE, line)
	end
end

concommand.Add("joinclinic_expected", function(ply)
	if IsValid(ply) and not JoinClinic.CanInspect(ply, ply) then
		return
	end
	local list = JoinClinic.ListExpected()
	dumpLine(ply, "Join Clinic expected " .. tostring(#list))
	local i = 1
	while list[i] do
		local item = list[i]
		dumpLine(ply, item.kind .. "\t" .. item.id .. "\t" .. (item.label or ""))
		i = i + 1
	end
end)

local lastRequestAt = {}
local REQUEST_COOLDOWN = 2

hook.Add("PlayerDisconnected", "JoinClinicRequestCooldown", function(ply)
	if not IsValid(ply) then
		return
	end
	lastRequestAt[ply:SteamID64()] = nil
end)

net.Receive(JoinClinic.NET_REQUEST, function(_, ply)
	if not IsValid(ply) then
		return
	end
	local sid = ply:SteamID64()
	local now = CurTime()
	if now - (lastRequestAt[sid] or 0) < REQUEST_COOLDOWN then
		return
	end
	lastRequestAt[sid] = now
	JoinClinic.SendExpected(ply)
end)
