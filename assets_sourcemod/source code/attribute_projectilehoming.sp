#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <kocwtools>
#include <tf2c>

public Plugin myinfo =
{
	name = "Attribute: Tracking Rocket",
	author = "Noclue",
	description = "Tracking rocket attribute.",
	version = "3.0",
	url = "no"
}

// storing data
bool		g_bActiveHoming[MAXPLAYERS + 1] = { false, ... };	// convert to bitfield?
float		g_flLookPosCache[MAXPLAYERS + 1][3];	//current look position for all players, updated every frame they are holding a homing compatible weapon

// glow model ID's
int g_iGlows[4] = { -1, ... };

public void OnMapStart() {
	g_iGlows[0] = PrecacheModel( "sprites/redglow1.vmt" );
	g_iGlows[1] = PrecacheModel( "sprites/blueglow1.vmt" );
	g_iGlows[2] = PrecacheModel( "sprites/greenglow1.vmt" );
	g_iGlows[3] = PrecacheModel( "sprites/yellowglow1.vmt" );
}

public void OnEntityCreated(int iEntity, const char[] sClassname) {
	if ( strcmp(sClassname, "tf_projectile_rocket") == 0 ) {
		RequestFrame( Frame_OnRocketSpawn, EntIndexToEntRef( iEntity ) ); //just being sure that all properties have been initialized first
		return;
	}
}

int g_iOldButtons[MAXPLAYERS+1] = { 0, ... };
public Action OnPlayerRunCmd(int iClient, int& iButtons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if( !IsPlayerAlive( iClient ) )
		return Plugin_Continue;

	int iWeapon = GetEntPropEnt( iClient, Prop_Send, "m_hActiveWeapon" );
	if( iWeapon == -1 || !CanThisWeaponHome( iWeapon ) )
		return Plugin_Continue;

	if( iButtons & IN_ATTACK2 && !( g_iOldButtons[iClient] & IN_ATTACK2 ) ) {
		g_bActiveHoming[iClient] = !g_bActiveHoming[iClient];
		/*todo: find sound effects
		if( bActiveHoming[client] )
			EmitGameSoundToClient( client, "BaseCombatWeapon.WeaponMaterialize" );
		else
			EmitGameSoundToClient( client, "Player.WeaponSelected" );
		*/	
	}

	if( g_bActiveHoming[iClient] && !TF2_IsPlayerInCondition( iClient, TFCond_Taunting ) ) {
		GetPlayerEye( iClient, g_flLookPosCache[iClient] );
		int iTeam = GetEntProp( iClient, Prop_Send, "m_iTeamNum" ) - 2;
		TE_SetupGlowSprite( g_flLookPosCache[iClient], g_iGlows[iTeam], 0.1, 0.17, 75 );
		TE_SendToAll();
	}

	g_iOldButtons[iClient] = iButtons;
	return Plugin_Continue;
}

bool DoProjectileTracking( int iEntity ) {
	int iOwnerIndex = GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" );
	int iLauncher = GetEntPropEnt( iEntity, Prop_Send, "m_hLauncher" );
	int iOriginal = GetEntPropEnt( iEntity, Prop_Send, "m_hOriginalLauncher" );

	if( iLauncher != iOriginal || !IsPlayerAlive( iOwnerIndex ) ) return false;

	if( g_bActiveHoming[ iOwnerIndex ] ) {
		float vecRocketPos[3]; //position of rocket
		float vecRocketAng[3]; //angle of rocket
		float vecRocketVec[3]; //velocity of rocket
		float vecTargetVec[3]; //target velocity

		GetEntPropVector( iEntity, Prop_Data, "m_vecAbsOrigin", vecRocketPos );
		GetEntPropVector( iEntity, Prop_Data, "m_vecAbsVelocity", vecRocketVec );

		float RocketSpeed = GetVectorLength( vecRocketVec );
		SubtractVectors( g_flLookPosCache[ iOwnerIndex ] , vecRocketPos, vecTargetVec );

		float flAccuracy = GetProjectileAccuracy( iEntity );
		flAccuracy = FloatClamp( flAccuracy, 0.0, 1.0 );

		SubtractVectors( vecTargetVec, vecRocketVec, vecTargetVec ); //get the difference between desired and current angle
		ScaleVector( vecTargetVec, flAccuracy ); //scale difference by accuracy
		AddVectors( vecTargetVec, vecRocketVec, vecRocketVec ); //subtract difference into result

		NormalizeVector( vecRocketVec, vecRocketVec );

		GetVectorAngles( vecRocketVec, vecRocketAng );
		SetEntPropVector( iEntity, Prop_Data, "m_angRotation", vecRocketAng );

		ScaleVector( vecRocketVec, RocketSpeed );
		SetEntPropVector( iEntity, Prop_Data, "m_vecAbsVelocity", vecRocketVec );
		
		ChangeEdictState( iEntity );
	}

	return true;
}

/*
	ROCKET SPECIFIC FUNCTIONS
*/

//todo: does funky stuff during server start
void Frame_OnRocketSpawn( int iProjectile ) {
	iProjectile = EntRefToEntIndex( iProjectile );
	if( iProjectile == -1 ) 
		return;

	int iWeapon = GetEntPropEnt( iProjectile, Prop_Send, "m_hLauncher");
	if( !CanThisWeaponHome( iWeapon ) ) 
		return;

	SDKHook( iProjectile, SDKHook_Think, Hook_RocketThink );
}

Action Hook_RocketThink( int iEntity ) {
	if( DoProjectileTracking( iEntity ) )
		return Plugin_Continue;

	return Plugin_Stop;
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
bool GetPlayerEye(int iClient, float flPos[3]) {
	float flAngles[3];
	float flOrigin[3];
	GetClientEyePosition( iClient, flOrigin );
	GetClientEyeAngles( iClient, flAngles );

	StartLagCompensation( iClient );
	Handle hTrace = TR_TraceRayFilterEx( flOrigin, flAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer, iClient );
	FinishLagCompensation( iClient );

	if ( TR_DidHit( hTrace ) ) {
		TR_GetEndPosition( flPos, hTrace );
		CloseHandle( hTrace );
		return true;
	}
	CloseHandle( hTrace );
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
bool TraceEntityFilterPlayer( int iEntity, int iContentsMask, any data ) {
	if ( iEntity <= 0 ) return true;
	if ( iEntity == data ) return false;

	if( iEntity <= MaxClients && TF2_GetClientTeam( data ) == TF2_GetClientTeam( iEntity ) )
		return false;

	static char sClassname[128];
	GetEdictClassname( iEntity, sClassname, sizeof(sClassname) );
	return strcmp( sClassname, "func_respawnroomvisualizer", false ) != 0;
}

float GetProjectileAccuracy( int iEntity ) {
	int iWeaponIndex =  GetEntPropEnt( iEntity, Prop_Send, "m_hLauncher" );
	if( !IsValidEntity( iWeaponIndex ) )
		return 0.0;

	return AttribHookFloat( 0.0, iWeaponIndex, "custom_rocket_homing_rate" );
}

bool CanThisWeaponHome( int iWeaponIndex ) {
	return AttribHookInt( 0, iWeaponIndex, "custom_rocket_homing" );
}