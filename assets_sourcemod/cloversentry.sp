#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#define PLUGIN_VERSION "2.0"

int g_heavySentryModels[4];
int g_SentryModels[4];

public Plugin myinfo =
{
	name = "LucyCharm Gun",
	author = "iamashaymin",
	description = "LucyCharm Sentry Gun loader.",
	version = PLUGIN_VERSION,
	url = "http://www.google.com"
}

public void OnPluginStart()
{
	HookEvent("player_builtobject", Event_player_builtobject);
	HookEvent("player_upgradedobject", Event_player_upgradedobject);
}

public void OnMapStart()
{
	DownloadTable();
}

void DownloadTable()
{
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1_blue.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1_yellow.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3_green.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1_blue.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2_blue.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1_green.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2_blue.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2_yellow.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1_green.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2b.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2_yellow.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3_yellow.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2b.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3_blue.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3_yellow.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2_green.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3_blue.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1_yellow.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2_green.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3_green.vmt");

	g_heavySentryModels[1] = PrecacheModel("models/buildables/sentry_clover1.mdl");
	g_heavySentryModels[2] = PrecacheModel("models/buildables/sentry_clover2.mdl");
	g_heavySentryModels[3] = PrecacheModel("models/buildables/sentry_clover3.mdl");
	
	g_SentryModels[1] = PrecacheModel("models/buildables/sentry1.mdl")
	g_SentryModels[2] = PrecacheModel("models/buildables/sentry2.mdl")
	g_SentryModels[3] = PrecacheModel("models/buildables/sentry3.mdl")
}

public Action Event_player_builtobject(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int ent = GetEventInt(event, "index");
	int level = GetEntProp(ent, Prop_Send, "m_iUpgradeLevel");
	
	char className[64];
	GetEntityClassname(ent, className, sizeof(className));
	if (strcmp(className, "obj_sentrygun", true) == 0)
	{
		int wrench = GetPlayerWeaponSlot(client, 2);
		if (wrench > MaxClients && GetEntProp(wrench, Prop_Send, "m_iItemDefinitionIndex") == 9175) // Linked to Heavy Support
		{
			for (int i = 0; i < 4; i++)
			{
				SetEntProp(ent, Prop_Send, "m_nModelIndexOverrides", g_heavySentryModels[level], _, i);
			}
			SetEntProp(ent, Prop_Send, "m_iMaxHealth", 250)
			SetEntProp(ent, Prop_Send, "m_iHealth", 250)
		}
	}
	return Plugin_Continue;
}

public Action Event_player_upgradedobject(Event event, const char[] name, bool dontBroadcast)
{
	int ent = event.GetInt("index");
	int level = GetEntProp(ent, Prop_Send, "m_iUpgradeLevel");
	int g_health = (level * 200)
	int g_upgrade = (175 * level)
	
	char className[64];
	GetEntityClassname(ent, className, sizeof(className));
	if (strcmp(className, "obj_sentrygun", true) == 0)
	{
		int iBuilder = GetEntPropEnt(ent, Prop_Send, "m_hBuilder");
		int wrench = GetPlayerWeaponSlot(iBuilder, 2);
		if (wrench > MaxClients && GetEntProp(wrench, Prop_Send, "m_iItemDefinitionIndex") == 9175) // Linked to Heavy Support
		{
			for (int i = 0; i < 4; i++)
			{
				SetEntProp(ent, Prop_Send, "m_nModelIndexOverrides", g_heavySentryModels[level], _, i);
			}
			SetEntProp(ent, Prop_Send, "m_iMaxHealth", g_health)
			SetEntProp(ent, Prop_Send, "m_iHealth", g_health)
			SetEntProp(ent, Prop_Send, "m_iUpgradeMetalRequired", g_upgrade)
		
			if (level == 3)
			{
				SetEntProp(ent, Prop_Send, "m_iAmmoRockets", 12)
				SetEntProp(ent, Prop_Send, "m_iMaxAmmoRockets", 12)
			}
		}
		else
		{
			SetEntProp(ent, Prop_Send, "m_nModelIndexOverrides", 0);
		}
	}
	return Plugin_Continue;
}