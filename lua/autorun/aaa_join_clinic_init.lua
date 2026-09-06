JoinClinic = JoinClinic or {}

if SERVER then
	AddCSLuaFile("join_clinic/shared/report.lua")
	AddCSLuaFile("join_clinic/shared/net.lua")
	AddCSLuaFile("join_clinic/client/mount_audit.lua")
	AddCSLuaFile("join_clinic/client/panel.lua")
	CreateConVar("joinclinic_staff_notify", "1", FCVAR_ARCHIVE, "Print a one-line miss to SuperAdmins")
end

if CLIENT then
	CreateClientConVar("joinclinic_auto", "1", true, false, "Open Join Clinic when the report has failures")
	CreateClientConVar("joinclinic_http", "1", true, false, "Probe FastDL via sv_downloadurl")
end

include("join_clinic/shared/report.lua")
include("join_clinic/shared/net.lua")

if SERVER then
	include("join_clinic/server/expected_registry.lua")
	include("join_clinic/server/report_store.lua")
	JoinClinic.IngestCritical(include("join_clinic/config/critical_assets.lua"))
end

if CLIENT then
	include("join_clinic/client/mount_audit.lua")
	include("join_clinic/client/panel.lua")
end
