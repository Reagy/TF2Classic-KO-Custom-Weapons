/*
[TF2] Throw Sapper
Allows you to throw a sapper, sapping buildings around it.
By: Chdata

Credits to the creator playpoints from which I used sapper code from.
-Tak (Chaosxk)

Also credits to the maker of the RMF ability pack, from which playpoints was probably made from.
-RIKUSYO

*/

#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <tf2c>

//#define DEBUG_ON

#define PLUGIN_VERSION "0.1"

#define TARGETNAME_THROWSAP     "tf2sapper%data"
#define MDL_SAPPER              "models/weapons/c_models/c_remotesap/c_remotesap.mdl"
#define SOUND_BOOT              "weapons/weapon_crit_charged_on.wav"
#define SOUND_SAPPER_REMOVED    "weapons/sapper_removed.wav"
#define SOUND_SAPPER_THROW      "weapons/knife_swing.wav"
#define SOUND_SAPPER_NOISE      "weapons/sapper_timer.wav"
#define SOUND_SAPPER_NOISE2     "player/invulnerable_off.wav"
#define SOUND_SAPPER_PLANT      "weapons/sapper_plant.wav"
#define EFFECT_TRAIL_RED        "kritz_beam_trail_red"
#define EFFECT_TRAIL_BLU        "kritz_beam_trail_blue"
#define EFFECT_TRAIL_GRN        "kritz_beam_trail_green"
#define EFFECT_TRAIL_YLW        "kritz_beam_trail_yellow"
#define EFFECT_CORE_FLASH       "sapper_coreflash"
#define EFFECT_DEBRIS           "sapper_debris"
#define EFFECT_FLASH            "sapper_flash"
#define EFFECT_FLASHUP          "sapper_flashup"
#define EFFECT_FLYINGEMBERS     "sapper_flyingembers"
#define EFFECT_SMOKE            "sapper_smoke"
#define EFFECT_SENTRY_FX        "sapper_sentry1_fx"
#define EFFECT_SENTRY_SPARKS1   "sapper_sentry1_sparks1"
#define EFFECT_SENTRY_SPARKS2   "sapper_sentry1_sparks2"
#define SPRITE_ELECTRIC_WAVE    "sprites/laser.vmt"

static const char g_szBuildingClasses[][] = {
	"obj_dispenser",
	"obj_sentrygun",
	"obj_teleporter"
};

//#define TEAM_SPEC 0
#define TEAM_RED    2
#define TEAM_BLU    3
#define TEAM_GRN    4
#define TEAM_YLW    5

bool bEnabled;                                                      // Bool for the plugin being enabled or disabled.
int g_hEffectSprite;                                                    // Handle for the lightning shockwave sprite.

Handle g_hSapperArray;                                           // Holds entrefs for spawned sappers.
Handle g_hTargetedArray;                                         // Holds entrefs for buildings targeted by sappers.
																		// Both have 2 blocks. [owner userid][entref]

//new g_CalCharge[MAXPLAYERS + 1];                                      // Holds the charge amount for being able to throw a sapper.

Handle g_cvEnabled;
Handle g_cvSapRadius;

//new Handle:tChargeTimer[MAXPLAYERS + 1] = INVALID_HANDLE;
Handle tTimerLoop[MAXPLAYERS + 1];
//new Handle:hHudCharge = INVALID_HANDLE;

public Plugin myinfo =
{
	name = "Throwable Sapper",
	description = "Programming was a mistake",
	author = "Clooooooooey",
	version = PLUGIN_VERSION,
	url = "no"
};

public void OnPluginStart()
{
	CreateConVar("throwsap_version", PLUGIN_VERSION, "Throwsap Version", FCVAR_REPLICATED | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
	g_cvEnabled = CreateConVar("throwsap_enabled", "1", "Enable/Disable throwsap plugin.", 0, true, 0.0, true, 1.0);
	g_cvSapRadius = CreateConVar("throwsap_sapradius", "300.0", "Radius of effect.");

	AutoExecConfig(true, "plugin.throwsap");

	//hHudCharge = CreateHudSynchronizer();

	g_hSapperArray = CreateArray(2);   // Each index has 2 blocks
	g_hTargetedArray = CreateArray(2);
	
	/*for (new client = 1; client <= MaxClients; client++)
	{   
		if (IsClientInGame(client))
		{
			// TODO: Destroy all existing sappers here and remove building targets

			//g_CalCharge[client] = 0;
			//tChargeTimer[client] = CreateTimer(0.5, Timer_ChargeMe, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		}
	}*/
}

public void OnMapStart()
{
	ClearArray(g_hSapperArray);
	ClearArray(g_hTargetedArray);
	PrecacheModel(MDL_SAPPER, true);
	PrecacheSound(SOUND_SAPPER_REMOVED, true);
	PrecacheSound(SOUND_SAPPER_NOISE2, true);
	PrecacheSound(SOUND_SAPPER_NOISE, true);
	PrecacheSound(SOUND_SAPPER_PLANT, true);
	PrecacheSound(SOUND_SAPPER_THROW, true);
	PrecacheSound(SOUND_BOOT, true);
	PrecacheGeneric(EFFECT_TRAIL_RED, true);
	PrecacheGeneric(EFFECT_TRAIL_BLU, true);
	PrecacheGeneric(EFFECT_TRAIL_GRN, true);
	PrecacheGeneric(EFFECT_TRAIL_YLW, true);
/*    PrecacheGeneric(EFFECT_CORE_FLASH, true);
	PrecacheGeneric(EFFECT_DEBRIS, true);
	PrecacheGeneric(EFFECT_FLASH, true);
	PrecacheGeneric(EFFECT_FLASHUP, true);
	PrecacheGeneric(EFFECT_FLYINGEMBERS, true);*/
	PrecacheGeneric(EFFECT_SMOKE, true);
	PrecacheGeneric(EFFECT_SENTRY_FX, true);
	PrecacheGeneric(EFFECT_SENTRY_SPARKS1, true);
	PrecacheGeneric(EFFECT_SENTRY_SPARKS2, true);
	g_hEffectSprite = PrecacheModel(SPRITE_ELECTRIC_WAVE, true);
}

public void OnConfigsExecuted()
{
	bEnabled = GetConVarBool(g_cvEnabled);
}

/*public OnClientPostAdminCheck(client)
{
	//g_CalCharge[client] = 0;
	//tChargeTimer[client] = CreateTimer(0.5, Timer_ChargeMe, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}*/

public void OnClientDisconnect(int client)
{
	//g_CalCharge[client] = 0;
	//ClearTimer(tChargeTimer[client]);

	DestroySapper(GetClientUserId(client), GetClientSapper(client));
}

public void OnEntityDestroyed(int ent)
{
	if (!IsValidEntity(ent) || ent <= 0) return;

	char sClassname[64];
	GetEntityClassname(ent, sClassname, sizeof(sClassname));

	for (int i = 0; i < sizeof(g_szBuildingClasses); i++)
	{
		if (StrEqual(sClassname, g_szBuildingClasses[i], false))
		{
			int entref = EntIndexToEntRef(ent);
			int iIndex = FindValueInArray(g_hTargetedArray, entref);
			if (iIndex != -1)                                           // If the building was being sapped,
			{                                                           // remove it from the array because it's destroyed
				RemoveFromArray(g_hTargetedArray, iIndex);              // and thus can't be sapped anymore
				StopSound(ent, 0, SOUND_SAPPER_NOISE);
				StopSound(ent, 0, SOUND_SAPPER_NOISE2);                 // So, if the entity destroyed was targeted by someone's sapper
				StopSound(ent, 0, SOUND_SAPPER_PLANT);                  // Turn off the sounds on that entity
				// EmitSoundToClient(i, HHHTheme, _, _, _, SND_STOPLOOPING);
			}
		}
	}
}

/*public Action:Timer_ChargeMe(Handle:timer, any:client)
{
	if (!bEnabled || !IsValidClient(client) || !IsPlayerAlive(client)) return; 

	if (TF2_GetPlayerClass(client) == TFClass_Spy && IsValidEntity(GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary))) //If they are a spy, and have a sapper still
	{
		if (g_CalCharge[client] > 100)
		{
			g_CalCharge[client] = 100;
		}
		else if(g_CalCharge[client] < 100)
		{
			g_CalCharge[client] += 2;
		}
		SetHudTextParams(-1.0, 0.12, 0.6, 255, 0, 0, 255);

		if (!(GetClientButtons(client) & IN_SCORE))
		{
			ShowSyncHudText(client, hHudCharge, "Charge: %d%", g_CalCharge[client]);
		}
	}
}*/

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!bEnabled || !IsValidClient(client) || !IsPlayerAlive(client)) return Plugin_Continue;

	if (TF2_GetPlayerClass(client) == TFClass_Spy && buttons & (IN_ATTACK3 | IN_RELOAD))
	{
		bool bCloaked = TF2_IsPlayerInCondition(client, TFCond_Cloaked) ? true : false;

		int weaponCheck = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);

		if (weaponCheck > MaxClients && GetEntProp(weaponCheck, Prop_Send, "m_iItemDefinitionIndex") == 9185)// && GetEntProp(weaponCheck, Prop_Send, "m_iItemDefinitionIndex") == 9185)
		{
			if (!bCloaked && IsWeaponSlotActive(client, TFWeaponSlot_Secondary))
			{
				if (!ThrownSapperExists(client)) //If not cloaked and you don't already have a sapper thrown //|| g_CalCharge[client] != 100
				{
					//EmitSoundToClient(client, SOUND_SAPPER_DENY);

					int index = GetIndexOfWeaponSlot(client, TFWeaponSlot_Secondary);
					//g_CalCharge[client] = 0;

					ThrowSapper(client, index);

					if (TF2_IsPlayerInCondition(client, TFCond_Disguised))
					{
						TF2_RemoveCondition(client, TFCond_Disguised);
					}
	#if defined DEBUG_ON
					if (IsClientChdata(client)) return Plugin_Continue;
	#endif
					SwitchToOtherWeapon(client);
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Secondary);
					//CreateTimer(0.3, tSwitchToOtherWeapon, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
				}
			}
		}
	}

	return Plugin_Continue;
}

stock int IsWeaponSlotActive(int iClient, int iSlot)
{
	int hActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
	int hWeapon = GetPlayerWeaponSlot(iClient, iSlot);
	return (hWeapon == hActive);
}

stock int GetIndexOfWeaponSlot(int client, int slot)
{
	int weapon = GetPlayerWeaponSlot(client, slot);

	return (weapon > MaxClients && IsValidEntity(weapon) ? GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"):-1);
}

/*public Action:tSwitchToOtherWeapon(Handle:hTimer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if (IsValidClient(client) && IsPlayerAlive(client))
	{
		SwitchToOtherWeapon(client);
	}
}*/

stock void SwitchToOtherWeapon(int client)
{
	int ammo = GetAmmo(client, 0);
	int weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	int clip = (IsValidEntity(weapon) ? GetEntProp(weapon, Prop_Send, "m_iClip1"):-1);

	if (!(ammo == 0 && clip <= 0))
	{
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", weapon);
	}
	else
	{
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", GetPlayerWeaponSlot(client, TFWeaponSlot_Melee));
	}
}

stock int GetAmmo(int client, int slot)
{
	if (!IsValidClient(client)) return -1;

	int weapon = GetPlayerWeaponSlot(client, slot);

	if (IsValidEntity(weapon))
	{
		int iOffset = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType", 1); // * 4;
		//new iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");

		//return GetEntData(client, iAmmoTable + iOffset);

		if (iOffset < 0)
		{
			return -1;
		}

		return GetEntProp(client, Prop_Send, "m_iAmmo", _, iOffset);
	}

	return -1;
}

stock void ThrowSapper(int client, int index)
{
	int sapper = CreateEntityByName("prop_physics_override");
	if (IsValidEntity(sapper))
	{
		SetEntPropEnt(sapper, Prop_Data, "m_hOwnerEntity", client);

		SetEntityModel(sapper, MDL_SAPPER); // Note: Bread (1102) is broken.
		
		SetEntityMoveType(sapper, MOVETYPE_VPHYSICS);
		SetEntProp(sapper, Prop_Data, "m_CollisionGroup", 1);
		SetEntPropFloat(sapper, Prop_Data, "m_flFriction", 10000.0);
		SetEntPropFloat(sapper, Prop_Data, "m_massScale", 100.0);
		DispatchKeyValue(sapper, "targetname", TARGETNAME_THROWSAP);
		DispatchSpawn(sapper);
		float pos[3];
		float ang[3];
		float vec[3];
		float svec[3];
		float pvec[3];
		
		GetClientEyePosition(client, pos);
		GetClientEyeAngles(client, ang);
		
		ang[1] += 2.0;
		pos[2] -= 20.0;
		GetAngleVectors(ang, vec, svec, NULL_VECTOR);
		ScaleVector(vec, 500.0);
		ScaleVector(svec, 30.0);
		AddVectors(pos, svec, pos);
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", pvec);
		AddVectors(pvec, vec, vec);
		TeleportEntity(sapper, pos, ang, vec);

//        AttachParticle(sapper, (GetClientTeam(client) == TEAM_RED) ? EFFECT_TRAIL_RED : EFFECT_TRAIL_BLU, 2.0);

		switch(GetClientTeam(client))
		{
			case TEAM_RED: 
				AttachParticle(sapper, EFFECT_TRAIL_RED, 2.0);
			case TEAM_BLU: 
				AttachParticle(sapper, EFFECT_TRAIL_BLU, 2.0);
			case TEAM_GRN:
				AttachParticle(sapper, EFFECT_TRAIL_GRN, 2.0);
			case TEAM_YLW:
				AttachParticle(sapper, EFFECT_TRAIL_YLW, 2.0);
		}

		EmitSoundToAll(SOUND_BOOT, sapper, _, _, SND_CHANGEPITCH, 0.2, 30);
		EmitSoundToAll(SOUND_SAPPER_THROW, client, _, _, _, 1.0);

		int arr[2];
		arr[0] = GetClientUserId(client);
		arr[1] = EntIndexToEntRef(sapper);
		PushArrayArray(g_hSapperArray, arr);

		//SDKHook(sapper, SDKHook_StartTouch, OnStartTouch);
		
		CreateTimer(5.1, StopSapping, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		tTimerLoop[client] = CreateTimer(0.1, LoopSapping, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

/*
 This timer controls finding and sapping nearby buildings, every 0.1s

*/
public Action LoopSapping(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (IsValidClient(client) && ThrownSapperExists(client) && IsPlayerAlive(client))
	{
		int sapper = GetClientSapper(client);
		AttachRings(sapper);

		float vSapperPos[3];
		GetEntPropVector(sapper, Prop_Data, "m_vecAbsOrigin", vSapperPos);

		//Find and sap buildings in relation to this sapper
		FindAllBuildings(client, "obj_dispenser", vSapperPos);
		FindAllBuildings(client, "obj_sentrygun", vSapperPos);
		FindAllBuildings(client, "obj_teleporter", vSapperPos);

		//If the player who threw it is in range, sap their cloak
		float vPlayerPos[3];
		GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", vPlayerPos);
		if (GetVectorDistance(vPlayerPos, vSapperPos) <= GetConVarFloat(g_cvSapRadius))
		{
			float flCloak = GetEntPropFloat(client, Prop_Send, "m_flCloakMeter");

			flCloak -= 3.0;
			if (flCloak < 0.0) flCloak = 0.0;

			SetEntPropFloat(client, Prop_Send, "m_flCloakMeter", flCloak);
		}
	}
}

/*
 This timer controls making the sapper stop sapping and destroying the sapper

*/
public Action StopSapping(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	int sapper = GetClientSapper(client);
	if (!IsValidClient(client) && sapper == -1)
	{
		return Plugin_Stop; // TODO: Figure out why this check exists
	}

	ClearTimer(tTimerLoop[client]);

	DestroySapper(userid, sapper);

	return Plugin_Stop;
}

void DestroySapper(int userid, int sapper)
{
	char Name[24];
	GetEntPropString(sapper, Prop_Data, "m_iName", Name, 128, 0);

	if (StrEqual(Name, TARGETNAME_THROWSAP))
	{
		AcceptEntityInput(sapper, "Kill");

		float SapperPos[3];
		GetEntPropVector(sapper, Prop_Data, "m_vecAbsOrigin", SapperPos);

		ShowParticle(EFFECT_CORE_FLASH, 1.0, SapperPos);
		ShowParticle(EFFECT_DEBRIS, 1.0, SapperPos);
		ShowParticle(EFFECT_FLASH, 1.0, SapperPos);
		ShowParticle(EFFECT_FLASHUP, 1.0, SapperPos);
		ShowParticle(EFFECT_FLYINGEMBERS, 1.0, SapperPos);
		ShowParticle(EFFECT_SMOKE, 1.0, SapperPos);

		StopSound(sapper, 0, SOUND_BOOT);
		EmitSoundToAll(SOUND_SAPPER_REMOVED, sapper, _, _, _, 1.0);

		int iIndex = -1;
		while ((iIndex = FindValueInArray(g_hTargetedArray, userid)) != -1)
		{
			int building = EntRefToEntIndex(GetArrayCell(g_hTargetedArray, iIndex, 1));

			if (IsValidEntity(building) && building > 0)
			{
				StopSound(building, 0, SOUND_SAPPER_NOISE);
				StopSound(building, 0, SOUND_SAPPER_NOISE2);
				StopSound(building, 0, SOUND_SAPPER_PLANT);
				
				SetVariantInt(1);
				AcceptEntityInput(building, "Enable");
			}

			RemoveFromArray(g_hTargetedArray, iIndex);
		}

		iIndex = FindValueInArray(g_hSapperArray, userid);
		RemoveFromArray(g_hSapperArray, iIndex);
	}
}

//Attaches team colored electrical rings to a sapper. Not tested with other entities.
stock void AttachRings(int entity)
{
	int red[4] = {184, 56, 59, 255};    //These are the same values as Team Spirit paint
	int blue[4] = {88, 133, 162, 255};
	int green[4] = {66, 214, 84, 255};
	int yellow[4] = {255, 249, 77, 255};

	int owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
	
	float vSapperPos[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", vSapperPos);

	float radius = GetConVarFloat(g_cvSapRadius);
	
	switch(GetClientTeam(owner))
	{
		case TEAM_RED: 
			MakeRings(vSapperPos, radius, red);
		case TEAM_BLU: 
			MakeRings(vSapperPos, radius, blue);
		case TEAM_GRN: 
			MakeRings(vSapperPos, radius, green);
		case TEAM_YLW: 
			MakeRings(vSapperPos, radius, yellow);
	}
}

void MakeRings(float vSapperPos[3], float radius, int colour[4])
{
	for(int i = 0; i < 4; i++)
	{
		TE_SetupBeamRingPoint(vSapperPos, 0.1, radius, g_hEffectSprite, g_hEffectSprite, 1, 1, 0.6, 3.0, 10.0, colour, 15, 0);
		TE_SendToAll();
	}
}

//Finds specified enemy buildings (or entities) and assigns them as targetable buildings for the client if in range.
//It also saps them if found and clears buildings if not targetable
stock void FindAllBuildings(int client, char clsname[64], float vPos[3])
{
	int ent = -1;

	while ((ent = FindEntityByClassname(ent, clsname)) != -1)
	{
		if (!IsValidEntity(ent)) return;

		float vFoundPos[3];
		GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", vFoundPos);

		int team = GetEntProp(ent, Prop_Data, "m_iTeamNum");

		int iIndex = FindValueInArray(g_hTargetedArray, EntIndexToEntRef(ent));

		bool bGodMode = (GetEntProp(ent, Prop_Data, "m_takedamage") == 0);

		if (GetVectorDistance(vPos, vFoundPos) <= GetConVarFloat(g_cvSapRadius) && team != GetClientTeam(client))
		{
			if (iIndex != -1) //If we're already targeting it
			{
				if (bGodMode)
				{
					RemoveFromArray(g_hTargetedArray, iIndex);
				}
				else
				{
					PerformSap(ent);
				}
			}
			else if (!bGodMode)  //Register new target if possible
			{
				int arr[2];
				arr[0] = GetClientUserId(client);
				arr[1] = EntIndexToEntRef(ent);
				iIndex = PushArrayArray(g_hTargetedArray, arr);

				if (iIndex != -1)
				{
					EmitSoundToAll(SOUND_SAPPER_NOISE, ent, _, _, SND_CHANGEPITCH, 1.0, 150);
					EmitSoundToAll(SOUND_SAPPER_NOISE2, ent, _, _, SND_CHANGEPITCH, 1.0, 60);
					EmitSoundToAll(SOUND_SAPPER_PLANT, ent, _, _, _, 1.0);

					PerformSap(ent);
				}
			}
		}
		else if (iIndex != -1)
		{
			RemoveFromArray(g_hTargetedArray, iIndex);            // //It's not in range/not an enemy so don't target it
		}
	}
}

stock void PerformSap(int entity)
{
	SetVariantInt(2);
	AcceptEntityInput(entity, "RemoveHealth");

	SetVariantInt(1);
	AcceptEntityInput(entity, "Disable");

	float vEffectPos[3];
	vEffectPos[0] = GetRandomFloat(-25.0, 25.0);
	vEffectPos[1] = GetRandomFloat(-25.0, 25.0);
	vEffectPos[2] = GetRandomFloat(10.0, (GetEntProp(entity, Prop_Send, "m_iObjectType") == 1) ? 25.0 : 65.0);
	
	ShowParticleEntity(entity, EFFECT_SENTRY_FX, 0.5, vEffectPos);
	ShowParticleEntity(entity, EFFECT_SENTRY_SPARKS1, 0.5, vEffectPos);
	ShowParticleEntity(entity, EFFECT_SENTRY_SPARKS2, 0.5, vEffectPos);
}

/*
stock FindEmptyBuildingTarget(client)
{
	new building = 0; //This loop jumps to the next empty building slot
	while (g_iTargetBuilding[client][building] != -1 && building < MAX_TARGET_BUILDING-1)
	{
		building++;
	}

	if (building == 127 && g_iTargetBuilding[client][127] != -1) return -1; //Slots are full

	return building;
}

stock GetOccupiedBuildingSlot(client, entity)
{
	for (new i = 0; i < MAX_TARGET_BUILDING; i++)
	{
		if (entity == g_iTargetBuilding[client][i])
		{
			return i; //Found the entity at this slot
		}
	}
	return -1; //Not found
}
*/

/*
 return true if player has a sapper thrown and in the world
 return false otherwise

 also validates its existence and removes the sapper if it doesn't exist

*/
stock bool ThrownSapperExists(int client)
{
	int userid = GetClientUserId(client);
	int iIndex = FindValueInArray(g_hSapperArray, userid);

	if (iIndex != -1)
	{
		return IsValidEntity(EntRefToEntIndex(GetArrayCell(g_hSapperArray, iIndex, 1)));
	}
	return false;

	/*
	RemoveFromArray(g_hSapperArray, iIndex);
	
	*/

	// return bool:(iIndex != -1);
}

/*
 TODO: GetClientSappers in an array

*/
stock int GetClientSapper(int client)
{
	int userid = GetClientUserId(client);
	int iIndex = FindValueInArray(g_hSapperArray, userid);

	if (iIndex != -1)
	{
		int ent = EntRefToEntIndex(GetArrayCell(g_hSapperArray, iIndex, 1));
		if(IsValidEntity(ent) && ent > 0) return ent;
		else return -1;
	}
	return false;
}

#if defined DEBUG_ON
#define MAX_STEAMAUTH_LENGTH 21
#define STEAMID_CHDATA "STEAM_0:0:6404564"

stock bool:IsClientChdata(client)
{
	if (!IsClientAuthorized(client)) return false;

	char clientAuth[MAX_STEAMAUTH_LENGTH];
	GetClientAuthString(client, clientAuth, sizeof(clientAuth));

	if (StrEqual(STEAMID_CHDATA, clientAuth))
	{
		return true;
	}

	return false;
}
#endif

//Below are things I need to put in an inc file /Find the inc file of.
stock any AttachParticle(int ent, char particleType[64], float time, float addPos[3]=NULL_VECTOR, float addAngle[3]=NULL_VECTOR)
{
	int particle = CreateEntityByName("info_particle_system");
	if (IsValidEdict(particle))
	{
		float pos[3];
		float ang[3];
		char tName[32];
		GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);
		AddVectors(pos, addPos, pos);
		GetEntPropVector(ent, Prop_Send, "m_angRotation", ang);
		AddVectors(ang, addAngle, ang);

		TeleportEntity(particle, pos, ang, NULL_VECTOR);
		GetEntPropString(ent, Prop_Data, "m_iName", tName, sizeof(tName));
		DispatchKeyValue(particle, "targetname", "tf2particle");
		DispatchKeyValue(particle, "parentname", tName);
		DispatchKeyValue(particle, "effect_name", particleType);
		DispatchSpawn(particle);
		SetVariantString("!activator");
		AcceptEntityInput(particle, "SetParent", ent, particle, 0);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "start");
		CreateTimer(time, RemoveParticle, particle);
	}
	return particle;
}

public Action RemoveParticle( Handle timer, any particle )
{
	if (IsValidEntity(particle))
	{
		char classname[32];
		GetEdictClassname(particle, classname, sizeof(classname));
		if (StrEqual(classname, "info_particle_system", false))
		{
			AcceptEntityInput(particle, "stop");
			AcceptEntityInput(particle, "Kill");
			particle = -1;
		}
	}
}

stock any ShowParticleEntity(int ent, char particleType[64], float time, float addPos[3]=NULL_VECTOR, float addAngle[3]=NULL_VECTOR)
{
	int particle = CreateEntityByName("info_particle_system");
	if (IsValidEdict(particle))
	{
		float pos[3];
		float ang[3];
		char tName[32];
		GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);
		AddVectors(pos, addPos, pos);
		GetEntPropVector(ent, Prop_Send, "m_angRotation", ang);
		AddVectors(ang, addAngle, ang);

		TeleportEntity(particle, pos, ang, NULL_VECTOR);
		GetEntPropString(ent, Prop_Data, "m_iName", tName, sizeof(tName));
		DispatchKeyValue(particle, "targetname", "tf2particle");
		DispatchKeyValue(particle, "parentname", tName);
		DispatchKeyValue(particle, "effect_name", particleType);
		DispatchSpawn(particle);
		SetVariantString(tName);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "start");
		CreateTimer(time, RemoveParticle, particle);
	}
	return particle;
}

stock void ShowParticle(char particlename[64], float time, float pos[3], float ang[3]=NULL_VECTOR)
{
	int particle = CreateEntityByName("info_particle_system");
	if (IsValidEdict(particle))
	{
		TeleportEntity(particle, pos, ang, NULL_VECTOR);
		DispatchKeyValue(particle, "targetname", "tf2particle");
		DispatchKeyValue(particle, "effect_name", particlename);
		DispatchSpawn(particle);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "start");
		CreateTimer(time, RemoveParticle, particle);
/*        DispatchKeyValue(particle, "effect_name", particlename);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "start");
		CreateTimer(time, RemoveParticle, particle);*/
	}
}

stock void ClearTimer(Handle &timer)
{
	if (timer != INVALID_HANDLE)
	{
		KillTimer(timer);
		timer = INVALID_HANDLE;
	}
}

stock bool IsValidClient(int i, bool replay = true)
{
	if (0 > i || i > MaxClients || !IsClientInGame(i)) return false;
	if (replay && (IsClientSourceTV(i) || IsClientReplay(i))) return false;
	return true;
}

/*
public OnEntityCreated(entity, const String:classname[])
{
	if (  (StrEqual(classname, "obj_teleporter", false)
		|| StrEqual(classname, "obj_sentrygun", false)
		|| StrEqual(classname, "obj_dispenser", false))
		)
	{
		CreateTimer(0.0, Timer_CheckBuilding, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
	}

	if ((StrEqual(classname, "prop_physics_override", false))
	{
		char Name[24];
		GetEntPropString(entity, Prop_Data, "m_iName", Name, 128, 0);
		if (StrEqual(Name, TARGETNAME_THROWSAP))
		{
			SDKHook(entity, SDKHook_StartTouch, OnStartTouch);
		}
	}
}

//Can't find the owner and other details directly during OnEntityCreated
public Action:Timer_CheckBuilding(Handle:timer, any:ref) 
{
	new entity = EntRefToEntIndex(ref);

	//This loop jumps to the next empty building slot
	new building = 0;
	while (g_iTargetBuilding[client][building] != -1 && building < MAX_TARGET_BUILDING-1)
	{
		building++;
	}

	g_iTargetBuilding[client][building] = entity;
}

public Action:OnStartTouch(entity, other)
{
	if (!IsValidClient(other))  //Only continue if the touched prop is a player
		return Plugin_Continue;

	new owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");

	if (owner == other)         //Don't collide with your own projectiles
		return Plugin_Continue;

	if (TF2_IsPlayerInCondition(other, TFCond_Ubercharged)) //If they're ubered, ignore
		return Plugin_Continue;

	DealDamage(other, 10, owner, DMG_GENERIC, "tf_weapon_builder");

	return Plugin_Continue;
}*/