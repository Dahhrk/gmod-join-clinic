local expected = {}

function JoinClinic.AddExpected(kind, id, label)
	if id == nil or id == "" then
		return
	end
	JoinClinic.AssertKind(kind)
	id = tostring(id)
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
	local i = 1
	while rows[i] do
		local row = rows[i]
		local kind = row.kind
		local id = row.id
		local label = row.label
		if kind == nil and row[1] ~= nil then
			kind = row[1]
			id = row[2]
			label = row[3]
		end
		JoinClinic.AddExpected(kind, id, label)
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
	JoinClinic.SendChunked(JoinClinic.NET_EXPECTED, { items = JoinClinic.ListExpected() }, ply)
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
	if IsValid(ply) and not ply:IsSuperAdmin() then
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

net.Receive(JoinClinic.NET_REQUEST, function(_, ply)
	if not IsValid(ply) then
		return
	end
	JoinClinic.SendExpected(ply)
end)
