#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <tf2c>
#include <geoip>

#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL		"https://raw.githubusercontent.com/Sinclair47/TF2_Kill_Log/master/klog.txt"
#define PLUGIN_VERSION "0.10.6"
#define MAX_LINE_WIDTH 36
#define DMG_CRIT (1 << 20)
#define JUMP_NONE 0
#define JUMP_EXPLOSIVE_START 1
#define JUMP_EXPLOSIVE 2
#define CUSTOMKILL_PARACHUTE 99
#define CUSTOMKILL_JUMP 98

new Handle:g_dbKill = INVALID_HANDLE;
new Handle:g_Reconnect = INVALID_HANDLE;
new Handle:g_ExLog = INVALID_HANDLE;
new Handle:g_CleanUp_killlog = INVALID_HANDLE;
new Handle:g_CleanUp_playerlog = INVALID_HANDLE;
new Handle:g_CleanUp_span = INVALID_HANDLE;
new Handle:g_URL = INVALID_HANDLE;
new Handle:version = INVALID_HANDLE;
new bool:g_ExLogEnabled = false;
new bool:g_CleanUp_killlog_enabled = false;
new bool:g_CleanUp_playerlog_enabled = false;
new g_ConnectTime[MAXPLAYERS + 1];
new jumpStatus[MAXPLAYERS + 1];
new g_RowID[MAXPLAYERS + 1] = {-1, ...};
new g_MapTime = 0;
new g_MapPlaytime = 0;
new g_MapKills = 0;
new g_MapAssists = 0;
new g_MapDoms = 0;
new g_MapRevs = 0;
new g_MapFP = 0;
new g_MapFC = 0;
new g_MapFD = 0;
new g_MapFDrop = 0;
new g_MapCPP = 0;
new g_MapCPB = 0;
new g_BossHealth = 0;

enum playerTracker {
	kills,
	deaths,
	assists,
	headshots,
	backstabs,
	dominations,
	revenges,
	feigns,
	p_teleported,
	obj_built,
	obj_destroy,
	flag_pick,
	flag_cap,
	flag_def,
	flag_drop,
	cp_captured,
	cp_blocked,
	steal_sandvich,
	medic_defended,
	stuns,
	deflects,
	soaks,
	bossdmg,
	hatman,
	eyeboss,
	merasmus,
}

new scores[MAXPLAYERS + 1][playerTracker];

public Plugin:myinfo = {
	name = "TF2 Kill Log",
	author = "Sinclair",
	description = "TF2 Kill Log",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showpost.php?p=2190062&postcount=1"
}

public OnPluginStart() {
	openDB();
	CreateConVar("klog_v", PLUGIN_VERSION, "TF2 Kill Log", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	g_ExLog = CreateConVar("klog_extended", "1", "1 Enables / 0 Disables extended log features");
	g_CleanUp_killlog = CreateConVar("klog_cleanup_killlog", "1", "1 Enables / 0 Disables purging killlog");
	g_CleanUp_playerlog = CreateConVar("klog_cleanup_playerlog", "0", "1 Enables / 0 Disables purging playerlog");
	g_CleanUp_span = CreateConVar("klog_cleanup_span", "8", "Delete old killlog entries after X amount of weeks", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	g_URL = CreateConVar("klog_url","","Kill Log URL, example: yoursite.com/stats/", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");
	
	HookEvent("player_death", Event_player_death);
	HookEvent("teamplay_point_captured", Event_teamplay_point_captured);
	HookEvent("teamplay_capture_blocked", Event_teamplay_capture_blocked);
	HookEvent("teamplay_flag_event", Event_teamplay_flag_event);
	HookEvent("object_destroyed", Event_object_destroyed);
	HookEvent("player_builtobject", Event_player_builtobject);
	HookEvent("player_teleported", Event_player_teleported);

	HookEvent("player_stealsandvich", Event_player_stealsandvich);
	HookEvent("player_stunned", Event_player_stunned);
	HookEvent("medic_defended", Event_medic_defended);
	HookEvent("object_deflected", Event_object_deflected);
	HookEvent("rocket_jump", Event_explosive_jump);
	HookEvent("sticky_jump", Event_explosive_jump);
	HookEvent("rocket_jump_landed", Event_jump_landed);
	HookEvent("sticky_jump_landed", Event_jump_landed);
//	HookUserMessage(GetUserMessageId("PlayerJarated"), Event_PlayerJarated);

	HookEvent("npc_hurt", Event_npc_hurt);
	HookEvent("pumpkin_lord_killed", Event_pumpkin_lord_killed);
	HookEvent("eyeball_boss_killed", Event_eyeball_boss_killed);
	HookEvent("merasmus_killed", Event_merasmus_killed);

	if (LibraryExists("updater")) {
		Updater_AddPlugin(UPDATE_URL);
	}
}

public OnLibraryAdded(const String:name[])
{
	if (StrEqual(name, "updater")) {
		Updater_AddPlugin(UPDATE_URL);
	}
}

public Action:Command_Say(client, const String:command[], args) {
	if (IsValidClient(client)) {
		new String:text[512];
		GetCmdArg(1, text, sizeof(text));

		if (StrEqual(text, "!Rank", false) || StrEqual(text, "Rank", false)) {
			new String:path[255], String:playerURL[255], String:cID[MAX_LINE_WIDTH];
			new Handle:Kv = CreateKeyValues("data");
			GetConVarString(g_URL,path, sizeof(path));
			GetClientAuthId(client, AuthId_Steam2, cID, sizeof(cID));

			Format(playerURL, sizeof(playerURL), "http://%splayer.php?id=%s",path,cID);
			KvSetNum(Kv, "customsvr", 1);
			KvSetString(Kv, "type", "2");
			KvSetString(Kv, "title", "");
			KvSetString(Kv, "msg", playerURL);
			ShowVGUIPanel(client, "info", Kv);
			CloseHandle(Kv);
		}
	}
	return Plugin_Continue;
}

public OnPluginEnd() {
	for (new client = 1; client <= MaxClients; client++) {
		if (IsValidClient(client)) {
			if(g_RowID[client] == -1 || g_ConnectTime[client] == 0) {
				g_ConnectTime[client] = 0;
				return;
			}

			new String:auth[32];
//			GetClientAuthString(client, auth, sizeof(auth[]));
			GetClientAuthId(client, AuthId_Engine, auth, sizeof(auth[]));

			decl String:query[1024];
			Format(query, sizeof(query), "UPDATE `playerlog` SET `disconnect_time` = %d, `playtime` = `playtime` + %d, `kills` = `kills` + %d, `deaths` = `deaths` + %d, `feigns` = `feigns` + %d, `assists` = `assists` + %d, `dominations` = `dominations` + %d, `revenges` = `revenges` + %d, `headshots` = `headshots` + %d, `backstabs` = `backstabs` + %d, `obj_built` = `obj_built` + %d, `obj_destroy` = `obj_destroy` + %d, `tele_player` = `tele_player` + %d, `flag_pick` = `flag_pick` + %d, `flag_cap` = `flag_cap` + %d, `flag_def` = `flag_def` + %d, `flag_drop` = `flag_drop` + %d, `cp_cap` = `cp_cap` + %d, `cp_block` = `cp_block` + %d WHERE id = %d",
				GetTime(), GetTime() - g_ConnectTime[client], scores[client][kills], scores[client][deaths], scores[client][feigns], scores[client][assists], scores[client][dominations], scores[client][revenges], scores[client][headshots], scores[client][backstabs], scores[client][obj_built], scores[client][obj_destroy], scores[client][p_teleported], scores[client][flag_pick], scores[client][flag_cap], scores[client][flag_def], scores[client][flag_drop], scores[client][cp_captured], scores[client][cp_blocked], g_RowID[client]);
			SQL_TQuery(g_dbKill, OnRowUpdated, query, g_RowID[client]);
		}
	}

	new String:mapName[MAX_LINE_WIDTH];
	GetCurrentMap(mapName,MAX_LINE_WIDTH);
	g_MapPlaytime = GetTime() - g_MapTime;
	decl String:query2[2048];
	Format(query2, sizeof(query2), "INSERT INTO `maplog` SET `name` = '%s', `kills` = %i, `assists` = %i, `dominations` = %i, `revenges` = %i, `flag_pick` = %i, `flag_cap` = %i, `flag_def` = %i, `flag_drop` = %i, `cp_captured` = %i, `cp_blocked` = %i, `playtime` = %i ON DUPLICATE KEY UPDATE `kills` = `kills` +%i, `assists` = `assists` + %i, `dominations` = `dominations` +%i, `revenges` = `revenges` + %i, `flag_pick` = `flag_pick` +%i, `flag_cap` = `flag_cap` +%i, `flag_def` = `flag_def` +%i, `flag_drop` = `flag_drop` + %i, `cp_captured` = `cp_captured` + %i, `cp_blocked` = `cp_blocked` + %i, `playtime` = `playtime` + %d", 
		mapName, g_MapKills, g_MapAssists, g_MapDoms, g_MapRevs, g_MapFP, g_MapFC, g_MapFD, g_MapFDrop, g_MapCPP, g_MapCPB, g_MapPlaytime, g_MapKills, g_MapAssists, g_MapDoms, g_MapRevs, g_MapFP, g_MapFC, g_MapFD, g_MapFDrop, g_MapCPP, g_MapCPB, g_MapPlaytime);
	SQL_TQuery(g_dbKill, OnRowUpdated, query2);
}

openDB() {
	SQL_TConnect(connectDB, "killlog");
}

public connectDB(Handle:owner, Handle:hndl, const String:error[], any:data) {
	if (hndl == INVALID_HANDLE) {
		LogError("Database failure: %s", error);
		return;
	} else {
		LogMessage("TF2 Kill Log Connected to Database!");
		g_dbKill = hndl;
		SQL_SetCharset(g_dbKill, "utf8");
		createDBKillLog();
		createDBSmallLog();
		createDBPlayerLog();
		createDBTeamLog();
		createDBObjectLog();
		createDBMapLog();
		CreateTimer(300.0, Timer_HandleUpdate, INVALID_HANDLE, TIMER_REPEAT);
	}
}

public Action:reconnectDB(Handle:timer, any:nothing) {
	if (SQL_CheckConfig("killlog")) {
		SQL_TConnect(connectDB, "killlog");
	}
}

public SQLError(Handle:owner, Handle:hndl, const String:error[], any:data) {
	if (!StrEqual("", error)) {
		LogMessage("SQL Error: %s", error);
	}
}

public OnClientConnected(client) {
	if(IsFakeClient(client)) {
		return;
	}

	g_ConnectTime[client] = GetTime();
	g_RowID[client] = -1;
	jumpStatus[client] = JUMP_NONE;
}

public OnClientAuthorized(client, const String:authid[]) {
	PurgeClient(client);
}

public OnClientPostAdminCheck(client) {
	if(IsFakeClient(client)) {
		return;
	}
	
	CreateTimer(1.0, Timer_HandleConnect, GetClientUserId(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action:Timer_HandleConnect(Handle:timer, any:userid) {
	new client = GetClientOfUserId(userid);
	if(client == 0) {
		return Plugin_Stop;
	}
	
	if(g_ConnectTime[client] == 0) {
		return Plugin_Continue;
	}
	
	new String:ip[64], String:c_code[3];
	new String:buffers[3][256];

	GetClientName(client, buffers[0], sizeof(buffers[]));
//	GetClientAuthString(client, buffers[1], sizeof(buffers[]));
	GetClientAuthId(client, AuthId_Engine, buffers[1], sizeof(buffers[]));
	GetClientIP(client, ip, sizeof(ip));
	GeoipCode2(ip, c_code);

	strcopy(buffers[2], sizeof(buffers[]), c_code);

	decl String:escapedBuffers[3][513];
	for(new i = 0; i < sizeof(buffers); i++) {
		if(strlen(buffers[i]) == 0) {
			strcopy(escapedBuffers[i], sizeof(escapedBuffers[]), "NULL");
		} else {
			SQL_EscapeString(g_dbKill, buffers[i], escapedBuffers[i], sizeof(escapedBuffers[]));
			Format(escapedBuffers[i], sizeof(escapedBuffers[]), "'%s'", escapedBuffers[i]);
		}
	}
	
	decl String:query[1024];
	Format(query, sizeof(query), "INSERT INTO `playerlog` SET name = %s, auth = %s, ip = '%s', cc = %s, connect_time = '%d', disconnect_time = '0' ON DUPLICATE KEY UPDATE name = %s, auth = %s, ip = '%s', cc = %s, connect_time = '%d', disconnect_time = '0'",
		escapedBuffers[0], escapedBuffers[1], ip, escapedBuffers[2], g_ConnectTime[client],escapedBuffers[0], escapedBuffers[1], ip, escapedBuffers[2], g_ConnectTime[client]);
	SQL_TQuery(g_dbKill, OnRowInserted, query, GetClientUserId(client));
	return Plugin_Stop;
}

public Action:Timer_HandleUpdate(Handle:timer)
{
	updateMap();
	return Plugin_Continue;
}

public OnClientDisconnect(client) {
	if(g_RowID[client] == -1 || g_ConnectTime[client] == 0) {
		g_ConnectTime[client] = 0;
		return;
	}

	new String:auth[32];
//	GetClientAuthString(client, auth, sizeof(auth[]));
	GetClientAuthId(client, AuthId_Engine, auth, sizeof(auth[]));

	decl String:query[1024];
	Format(query, sizeof(query), "UPDATE `playerlog` SET `disconnect_time` = %d, `playtime` = `playtime` + %d, `kills` = `kills` + %d, `deaths` = `deaths` + %d, `feigns` = `feigns` + %d, `assists` = `assists` + %d, `dominations` = `dominations` + %d, `revenges` = `revenges` + %d, `headshots` = `headshots` + %d, `backstabs` = `backstabs` + %d, `obj_built` = `obj_built` + %d, `obj_destroy` = `obj_destroy` + %d, `tele_player` = `tele_player` + %d, `flag_pick` = `flag_pick` + %d, `flag_cap` = `flag_cap` + %d, `flag_def` = `flag_def` + %d, `flag_drop` = `flag_drop` + %d, `cp_cap` = `cp_cap` + %d, `cp_block` = `cp_block` + %d WHERE id = %d",
		GetTime(), GetTime() - g_ConnectTime[client], scores[client][kills], scores[client][deaths], scores[client][feigns], scores[client][assists], scores[client][dominations], scores[client][revenges], scores[client][headshots], scores[client][backstabs], scores[client][obj_built], scores[client][obj_destroy], scores[client][p_teleported], scores[client][flag_pick], scores[client][flag_cap], scores[client][flag_def], scores[client][flag_drop], scores[client][cp_captured], scores[client][cp_blocked], g_RowID[client]);
	SQL_TQuery(g_dbKill, OnRowUpdated, query, g_RowID[client]);
	g_ConnectTime[client] = 0;
}

public OnMapStart() {
	g_MapTime = GetTime();
}

public OnConfigsExecuted() {
	TagsCheck("KLog");
	version = FindConVar("klog_v");
	SetConVarString(version,PLUGIN_VERSION,true,true);
	g_ExLogEnabled = GetConVarBool(g_ExLog);
	g_CleanUp_killlog_enabled = GetConVarBool(g_CleanUp_killlog);
	g_CleanUp_playerlog_enabled = GetConVarBool(g_CleanUp_playerlog);
}

TagsCheck(const String:tag[])
{
	new Handle:hTags = FindConVar("sv_tags");
	decl String:tags[255];
	GetConVarString(hTags, tags, sizeof(tags));

	if (!(StrContains(tags, tag, false)>-1))
	{
		decl String:newTags[255];
		Format(newTags, sizeof(newTags), "%s,%s", tags, tag);
		SetConVarString(hTags, newTags);
		GetConVarString(hTags, tags, sizeof(tags));
	}
	CloseHandle(hTags);
}

public OnMapEnd() {
	updateTime();
	for (new client = 1; client <= MaxClients; client++) {
		if (IsValidClient(client)) {
			if(g_RowID[client] == -1 || g_ConnectTime[client] == 0) {
				g_ConnectTime[client] = 0;
				return;
			}

			new String:auth[32];
//			GetClientAuthString(client, auth, sizeof(auth[]));
			GetClientAuthId(client, AuthId_Engine, auth, sizeof(auth[]));

			decl String:query[1024];
			Format(query, sizeof(query), "UPDATE `playerlog` SET `disconnect_time` = %d, `playtime` = `playtime` + %d, `kills` = `kills` + %d, `deaths` = `deaths` + %d, `feigns` = `feigns` + %d, `assists` = `assists` + %d, `dominations` = `dominations` + %d, `revenges` = `revenges` + %d, `headshots` = `headshots` + %d, `backstabs` = `backstabs` + %d, `obj_built` = `obj_built` + %d, `obj_destroy` = `obj_destroy` + %d, `tele_player` = `tele_player` + %d, `flag_pick` = `flag_pick` + %d, `flag_cap` = `flag_cap` + %d, `flag_def` = `flag_def` + %d, `flag_drop` = `flag_drop` + %d, `cp_cap` = `cp_cap` + %d, `cp_block` = `cp_block` + %d WHERE id = %d",
				GetTime(), GetTime() - g_ConnectTime[client], scores[client][kills], scores[client][deaths], scores[client][feigns], scores[client][assists], scores[client][dominations], scores[client][revenges], scores[client][headshots], scores[client][backstabs], scores[client][obj_built], scores[client][obj_destroy], scores[client][p_teleported], scores[client][flag_pick], scores[client][flag_cap], scores[client][flag_def], scores[client][flag_drop], scores[client][cp_captured], scores[client][cp_blocked], g_RowID[client]);
			SQL_TQuery(g_dbKill, OnRowUpdated, query, g_RowID[client]);
			g_ConnectTime[client] = 0;
		}
	}

	new String:mapName[MAX_LINE_WIDTH];
	GetCurrentMap(mapName,MAX_LINE_WIDTH);
	g_MapPlaytime = GetTime() - g_MapTime;
	decl String:query2[2048];
	Format(query2, sizeof(query2), "INSERT INTO `maplog` SET `name` = '%s', `kills` = %i, `assists` = %i, `dominations` = %i, `revenges` = %i, `flag_pick` = %i, `flag_cap` = %i, `flag_def` = %i, `flag_drop` = %i, `cp_captured` = %i, `cp_blocked` = %i, `playtime` = %i ON DUPLICATE KEY UPDATE `kills` = `kills` +%i, `assists` = `assists` + %i, `dominations` = `dominations` +%i, `revenges` = `revenges` + %i, `flag_pick` = `flag_pick` +%i, `flag_cap` = `flag_cap` +%i, `flag_def` = `flag_def` +%i, `flag_drop` = `flag_drop` + %i, `cp_captured` = `cp_captured` + %i, `cp_blocked` = `cp_blocked` + %i, `playtime` = `playtime` + %d", 
		mapName, g_MapKills, g_MapAssists, g_MapDoms, g_MapRevs, g_MapFP, g_MapFC, g_MapFD, g_MapFDrop, g_MapCPP, g_MapCPB, g_MapPlaytime, g_MapKills, g_MapAssists, g_MapDoms, g_MapRevs, g_MapFP, g_MapFC, g_MapFD, g_MapFDrop, g_MapCPP, g_MapCPB, g_MapPlaytime);
	SQL_TQuery(g_dbKill, OnRowUpdated, query2);

	if (g_CleanUp_killlog_enabled) {
		cleanup_killlog();
	}
	if (g_CleanUp_playerlog_enabled){
		cleanup_playerlog();
	}
}

public OnRowInserted(Handle:owner, Handle:hndl, const String:error[], any:userid) {
	new client = GetClientOfUserId(userid);
	if(client == 0) {
		return;
	}
	
	if(hndl == INVALID_HANDLE) {
		LogError("Unable to insert row for %L. %s", client, error);
		return;
	}

	g_RowID[client] = SQL_GetInsertId(hndl);
}

public OnRowUpdated(Handle:owner, Handle:hndl, const String:error[], any:client) {
	if (!IsValidClient(client)){
		return;
	}
	if(hndl == INVALID_HANDLE) {
		LogError("Unable to update row %L. %s", client, error);
		return;
	}
}

public Event_player_death(Handle:hEvent, const String:name[], bool:dontBroadcast) {
	if (g_dbKill == INVALID_HANDLE && g_Reconnect == INVALID_HANDLE) {
		g_Reconnect = CreateTimer(900.0, reconnectDB);
		return;
	}

	new victimId = GetEventInt(hEvent, "userid");
	new attackerId = GetEventInt(hEvent, "attacker");
	new assisterId = GetEventInt(hEvent, "assister");
	new deathflags = GetEventInt(hEvent, "death_flags");
	new customkill = GetEventInt(hEvent, "customkill");
	new killstreak = GetEventInt(hEvent, "kill_streak_victim");
	new killstreak_wep = GetEventInt(hEvent, "kill_streak_wep");
	new dmgtype = GetEventInt(hEvent, "damagebits");

	if(attackerId == 0) {
		return;
	}

	new String:aID[MAX_LINE_WIDTH];
	new String:vID[MAX_LINE_WIDTH];
	new String:asID[MAX_LINE_WIDTH];
	new String:map[MAX_LINE_WIDTH];
	new String:weapon[64];

	new assister = GetClientOfUserId(assisterId);
	new victim = GetClientOfUserId(victimId);
	new attacker = GetClientOfUserId(attackerId);

	new attackerteam = GetClientTeam(attacker);
	new victimteam = GetClientTeam(victim);
	new TFClassType:attackerclass = TF2_GetPlayerClass(attacker);
	new TFClassType:victimclass = TF2_GetPlayerClass(victim);
	new TFClassType:assisterclass;

	GetCurrentMap(map, MAX_LINE_WIDTH);
	GetEventString(hEvent, "weapon_logclassname", weapon, sizeof(weapon));
//	GetClientAuthString(attacker, aID, sizeof(aID));
	GetClientAuthId(attacker, AuthId_Engine, aID, sizeof(aID));
//	GetClientAuthString(victim, vID, sizeof(vID));
	GetClientAuthId(victim, AuthId_Engine, vID, sizeof(vID));
	
	if (TF2_IsPlayerInCondition(attacker,TFCond_HalloweenKart)) {
		weapon = "bumper_car";
		customkill = 82;
	}

	if (deathflags & 32) {
		scores[victim][feigns]++;
		return;
	}

	if (attacker != victim) {
		g_MapKills++;
		scores[attacker][kills]++;
	}

	scores[victim][deaths]++;

	if (assister != 0) {
//		GetClientAuthString(assister, asID, sizeof(asID));
		GetClientAuthId(assister, AuthId_Engine, asID, sizeof(asID));
		assisterclass = TF2_GetPlayerClass(assister);
		g_MapAssists++;
		scores[assister][assists]++;
	}

	if(customkill == 1 || customkill == 51) {
		scores[attacker][headshots]++;
	}
	if(customkill == 2) {
		scores[attacker][backstabs]++;
	}

	new df_assisterrevenge = 0;
	new df_killerrevenge = 0;
	new df_assisterdomination = 0;
	new df_killerdomination = 0;

	if (deathflags & 1) {
		df_killerdomination = 1;
		g_MapDoms++;
		scores[attacker][dominations]++;
	}
	if (deathflags & 2) {
		df_assisterdomination = 1;
		g_MapDoms++;
		scores[assister][dominations]++;
	}
	if (deathflags & 4) {
		df_killerrevenge = 1;
		g_MapRevs++;
		scores[attacker][revenges]++;
	}
	if (deathflags & 8) {
		df_assisterrevenge = 1;
		g_MapRevs++;
		scores[assister][revenges]++;
	}

	new dmg_crit;

	if (dmgtype & DMG_CRIT) {
		dmg_crit = 1;
	}

	if (jumpStatus[attacker] == JUMP_EXPLOSIVE) {
		if (TF2_IsPlayerInCondition(attacker, TFCond_Parachute)) {
			customkill = CUSTOMKILL_PARACHUTE;
		}
		else {
			customkill = CUSTOMKILL_JUMP;
		}
	}

	if (g_ExLogEnabled) {
		new len = 0;
		decl String:buffer[2512];
		len += Format(buffer[len], sizeof(buffer)-len, "INSERT INTO `killlog` (`attacker`, `ateam`, `aclass`, `victim`, `vteam`, `vclass`, `assister`, `asclass`, `weapon`, `killtime`, `dominated`, `assister_dominated`, `revenge`, `assister_revenge`, `customkill`, `crit`, `wep_ks`, `victim_ks`, `map`)");
		len += Format(buffer[len], sizeof(buffer)-len, " VALUES ('%s', '%i', '%i', '%s', '%i', '%i', '%s', '%i', '%s', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%s');",aID,attackerteam,attackerclass,vID,victimteam,victimclass,asID,assisterclass,weapon,GetTime(),df_killerdomination,df_assisterdomination,df_killerrevenge,df_assisterrevenge,customkill,dmg_crit,killstreak_wep,killstreak,map);	
		SQL_TQuery(g_dbKill, SQLError, buffer);
	}

	if (attacker != victim) {
		new len2 = 0;
		decl String:buffer2[1024];
		len2 += Format(buffer2[len2], sizeof(buffer2)-len2, "INSERT INTO `smalllog` (`attacker`, `weapon`, `kills`, `crits`, `ks`, `customkill`)");
		len2 += Format(buffer2[len2], sizeof(buffer2)-len2, " VALUES ('%s', '%s', '%i', '%i', '%i', '%i') ON DUPLICATE KEY UPDATE `kills` = `kills` + 1, `crits` = `crits` + %i, `ks` = GREATEST(`ks`,VALUES(`ks`));",aID,weapon,1,dmg_crit,killstreak_wep,customkill,dmg_crit);
		SQL_TQuery(g_dbKill, SQLError, buffer2);
	}

	new len3 = 0;
	decl String:buffer3[1024];
	len3 += Format(buffer3[len3], sizeof(buffer3)-len3, "INSERT INTO `smalllog` (`attacker`, `weapon`, `deaths`, `customkill`)");
	len3 += Format(buffer3[len3], sizeof(buffer3)-len3, " VALUES ('%s', '%s', '%i', '%i') ON DUPLICATE KEY UPDATE `deaths` = `deaths` + 1;",vID,weapon,1,customkill);
	SQL_TQuery(g_dbKill, SQLError, buffer3);

	decl String:query[1024];
	Format(query, sizeof(query), "UPDATE `playerlog` SET `kills` = `kills` + %d, `deaths` = `deaths` + %d, `feigns` = `feigns` + %d, `assists` = `assists` + %d, `dominations` = `dominations` + %d, `revenges` = `revenges` + %d, `headshots` = `headshots` + %d, `backstabs` = `backstabs` + %d, `obj_built` = `obj_built` + %d, `obj_destroy` = `obj_destroy` + %d, `tele_player` = `tele_player` + %d, `flag_pick` = `flag_pick` + %d, `flag_cap` = `flag_cap` + %d, `flag_def` = `flag_def` + %d, `flag_drop` = `flag_drop` + %d, `cp_cap` = `cp_cap` + %d, `cp_block` = `cp_block` + %d WHERE id = %d",
		scores[victim][kills], scores[victim][deaths], scores[victim][feigns], scores[victim][assists], scores[victim][dominations], scores[victim][revenges], scores[victim][headshots], scores[victim][backstabs], scores[victim][obj_built], scores[victim][obj_destroy], scores[victim][p_teleported], scores[victim][flag_pick], scores[victim][flag_cap], scores[victim][flag_def], scores[victim][flag_drop], scores[victim][cp_captured], scores[victim][cp_blocked], g_RowID[victim]);
	SQL_TQuery(g_dbKill, OnRowUpdated, query, g_RowID[victim]);
	PurgeClient(victim);
}

public Action:Event_player_teleported(Handle:hEvent, const String:name[], bool:dontBroadcast) {
	new user = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	new builder = GetClientOfUserId(GetEventInt(hEvent, "builderid"));

	if (user != builder) {
		scores[builder][p_teleported]++;
	}
}

public Action:Event_player_builtobject(Handle:hEvent, const String:name[], bool:dontBroadcast) {
	new user = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	new builtobject = GetEventInt(hEvent, "object");

	if (builtobject != 3) {
		scores[user][obj_built]++;
	}
}

public Action:Event_object_destroyed(Handle:hEvent, const String:name[], bool:dontBroadcast) {
	new String:vID[64], String:aID[64], String:object_name[25], String:object_lvl[25], String:weapon[25];
	new victim = GetClientOfUserId(GetEventInt(hEvent, "userid"));
//	GetClientAuthString(victim, vID, sizeof(vID));
	GetClientAuthId(victim, AuthId_Engine, vID, sizeof(vID));
	new victimteam = GetClientTeam(victim);
	new TFClassType:victimclass = TF2_GetPlayerClass(victim);

	new attacker = GetClientOfUserId(GetEventInt(hEvent, "attacker"));
//	GetClientAuthString(attacker, aID, sizeof(aID));
	GetClientAuthId(attacker, AuthId_Engine, aID, sizeof(aID));
	new attackerteam = GetClientTeam(attacker);
	new TFClassType:attackerclass = TF2_GetPlayerClass(attacker);
	GetEventString(hEvent, "weapon", weapon, sizeof(weapon));

	if (attacker == victim) {
		return;
	}

	new builtobject = GetEventInt(hEvent, "objecttype");
	new obj_index = GetEventInt(hEvent, "index");
	new lvl = GetEntProp(obj_index, Prop_Send, "m_iUpgradeLevel");
	new bool:mini = (GetEntProp(obj_index, Prop_Send, "m_bMiniBuilding") == 1);

	if (builtobject == 0) {
		object_name = "dispenser";
		scores[attacker][obj_destroy]++;
	}
	if (builtobject == 1) {
		object_name = "teleporter";
		scores[attacker][obj_destroy]++;
	}
	if (builtobject == 2) {
		object_name = "sentry";
		scores[attacker][obj_destroy]++;
	}
	if (builtobject == 3) {
		new sapper = GetPlayerWeaponSlot(victim, 1);
		if (sapper > 0 && IsValidEdict(sapper)) {
			new sapper_index = GetEntProp(sapper, Prop_Send, "m_iItemDefinitionIndex");

			if (sapper_index == 810 || sapper_index == 831) {
				object_name = "recorder";
			}
			else if (sapper_index == 933) {
				object_name = "psapper";
			}
			else if (sapper_index == 1080) {
				object_name = "fsapper";
			}
			else if (sapper_index == 1102) {
				object_name = "snack_attack";
			}
			else {
				object_name = "sapper";
			}
		}
	}
	if (mini == false) {
		if (builtobject == 3) {
			Format(object_lvl, sizeof(object_lvl), "%s", object_name);
		} else {
			Format(object_lvl, sizeof(object_lvl), "%s_%i", object_name, lvl);
		}
	} else {
		object_lvl = "mini_sentry";
	}

	new len = 0;
	decl String:query[2512];
	len += Format(query[len], sizeof(query)-len, "INSERT INTO `objectlog` (`attacker`, `ateam`, `aclass`, `victim`, `vteam`, `vclass`, `weapon`, `killtime`, `object`)");
	len += Format(query[len], sizeof(query)-len, " VALUES ('%s', '%i', '%i', '%s', '%i', '%i', '%s', '%i', '%s');",aID,attackerteam,attackerclass,vID,victimteam,victimclass,weapon,GetTime(),object_lvl);	
	SQL_TQuery(g_dbKill, SQLError, query);
}

public Action:Event_teamplay_flag_event(Handle:hEvent, const String:name[], bool:dontBroadcast) {
	new String:uID[64], String:action[15], String:map[MAX_LINE_WIDTH], String:cID[64], TFClassType:carrierclass, carrierteam;
	new user = GetEventInt(hEvent, "player");
	new state = GetEventInt(hEvent, "eventtype");
	if (!IsValidClient(user)) {
		return;
	}
	new userteam = GetClientTeam(user);
	new TFClassType:userclass = TF2_GetPlayerClass(user);

//	GetClientAuthString(user,uID, sizeof(uID));
	GetClientAuthId(user, AuthId_Engine, uID, sizeof(uID));
	GetCurrentMap(map, MAX_LINE_WIDTH);

	if (state == 1) {
		g_MapFP++;
		scores[user][flag_pick]++;
	}
	if (state == 2) {
		action = "flag_cap";
		g_MapFC++;
		scores[user][flag_cap]++;
	}
	if (state == 3) {
		new carrier = GetEventInt(hEvent, "carrier");

		carrierteam = GetClientTeam(carrier);
		carrierclass = TF2_GetPlayerClass(carrier);
//		GetClientAuthString(carrier,cID, sizeof(cID));
		GetClientAuthId(carrier, AuthId_Engine, cID, sizeof(cID));

		action = "flag_def";
		g_MapFD++;
		scores[user][flag_def]++;
	}
	if (state == 4) {
		g_MapFDrop++;
		scores[user][flag_drop]++;
	}
	if (state == 2 || state == 3) {
		new len = 0;
		decl String:query[1024];
		len += Format(query[len], sizeof(query)-len, "INSERT INTO `teamlog` (`capper`, `cteam`, `cclass`, `defender`, `dteam`, `dclass`, `killtime`, `event`, `map`)");
		len += Format(query[len], sizeof(query)-len, " VALUES ('%s', '%i', '%i', '%s', '%i', '%i', '%i', '%s', '%s');",uID,userteam,userclass,cID,carrierteam,carrierclass,GetTime(),action,map);	
		SQL_TQuery(g_dbKill, SQLError, query);
	}
}

public Action:Event_teamplay_point_captured(Handle:hEvent, const String:name[], bool:dontBroadcast) {
	new String:cappers[128], String:action[15], String:map[MAX_LINE_WIDTH];
	new cteam = GetEventInt(hEvent, "team");

	GetEventString(hEvent, "cappers", cappers, sizeof(cappers));
	GetCurrentMap(map, MAX_LINE_WIDTH);

	new x = strlen(cappers);
	action = "cp_captured";

	for (new i = 0; i < x; i++) {
		new String:cID[64];
		new client = cappers[i];
		new TFClassType:capperclass = TF2_GetPlayerClass(client);

//		GetClientAuthString(client, cID, sizeof(cID));
		GetClientAuthId(client, AuthId_Engine, cID, sizeof(cID));
		g_MapCPP++;
		scores[client][cp_captured]++;

		new len = 0;
		decl String:query[1024];
		len += Format(query[len], sizeof(query)-len, "INSERT INTO `teamlog` (`capper`, `cteam`, `cclass`, `killtime`, `event`, `map`)");
		len += Format(query[len], sizeof(query)-len, " VALUES ('%s', '%i', '%i', '%i', '%s', '%s');",cID,cteam,capperclass,GetTime(),action,map);	
		SQL_TQuery(g_dbKill, SQLError, query);
	}
}

public Action:Event_teamplay_capture_blocked(Handle:hEvent, const String:name[], bool:dontBroadcast) {
	new client = GetEventInt(hEvent, "blocker");

	if (IsValidClient(client)) {
		g_MapCPB++;
		scores[client][cp_blocked]++;
	}
}

public Action:Event_player_stealsandvich(Handle:hEvent, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(hEvent, "target"));

	if (IsValidClient(client)) {
		scores[client][steal_sandvich]++;
	}
}

public Action:Event_medic_defended(Handle:hEvent, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));

	if (IsValidClient(client)) {
		scores[client][medic_defended]++;
	}
}

public Action:Event_player_stunned(Handle:hEvent, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(hEvent, "stunner"));

	if (IsValidClient(client)) {
		scores[client][stuns]++;
	}
}

public Action:Event_object_deflected(Handle:hEvent, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	new weaponid = GetEventInt(hEvent, "weaponid");

	if (IsValidClient(client) && weaponid != 0) {
		scores[client][deflects]++;
	}
}

public Action:Event_PlayerJarated(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init) {
	new client = BfReadByte(bf);
	new victim = BfReadByte(bf);
	
	if (IsValidClient(client)) {
		if (TF2_IsPlayerInCondition(victim, TFCond_Jarated) || TF2_IsPlayerInCondition(victim, TFCond_Milked)) {
			scores[client][soaks]++;
		}
	}
}

public Event_explosive_jump(Handle:event, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new status = jumpStatus[client];

	if(status == JUMP_EXPLOSIVE_START)
	{
		jumpStatus[client] = JUMP_EXPLOSIVE;
	}
	else if(status != JUMP_EXPLOSIVE)
		jumpStatus[client] = JUMP_EXPLOSIVE_START;
}

public Event_jump_landed(Handle:event, const String:name[], bool:dontBroadcast) {
	jumpStatus[GetClientOfUserId(GetEventInt(event, "userid"))] = JUMP_NONE;
}

public Action:Event_npc_hurt(Handle:event, const String:name[], bool:dontBroadcast) {
	new String:bossClass[24];
	new boss = GetEventInt(event, "entindex");

	GetEdictClassname(boss, bossClass, sizeof(bossClass));
	g_BossHealth = GetEntProp(boss, Prop_Data, "m_iMaxHealth");

	if (StrEqual("headless_hatman", bossClass) || StrEqual("eyeball_boss", bossClass) || StrEqual("merasmus", bossClass)) {
		new client = GetClientOfUserId(GetEventInt(event, "attacker_player"));
		if (IsValidClient(client)) {
			scores[client][bossdmg] += GetEventInt(event, "damageamount");
		}
	}
}

public Action:Event_pumpkin_lord_killed(Handle:event, const String:name[], bool:dontBroadcast) {
	for (new client = 1; client <= MaxClients; client++) {
		if (IsValidClient(client)) {
			if (scores[client][bossdmg] >= (g_BossHealth/6)) {
				scores[client][hatman]++;
			}
			scores[client][bossdmg] = 0;
		}
	}
}

public Action:Event_eyeball_boss_killed(Handle:event, const String:name[], bool:dontBroadcast) {
	for (new client = 1; client <= MaxClients; client++) {
		if (IsValidClient(client)) {
			if (scores[client][bossdmg] >= (g_BossHealth/6)) {
				scores[client][eyeboss]++;
			}
			scores[client][bossdmg] = 0;
		}
	}
}

public Action:Event_merasmus_killed(Handle:event, const String:name[], bool:dontBroadcast) {
	for (new client = 1; client <= MaxClients; client++) {
		if (IsValidClient(client)) {
			if (scores[client][bossdmg] >= (g_BossHealth/6)) {
				scores[client][merasmus]++;
			}
			scores[client][bossdmg] = 0;
		}
	}
}

stock bool:IsValidClient(client) {
	if(client <= 0 || client > MaxClients || !IsClientInGame(client)) {
		return false;
	}
	return true;
}


updateMap(){
	new String:mapName[MAX_LINE_WIDTH];
	GetCurrentMap(mapName,MAX_LINE_WIDTH);
	decl String:query2[2048];
	Format(query2, sizeof(query2), "INSERT INTO `maplog` SET `name` = '%s', `kills` = %i, `assists` = %i, `dominations` = %i, `revenges` = %i, `flag_pick` = %i, `flag_cap` = %i, `flag_def` = %i, `flag_drop` = %i, `cp_captured` = %i, `cp_blocked` = %i ON DUPLICATE KEY UPDATE `kills` = `kills` +%i, `assists` = `assists` + %i, `dominations` = `dominations` +%i, `revenges` = `revenges` + %i, `flag_pick` = `flag_pick` +%i, `flag_cap` = `flag_cap` +%i, `flag_def` = `flag_def` +%i, `flag_drop` = `flag_drop` + %i, `cp_captured` = `cp_captured` + %i, `cp_blocked` = `cp_blocked` + %i", 
		mapName, g_MapKills, g_MapAssists, g_MapDoms, g_MapRevs, g_MapFP, g_MapFC, g_MapFD, g_MapFDrop, g_MapCPP, g_MapCPB, g_MapKills, g_MapAssists, g_MapDoms, g_MapRevs, g_MapFP, g_MapFC, g_MapFD, g_MapFDrop, g_MapCPP, g_MapCPB);
	SQL_TQuery(g_dbKill, OnRowUpdated, query2);
	PurgeMap();
}

//Adds disconnect time to "stuck" players
updateTime() {
	SQL_FastQuery(g_dbKill, "UPDATE `playerlog` SET disconnect_time = UNIX_TIMESTAMP(NOW()) WHERE disconnect_time = 0");
}

//Removes old entries as defined by g_CleanUp_span
cleanup_killlog() {
	decl String:query[2048];
	Format(query, sizeof(query), "DELETE FROM killlog WHERE killtime <= UNIX_TIMESTAMP(DATE(NOW()) - INTERVAL %i WEEK)", GetConVarInt(g_CleanUp_span));
	SQL_FastQuery(g_dbKill, query);
}

//Removes old entries as defined by g_CleanUp_span
cleanup_playerlog() {
	decl String:query[2048];
	Format(query, sizeof(query), "DELETE FROM playerlog WHERE disconnect_time <= UNIX_TIMESTAMP(DATE(NOW()) - INTERVAL %i WEEK)", GetConVarInt(g_CleanUp_span));
	SQL_FastQuery(g_dbKill, query);
	SQL_FastQuery(g_dbKill, "DELETE FROM smalllog WHERE attacker NOT IN (SELECT pl.auth FROM playerlog pl)");
	SQL_FastQuery(g_dbKill, "DELETE FROM objectlog WHERE attacker NOT IN (SELECT pl.auth FROM playerlog pl)");
	SQL_FastQuery(g_dbKill, "DELETE FROM teamlog WHERE capper NOT IN (SELECT pl.auth FROM playerlog pl)");
}

PurgeClient(client) {
	scores[client][kills] = 0;
	scores[client][deaths] = 0;
	scores[client][assists] = 0;
	scores[client][headshots] = 0;
	scores[client][backstabs] = 0;
	scores[client][dominations] = 0;
	scores[client][revenges] = 0;
	scores[client][feigns] = 0;
	scores[client][p_teleported] = 0;
	scores[client][obj_built] = 0;
	scores[client][obj_destroy] = 0;
	scores[client][flag_pick] = 0;
	scores[client][flag_cap] = 0;
	scores[client][flag_def] = 0;
	scores[client][flag_drop] = 0;
	scores[client][cp_captured] = 0;
	scores[client][cp_blocked] = 0;
	scores[client][steal_sandvich] = 0;
	scores[client][medic_defended] = 0;
	scores[client][stuns] = 0;
	scores[client][deflects] = 0;
	scores[client][soaks] = 0;
	scores[client][bossdmg] = 0;
	scores[client][hatman] = 0;
	scores[client][eyeboss] = 0;
	scores[client][merasmus] = 0;
}

PurgeMap() {
	g_MapKills = 0;
	g_MapAssists = 0;
	g_MapDoms = 0;
	g_MapRevs = 0;
	g_MapFP = 0;
	g_MapFC = 0;
	g_MapFD = 0;
	g_MapFDrop = 0;
	g_MapCPP = 0;
	g_MapCPB = 0;
}

createDBKillLog() {
	new len = 0;
	decl String:query[1024];
	len += Format(query[len], sizeof(query)-len, "CREATE TABLE IF NOT EXISTS `killlog` (");
	len += Format(query[len], sizeof(query)-len, "`attacker` VARCHAR( 20 ) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`ateam` TINYINT( 1 ) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`aclass` TINYINT( 1 ) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`victim` VARCHAR( 20 ) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`vteam` TINYINT( 1 ) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`vclass` TINYINT( 1 ) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`assister` VARCHAR( 20 ) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`asclass` TINYINT( 1 ) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`weapon` VARCHAR( 25 ) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`killtime` INT( 11 ) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`dominated` BOOL NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`assister_dominated` BOOL NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`revenge` BOOL NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`assister_revenge` BOOL NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`customkill` TINYINT( 2 ) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`crit` TINYINT( 2 ) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`wep_ks` TINYINT( 3 ) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`victim_ks` TINYINT( 3 ) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`map` VARCHAR( 36 ) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "KEY `attacker` (`attacker`),");
	len += Format(query[len], sizeof(query)-len, "KEY `victim` (`victim`),");
	len += Format(query[len], sizeof(query)-len, "KEY `assister` (`assister`),");
	len += Format(query[len], sizeof(query)-len, "KEY `weapon` (`weapon`),");
	len += Format(query[len], sizeof(query)-len, "KEY `killtime` (`killtime`),");
	len += Format(query[len], sizeof(query)-len, "KEY `map` (`map`))");
	len += Format(query[len], sizeof(query)-len, "ENGINE = InnoDB DEFAULT CHARSET=utf8;");
	SQL_FastQuery(g_dbKill, query);
}

createDBSmallLog() {
	new len = 0;
	decl String:query[512];
	len += Format(query[len], sizeof(query)-len, "CREATE TABLE IF NOT EXISTS `smalllog` (");
	len += Format(query[len], sizeof(query)-len, "`attacker` varchar(20) DEFAULT NULL,");
	len += Format(query[len], sizeof(query)-len, "`weapon` varchar(25) DEFAULT NULL,");
	len += Format(query[len], sizeof(query)-len, "`kills` int(11) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`deaths` int(11) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`crits` int(11) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`ks` int(11) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`customkill` tinyint(2) DEFAULT NULL,");
	len += Format(query[len], sizeof(query)-len, "UNIQUE KEY `attacker` (`attacker`,`weapon`,`customkill`)");
	len += Format(query[len], sizeof(query)-len, ") ENGINE=InnoDB DEFAULT CHARSET=utf8;");
	SQL_FastQuery(g_dbKill, query);
}

createDBPlayerLog() {
	new len = 0;
	decl String:query[1024];
	len += Format(query[len], sizeof(query)-len, "CREATE TABLE IF NOT EXISTS `playerlog` (");
	len += Format(query[len], sizeof(query)-len, "`id` int(11) NOT NULL AUTO_INCREMENT,"); 
	len += Format(query[len], sizeof(query)-len, "`name` varchar(32),");
	len += Format(query[len], sizeof(query)-len, "`auth` varchar(32),");
	len += Format(query[len], sizeof(query)-len, "`ip` varchar(32),");
	len += Format(query[len], sizeof(query)-len, "`cc` varchar(2),");
	len += Format(query[len], sizeof(query)-len, "`connect_time` int(11),");
	len += Format(query[len], sizeof(query)-len, "`disconnect_time` int(11),");
	len += Format(query[len], sizeof(query)-len, "`playtime` int(11) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`kills` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`deaths` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`assists` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`feigns` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`dominations` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`revenges` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`headshots` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`backstabs` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`obj_built` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`obj_destroy` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`tele_player` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`flag_pick` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`flag_cap` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`flag_def` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`flag_drop` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`cp_cap` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`cp_block` int(6) DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "PRIMARY KEY (`id`), UNIQUE KEY `auth` (`auth`)) ENGINE=InnoDB  DEFAULT CHARSET=utf8;");
	SQL_FastQuery(g_dbKill, query);
}

createDBTeamLog() {
	new len = 0;
	decl String:query[1024];
	len += Format(query[len], sizeof(query)-len, "CREATE TABLE IF NOT EXISTS `teamlog` (");
	len += Format(query[len], sizeof(query)-len, " `capper` varchar(20) DEFAULT NULL,");
	len += Format(query[len], sizeof(query)-len, " `cteam` tinyint(1) DEFAULT NULL,");
	len += Format(query[len], sizeof(query)-len, " `cclass` tinyint(1) DEFAULT NULL,");
	len += Format(query[len], sizeof(query)-len, " `defender` varchar(20) DEFAULT NULL,");
	len += Format(query[len], sizeof(query)-len, " `dteam` tinyint(1) DEFAULT NULL,");
	len += Format(query[len], sizeof(query)-len, " `dclass` tinyint(1) DEFAULT NULL,");
	len += Format(query[len], sizeof(query)-len, " `killtime` int(11) DEFAULT NULL,");
	len += Format(query[len], sizeof(query)-len, " `event` varchar(20) DEFAULT NULL,");
	len += Format(query[len], sizeof(query)-len, " `map` varchar(32) DEFAULT NULL,");
	len += Format(query[len], sizeof(query)-len, " KEY `capper` (`capper`),");
	len += Format(query[len], sizeof(query)-len, " KEY `defender` (`defender`),");
	len += Format(query[len], sizeof(query)-len, " KEY `killtime` (`killtime`),");
	len += Format(query[len], sizeof(query)-len, " KEY `event` (`event`),");
	len += Format(query[len], sizeof(query)-len, " KEY `map` (`map`)");
	len += Format(query[len], sizeof(query)-len, ") ENGINE=InnoDB DEFAULT CHARSET=utf8;");
	SQL_FastQuery(g_dbKill, query);
}

createDBObjectLog() {
	new len = 0;
	decl String:query[1024];
	len += Format(query[len], sizeof(query)-len, "CREATE TABLE IF NOT EXISTS `objectlog` (");
	len += Format(query[len], sizeof(query)-len, "`attacker` varchar(20) CHARACTER SET utf8 NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`ateam` tinyint(1) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`aclass` tinyint(1) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`victim` varchar(20) CHARACTER SET utf8 NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`vteam` tinyint(1) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`vclass` tinyint(1) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`weapon` varchar(25) CHARACTER SET utf8 NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`killtime` int(11) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`object` varchar(25) CHARACTER SET utf8 NOT NULL,");
	len += Format(query[len], sizeof(query)-len, " KEY `attacker` (`attacker`),");
	len += Format(query[len], sizeof(query)-len, " KEY `victim` (`victim`),");
	len += Format(query[len], sizeof(query)-len, " KEY `weapon` (`weapon`),");
	len += Format(query[len], sizeof(query)-len, " KEY `killtime` (`killtime`),");
	len += Format(query[len], sizeof(query)-len, " KEY `object` (`object`)");
	len += Format(query[len], sizeof(query)-len, ") ENGINE=InnoDB DEFAULT CHARSET=utf8;");
	SQL_FastQuery(g_dbKill, query);
}

createDBMapLog() {
	new len = 0;
	decl String:query[1024];
	len += Format(query[len], sizeof(query)-len, "CREATE TABLE IF NOT EXISTS `maplog` (");
	len += Format(query[len], sizeof(query)-len, "`name` varchar(32) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`kills` int(11) NOT NULL,");
	len += Format(query[len], sizeof(query)-len, "`assists` int(11) NOT NULL DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`dominations` int(11) NOT NULL DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`revenges` int(11) NOT NULL DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`flag_pick` int(11) NOT NULL DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`flag_cap` int(11) NOT NULL DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`flag_def` int(11) NOT NULL DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`flag_drop` int(11) NOT NULL DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`cp_captured` int(11) NOT NULL DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`cp_blocked` int(11) NOT NULL DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "`playtime` int(11) NOT NULL DEFAULT '0',");
	len += Format(query[len], sizeof(query)-len, "UNIQUE KEY `name` (`name`)");
	len += Format(query[len], sizeof(query)-len, ") ENGINE=InnoDB DEFAULT CHARSET=utf8;");
	SQL_FastQuery(g_dbKill, query);
}
