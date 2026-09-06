JoinClinic = JoinClinic or {}

if SERVER then
	AddCSLuaFile("joinclinic/sh_types.lua")
	AddCSLuaFile("joinclinic/sh_net.lua")
	AddCSLuaFile("joinclinic/cl_audit.lua")
	AddCSLuaFile("joinclinic/cl_panel.lua")
	CreateConVar("joinclinic_staff_notify", "1", FCVAR_ARCHIVE, "Print a one-line miss to SuperAdmins")
end

if CLIENT then
	CreateClientConVar("joinclinic_auto", "1", true, false, "Open Join Clinic when the report has failures")
	CreateClientConVar("joinclinic_http", "1", true, false, "Probe FastDL via sv_downloadurl")
end

include("joinclinic/sh_types.lua")
include("joinclinic/sh_net.lua")

if SERVER then
	include("joinclinic/sv_expected.lua")
	include("joinclinic/sv_report.lua")
	JoinClinic.IngestCritical(include("joinclinic/critical.lua"))
end

if CLIENT then
	include("joinclinic/cl_audit.lua")
	include("joinclinic/cl_panel.lua")
end
