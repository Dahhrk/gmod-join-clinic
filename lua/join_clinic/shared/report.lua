local KINDS = {
	workshop = true,
	fastdl = true,
	asset = true
}

local STATUSES = {
	ok = true,
	missing = true,
	not_downloaded = true,
	not_mounted = true,
	http_fail = true,
	error_texture = true
}

function JoinClinic.AssertKind(kind)
	if KINDS[kind] then
		return kind
	end
	error("JoinClinic: unknown kind " .. tostring(kind))
end

function JoinClinic.AssertStatus(status)
	if STATUSES[status] then
		return status
	end
	error("JoinClinic: unknown status " .. tostring(status))
end

function JoinClinic.ExpectedKey(kind, id)
	return JoinClinic.AssertKind(kind) .. "\0" .. tostring(id)
end

function JoinClinic.IsMaterialPath(id)
	local lower = string.lower(id)
	if string.sub(lower, -4) == ".vmt" then
		return true
	end
	if string.sub(lower, 1, 10) ~= "materials/" then
		return false
	end
	local ext = string.match(lower, "%.([a-z0-9]+)$")
	if ext == nil or ext == "vmt" then
		return true
	end
	return false
end

function JoinClinic.MaterialName(id)
	local name = id
	name = string.gsub(name, "^[Mm][Aa][Tt][Ee][Rr][Ii][Aa][Ll][Ss]/", "")
	name = string.gsub(name, "%.[Vv][Mm][Tt]$", "")
	return name
end

function JoinClinic.ParseExpectedItem(raw)
	if type(raw) ~= "table" then
		error("JoinClinic: ExpectedItem must be a table")
	end
	if raw.id == nil then
		error("JoinClinic: ExpectedItem.id required")
	end
	local item = {
		kind = JoinClinic.AssertKind(raw.kind),
		id = tostring(raw.id)
	}
	if raw.label ~= nil and raw.label ~= "" then
		item.label = tostring(raw.label)
	end
	return item
end

function JoinClinic.ParseItemResult(raw)
	if type(raw) ~= "table" then
		error("JoinClinic: ItemResult must be a table")
	end
	return {
		item = JoinClinic.ParseExpectedItem(raw.item),
		status = JoinClinic.AssertStatus(raw.status),
		detail = tostring(raw.detail or "")
	}
end

function JoinClinic.CountResults(results)
	local ok = 0
	local bad = 0
	local i = 1
	while results[i] do
		local status = JoinClinic.AssertStatus(results[i].status)
		if status == "ok" then
			ok = ok + 1
		else
			bad = bad + 1
		end
		i = i + 1
	end
	return { ok = ok, bad = bad }
end

function JoinClinic.ParseJoinReport(raw)
	if type(raw) ~= "table" then
		error("JoinClinic: JoinReport must be a table")
	end
	if raw.steamid64 == nil then
		error("JoinClinic: steamid64 required")
	end
	local src = raw.results
	if src == nil then
		src = {}
	end
	if type(src) ~= "table" then
		error("JoinClinic: results must be a table")
	end
	local results = {}
	local i = 1
	while src[i] ~= nil do
		if i > 8192 then
			error("JoinClinic: JoinReport.results exceeds 8192 rows")
		end
		results[i] = JoinClinic.ParseItemResult(src[i])
		i = i + 1
	end
	return {
		steamid64 = tostring(raw.steamid64),
		nick = tostring(raw.nick or ""),
		map = tostring(raw.map or ""),
		started = tonumber(raw.started) or 0,
		finished = tonumber(raw.finished) or 0,
		results = results,
		counts = JoinClinic.CountResults(results)
	}
end

function JoinClinic.MakeResult(item, status, detail)
	JoinClinic.AssertKind(item.kind)
	JoinClinic.AssertStatus(status)
	detail = detail or ""
	if item.label and item.label ~= "" then
		if detail ~= "" then
			detail = item.label .. "; " .. detail
		else
			detail = item.label
		end
	end
	return {
		item = item,
		status = status,
		detail = detail
	}
end

function JoinClinic.FormatReport(report)
	local counts = report.counts or { ok = 0, bad = 0 }
	local lines = {
		"Join Clinic",
		"map " .. tostring(report.map or ""),
		"player " .. tostring(report.nick or "") .. " (" .. tostring(report.steamid64 or "") .. ")",
		"ok " .. tostring(counts.ok) .. " / bad " .. tostring(counts.bad),
		""
	}
	local results = report.results or {}
	local i = 1
	while results[i] do
		local row = results[i]
		lines[#lines + 1] = row.item.kind .. " " .. row.item.id .. " " .. row.status .. " " .. (row.detail or "")
		i = i + 1
	end
	return table.concat(lines, "\n")
end
