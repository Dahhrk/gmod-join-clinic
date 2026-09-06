JoinClinic.CHUNK_SIZE = 60 * 1024
-- Seconds between outbound chunks so large transfers do not flood one tick.
JoinClinic.CHUNK_GAP = 0.05

local NET_EXPECTED = "joinclinic_expected"
local NET_REPORT = "joinclinic_report"
local NET_INSPECT = "joinclinic_inspect"
local NET_REQUEST = "joinclinic_request"

JoinClinic.NET_EXPECTED = NET_EXPECTED
JoinClinic.NET_REPORT = NET_REPORT
JoinClinic.NET_INSPECT = NET_INSPECT
JoinClinic.NET_REQUEST = NET_REQUEST

if SERVER then
	util.AddNetworkString(NET_EXPECTED)
	util.AddNetworkString(NET_REPORT)
	util.AddNetworkString(NET_INSPECT)
	util.AddNetworkString(NET_REQUEST)
end

local buffers = {}
local xferSeq = 0
local sendGens = {}
local MAX_DECOMPRESS = 8 * 1024 * 1024

local function peerKey(ply)
	if SERVER then
		if not IsValid(ply) then
			return "console"
		end
		return ply:SteamID64()
	end
	return "local"
end

local function dropStale(prefix, keep)
	local stale = {}
	for key in pairs(buffers) do
		if key ~= keep and string.sub(key, 1, #prefix) == prefix then
			stale[#stale + 1] = key
		end
	end
	local i = 1
	while stale[i] do
		buffers[stale[i]] = nil
		i = i + 1
	end
end

local function writeChunk(netName, xfer, idx, chunks, part, ply)
	net.Start(netName)
	net.WriteUInt(xfer, 32)
	net.WriteUInt(idx, 16)
	net.WriteUInt(chunks, 16)
	net.WriteUInt(#part, 16)
	-- LZMA bytes can contain NUL. WriteString would cut the chunk short.
	net.WriteData(part, #part)
	if SERVER then
		if not IsValid(ply) then
			return
		end
		net.Send(ply)
	else
		net.SendToServer()
	end
end

function JoinClinic.SendChunked(netName, tbl, ply)
	local json = util.TableToJSON(tbl)
	if not json then
		error("JoinClinic: TableToJSON failed")
	end
	local payload = util.Compress(json)
	if not payload or payload == "" then
		error("JoinClinic: Compress failed")
	end
	local size = JoinClinic.CHUNK_SIZE
	local chunks = math.ceil(#payload / size)
	if chunks < 1 then
		chunks = 1
	end
	local maxChunks = math.ceil(MAX_DECOMPRESS / size)
	if chunks > maxChunks then
		error("JoinClinic: payload exceeds decompress budget (" .. tostring(#payload) .. " bytes)")
	end
	xferSeq = xferSeq + 1
	local xfer = xferSeq
	local genKey = netName .. "\0" .. peerKey(ply)
	local gen = (sendGens[genKey] or 0) + 1
	sendGens[genKey] = gen
	local gap = tonumber(JoinClinic.CHUNK_GAP) or 0.05
	if gap < 0 then
		gap = 0
	end
	local i = 1
	while i <= chunks do
		local startAt = (i - 1) * size + 1
		local part = string.sub(payload, startAt, startAt + size - 1)
		local idx = i
		local delay = (i - 1) * gap
		local function fire()
			if sendGens[genKey] ~= gen then
				return
			end
			writeChunk(netName, xfer, idx, chunks, part, ply)
		end
		if delay <= 0 then
			fire()
		else
			timer.Simple(delay, fire)
		end
		i = i + 1
	end
end

function JoinClinic.RecvChunked(netName, callback)
	local maxChunks = math.ceil(MAX_DECOMPRESS / JoinClinic.CHUNK_SIZE)
	net.Receive(netName, function(_, ply)
		local xfer = net.ReadUInt(32)
		local idx = net.ReadUInt(16)
		local chunks = net.ReadUInt(16)
		local partLen = net.ReadUInt(16)
		local part = net.ReadData(partLen)
		if chunks < 1 or chunks > maxChunks then
			ErrorNoHalt("[JoinClinic] bad chunk count " .. tostring(chunks) .. "\n")
			return
		end
		if idx < 1 or idx > chunks then
			ErrorNoHalt("[JoinClinic] bad chunk index " .. tostring(idx) .. "/" .. tostring(chunks) .. "\n")
			return
		end
		if partLen ~= #part then
			ErrorNoHalt("[JoinClinic] chunk length mismatch\n")
			return
		end
		local prefix = netName .. "\0" .. peerKey(ply) .. "\0"
		local key = prefix .. tostring(xfer)
		local slot = buffers[key]
		if not slot then
			dropStale(prefix, key)
			slot = { n = 0, chunks = chunks, parts = {} }
			buffers[key] = slot
		elseif slot.chunks ~= chunks then
			ErrorNoHalt("[JoinClinic] chunk count changed mid-transfer\n")
			buffers[key] = nil
			return
		end
		if not slot.parts[idx] then
			slot.parts[idx] = part
			slot.n = slot.n + 1
		end
		if slot.n ~= slot.chunks then
			return
		end
		local pieces = {}
		local i = 1
		while i <= slot.chunks do
			if slot.parts[i] == nil then
				ErrorNoHalt("[JoinClinic] missing chunk " .. tostring(i) .. "\n")
				buffers[key] = nil
				return
			end
			pieces[i] = slot.parts[i]
			i = i + 1
		end
		buffers[key] = nil
		local json = util.Decompress(table.concat(pieces), MAX_DECOMPRESS)
		if not json or json == "" then
			ErrorNoHalt("[JoinClinic] Decompress failed\n")
			return
		end
		local tbl = util.JSONToTable(json)
		if not tbl then
			ErrorNoHalt("[JoinClinic] JSONToTable failed\n")
			return
		end
		local ok, err = pcall(callback, tbl, ply)
		if not ok then
			ErrorNoHalt("[JoinClinic] " .. tostring(err) .. "\n")
		end
	end)
end
