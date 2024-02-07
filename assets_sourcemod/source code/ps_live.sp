/**
 * =============================================================================
 * SourceMod PsychoStats Plugin
 * Implements "PsychoLive" for Psychostats.
 *
 * This plugin records a game into the PsychoStats database for real-time 
 * viewing or playback at any other time.
 *
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Version: $Id: ps_live.sp 564 2008-10-10 12:26:35Z lifo $
 * Author: Stormtrooper
 * 
 */

#define DEBUG 	0

#pragma semicolon 1
#pragma dynamic 131072
#include <sdktools>
#include <sourcemod>

const ENT_NULL		= 0;
const ENT_UNKNOWN 	= 1;
const ENT_PLAYER	= 2;
const ENT_BOT		= 3;

enum T_PLRSTATS {
	PLR_GAMEID	= 0,
	PLR_UID		= 1,
	PLR_TYPE	= 2, 
	PLR_KILLS	= 3,
	PLR_DEATHS	= 4,
	PLR_SUICIDES	= 5,
	PLR_HEALTH	= 6,
	PLR_TEAM	= 7
}
const T_PLRSTATS_SIZE 	= 8;

// cached player info
const MAXPLRS = 64;
new plr_stats[MAXPLRS][T_PLRSTATS_SIZE];	// basic player stats (kills, deaths)

// global handles for our environment
new Handle:hDatabase		= INVALID_HANDLE;
new Handle:hRecording		= INVALID_HANDLE;
new Handle:pendingEvents	= INVALID_HANDLE; 	// datapack handle for events
new Handle:pendingEnts		= INVALID_HANDLE;	// datapack handle for new entities
new Handle:pendingEntUpdates	= INVALID_HANDLE;	// datapack handle for entities
new pendingEventSize		= 0;
new pendingEntSize 		= 0;
new pendingEntUpdateSize	= 0;

// global vars to help track certain items in our environment
new bool:roundActive 		= false;
new bool:mapActive		= false;
new gameID			= 0;		// the current game_id being recorded
new eventIDX			= -1;		// the current event IDX for the game
new String:currentMap[32]	= "";		// the current map being played
new String:gamename[32]		= "";		// the game name
new String:dbTblPrefix[17] 	= "ps_";	// table prefix for psychostats database tables

// keep track of our cvars
new Handle:cv_enabled		= INVALID_HANDLE;	// is recording active?
new Handle:cv_interval		= INVALID_HANDLE;	// recording interval in seconds
new Handle:cv_attack		= INVALID_HANDLE;	// record attack damage?
new Handle:cv_c4timer		= INVALID_HANDLE;	// mp_c4timer

new bool:ps_enabled		= true;
new bool:ps_attack		= true;
new Float:ps_interval		= 1.0;


public Plugin:myinfo = {
        name = "PsychoStats (PsychoLive) Plugin",
        author = "Stormtrooper",
        description = "Records game play for real-time and pre-recorded playback using PsychoLive from PsychoStats.",
        version = "1.0"
};

public OnPluginStart() {
	decl String:game[128];
	GetGameDescription(game, sizeof(game), true);
	// determine the mod playing by checking the game description. This way
	// if the game folder is changed on a server it won't cause problems.
	if (StrContains(game, "Counter-Strike") != -1) {
		gamename = "cstrikes";
	} else if (StrContains(game, "Team Fortress") != -1) {
		gamename = "tf2";
	} else if (StrContains(game, "Day of Defeat") != -1) {
		gamename = "dods";
	} else if (StrContains(game, "Battle Grounds") != -1) {
		gamename = "bg3";
	} else {
		GetGameFolderName(gamename, sizeof(gamename));
	}
	PrintToServer("Game Description = '%s' (%s)", game, gamename);

	// setup our ConVar's
	cv_enabled 	= CreateConVar("ps_enabled", "1", "Enable or disable PsychoLive game recordings (1 to enable; 0 to disable)");
	cv_interval 	= CreateConVar("ps_interval", "1.0", "Specifies the update interval in seconds for PsychoLive recordings.", _, true, 1.0, true, 5.0);
	cv_attack 	= CreateConVar("ps_attack", "1", "Should attack damage be recorded by PsychoLive? (1 to enable; 0 to disable)");
	HookConVarChange(cv_enabled, OnConVarChange);
	HookConVarChange(cv_interval, OnConVarChange);
	HookConVarChange(cv_attack, OnConVarChange);

	ps_enabled = GetConVarBool(cv_enabled);
	ps_interval = GetConVarFloat(cv_interval);
	ps_attack = GetConVarBool(cv_attack);

	if (ps_enabled) {
		// Initialize SQL
		// If it fails, we won't bother registering any hooks, etc.
		if (!StartSQL()) {
			return;
		}

		// setup the dataPack to hold our pending events and entities
		pendingEvents = CreateDataPack();
		pendingEnts = CreateDataPack();
		pendingEntUpdates = CreateDataPack();

		// Setup our various hooks to watch for player events
		HookEvent("round_start", Event_round);
		HookEvent("round_end", Event_round);
//		HookEvent("player_disconnect", Event_player_disconnect, EventHookMode_Pre);
		HookEvent("player_death", Event_player_death);
		HookEvent("player_team", Event_player_team);
		HookEvent("player_spawn", Event_player_spawn);
		HookEvent("player_changename", Event_player_changename);
		if (strcmp(gamename, "cstrikes") == 0) {
			HookEvent("bomb_pickup", Event_player_bomb);
			HookEvent("bomb_dropped", Event_player_bomb);
			HookEvent("bomb_planted", Event_player_bomb);
			HookEvent("bomb_defused", Event_player_bomb);
			HookEvent("bomb_exploded", Event_player_bomb);

			// monitor the C4 timer
			cv_c4timer = FindConVar("mp_c4timer");
		} else if (strcmp(gamename, "tf2") == 0) {
			HookEvent("teamplay_round_start", Event_round);
			HookEvent("teamplay_round_win", Event_round);
			HookEvent("teamplay_round_stalemate", Event_round);
			HookEvent("player_builtobject", Event_player_built);
			HookEvent("player_changeclass", Event_player_class);
		} else if (strcmp(gamename, "dods") == 0) {
			
		} else if (strcmp(gamename, "bg3") == 0) {
			
		}
		
		if (ps_attack) {
			HookEvent("player_hurt", Event_player_hurt);
		}
	
		// Start interval timer to save player events
		hRecording = CreateTimer(ps_interval, Timer_Record, _, TIMER_REPEAT);
	}
}

public OnConVarChange(Handle:cvar, const String:old[], const String:value[]) {
	if (cvar == cv_enabled) {
		// changes to this cvar aren't actually acted upon yet
		ps_enabled = (StringToInt(value) != 0);
	} else if (cvar == cv_interval) {
		new Float:newint = StringToFloat(value);
		if (newint >= 0.5 && newint <= 5.0) {
			ps_interval = newint;
			KillTimer(hRecording);
			PrintToServer("[PSLIVE] PsychoLive recording interval changed to %0.1f seconds", ps_interval);
			hRecording = CreateTimer(ps_interval, Timer_Record, _, TIMER_REPEAT);
		} else {
			PrintToServer("[PSLIVE] ps_interval must be between 0.5 - 5.0 seconds");
		}
	} else if (cvar == cv_attack) {
		ps_attack = (StringToInt(value) != 0);
		if (ps_attack) {
			PrintToServer("[PSLIVE] PsychoLive will record player attack damage.");
			HookEvent("player_hurt", Event_player_hurt);
		} else {
			PrintToServer("[PSLIVE] PsychoLive will no longer record player attack damage.");
			UnhookEvent("player_hurt", Event_player_hurt);
		}
	}
}

// A new map is loaded
public OnMapStart() {
	if (mapActive) {
		endMap();
	}
	startMap();
}

// A map has ended and is closed
public OnMapEnd() {
	if (mapActive) {
		endMap();
	}
}

public OnClientPutInServer(client) {

	plr_stats[client][PLR_GAMEID]	= gameID;
	plr_stats[client][PLR_UID]	= GetClientUserId(client);
	plr_stats[client][PLR_TYPE]	= IsFakeClient(client) ? ENT_BOT : ENT_PLAYER;
	plr_stats[client][PLR_KILLS]	= 0;
	plr_stats[client][PLR_DEATHS]	= 0;
	plr_stats[client][PLR_SUICIDES]	= 0;
	plr_stats[client][PLR_HEALTH]	= 100;
	plr_stats[client][PLR_TEAM]	= GetClientTeam(client);

	createPlayerEntity(client);

	// get the player's name
	new String:plrname[512];
	GetClientName(client, plrname, sizeof(plrname));
	ReplaceString(plrname, sizeof(plrname), "\\", "\\\\");
	ReplaceString(plrname, sizeof(plrname), "\"", "\\\"");
//	new plrnameLen = strlen(plrname) * 2 + 1;
//	new String:Q_plrname[plrnameLen];
//	SQL_QuoteString(hDatabase, plrname, Q_plrname, plrnameLen);

	// get the player's IP address
	new String:ipaddr[17];
	GetClientIP(client, ipaddr, sizeof(ipaddr), true);

	// build a json structure for the player info so this player can be
	// initialized in the front-end w/o having to do a separate request.
	decl String:json[255];
	Format(json, sizeof(json), "{\"ent_type\":%d,\"ent_name\":\"%s\",\"ent_ip\":\"%s\"}",
	       plr_stats[client][PLR_TYPE],
	       plrname,
	       ipaddr
	);

	new jsonLen = strlen(json) * 2 + 1;
	new String:Q_json[jsonLen];
	SQL_QuoteString(hDatabase, json, Q_json, jsonLen);

	// build our player query
	decl String:query[300];
	Format(query, sizeof(query), "(%d,%d,%d,'PLR_CONNECT',%d,NULL,NULL,NULL,NULL,'%s')",
		gameID,
		++eventIDX,
		GetTime(),
		plr_stats[client][PLR_UID],
		Q_json
	);

#if DEBUG
	PrintToServer("OnClientPutInServer: %s", query);
#endif

	WritePackString(pendingEvents, query);
	pendingEventSize += strlen(query);
}

// a player disconnected
public OnClientDisconnect(client) {
//public Action:Event_player_disconnect(Handle:event, const String:name[], bool:dontBroadcast) {
//	// get player UID (1 .. infinity)
//	new userid = GetEventInt(event, "userid");
//	// get client ID (1 .. maxplayers)
//	new client = GetClientOfUserId(userid);

	savePlayerEntity(client);

	// build our player query
	decl String:query[255];
	Format(query, sizeof(query), "(%d,%d,%d,'PLR_DISCONNECT',%d,NULL,NULL,NULL,NULL,NULL)",
		gameID,
		++eventIDX,
		GetTime(),
		plr_stats[client][PLR_UID]
	);

#if DEBUG
	PrintToServer("OnClientDisconnect: %s", query);
#endif

	WritePackString(pendingEvents, query);
	pendingEventSize += strlen(query);
	
	// clear cached player data
	plr_stats[client][PLR_GAMEID]	= 0;
	plr_stats[client][PLR_UID]	= 0;
	plr_stats[client][PLR_TYPE]	= ENT_UNKNOWN;
	plr_stats[client][PLR_KILLS]	= 0;
	plr_stats[client][PLR_DEATHS]	= 0;
	plr_stats[client][PLR_SUICIDES]	= 0;
	plr_stats[client][PLR_HEALTH]	= 0;
	
//	return Plugin_Continue;
}

// A round started or ended
public Action:Event_round(Handle:event, const String:name[], bool:dontBroadcast) {
	PrintToServer("ROUND EVENT: %s", name);

	// end a previous round if it was active already
	if (roundActive) {
		endRound();
	}

	// initialize the new round
	if (StrContains(name, "round_start") != -1) {
		startRound();
	}
	
	return Plugin_Continue;
}

// A player died
public Action:Event_player_death(Handle:event, const String:name[], bool:dontBroadcast) {
	// get player UID's (1 .. infinity)
	new victim_id = GetEventInt(event, "userid");
	new attacker_id = GetEventInt(event, "attacker");
        new bool:headshot = GetEventBool(event, "headshot");

	// get client ID's (1 .. maxplayers)
	new victim = GetClientOfUserId(victim_id);
	new attacker = GetClientOfUserId(attacker_id);

	new bool:suicide = (victim_id == attacker_id);

	plr_stats[victim][PLR_DEATHS]++;
	if (suicide) {
		plr_stats[victim][PLR_SUICIDES]++;
	} else {
		plr_stats[attacker][PLR_KILLS]++;
	}
	
	// get the attacker's weapon and strip off 'weapon_' in front of it.
	decl String:weapon[32];
	if (attacker) {
		GetClientWeapon(attacker, weapon, sizeof(weapon));
		ReplaceString(weapon, sizeof(weapon), "weapon_", "");
	} else {
		attacker_id = victim_id;
		weapon = "world";
	}
	new weaponLen = strlen(weapon) * 2 + 1;
	new String:Q_weapon[weaponLen];
	SQL_QuoteString(hDatabase, weapon, Q_weapon, weaponLen);

	// build our query
	decl String:query[255];
	Format(query, sizeof(query), "(%d,%d,%d,'PLR_KILL',%d,%d,NULL,'%s',%s,NULL)",
		gameID,
		++eventIDX,
		GetTime(),
		attacker_id,	// UID
		victim_id,	// UID
		Q_weapon,
		headshot ? "'1'" : "NULL"
	);

#if DEBUG
	PrintToServer("player_death: %s", query);
#endif

	WritePackString(pendingEvents, query);
	pendingEventSize += strlen(query);
	
	return Plugin_Continue;
}

// A player attacked someone else
public Action:Event_player_hurt(Handle:event, const String:name[], bool:dontBroadcast) {
	// current health of the victim
	new health = GetEventInt(event, "health");
	
	// get player UID's (1 .. infinity)
	new victim_id = GetEventInt(event, "userid");
	new attacker_id = GetEventInt(event, "attacker");

	// sometimes the attacker is 0, and I'm not sure why. It doesn't
	// appear to be 'self' inflicted damage either...
	// So we'll just ignore for this now.
	if (!attacker_id) {
		return Plugin_Continue;
	}

	// get client ID's (1 .. maxplayers)
	new victim = GetClientOfUserId(victim_id);
	new attacker = GetClientOfUserId(attacker_id);

//	new bool:hurtself = (victim_id == attacker_id);
//	new bool:hurtteam = (!hurtself && GetClientTeam(victim) == GetClientTeam(attacker));
	new dmg;
	if (strcmp(gamename, "cstrikes") == 0 || strcmp(gamename, "tf2") == 0) {
		dmg = GetEventInt(event, "dmg_health");
	} else if (strcmp(gamename, "dods") == 0) {
		dmg = GetEventInt(event, "damage");
	} else {
		dmg = plr_stats[victim][PLR_HEALTH] - health;
	}

	//PrintToServer("victim(%02d) :: %3d, %3d, %3d",
	//	victim,
	//	health,
	//	dmg,
	//	GetClientArmor(victim)
	//);

	// track the player's current health
	plr_stats[victim][PLR_HEALTH] = health;

	// get the attacker's weapon and strip off 'weapon_' in front of it.
	decl String:weapon[64];
	GetClientWeapon(attacker, weapon, sizeof(weapon));
	ReplaceString(weapon, sizeof(weapon), "weapon_", "");
	new weaponLen = strlen(weapon) * 2 + 1;
	new String:Q_weapon[weaponLen];
	SQL_QuoteString(hDatabase, weapon, Q_weapon, weaponLen);

	// build our query
	decl String:query[255];
	Format(query, sizeof(query), "(%d,%d,%d,'PLR_HURT',%d,%d,NULL,'%s','%d',NULL)",
		gameID,
		++eventIDX,
		GetTime(),
		attacker_id,	// UID
		victim_id,	// UID
		Q_weapon,
		dmg
	);

#if DEBUG
//	PrintToServer("player_hurt: %s", query);
#endif

	WritePackString(pendingEvents, query);
	pendingEventSize += strlen(query);
	
	return Plugin_Continue;
}

// A player spawned
public Action:Event_player_spawn(Handle:event, const String:name[], bool:dontBroadcast) {
	// get player UID (1 .. infinity)
	new userid = GetEventInt(event, "userid");
	// get client ID (1 .. maxplayers)
	new client = GetClientOfUserId(userid);

	// Get player location coordinates
	decl Float:vec[3], String:xyz[21];
	GetClientAbsOrigin(client, vec);
	// Do not record the spawn if the player spawns in the center.
	// TF does this, and it's annoying to see a player dot appear on the
	// map before they even join a team.
	if (vec[0] == 0 && vec[1] == 0) {
		return Plugin_Continue;
	}
	Format(xyz, sizeof(xyz), "%d %d %d", RoundFloat(vec[0]), RoundFloat(vec[1]), RoundFloat(vec[2]));

	// build our query
	decl String:query[255];
	Format(query, sizeof(query), "(%d,%d,%d,'PLR_SPAWN',%d,NULL,'%s',NULL,NULL,NULL)",
		gameID,
		++eventIDX,
		GetTime(),
		userid,		// UID
		xyz
	);

#if DEBUG
	PrintToServer("player_spawn: %s", query);
#endif

	WritePackString(pendingEvents, query);
	pendingEventSize += strlen(query);
	
	return Plugin_Continue;
}

// A player changed teams
public Action:Event_player_team(Handle:event, const String:name[], bool:dontBroadcast) {
	// get player UID (1 .. infinity)
	new userid = GetEventInt(event, "userid");
	// get client ID (1 .. maxplayers)
	new client = GetClientOfUserId(userid);

	new team = GetEventInt(event, "team");

	// do not record the team if it's 0. I notice this occurs right after
	// a player disconnects and serves no actual purpose and actually
	// messes up the playback in the front-end.
	if (team == 0) {
		return Plugin_Continue;
	}

	plr_stats[client][PLR_TEAM] = team;

	// don't save the player entity here anymore, its not useful and just
	// causes a delay for the rest of the events being inserted...
	//savePlayerEntity(client);
	
	// build our query
	decl String:query[255];
	Format(query, sizeof(query), "(%d,%d,%d,'PLR_TEAM',%d,NULL,NULL,NULL,'%d',NULL)",
		gameID,
		++eventIDX,
		GetTime(),
		userid,		// UID
		team
	);

#if DEBUG
	PrintToServer("player_team: %s", query);
#endif

	WritePackString(pendingEvents, query);
	pendingEventSize += strlen(query);
	
	return Plugin_Continue;
}

// A player changed their class
public Action:Event_player_class(Handle:event, const String:name[], bool:dontBroadcast) {
	// get player UID (1 .. infinity)
	new userid = GetEventInt(event, "userid");
	// get client ID (1 .. maxplayers)
//	new client = GetClientOfUserId(userid);

	new class = GetEventInt(event, "class");
	if (class == 0) {
		return Plugin_Continue;
	}
	
	// build our query
	decl String:query[255];
	Format(query, sizeof(query), "(%d,%d,%d,'PLR_CLASS',%d,NULL,NULL,NULL,'%d',NULL)",
		gameID,
		++eventIDX,
		GetTime(),
		userid,		// UID
		class
	);

#if DEBUG
	PrintToServer("player_class: %s", query);
#endif

	WritePackString(pendingEvents, query);
	pendingEventSize += strlen(query);
	
	return Plugin_Continue;
}

// A player changed their name
public Action:Event_player_changename(Handle:event, const String:name[], bool:dontBroadcast) {
	// get player UID (1 .. infinity)
	new userid = GetEventInt(event, "userid");
	decl String:newname[255];
	GetEventString(event, "newname", newname, sizeof(newname));
	
	// get client ID (1 .. maxplayers)
//	new client = GetClientOfUserId(userid);

	new newnameLen = strlen(newname) * 2 + 1;
	new String:Q_newname[newnameLen];
	SQL_QuoteString(hDatabase, newname, Q_newname, newnameLen);

	// build our query
	decl String:query[255];
	Format(query, sizeof(query), "(%d,%d,%d,'PLR_NAME',%d,NULL,NULL,NULL,'%s',NULL)",
		gameID,
		++eventIDX,
		GetTime(),
		userid,		// UID
		Q_newname
	);

#if DEBUG
	PrintToServer("player_changename: %s", query);
#endif

	WritePackString(pendingEvents, query);
	pendingEventSize += strlen(query);
	
	return Plugin_Continue;
}

// A player built an object (turrets, etc)
public Action:Event_player_built(Handle:event, const String:name[], bool:dontBroadcast) {
	// get player UID (1 .. infinity)
	new userid = GetEventInt(event, "userid");
	// get client ID (1 .. maxplayers)
	new client = GetClientOfUserId(userid);
	new obj = GetEventInt(event, "object");

	PrintToServer("Player '%d' built '%d'", client, obj);

	return Plugin_Continue;
}

// A player picked up the bomb
public Action:Event_player_bomb(Handle:event, const String:name[], bool:dontBroadcast) {
	// get player UID (1 .. infinity)
	new userid = GetEventInt(event, "userid");
	// get client ID (1 .. maxplayers)
	//new client = GetClientOfUserId(userid);

	new String:value[10] = "NULL";
	new String:xyz[23] = "NULL";
	if (strcmp(gamename, "cstrikes") == 0) {
		if (strcmp(name, "bomb_planted") == 0) {
			// CSTRIKE: record the c4 timer so we can display a countdown
			Format(value, sizeof(value), "'%d'", GetConVarInt(cv_c4timer));
			Format(xyz, sizeof(xyz), "'%d %d 0'", GetEventInt(event, "posx"), GetEventInt(event, "posy"));
		} else if (strcmp(name, "bomb_dropped") == 0) {
			decl Float:vec[3];
			new client = GetClientOfUserId(userid);
			GetClientAbsOrigin(client, vec);
			Format(xyz, sizeof(xyz), "'%d %d %d'", RoundFloat(vec[0]), RoundFloat(vec[1]), RoundFloat(vec[2]));
		}
	}
	
	decl String:query[200];
	Format(query, sizeof(query), "(%d,%d,%d,'PLR_%s',%d,NULL,%s,NULL,%s,NULL)",
		gameID,
		++eventIDX,
		GetTime(),
		name,		// event_type
		userid,		// UID
		xyz,
		value
	);
	
#if DEBUG
	PrintToServer("Event_player_bomb: %s", query);
#endif

	WritePackString(pendingEvents, query);
	pendingEventSize += strlen(query);
	
	return Plugin_Continue;
}

// called every 'X' seconds to record player movement and send event queries
// to the database.
public Action:Timer_Record(Handle:timer) {
	new maxplayers = GetClientCount();
	// nothing to do if no players are connected or if we don't have a gameID yet...
	if (maxplayers == 0 || !gameID || !roundActive) {
		// make sure the pending events queue is empty ... 
		dumpSQL();
		return Plugin_Continue;
	}

	new time = GetTime();
	new i, uid;
	decl String:query[128], Float:vec[3], String:xyz[21], String:ang[21];

	// loop through all connected players and track their current location
        for (i=1; i <= maxplayers; i++) {
		// Ignore those not actually connected or observing.
		// Dead players are observing.
		// BOTS are "fake" clients.
		if (!IsClientInGame(i) || IsClientObserver(i)) {
			continue;
		}

		// Get user and client ID
		uid = GetClientUserId(i);		// 1 .. infinity (UID)
//		client = GetClientOfUserId(uid);	// 1 .. maxplayers (slot #)


		// If the player has not been created yet we do so here.
		// This assures that our asyncronous inserts and updates are
		// properly maintained from player connections.
		if (plr_stats[i][PLR_GAMEID] == 0) {
			createPlayerEntity(i);
		}

		// Get player location coordinates
		GetClientAbsOrigin(i, vec);
		Format(xyz, sizeof(xyz), "%d %d %d", RoundFloat(vec[0]), RoundFloat(vec[1]), RoundFloat(vec[2]));

		// Get player direction
		//GetClientEyeAngles(i, vec);
		//decl Float:vec2[3];
		//GetVectorAngles(vec, vec2);
//		Format(ang, sizeof(ang), "%d %d", RoundFloat(vec2[0]), RoundFloat(vec2[1]), RoundFloat(vec[2]));
		GetClientAbsAngles(i, vec);
		Format(ang, sizeof(ang), "%d",RoundFloat(vec[1]));

		// add player movement to query
		Format(query, sizeof(query), "(%d,%d,%d,'PLR_MOVE',%d,NULL,'%s',NULL,'%s',NULL)",
			gameID,
			++eventIDX,
			time,
			uid,
			xyz,
			ang
		);
		
		WritePackString(pendingEvents, query);
		pendingEventSize += strlen(query);

#if DEBUG
		//// Get player team
		//decl String:team[32];
		//GetTeamName(GetClientTeam(i), team, sizeof(team));
		//PrintToServer("%2u [%4u] (%5i, %5i, %5i) %c %9s K %2u D %2u",
		//	      i, uid,
		//	      RoundFloat(vec[0]), RoundFloat(vec[1]), RoundFloat(vec[2]),
		//	      IsPlayerAlive(i) ? 'A' : ' ',
		//	      team, plr_stats[i][PLR_KILLS], plr_stats[i][PLR_DEATHS]
		//);
		//if (i == maxplayers) {
		//	PrintToServer("");
		//}
#endif

		/* Get map name */
		//decl String:map[64];
		//GetCurrentMap(map, sizeof(map));
	}

	dumpSQL();
	
	return Plugin_Continue;
}

// send SQL to server for insertion
stock dumpSQL() {
	ResetPack(pendingEvents);
	ResetPack(pendingEnts);
	ResetPack(pendingEntUpdates);

	new len;
	// I thought dynamic arrays would work, but apparently the below doesn't...
	// the query string gets cut off. So I set a large buffer (which sucks)
	// to handle virtually any amount of events.
	new size = 30000; //pendingEventSize + 1;
	decl String:query[size], String:event[300];

	if (IsPackReadable(pendingEvents, 1)) {
		len = Format(query, size, "INSERT INTO %slive_events VALUES ", dbTblPrefix);
		while (IsPackReadable(pendingEvents, 1)) {
			ReadPackString(pendingEvents, event, sizeof(event));
			len += StrCat(query, size, event);
			len += StrCat(query, size, ",");
		}
		ResetPack(pendingEvents, true);		// clear the datapack queue
		pendingEventSize = 0;
		query[len-1] = '\0';			// remove the trailing comma ','
		SQL_TQuery(hDatabase, T_generic, query);
	}

	// now dump the pending entity data
	if (IsPackReadable(pendingEnts, 1)) {
		len = Format(query, size, "INSERT INTO %slive_entities (game_id,ent_id,ent_type,ent_name,ent_team) VALUES ", dbTblPrefix);
		while (IsPackReadable(pendingEnts, 1)) {
			ReadPackString(pendingEnts, event, sizeof(event));
			len += StrCat(query, size, event);
			len += StrCat(query, size, ",");
		}
		ResetPack(pendingEnts, true);		// clear the datapack queue
		pendingEntSize = 0;
		query[len-1] = '\0';			// remove the trailing comma ','
		SQL_TQuery(hDatabase, T_generic, query);
	}

	// now dump the pending updated entity data
	if (IsPackReadable(pendingEntUpdates, 1)) {
		while (IsPackReadable(pendingEntUpdates, 1)) {
			ReadPackString(pendingEntUpdates, event, sizeof(event));
			Format(query, size, "UPDATE %slive_entities SET %s", dbTblPrefix, event);
			SQL_TQuery(hDatabase, T_generic, query);
		}
		ResetPack(pendingEntUpdates, true);	// clear the datapack queue
		pendingEntUpdateSize = 0;
	}
	
	
#if DEBUG
//	PrintToServer("QUERY SIZE: %d (%d)", strlen(query), size);
#endif
}

// initializes our SQL connection
public bool:StartSQL() {
	// read databases.cfg so we can discover the table prefix to use
	new String:dbfile[255];
	BuildPath(Path_SM, dbfile, sizeof(dbfile), "configs/databases.cfg");
	new Handle:kv = CreateKeyValues("Databases");
	FileToKeyValues(kv, dbfile);
	if (KvJumpToKey(kv, "psychostats")) {
		KvGetString(kv, "tableprefix", dbTblPrefix, sizeof(dbTblPrefix), dbTblPrefix);
	} else {
		// if psychostats doesn't exist use the default prefix 'ps_'
		LogToGame("[PSLIVE] \"psychostats\" DB config not found in %s", dbfile);
	}
	CloseHandle(kv);

//        SQL_TConnect(DB_Connected, "psychostats");
	// I don't use a thread to connect since there can be a delay in
	// connecting which will cause the first map to sometimes load before
	// our connection is established so you end up losing that game.
	new String:error[255];
	hDatabase = SQL_Connect("psychostats", true, error, sizeof(error));
	if (hDatabase == INVALID_HANDLE) {
		LogError("[PSLIVE] Could not connect to psychostats DB: %s", error);
		return false;
	}
	return true;
}

//public DB_Connected(Handle:owner, Handle:hndl, const String:error[], any:data) {
//        if (hndl == INVALID_HANDLE)
//        {
//                LogError("[PSLIVE] Database failure: %s", error);
//        } else {
//                hDatabase = hndl;
//        }
//}

// makes sure the current round data is saved
endRound() {
	roundActive = false;

	// build our query
	decl String:query[128];
	Format(query, sizeof(query), "(%d,%d,%d,'ROUND_END',NULL,NULL,NULL,NULL,NULL,NULL)",
		gameID,
		++eventIDX,
		GetTime()
	);

#if DEBUG
	PrintToServer("endRound: %s", query);
#endif

	WritePackString(pendingEvents, query);
	pendingEventSize += strlen(query);
}

startRound() {
	if (!gameID) {
		return;
	}
	roundActive = true;

	// update the health of all players
	// since I'm not sure if all mods use 100 for max health I do this...
	new maxplayers = GetClientCount();
	new i, uid, client;
        for (i=1; i <= maxplayers; i++) {
		if (IsClientConnected(i)) {
			// Get user and client ID
			uid = GetClientUserId(i);		// 1 .. infinity (UID)
			client = GetClientOfUserId(uid);	// 1 .. maxplayers (slot #)
			plr_stats[client][PLR_HEALTH] = GetClientHealth(client);
		}
	}

	// get map time left
	new timeleft = -1;
	GetMapTimeLeft(timeleft);
	
	// build our query
	decl String:query[100];
	Format(query, sizeof(query), "(%d,%d,%d,'ROUND_START',NULL,NULL,NULL,NULL,'%d',NULL)",
		gameID,
		++eventIDX,
		GetTime(),
		timeleft
	);

#if DEBUG
	PrintToServer("startRound: %s", query);
#endif

	WritePackString(pendingEvents, query);
	pendingEventSize += strlen(query);
}



// makes sure the current game data is saved
endMap() {
	// update the name of the server when the map ends. On the very first
	// game recorded the hostname of the server ends up being the default
	// instead of what is configured in server.cfg. I assume that's
	// because the configs haven't fully loaded before startMap() on the
	// first load.
	new String:hostname[255];
	GetConVarString(FindConVar("hostname"), hostname, sizeof(hostname));
	new hostnameLen = strlen(hostname) * 2 + 1;
	new String:Q_hostname[hostnameLen];
	SQL_QuoteString(hDatabase, hostname, Q_hostname, hostnameLen);

	// update the ending time of the game
	decl String:query[255];
	Format(query, sizeof(query), "UPDATE %slive_games SET end_time=%d, server_name='%s' WHERE game_id=%d",
		dbTblPrefix,
		GetTime(),
		Q_hostname,
		gameID
	);
#if DEBUG
	PrintToServer("Ending recording: %s", query);
#endif

	SQL_TQuery(hDatabase, T_generic, query);

	mapActive = false;
	gameID = 0;
	currentMap = "";
}

// starts recording a new game map
startMap() {
	// reset the event index counter and get our current map
	eventIDX = -1;
	GetCurrentMap(currentMap, sizeof(currentMap));

	// get server IP:port
	new Q_hostip = GetConVarInt(FindConVar("hostip"));
	new Q_hostport = GetConVarInt(FindConVar("hostport"));

	// get server name
	new String:hostname[255];
	GetConVarString(FindConVar("hostname"), hostname, sizeof(hostname));
	new hostnameLen = strlen(hostname) * 2 + 1;
	new String:Q_hostname[hostnameLen];
	SQL_QuoteString(hDatabase, hostname, Q_hostname, hostnameLen);

	// game mod type
	new gamenameLen = strlen(gamename) * 2 + 1;
	new String:Q_gamename[gamenameLen];
	SQL_QuoteString(hDatabase, gamename, Q_gamename, gamenameLen);
 
	// get current map
	new currentMapLen = strlen(currentMap) * 2 + 1;
	new String:Q_currentMap[currentMapLen];
	SQL_QuoteString(hDatabase, currentMap, Q_currentMap, currentMapLen);
 
	// Start a new recording for the game
	decl String:query[255];
	Format(query, sizeof(query), "INSERT INTO %slive_games (start_time,server_ip,server_port,server_name,gametype,modtype,map) VALUES (%d,%d,%d,'%s','halflife','%s','%s')",
		dbTblPrefix,
		GetTime(),
		Q_hostip,
		Q_hostport,
		Q_hostname,
		Q_gamename,
		Q_currentMap
	);
#if DEBUG
	PrintToServer("Starting new recording: %s", query);
#endif

	// I don't use a threaded query here so we can garauntee that we will
	// have a valid gameID before any players events occur. Even if the
	// SQL server responds slowly it'll only have a small delay at the
	// start of the map and shouldn't really be noticable by players.
	SQL_LockDatabase(hDatabase);
	if (!SQL_FastQuery(hDatabase, query)) {
		new String:error[255];
		SQL_GetError(hDatabase, error, sizeof(error));
		LogError("[PSLIVE] Error starting recording: %s", error);
	} else {
		gameID = SQL_GetInsertId(hDatabase);
		if (gameID) {
			mapActive = true;
			PrintToServer("This game is being recorded by PsychoLive! (GameID %d)", gameID);
			CreateTimer(5.0, Advertise);
		} else {
			PrintToServer("Error fetching GameID from database!");
		}
	}
	SQL_UnlockDatabase(hDatabase);

	// threaded query ....
	//new Handle:dp = CreateDataPack();
	//WritePackString(dp, currentMap);
	//ResetPack(dp);
	//SQL_TQuery(hDatabase, T_startMap, query, dp);
}

//public T_startMap(Handle:owner, Handle:hndl, const String:error[], any:data) {
//	decl String:map[64];
//	ReadPackString(data, map, sizeof(map));
//	if (hndl == INVALID_HANDLE) {
//		LogError("[PSLIVE] Error starting recording: %s", error);
//	} else if (strlen(currentMap) != 0 && !StrEqual(map,currentMap)) {
//		// make sure the map hasn't changed since the query was sent.
//		// do nothing if it's changed. The game will remain empty
//		// in the database.
//	} else {
//		gameID = SQL_GetInsertId(owner);
//		if (gameID) {
//			mapActive = true;
//			PrintHintTextToAll("This game is being recorded by PsychoLive! Watch Online (GameID %d)!", gameID);
//			PrintToServer("This game is being recorded by PsychoLive! (GameID %d)", gameID);
//		}
////	} else {
////		LogError("Error inserting game for PsychoLive.");
//	}
//
//	CloseHandle(data);
//}

public Action:Advertise(Handle:timer) {
	if (gameID) {
		PrintHintTextToAll("This game is being recorded by PsychoLive! Watch Online (GameID %d)!", gameID);
	}
}

// Adds the player to the database under the current gameID, if there is no
// gameID then the player is NOT saved.
stock createPlayerEntity(client) {
	// do not try and save the player if we have no gameID since all
	// entities must have a game associated
	if (!gameID) {
		return;
	}
	
	// make sure the player is assigned to this game
	if (!plr_stats[client][PLR_GAMEID]) {
		plr_stats[client][PLR_GAMEID] = gameID;
	}
	
	// get the player's name
	new String:name[255];
	GetClientName(client, name, sizeof(name));
	new nameLen = strlen(name) * 2 + 1;
	new String:Q_name[nameLen];
	SQL_QuoteString(hDatabase, name, Q_name, nameLen);

	// build our player query
	decl String:query[255];
	Format(query, sizeof(query), "(%d,%d,%d,'%s',%d)",
		gameID,
		plr_stats[client][PLR_UID],
		plr_stats[client][PLR_TYPE],
		Q_name,
		GetClientTeam(client)
	);

#if DEBUG
	PrintToServer("createPlayerEntity: %s", query);
#endif

	WritePackString(pendingEnts, query);
	pendingEntSize += strlen(query);
}

// updates a player entity in the database. This is used to save the
// accumulated totals for the player at the end of a game.
stock savePlayerEntity(client) {
	// do not try and save the player if we have no gameID since all
	// entities must have a game associated
	if (!gameID) {
		return;
	}
	
	// make sure this player is assigned to this game
	plr_stats[client][PLR_GAMEID] = gameID;

	// get the player's name
	new String:name[255];
	GetClientName(client, name, sizeof(name));
	new nameLen = strlen(name) * 2 + 1;
	new String:Q_name[nameLen];
	SQL_QuoteString(hDatabase, name, Q_name, nameLen);

	// build our player query
	decl String:query[768];
//	Format(query, sizeof(query), "UPDATE %slive_entities SET onlinetime=%d, kills=%d, deaths=%d, suicides=%d, ent_team=%d WHERE game_id=%d AND ent_id=%d AND ent_type=%d",
	Format(query, sizeof(query), "onlinetime=%d,kills=%d,deaths=%d,suicides=%d,ent_team=%d,ent_name='%s' WHERE game_id=%d AND ent_id=%d AND ent_type=%d",
		!IsFakeClient(client) ? RoundFloat(GetClientTime(client)) : 0,
		plr_stats[client][PLR_KILLS],
		plr_stats[client][PLR_DEATHS],
		plr_stats[client][PLR_SUICIDES],
		plr_stats[client][PLR_TEAM],
		Q_name,
		plr_stats[client][PLR_GAMEID],
		plr_stats[client][PLR_UID],
		plr_stats[client][PLR_TYPE]
	);

	WritePackString(pendingEntUpdates, query);
	pendingEntUpdateSize += strlen(query);

#if DEBUG
	PrintToServer("savePlayerEntity: %s", query);
#endif
//	SQL_TQuery(hDatabase, T_generic, query);
}

public T_generic(Handle:owner, Handle:hndl, const String:error[], any:data) {
	if (hndl == INVALID_HANDLE) {
		LogError("[PSLIVE] SQL Error: %s", error);
	}
}

