#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <kocwtools>

public Plugin myinfo =
{
	name = "Attribute: Magnet Wrench",
	author = "Noclue",
	description = "Attributes for the Magnet Wrench.",
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

Handle hAmmoTouch;
Handle hDispenseAmmo;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFAmmoPack::PackTouch" );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	hAmmoTouch = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CObjectDispenser::DispenseAmmo" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	hDispenseAmmo = EndPrepSDKCall();

	delete hGameConf;
}

int oldButtons[MAXPLAYERS+1] = { 0, ... };
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if( !IsPlayerAlive( client ) )
		return Plugin_Continue;

	int iWeapon = GetEntPropEnt( client, Prop_Send, "m_hActiveWeapon" );
	if( iWeapon == -1 )
		return Plugin_Continue;

	if( buttons & IN_RELOAD && !( oldButtons[client] & IN_RELOAD ) ) {
		if( AttribHookFloat( 0.0, iWeapon, "custom_magnet_grab_ammo" ) != 0.0 )
			TryGrabAmmo( client );
	}

	oldButtons[client] = buttons;
	return Plugin_Continue;
}

#define RADIUS 6.0

int g_iHit = -1;
int g_iType = 0;

void TryGrabAmmo( int iClient ) {
	float flAngles[3];
	float flOrigin[3];
	float flEndPos[3];

	GetClientEyePosition( iClient, flOrigin );
	GetClientEyeAngles( iClient, flAngles );

	GetAngleVectors( flAngles, flEndPos, NULL_VECTOR, NULL_VECTOR );
	ScaleVector( flEndPos, 2000.0 );
	AddVectors( flOrigin, flEndPos, flEndPos );

	g_iHit = -1;
	g_iType = 0;
	TR_EnumerateEntitiesHull( flOrigin, flEndPos, { -RADIUS, -RADIUS, -RADIUS }, { RADIUS, RADIUS, RADIUS }, MASK_SHOT, EnumerateAmmo, iClient );

	float vecTarget[3];
	if( g_iType == 1 ) { //ammo pack
		GetEntPropVector( g_iHit, Prop_Data, "m_vecAbsOrigin", vecTarget );
		if( CheckLOS( flOrigin, vecTarget, g_iHit ) ) {
			//int iAmmo1, iAmmo2, iMetal, iGrenade1, iGrenade2;
			int iOldAmmo[ 6 ];

			for( int i = 0; i < sizeof( iOldAmmo ); i++ ) {
				iOldAmmo[ i ] = GetEntProp( iClient, Prop_Send, "m_iAmmo", 4, i );
				PrintToServer("%i", iOldAmmo[i] );
			}

			SDKCall( hAmmoTouch, g_iHit, iClient );

			bool bGave = false;
			for( int i = 0; i < sizeof( iOldAmmo ); i++ ) {
				if( GetEntProp( iClient, Prop_Send, "m_iAmmo", 4, i ) > iOldAmmo[ i ] ) {
					bGave = true;
					break;
				}
			}

			if( bGave ) {
				CreateParticles( iClient, g_iHit );
				PrintToServer("test3");
			}
		}
			

		return;
	} else if( g_iType == 2 ) { //dispenser
		//check the base of the dispenser
		GetEntPropVector( g_iHit, Prop_Data, "m_vecAbsOrigin", vecTarget );
		if( CheckLOS( flOrigin, vecTarget, g_iHit ) ) {
			PullAmmo( g_iHit, iClient );
			return;
		}
		
		//check top of dispenser
		vecTarget[2] += 70.0;
		if( CheckLOS( flOrigin, vecTarget, g_iHit ) ) {
			PullAmmo( g_iHit, iClient );
			return;
		}
	}

	//play fail sound
}

bool EnumerateAmmo( int iEntity, any data )
{
	if ( iEntity <= MaxClients ) return true;

	static char szClassname[ 64 ];
	GetEdictClassname( iEntity, szClassname, sizeof( szClassname ) );
	
	if( StrEqual( "tf_ammo_pack", szClassname ) ) {
		g_iHit = iEntity;
		g_iType = 1;
		return false;
	}
	else if( StrEqual( "obj_dispenser", szClassname ) ) {
		g_iHit = iEntity;
		g_iType = 2;
		return false;
	}

	return true;
}

bool CheckLOS( const float vecStart[3], const float vecEnd[3], int iEntity ) {
	Handle hTrace = TR_TraceRayFilterEx( vecStart, vecEnd, 0x1 | 0x4000 | 0x40, RayType_EndPoint, LOSFilter, 0 );

	if( TR_GetFraction( hTrace ) >= 1.0 ) return false;

	int iHit = TR_GetEntityIndex( hTrace );

	if( IsValidEntity( iHit ) ) {
		static char fuck[32];
		GetEntityClassname( iHit, fuck, 32 );
	}

	if( iHit != iEntity ) return false;

	return true;
}

bool LOSFilter( int iEntity, int iMask, any data ) {
	if( iEntity <= MaxClients )
		return false;

	return true;
}

void PullAmmo( int iDispenser, int iPlayer ) {

	if( GetEntProp( iDispenser, Prop_Send, "m_bDisabled" ) || GetEntProp( iDispenser, Prop_Send, "m_bBuilding" ) || GetEntProp( iDispenser, Prop_Send, "m_bPlacing" ) )
		return;

	int iDispenserTeam = GetEntProp( iDispenser, Prop_Send, "m_iTeamNum" );
	int iPlayerTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" );

	if( iDispenserTeam != iPlayerTeam )
		return;

	if( SDKCall( hDispenseAmmo, g_iHit, iPlayer ) )
		CreateParticles( iPlayer, iDispenser, true );
}

static char g_szBeamParticles[][] = {
	"dxhr_sniper_rail_red",
	"dxhr_sniper_rail_blue",
	"dxhr_sniper_rail_green",
	"dxhr_sniper_rail_yellow"
};

static char g_szTeleportParticles[][] = {
	"teleported_red",
	"teleported_blue",
	"teleported_green",
	"teleported_yellow"
};

void CreateParticles( int iOrigin, int iTarget, bool bDispenser = false ) {
	int iTeam = GetEntProp( iOrigin, Prop_Send, "m_iTeamNum" ) - 2;

	int iParticles[2];
	iParticles[0] = CreateEntityByName( "info_particle_system" );
	iParticles[1] = CreateEntityByName( "info_particle_system" );

	DispatchKeyValue( iParticles[0], "effect_name", g_szBeamParticles[ iTeam ] );
	DispatchKeyValue( iParticles[1], "effect_name", g_szTeleportParticles[ iTeam ] );

	float vecTarget[3];
	GetEntPropVector( iTarget, Prop_Data, "m_vecAbsOrigin", vecTarget );

	if( bDispenser )
		ParentModel( iParticles[0], iTarget, "build_point_0" );
	else
		TeleportEntity( iParticles[0], vecTarget );

	SetEntPropEnt( iParticles[0], Prop_Send, "m_hControlPointEnts", iOrigin, 0 );
	DispatchSpawn( iParticles[0] );
	ActivateEntity( iParticles[0] );
	AcceptEntityInput( iParticles[0], "Start" );

	TeleportEntity( iParticles[1], vecTarget );
	DispatchSpawn( iParticles[1] );
	ActivateEntity( iParticles[1] );
	AcceptEntityInput( iParticles[1], "Start" );
}

void CheckAmmoExists( int iValue ) {
	int iClient = iValue & 0xFFFF;
	int iAmmo = iValue >> 16;
	
	int iTeam = GetEntProp( iClient, Prop_Send, "m_iTeamNum" ) - 2;

	int iParticle;
	iParticle = CreateEntityByName( "info_particle_system" );
	DispatchKeyValue( iParticle, "effect_name", g_szTeleportParticles[ iTeam ] );

	float vecTarget[3];
	GetEntPropVector( iAmmo, Prop_Data, "m_vecAbsOrigin", vecTarget );

	TeleportEntity( iParticle, vecTarget );
	DispatchSpawn( iParticle );
	ActivateEntity( iParticle );
	AcceptEntityInput( iParticle, "Start" );
}