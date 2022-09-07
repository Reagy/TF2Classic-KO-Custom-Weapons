#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#define PLUGIN_VERSION "2.0"

int g_minidispenser;
int g_blueprints;

public Plugin myinfo =
{
	name = "Mini-Dispenser",
	author = "iamashaymin",
	description = "Mini-Dispenser loader.",
	version = PLUGIN_VERSION,
	url = "http://www.google.com"
}

public void OnPluginStart()
{
	HookEvent("player_builtobject", Event_player_builtobject);
//	HookEvent("player_carryobject", Event_player_carryobject);
	HookEvent("player_upgradedobject", Event_player_upgradedobject);
	HookEvent("player_dropobject", Event_player_dropobject);
}

public void OnMapStart()
{
	DownloadTable();
	
	PrecacheModel("models/buildables/gibs/minidisps_gib1.mdl");
	PrecacheModel("models/buildables/gibs/minidisps_gib2.mdl");
	PrecacheModel("models/buildables/gibs/minidisps_gib3.mdl");
	PrecacheModel("models/buildables/gibs/minidisps_gib4.mdl");
	PrecacheModel("models/buildables/gibs/minidisps_gib5.mdl");
}

void DownloadTable()
{
	AddFileToDownloadsTable("materials/models/workshop/buildables/mini_dispenser/mini_dispenser.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/mini_dispenser/mini_dispenser.vtf");
	
	AddFileToDownloadsTable("materials/models/workshop/buildables/mini_dispenser/mini_dispenser_blue.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/mini_dispenser/mini_dispenser_blue.vtf");
	
	AddFileToDownloadsTable("materials/models/workshop/buildables/mini_dispenser/mini_dispenser_green.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/mini_dispenser/mini_dispenser_green.vtf");
	
	AddFileToDownloadsTable("materials/models/workshop/buildables/mini_dispenser/mini_dispenser_yellow.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/mini_dispenser/mini_dispenser_yellow.vtf");
	
	AddFileToDownloadsTable("materials/models/workshop/buildables/mini_dispenser/minidisp_blueprint_build.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/mini_dispenser/minidisp_blueprint_build.vtf");
	
	AddFileToDownloadsTable("materials/models/workshop/buildables/mini_dispenser/minidisp_blueprint_model.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/mini_dispenser/minidisp_blueprint_model.vtf");
	
	AddFileToDownloadsTable("materials/models/workshop/buildables/mini_dispenser/mini_dispenser_exponent.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/mini_dispenser/mini_dispenser_phongmask.vtf");
	
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry1/mini_sentry_light_blue.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry1/mini_sentry_light_blue.vtf");
	
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry1/mini_sentry_light_red.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry1/mini_sentry_light_red.vtf");
	
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry1/mini_sentry_light_green.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry1/mini_sentry_light_green.vtf");
	
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry1/mini_sentry_light_yellow.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry1/mini_sentry_light_yellow.vtf");
	
	AddFileToDownloadsTable("models/buildables/minidispenser.mdl");
	AddFileToDownloadsTable("models/buildables/minidispenser.phy");
	AddFileToDownloadsTable("models/buildables/minidispenser_blueprint.mdl");
	AddFileToDownloadsTable("models/buildables/gibs/minidisps_gib1.mdl");
	AddFileToDownloadsTable("models/buildables/gibs/minidisps_gib2.mdl");
	AddFileToDownloadsTable("models/buildables/gibs/minidisps_gib3.mdl");
	AddFileToDownloadsTable("models/buildables/gibs/minidisps_gib4.mdl");
	AddFileToDownloadsTable("models/buildables/gibs/minidisps_gib5.mdl");

	g_minidispenser = PrecacheModel("models/buildables/minidispenser.mdl");
	g_blueprints = PrecacheModel("models/buildables/minidispenser_blueprint.mdl");
}

public Action Event_player_builtobject(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int ent = GetEventInt(event, "index");
	
	char className[64];
	GetEntityClassname(ent, className, sizeof(className));
	if (strcmp(className, "obj_dispenser", true) == 0)
	{
		int pda = GetPlayerWeaponSlot(client, 3);
		if (pda > MaxClients && GetEntProp(pda, Prop_Send, "m_iItemDefinitionIndex") == 3456)
		{
			for (int i = 0; i < 4; i++)
			{
				if (GetEntProp(ent, Prop_Send, "m_nModelIndexOverrides") == g_blueprints)
				{
					SetEntProp(ent, Prop_Send, "m_nModelIndexOverrides", g_minidispenser, _, i);
					SetEntProp(ent, Prop_Send, "m_iUpgradeLevel", 3);
				}
				SetEntProp(ent, Prop_Send, "m_nModelIndexOverrides", g_minidispenser, _, i);
				SetEntProp(ent, Prop_Send, "m_iUpgradeLevel", 3);
			}
		}
	}
	return Plugin_Continue;
}

/*public Action Event_player_carryobject(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int ent = GetEventInt(event, "index");
	
	char className[64];
	GetEntityClassname(ent, className, sizeof(className));
	if (strcmp(className, "obj_dispenser", true) == 0)
	{
		int pda = GetPlayerWeaponSlot(client, 3);
		if (pda > MaxClients && GetEntProp(pda, Prop_Send, "m_iItemDefinitionIndex") == 3456)
		{
			for (int i = 0; i < 4; i++)
			{
				SetEntProp(ent, Prop_Send, "m_nModelIndexOverrides", g_blueprints, _, i);
			}
		}
	}
	return Plugin_Continue;
}*/

public Action Event_player_dropobject(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int ent = GetEventInt(event, "index");
	
	char className[64];
	GetEntityClassname(ent, className, sizeof(className));
	if (strcmp(className, "obj_dispenser", true) == 0)
	{
		int pda = GetPlayerWeaponSlot(client, 3);
		if (pda > MaxClients && GetEntProp(pda, Prop_Send, "m_iItemDefinitionIndex") == 3456)
		{
			for (int i = 0; i < 4; i++)
			{
				SetEntProp(ent, Prop_Send, "m_nModelIndexOverrides", g_minidispenser, _, i);
				SetEntProp(ent, Prop_Send, "m_iUpgradeLevel", 3);
			}
		}
	}
	return Plugin_Continue;
}

public Action Event_player_upgradedobject(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int ent = GetEventInt(event, "index");
	
	char className[64];
	GetEntityClassname(ent, className, sizeof(className));
	if (strcmp(className, "obj_dispenser", true) == 0)
	{
		int pda = GetPlayerWeaponSlot(client, 3);
		if (pda > MaxClients && GetEntProp(pda, Prop_Send, "m_iItemDefinitionIndex") == 3456)
		{
			for (int i = 0; i < 4; i++)
			{
				SetEntProp(ent, Prop_Send, "m_nModelIndexOverrides", g_minidispenser, _, i);
				SetEntProp(ent, Prop_Send, "m_iUpgradeLevel", 3);
			}
		}
	}
	return Plugin_Continue;
}