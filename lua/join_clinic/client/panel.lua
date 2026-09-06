local STATUS_COLOR = {
	ok = Color(140, 200, 140),
	missing = Color(220, 120, 120),
	not_downloaded = Color(220, 120, 120),
	not_mounted = Color(220, 170, 100),
	http_fail = Color(220, 120, 120),
	error_texture = Color(220, 120, 120)
}

function JoinClinic.OpenPanel(report)
	if not report then
		return
	end
	if IsValid(JoinClinic.Frame) then
		JoinClinic.Frame:Remove()
	end

	local counts = report.counts or { ok = 0, bad = 0 }
	local results = report.results or {}

	local frame = vgui.Create("DFrame")
	JoinClinic.Frame = frame
	frame:SetTitle("Join Clinic")
	frame:SetSize(780, 500)
	frame:Center()
	frame:MakePopup()

	local sub = vgui.Create("DLabel", frame)
	sub:Dock(TOP)
	sub:SetTall(40)
	sub:DockMargin(8, 4, 8, 4)
	sub:SetWrap(true)
	sub:SetTextColor(Color(220, 220, 220))
	if #results == 0 then
		sub:SetText("Expected registry is empty. Join Clinic wrapped resource.Add* too late, or nothing was added.")
	else
		sub:SetText("map " .. tostring(report.map or "") .. "   player " .. tostring(report.nick or "") .. " (" .. tostring(report.steamid64 or "") .. ")   ok " .. tostring(counts.ok) .. " / bad " .. tostring(counts.bad))
	end

	local btn = vgui.Create("DButton", frame)
	btn:Dock(BOTTOM)
	btn:SetTall(28)
	btn:DockMargin(8, 4, 8, 8)
	btn:SetText("Copy")
	btn.DoClick = function()
		SetClipboardText(JoinClinic.FormatReport(report))
	end

	local list = vgui.Create("DListView", frame)
	list:Dock(FILL)
	list:DockMargin(8, 0, 8, 0)
	list:SetMultiSelect(false)
	list:AddColumn("Kind")
	list:AddColumn("ID")
	list:AddColumn("Status")
	list:AddColumn("Detail")

	local i = 1
	while results[i] do
		local row = results[i]
		local line = list:AddLine(row.item.kind, row.item.id, row.status, row.detail)
		local col = STATUS_COLOR[row.status]
		if col then
			line:SetTextColor(col)
		end
		i = i + 1
	end
end

JoinClinic.RecvChunked(JoinClinic.NET_INSPECT, function(raw)
	if not JoinClinic.ClientReady then
		return
	end
	JoinClinic.OpenPanel(JoinClinic.ParseJoinReport(raw))
end)

concommand.Add("joinclinic", function()
	if not JoinClinic.LastReport then
		print("Join Clinic: no report yet")
		return
	end
	JoinClinic.OpenPanel(JoinClinic.LastReport)
end)

concommand.Add("joinclinic_copy", function()
	if not JoinClinic.LastReport then
		print("Join Clinic: no report yet")
		return
	end
	SetClipboardText(JoinClinic.FormatReport(JoinClinic.LastReport))
	print("Join Clinic: copied")
end)
