#pragma semicolon 1
#pragma newdecls required

#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
#include <tf2c>

#if !defined VDECODE_FLAG_ALLOWWORLD
	#define VDECODE_FLAG_ALLOWWORLD (1 << 2)
#endif

#define WEAPON_COMBAT_DIRECTIVE 3437
#define WEAPON_MANIACS_BURSTER  9084
#define WEAPON_THE_LAW			9165

//////////////////////////////////////////////////
public Plugin myinfo =
{
	name        = "KOCW Projectile Tracking",
	author      = "Notclue",
	description = "Projectile Tracking attribute",
	version     = "2.0",
	url         = ""

}

enum ProjectileType {
	PROJECTILE_ROCKET,
}

enum struct ProjectileProperties {
	ProjectileType 	eProjectileType;	//type of projectile
	Handle			hTimer;				//timer that handles projectile age
	int				iAccuracy;			//the higher the number the less tracking the rocket has

	int				iProjectile;		//Reference ID of the projectile
	int				iOriginalOwner;		//Reference ID of the player who owns the projectile
}

//////////////////////////////////////////////////
// SDK calls
//Handle hRocketTouch;

// storing data
bool		bActiveHoming[MAXPLAYERS + 1] = { false, ... };	// convert to bitfield?
float		fLookPosCache[MAXPLAYERS + 1][3];	//current look position for all players, updated every frame they are holding a homing compatible weapon
ArrayList	projectiles[MAXPLAYERS+1]; //list of tracked projectiles

// console variables
ConVar hIsPluginOn;
bool   bPluginOn = true;

// glow model ID's
int iGlows[4] = { -1, ... };

public void OnPluginStart() {
	/*Handle hGameConf = LoadGameConfigFile("sdkhooks.games/custom/common.games");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (homingrocket.gamedata.txt).");
	}

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "Touch");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWWORLD);
	hRocketTouch = EndPrepSDKCall();

	delete hGameConf;*/
	
	for( int i = 0; i < MAXPLAYERS+1; i++) {
		projectiles[i] = new ArrayList(5, 0);
	}
	

	hIsPluginOn = CreateConVar("sm_homing", "1", "Enable/Disable rocket homing.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	hIsPluginOn.AddChangeHook(OnConVarChanged_PluginOn);
	bPluginOn   = (GetConVarInt(hIsPluginOn) != 0 ? true : false);
}

public void OnConVarChanged_PluginOn(Handle hConVar, char[] sOldValue, char[] sNewValue) {
	bPluginOn = hIsPluginOn.BoolValue;
}

public void OnPluginEnd() {
	//delete hRocketTouch;
	delete hIsPluginOn;
	for(int i = 0; i < MAXPLAYERS+1; i++) {
		CloseHandle( projectiles[ i ] );
	}
}

public void OnMapStart() {
	bPluginOn = hIsPluginOn.BoolValue;

	iGlows[0] = PrecacheModel("sprites/redglow1.vmt");
	iGlows[1] = PrecacheModel("sprites/blueglow1.vmt");
	iGlows[2] = PrecacheModel("sprites/greenglow1.vmt");
	iGlows[3] = PrecacheModel("sprites/yellowglow1.vmt");

	HookEvent("player_death", OnPlayerKilled);
}

Action OnPlayerKilled(Event event, const char[] name, bool dontBroadcast) {
	int iPlayerID = event.GetInt("userid");
	int iPlayerIndex = GetClientOfUserId(iPlayerID);

	projectiles[ iPlayerIndex ].Clear();

	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname) {
	if ( !bPluginOn)  return;

	if (strcmp(classname, "tf_projectile_rocket") == 0) {
		RequestFrame(Frame_OnRocketSpawn, entity); //just being sure that all properties have been initialized first
	}
}

ProjectileProperties RegisterNewProjectile( int iIndex, ProjectileType eType ) {
	int iProjectileRef = EntIndexToEntRef( iIndex );
	ProjectileProperties props;

	// setup attributes here
	props.iAccuracy  = GetAccuracy( iIndex );
	
	props.iProjectile = iProjectileRef;

	int iOwner = GetEntPropEnt( iIndex, Prop_Send, "m_hOwnerEntity" );
	props.iOriginalOwner = EntIndexToEntRef( iOwner );

	projectiles[ iOwner ].PushArray( props );

	props.eProjectileType = eType;

	DataPack pack = new DataPack();

	switch(eType) {
		case PROJECTILE_ROCKET: {
			SDKHook( iIndex, SDKHook_Think, Hook_RocketThink );
			props.hTimer = CreateDataTimer( GetProjectileLifetime( iIndex ), Timer_RocketExpire, pack, TIMER_FLAG_NO_MAPCHANGE );
		}
	}

	pack.WriteCell( iOwner );
	pack.WriteCell( iProjectileRef );
	return props;
}

/**
 * Find index of projectile in array.
 * This may no longer work if the projectile is reflected, the expire timer should make sure the list doesn't leak
 * 
 * @param index     Entity Index of the entity
 * @return          Index of the struct
 */
int FindProjectileData( int iIndex, int iPlayer = 0 ) {
	if( iPlayer == 0)
		iPlayer = GetEntPropEnt( iIndex, Prop_Send, "m_hOwnerEntity" );
	
	ArrayList list = projectiles[ iPlayer ];

	ProjectileProperties props;
	for( int i = 0; i < list.Length; i++) {
		list.GetArray(i, props);
		if( props.iProjectile == iIndex || EntRefToEntIndex( props.iProjectile ) == iIndex )
			return i;
	}

	return -1;
}

/**
 * Remove the specified Entity Index from the projectile list
 * 
 * @param iIndex     Entity Index
 * @return           No return
 */
bool RemoveProjectileProperties( int iIndex, int iPlayer = 0) {
	if( iPlayer == 0)
		iPlayer = GetEntPropEnt( iIndex, Prop_Send, "m_hOwnerEntity" );

	int iPropIndex = FindProjectileData( iIndex, iPlayer );
	if(iPropIndex == -1) return false;

	ArrayList list = projectiles[ iPlayer ];

	list.Erase( iPropIndex );

	return true;
}

/*
	ROCKET SPECIFIC FUNCTIONS
*/

void Frame_OnRocketSpawn( int iProjectile ) {
	if( !( IsValidEntity( iProjectile ) ) ) return;
	int iWeapon = GetEntPropEnt( iProjectile, Prop_Send, "m_hLauncher");
	if( CanThisWeaponHome( iWeapon ) )
		RegisterNewProjectile( iProjectile, PROJECTILE_ROCKET );
}

Action Hook_RocketThink( int iEntity ) {
	if( DoProjectileTracking( iEntity ) )
		return Plugin_Continue;

	return Plugin_Stop;
}

Action Timer_RocketExpire( Handle timer, DataPack pack) {
	pack.Reset();
	int iOwner = pack.ReadCell();
	int iProjectileRef = pack.ReadCell();

	RemoveProjectileProperties( iProjectileRef, iOwner );

	return Plugin_Stop;
}

int oldButtons[MAXPLAYERS+1] = { 0, ... };
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if( IsPlayerAlive( client ) ) {
		int iWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if( IsValidEntity( iWeapon ) && CanThisWeaponHome( iWeapon ) ) {
			if( buttons & IN_ATTACK2 && !( oldButtons[client] & IN_ATTACK2) )
				bActiveHoming[client] = !bActiveHoming[client];

			if( bActiveHoming[client] && !TF2_IsPlayerInCondition(client, TFCond_Taunting) ) {
				GetPlayerEye( client , fLookPosCache[client] );
				switch( TF2_GetClientTeam(client) ) {
					case TFTeam_Red: {
						TE_SetupGlowSprite( fLookPosCache[client], iGlows[0], 0.1, 0.17, 75 );
					}
					case TFTeam_Blue: {
						TE_SetupGlowSprite( fLookPosCache[client], iGlows[1], 0.1, 0.17, 75 );
					}
					case TFTeam_Green: {
						TE_SetupGlowSprite( fLookPosCache[client], iGlows[2], 0.1, 0.17, 75 );
					}
					case TFTeam_Yellow: {
						TE_SetupGlowSprite( fLookPosCache[client], iGlows[3], 0.1, 0.17, 75 );
					}
				}
				TE_SendToAll();
			}
		}
		oldButtons[client] = buttons;
	}

	return Plugin_Continue;
}

/**
 * Do rocket tracking
 * 
 * @param iIndex     Index of the projectile in rocketList
 * @return           Return if the projectile should stop trying to track or not
 */
bool DoProjectileTracking( int iEntity ) {
	int iOwnerIndex = GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" );

	int iProjectileIndex = FindProjectileData( iEntity );
	if( iProjectileIndex == -1 ) return false;

	ProjectileProperties props;
	projectiles[iOwnerIndex].GetArray(iProjectileIndex, props);

	if( iOwnerIndex != EntRefToEntIndex( props.iOriginalOwner ) ) {
		RemoveProjectileProperties( iEntity );
		return false;
	}

	if( bActiveHoming[ iOwnerIndex ] ) {
		float RocketPos[3];
		float RocketAng[3];
		float RocketVec[3];
		float TargetVec[3];
		float MiddleVec[3];

		GetEntPropVector( iEntity, Prop_Data, "m_vecAbsOrigin", RocketPos );
		GetEntPropVector( iEntity, Prop_Data, "m_angRotation", RocketAng );
		GetEntPropVector( iEntity, Prop_Data, "m_vecAbsVelocity", RocketVec );

		float RocketSpeed = GetVectorLength( RocketVec );
		SubtractVectors( fLookPosCache[ iOwnerIndex ] , RocketPos, TargetVec );
		
		int iAccuracy = props.iAccuracy;
		
		//this seems less than spectacular but i'm bad at math so i can't figure out how to do better
		if ( iAccuracy<=0 ) // negative values
			NormalizeVector( TargetVec, RocketVec );
		else
		{
			if ( iAccuracy==1 )
				AddVectors( RocketVec, TargetVec, RocketVec );
			else if ( iAccuracy==2 ) {
				AddVectors( RocketVec, TargetVec, MiddleVec );
				AddVectors( RocketVec, MiddleVec, RocketVec );
			}
			else {
				AddVectors( RocketVec, TargetVec, MiddleVec );
				for( int j=0; j < iAccuracy-2; j++ )
					AddVectors( RocketVec, MiddleVec, MiddleVec );
				AddVectors( RocketVec, MiddleVec, RocketVec );
			}
			NormalizeVector( RocketVec, RocketVec );
		}
		
		GetVectorAngles( RocketVec, RocketAng );
		SetEntPropVector( iEntity, Prop_Data, "m_angRotation", RocketAng );

		ScaleVector( RocketVec, RocketSpeed );
		SetEntPropVector( iEntity, Prop_Data, "m_vecAbsVelocity", RocketVec );
		
		ChangeEdictState( iEntity );
	}

	return true;
}

/*
	support functions
*/

/**
 * Retrieve the position the player is looking at
 * 
 * @param client     Entity index of the player to get
 * @param pos        Array to store the results into
 * @return           Returns whether the trace hit anything
 */
bool GetPlayerEye(int client, float pos[3]) {
	float vAngles[3];
	float vOrigin[3];
	GetClientEyePosition(client, vOrigin);
	GetClientEyeAngles(client, vAngles);

	Handle trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer, client);

	if (TR_DidHit(trace))
	{
		TR_GetEndPosition(pos, trace);
		CloseHandle(trace);
		return true;
	}
	CloseHandle(trace);
	return false;
}

/**
 * Trace filter for GetPlayerEye
 * 
 * @param entity           Entity to check trace against
 * @param contentsMask     Filter bitfield for the trace
 * @param data             Other crap
 * @return                 Returns if the trace should continue
 */
bool TraceEntityFilterPlayer( int entity, int contentsMask, any data )
{
	if (entity <= 0) return true;
	if (entity == data) return false;

	if( entity > 0 && entity <= MaxClients && IsClientInGame( entity ) && TF2_GetClientTeam( data ) == TF2_GetClientTeam( entity ) )
			return false;

	//todo: this seems inefficient
	static char sClassname[128];
	GetEdictClassname(entity, sClassname, sizeof(sClassname));
	if (strcmp(sClassname, "func_respawnroomvisualizer", false) == 0)
		return false;
	else
		return true;
}

//adjust rocket life span here
//this should do an attribute check when that's possible
float GetProjectileLifetime( int iEntity ) {
	int iWeaponIndex = GetEntPropEnt( iEntity, Prop_Send, "m_hLauncher" );
	int iWeaponID = GetEntProp( iWeaponIndex, Prop_Send, "m_iItemDefinitionIndex" );

	switch( iWeaponID ) {
		case WEAPON_COMBAT_DIRECTIVE: {
			return 10.0;
		}
		case WEAPON_MANIACS_BURSTER: {
			return 10.0;
		}
		case WEAPON_THE_LAW: {
			return 10.0;
		}
	}

	return 10.0;
}

//adjust rocket accuracy here
//this should do an attribute check when that's possible
int GetAccuracy( int iEntity ) {
	int iWeaponIndex = GetEntPropEnt( iEntity, Prop_Send, "m_hLauncher" );
	int iWeaponID = GetEntProp( iWeaponIndex, Prop_Send, "m_iItemDefinitionIndex" );

	switch( iWeaponID ) {
		case WEAPON_COMBAT_DIRECTIVE: {
			return 1;
		}
		case WEAPON_MANIACS_BURSTER: {
			return 1;
		}
		case WEAPON_THE_LAW: {
			return 0;
		}
	}

	return 1;
}

/**
 * Decides whether a weapon is capable of tracking or not
 * 
 * @param weaponIndex     Param description
 * @return                Return description
 */
bool CanThisWeaponHome( int weaponIndex )
{
	// todo: include attribute check when that's possible
	if(!IsValidEntity(weaponIndex)) return false;

	int schemaIndex = GetEntProp(weaponIndex, Prop_Send, "m_iItemDefinitionIndex");
	return schemaIndex == WEAPON_COMBAT_DIRECTIVE || schemaIndex == WEAPON_MANIACS_BURSTER || schemaIndex == WEAPON_THE_LAW;
}