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

float g_flGrabCooler[ MAXPLAYERS+1 ] = { 0.0, ... };
bool g_bHasMagnetWrench[ MAXPLAYERS+1 ] = { false, ... };

ArrayList g_iAmmoSearchTable;

public void OnPluginStart() {
	HookEvent( EVENT_POSTINVENTORY,	Event_PostInventory );

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

	g_iAmmoSearchTable = new ArrayList( 2 );

	delete hGameConf;
}

public void OnMapStart() {
	PrecacheSound( "weapons/teleporter_send.wav" );
	PrecacheSound( "weapons/teleporter_receive.wav" );
}

Action Event_PostInventory( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	if( !IsValidPlayer( iPlayer ) )
		return Plugin_Continue;

	float flMagnet = AttribHookFloat( 0.0, iPlayer, "custom_magnet_grab_ammo" );
	g_bHasMagnetWrench[ iPlayer ] = flMagnet != 0.0;

	return Plugin_Continue;
}

public void OnEntityCreated( int iEntity ) {
	static char szEntityName[ 32 ];
	GetEntityClassname( iEntity, szEntityName, sizeof( szEntityName ) );
	if( StrEqual( szEntityName, "tf_ammo_pack", false ) )
		RequestFrame( SetAmmoOutline, iEntity );
}

void SetAmmoOutline( int iEntity ) {
	int iGlow = CreateEntityByName( "tf_glow" );

	static char szOldName[ 64 ];
	GetEntPropString( iEntity, Prop_Data, "m_iName", szOldName, sizeof(szOldName) );

	char szNewName[ 128 ], szClassname[ 64 ];
	GetEntityClassname( iEntity, szClassname, sizeof( szClassname ) );
	Format( szNewName, sizeof( szNewName ), "%s%i", szClassname, iEntity );
	DispatchKeyValue( iEntity, "targetname", szNewName );

	DispatchKeyValue( iGlow, "target", szNewName);
	DispatchSpawn( iGlow );
	
	SetEntPropString( iEntity, Prop_Data, "m_iName", szOldName );
	
	ParentModel( iGlow, iEntity );

	SetEdictFlags( iGlow, 0 );
	SDKHook( iGlow, SDKHook_SetTransmit, GlowTransmit );

	int iColor[4] = { 255,255,255,255 };
	SetVariantColor( iColor );
	AcceptEntityInput( iGlow, "SetGlowColor" );
}

Action GlowTransmit( int iEntity, int iClient ) {
	SetEdictFlags( iEntity, 0 );
	return g_bHasMagnetWrench[ iClient ] ? Plugin_Continue : Plugin_Handled;
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

#define RADIUS 4.0

void TryGrabAmmo( int iClient ) {
	float flAngles[3];
	float flOrigin[3];
	float flEndPos[3];

	GetClientEyePosition( iClient, flOrigin );
	GetClientEyeAngles( iClient, flAngles );

	GetAngleVectors( flAngles, flEndPos, NULL_VECTOR, NULL_VECTOR );
	ScaleVector( flEndPos, 2000.0 );
	AddVectors( flOrigin, flEndPos, flEndPos );

	TR_EnumerateEntitiesHull( flOrigin, flEndPos, { -RADIUS, -RADIUS, -RADIUS }, { RADIUS, RADIUS, RADIUS }, MASK_SHOT, EnumerateAmmo, iClient );

	int iClosest = -1;
	int iClosestType = 0;
	float flDist = 99999999.0;

	float vecTargetPos[3];
	float vecAngleToTarget[3];
	for( int i = 0; i < g_iAmmoSearchTable.Length; i++ ) {
		int iData[2];
		g_iAmmoSearchTable.GetArray( i, iData );

		GetEntPropVector( iData[0], Prop_Data, "m_vecAbsOrigin", vecTargetPos );
		MakeVectorFromPoints( flOrigin, vecTargetPos, vecAngleToTarget );
		GetVectorAngles( vecAngleToTarget, vecAngleToTarget );

		float flNewDist = FloatAbs( GetVectorDistance( flAngles, vecAngleToTarget ) );
		PrintToServer("%i %i %f", iData[0], iData[1], flNewDist );

		if( flNewDist < flDist ) {
			iClosest = iData[0];
			iClosestType = iData[1];
			flDist = flNewDist;
		}
	}

	g_iAmmoSearchTable.Clear();

	if( iClosestType == 1 ) { //ammo pack
		PickupAmmoBox( iClient, iClosest );
		return;
	} else if( iClosestType == 2 ) { //dispenser
		PickupAmmoDispenser( iClosest, iClient );
		return;
	}

	EmitGameSoundToClient( iClient, "Player.DenyWeaponSelection" );
}

void PickupAmmoBox( int iClient, int iAmmo ) {
	int iOldAmmo[ 6 ];

	for( int i = 0; i < sizeof( iOldAmmo ); i++ ) {
		iOldAmmo[ i ] = GetEntProp( iClient, Prop_Send, "m_iAmmo", 4, i );
	}

	SDKCall( hAmmoTouch, iAmmo, iClient );

	for( int i = 0; i < sizeof( iOldAmmo ); i++ ) {
		if( GetEntProp( iClient, Prop_Send, "m_iAmmo", 4, i ) > iOldAmmo[ i ] ) {
			CreateParticles( iClient, iAmmo );
			return;
		}
	}
}

bool EnumerateAmmo( int iEntity, any data ) {
	if ( iEntity <= MaxClients ) return true;

	static char szClassname[ 64 ];
	GetEdictClassname( iEntity, szClassname, sizeof( szClassname ) );

	if( StrEqual( "tf_ammo_pack", szClassname ) ) {
		float vecOrigin[3];
		GetClientEyePosition( data, vecOrigin );
		return PushAmmo( vecOrigin, iEntity, 1 );
	}
	else if( StrEqual( "obj_dispenser", szClassname ) ) {
		float vecOrigin[3];
		GetClientEyePosition( data, vecOrigin );
		return PushAmmo( vecOrigin, iEntity, 2 );
	}

	return true;
}

bool PushAmmo( const float vecOrigin[3], int iEntity, int iType ) {
	float vecTarget[3];
	GetEntPropVector( iEntity, Prop_Data, "m_vecAbsOrigin", vecTarget );

	if( !CheckLOS( vecOrigin, vecTarget, iEntity ) ) {
		if( iType == 2 ) {
			vecTarget[2] += 70.0;
			if( !CheckLOS( vecOrigin, vecTarget, iEntity ) )
				return true;
		}

		return true;
	}

	int iPush[2];
	iPush[0] = iEntity;
	iPush[1] = iType;
	
	g_iAmmoSearchTable.PushArray( iPush );

	return true;
}

bool CheckLOS( const float vecStart[3], const float vecEnd[3], int iEntity ) {
	Handle hTrace = TR_TraceRayFilterEx( vecStart, vecEnd, CONTENTS_SOLID | CONTENTS_MOVEABLE | CONTENTS_MIST, RayType_EndPoint, LOSFilter, 0 );

	if( TR_GetFraction( hTrace ) >= 1.0 ) return false;

	int iHit = TR_GetEntityIndex( hTrace );

	if( iHit != iEntity ) return false;

	return true;
}

bool LOSFilter( int iEntity, int iMask, any data ) {
	if( iEntity <= MaxClients )
		return false;

	return true;
}

bool PickupAmmoDispenser( int iDispenser, int iPlayer ) {

	if( GetEntProp( iDispenser, Prop_Send, "m_bDisabled" ) || GetEntProp( iDispenser, Prop_Send, "m_bBuilding" ) || GetEntProp( iDispenser, Prop_Send, "m_bPlacing" ) )
		return false;

	int iDispenserTeam = GetEntProp( iDispenser, Prop_Send, "m_iTeamNum" );
	int iPlayerTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" );

	if( iDispenserTeam != iPlayerTeam )
		return false;

	if( g_flGrabCooler[ iPlayer ] <= GetGameTime() && SDKCall( hDispenseAmmo, iDispenser, iPlayer ) ) {
		CreateParticles( iPlayer, iDispenser, true );
		g_flGrabCooler[ iPlayer ] = GetGameTime() + 1.0;
		return true;
	}
	return false;
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

	CreateTimer( 0.1, DeletThis, iParticles[0], TIMER_FLAG_NO_MAPCHANGE );
	CreateTimer( 0.1, DeletThis, iParticles[1], TIMER_FLAG_NO_MAPCHANGE );

	EmitSoundToAll( "weapons/teleporter_send.wav", iTarget );
	EmitSoundToAll( "weapons/teleporter_receive.wav", iOrigin );
}

Action DeletThis( Handle hTimer, int iDelete ) {
	RemoveEntity( iDelete );
	return Plugin_Stop;
}