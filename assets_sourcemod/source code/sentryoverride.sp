#pragma newdecls required
#pragma semicolon 1
#include <tf2c>
#include <sourcemod>
#include <sdktools>
#define PLUGIN_VERSION "1.0"

int g_SentryModels[4];
int g_heavySentryModels[4];
int g_cloverSentryModels[4];

ArrayList sentryList;
int wrenchList[MAXPLAYERS + 1];

//sentry levels start at 1 and not 0 lmao
static int i_heavySentryHealth[] =	{0, 175, 220, 330};
static int i_heavySentryCost[] =	{0, 200, 275, 0};

static int i_cloverSentryHealth[] =	{0, 200, 300, 500};
static int i_cloverSentryCost[] =	{0, 175, 400, 0};

#define IRONCLAD_CONSTRUCTION 7000
#define HEAVY_SUPPORT 9175

#define BUILDING_SENTRY 2
#define BUILDING_DISPENSER 1
#define BUILDING_TELEPORTER 0

public Plugin myinfo =
{
	name = "Sentry Override",
	author = "iamashaymin",
	description = "Sentry Gun model handler.",
	version = PLUGIN_VERSION,
	url = "http://www.google.com"
}

public void OnPluginStart()
{
	HookEvent("player_builtobject", Event_player_builtobject);
	HookEvent("player_upgradedobject", Event_player_upgradedobject);
	HookEvent("object_destroyed", Event_ObjectDestroyed);
	HookEvent("object_detonated", Event_ObjectDetonated);
	HookEvent("object_removed", Event_ObjectRemoved);
	HookEvent("player_spawn", Event_PlayerSpawned, EventHookMode_Post);
	HookEvent("post_inventory_application", Event_PostInventory, EventHookMode_Post);

	//initialize list of equipped wrenches
	for(int i = 0; i < MAXPLAYERS + 1; i++) {
		wrenchList[i] = -1;
	}

	sentryList = new ArrayList(1, 0);
	sentryList.Clear();
}

public void OnMapStart()
{
	DownloadTable();
}

void DownloadTable()
{
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1_blue.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1_blue.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1_green.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1_green.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1_yellow.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl1_yellow.vtf");
	
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2b.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2b.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2_blue.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2_blue.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2_green.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2_green.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2_yellow.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl2_yellow.vtf");
	
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3_blue.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3_blue.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3_green.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3_green.vtf");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3_yellow.vmt");
	AddFileToDownloadsTable("materials/models/buildables/floral_defence_plugin/lucycharm/lucycharm_lvl3_yellow.vtf");
	

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

	g_SentryModels[1] = PrecacheModel("models/buildables/sentry1.mdl");
	g_SentryModels[2] = PrecacheModel("models/buildables/sentry2.mdl");
	g_SentryModels[3] = PrecacheModel("models/buildables/sentry3.mdl");

	g_heavySentryModels[1] = PrecacheModel("models/buildables/sentry_heavy1.mdl");
	g_heavySentryModels[2] = PrecacheModel("models/buildables/sentry_heavy2.mdl");
	g_heavySentryModels[3] = PrecacheModel("models/buildables/sentry_heavy3.mdl");

	g_cloverSentryModels[1] = PrecacheModel("models/buildables/sentry_clover1.mdl");
	g_cloverSentryModels[2] = PrecacheModel("models/buildables/sentry_clover2.mdl");
	g_cloverSentryModels[3] = PrecacheModel("models/buildables/sentry_clover3.mdl");
}

//update sentry models
public Action Event_player_builtobject(Event event, const char[] name, bool dontBroadcast) {
	int ent = event.GetInt("index");
	AddSentryToList(ent);
	UpdateSentry(ent);

	return Plugin_Continue;
}

public Action Event_player_upgradedobject(Event event, const char[] name, bool dontBroadcast) {
	int ent = event.GetInt("index");
	UpdateSentry(ent);

	return Plugin_Continue;
}

//handle removing buildings from the global table
public Action Event_ObjectDestroyed(Event event, const char[] name, bool dontBroadcast) {
	int building = event.GetInt("index");
	int type = event.GetInt("objecttype");

	if(type == BUILDING_SENTRY) RemoveSentryFromList(building);
}

public Action Event_ObjectDetonated(Event event, const char[] name, bool dontBroadcast) {
	int building = event.GetInt("index");
	int type = event.GetInt("objecttype");

	if(type == BUILDING_SENTRY) RemoveSentryFromList(building);
}

public Action Event_ObjectRemoved(Event event, const char[] name, bool dontBroadcast) {
	int building = event.GetInt("index");
	int type = event.GetInt("objecttype");

	if(type == BUILDING_SENTRY) RemoveSentryFromList(building);
}

//check player for wrench changes
public Action Event_PlayerSpawned(Event event, const char[] name, bool dontBroadcast)
{
	int player = event.GetInt("userid");
	player = GetClientOfUserId(player);

	CheckWrench(player);
	return Plugin_Continue;
}

public Action Event_PostInventory(Event event, const char[] name, bool dontBroadcast) {
	int player = event.GetInt("userid");
	player = GetClientOfUserId(player);

	CheckWrench(player);
	return Plugin_Continue;
}

public void CheckWrench(int player) {
	if(TF2_GetPlayerClass(player) != TFClass_Engineer) return;

	int currentWrench = GetPlayerWeaponSlot(player, 2);
	if(!IsValidEnt(currentWrench)) return;
	int currentId = GetEntProp(currentWrench, Prop_Send, "m_iItemDefinitionIndex");

	//this is terrible
	if( 
		( (wrenchList[player] == IRONCLAD_CONSTRUCTION || wrenchList[player] == HEAVY_SUPPORT) && wrenchList[player] != currentId)  ||
		(wrenchList[player] != IRONCLAD_CONSTRUCTION && currentId == IRONCLAD_CONSTRUCTION) ||
		(wrenchList[player] != HEAVY_SUPPORT && currentId == HEAVY_SUPPORT)
		) {
			for(int i = 0; i < sentryList.Length; i++) {
				int sentryID = GetSentryFromList(i);
				if(IsValidEntity(sentryID)) {
					int engineerID = GetEntPropEnt(sentryID, Prop_Send, "m_hBuilder");
					if(engineerID == player) {
						AcceptEntityInput(sentryID, "Kill");
						RemoveSentryFromList(sentryID);
						break; //if someday engineer can have more than one sentry remove this break to kill all of them
					}
				}
			}
	}

	wrenchList[player] = currentId;
}

public void AddSentryToList(int building) {
	int sentryRef = EntIndexToEntRef(building);
	sentryList.Push(sentryRef);
}

public int GetSentryFromList(int index) {
	int sentryRef = sentryList.Get(index);
	int sentryID = EntRefToEntIndex(sentryRef);
	return sentryID;
}

public void RemoveSentryFromList(int building) {
	building = EntIndexToEntRef(building);
	int sentryPos = sentryList.FindValue(building);

	if(sentryPos != -1) sentryList.Erase(sentryPos);
	if(sentryPos == 0) sentryList.Clear();
}

public void UpdateSentry(int ent) {
	char className[64];
	GetEntityClassname(ent, className, sizeof(className));
	if (strcmp(className, "obj_sentrygun", true) != 0) return;

	int builderID = GetEntPropEnt(ent, Prop_Send, "m_hBuilder");
	int wrench = GetPlayerWeaponSlot(builderID, 2);
	int level = GetEntProp(ent, Prop_Send, "m_iUpgradeLevel");

	if(IsValidEnt(wrench)) {
		int wrenchID = GetEntProp(wrench, Prop_Send, "m_iItemDefinitionIndex");
		switch(wrenchID) {
			case HEAVY_SUPPORT: {
				SetSentryModel(ent, g_cloverSentryModels, level);

				SetEntProp(ent, Prop_Send, "m_iMaxHealth", i_cloverSentryHealth[level]);
				SetEntProp(ent, Prop_Send, "m_iHealth", i_cloverSentryHealth[level]);
				SetEntProp(ent, Prop_Send, "m_iUpgradeMetalRequired", i_cloverSentryCost[level]);
			}
			case IRONCLAD_CONSTRUCTION: {
				SetSentryModel(ent, g_heavySentryModels, level);

				SetEntProp(ent, Prop_Send, "m_iMaxHealth", i_heavySentryHealth[level]);
				SetEntProp(ent, Prop_Send, "m_iHealth", i_heavySentryHealth[level]);
				SetEntProp(ent, Prop_Send, "m_iUpgradeMetalRequired", i_heavySentryCost[level]);
			}
			default: {
				SetEntProp(ent, Prop_Send, "m_nModelIndexOverrides", 0);
			}
		}

		if (level == 3) {
			SetEntProp(ent, Prop_Send, "m_iAmmoRockets", 12);
			SetEntProp(ent, Prop_Send, "m_iMaxAmmoRockets", 12);
		}
	}
}

public void SetSentryModel(int ent, int[] sentryModels, int level) {
	for (int i = 0; i < 4; i++) {
		SetEntProp(ent, Prop_Send, "m_nModelIndexOverrides", sentryModels[level], _, i);
	}
}

public bool IsValidEnt(int ent) {
	return ent > MaxClients;
}