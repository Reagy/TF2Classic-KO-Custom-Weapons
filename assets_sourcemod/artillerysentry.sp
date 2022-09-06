#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#define PLUGIN_VERSION "2.0"

int g_heavySentryModels[4];
int g_SentryModels[4];

public Plugin myinfo =
{
	name = "Artillery Gun",
	author = "iamashaymin",
	description = "Artillery Sentry Gun loader.",
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
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry1_artillery.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry1_artillery.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry1_artillery_blue.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry1_artillery_blue.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry1_artillery_green.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry1_artillery_green.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry1_artillery_illum.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry1_artillery_yellow.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry1_artillery_yellow.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry2_artillery.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry2_artillery.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry2_artillery_blue.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry2_artillery_blue.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry2_artillery_green.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry2_artillery_green.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry2_artillery_yellow.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry2_artillery_yellow.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry3_artillery.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry3_artillery.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry3_artillery_blue.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry3_artillery_blue.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry3_artillery_green.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry3_artillery_green.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry3_artillery_yellow.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry3_artillery_yellow.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry3_artillery_rockets.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/sentry3_artillery_rockets.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/woodbox.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/woodbox.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/woodbox_blue.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/woodbox_blue.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/woodbox_green.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/woodbox_green.vtf");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/woodbox_yellow.vmt");
	AddFileToDownloadsTable("materials/models/workshop/buildables/sentry_artillery/woodbox_yellow.vtf");

	g_heavySentryModels[1] = PrecacheModel("models/buildables/sentry_heavy1.mdl");
	g_heavySentryModels[2] = PrecacheModel("models/buildables/sentry_heavy2.mdl");
	g_heavySentryModels[3] = PrecacheModel("models/buildables/sentry_heavy3.mdl");
	
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
		if (wrench > MaxClients && GetEntProp(wrench, Prop_Send, "m_iItemDefinitionIndex") == 7000)
		{
			for (int i = 0; i < 4; i++)
			{
				SetEntProp(ent, Prop_Send, "m_nModelIndexOverrides", g_heavySentryModels[level], _, i);
			}
			SetEntProp(ent, Prop_Send, "m_iMaxHealth", 175)
			SetEntProp(ent, Prop_Send, "m_iHealth", 175)
		}
	}
	return Plugin_Continue;
}

public Action Event_player_upgradedobject(Event event, const char[] name, bool dontBroadcast)
{
	int ent = event.GetInt("index");
	int level = GetEntProp(ent, Prop_Send, "m_iUpgradeLevel");
	int g_health = (level * 110)
	int g_upgrade = (125 * level)
	
	char className[64];
	GetEntityClassname(ent, className, sizeof(className));
	if (strcmp(className, "obj_sentrygun", true) == 0)
	{
		int iBuilder = GetEntPropEnt(ent, Prop_Send, "m_hBuilder");
		int wrench = GetPlayerWeaponSlot(iBuilder, 2);
		if (wrench > MaxClients && GetEntProp(wrench, Prop_Send, "m_iItemDefinitionIndex") == 7000)
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