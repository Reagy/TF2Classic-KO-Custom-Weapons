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
bool		bActiveHoming[MAXPLAYERS + 1] = { false, ... };	// convert to bitfield?
float		fLookPosCache[MAXPLAYERS + 1][3];	//current look position for all players, updated every frame they are holding a homing compatible weapon

// glow model ID's
int iGlows[4] = { -1, ... };

public void OnMapStart() {
	iGlows[0] = PrecacheModel("sprites/redglow1.vmt");
	iGlows[1] = PrecacheModel("sprites/blueglow1.vmt");
	iGlows[2] = PrecacheModel("sprites/greenglow1.vmt");
	iGlows[3] = PrecacheModel("sprites/yellowglow1.vmt");
}

public void OnEntityCreated(int iEntity, const char[] sClassname) {
	if (strcmp(sClassname, "tf_projectile_rocket") == 0) {
		RequestFrame(Frame_OnRocketSpawn, iEntity); //just being sure that all properties have been initialized first
		return;
	}
}

int oldButtons[MAXPLAYERS+1] = { 0, ... };
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if( !IsPlayerAlive( client ) )
		return Plugin_Continue;

	int iWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if( !( IsValidEntity( iWeapon ) && CanThisWeaponHome( iWeapon ) ) )
		return Plugin_Continue;

	if( buttons & IN_ATTACK2 && !( oldButtons[client] & IN_ATTACK2) ) {
		bActiveHoming[client] = !bActiveHoming[client];
		/*todo: find sound effects
		if( bActiveHoming[client] )
			EmitGameSoundToClient( client, "BaseCombatWeapon.WeaponMaterialize" );
		else
			EmitGameSoundToClient( client, "Player.WeaponSelected" );
		*/	
	}

	if( bActiveHoming[client] && !TF2_IsPlayerInCondition(client, TFCond_Taunting) ) {
		GetPlayerEye( client , fLookPosCache[client] );
		switch( TF2_GetClientTeam(client) ) {
			case TFTeam_Red:
				TE_SetupGlowSprite( fLookPosCache[client], iGlows[0], 0.1, 0.17, 75 );
			case TFTeam_Blue:
				TE_SetupGlowSprite( fLookPosCache[client], iGlows[1], 0.1, 0.17, 75 );
			case TFTeam_Green:
				TE_SetupGlowSprite( fLookPosCache[client], iGlows[2], 0.1, 0.17, 75 );
			case TFTeam_Yellow:
				TE_SetupGlowSprite( fLookPosCache[client], iGlows[3], 0.1, 0.17, 75 );
		}
		TE_SendToAll();
	}

	oldButtons[client] = buttons;
	return Plugin_Continue;
}

bool DoProjectileTracking( int iEntity ) {
	int iOwnerIndex = GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" );
	int iLauncher = GetEntPropEnt( iEntity, Prop_Send, "m_hLauncher" );
	int iOriginal = GetEntPropEnt( iEntity, Prop_Send, "m_hOriginalLauncher" );

	if( iLauncher != iOriginal || !IsPlayerAlive( iOwnerIndex ) ) return false;

	if( bActiveHoming[ iOwnerIndex ] ) {
		float RocketPos[3]; //position of rocket
		float RocketAng[3]; //angle of rocket
		float RocketVec[3]; //velocity of rocket
		float TargetVec[3]; //target velocity

		GetEntPropVector( iEntity, Prop_Data, "m_vecAbsOrigin", RocketPos );
		GetEntPropVector( iEntity, Prop_Data, "m_vecAbsVelocity", RocketVec );

		float RocketSpeed = GetVectorLength( RocketVec );
		SubtractVectors( fLookPosCache[ iOwnerIndex ] , RocketPos, TargetVec );

		float flAccuracy = GetProjectileAccuracy( iEntity );
		flAccuracy = FloatClamp( flAccuracy, 0.0, 1.0 );
		if(flAccuracy == 0.0) {
			NormalizeVector( TargetVec, RocketVec );
		}
		else {
			ScaleVector( TargetVec, flAccuracy );
			AddVectors( RocketVec, TargetVec, RocketVec );
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
	ROCKET SPECIFIC FUNCTIONS
*/

//todo: does funky stuff during server start
void Frame_OnRocketSpawn( int iProjectile ) {
	if( !( IsValidEntity( iProjectile ) ) ) return;
	int iWeapon = GetEntPropEnt( iProjectile, Prop_Send, "m_hLauncher");
	if( !CanThisWeaponHome( iWeapon ) ) return;

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

	Handle hTrace = TR_TraceRayFilterEx( flOrigin, flAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer, iClient );

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
bool TraceEntityFilterPlayer( int iEntity, int iContentsMask, any data )
{
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
	if( !IsValidEntity( iWeaponIndex ) ) return 0.0;
	return AttribHookFloat( 0.0, iWeaponIndex, "custom_rocket_homing_rate" );
}

bool CanThisWeaponHome( int iWeaponIndex )
{
	return AttribHookFloat( 0.0, iWeaponIndex, "custom_rocket_homing" ) != 0.0;
}