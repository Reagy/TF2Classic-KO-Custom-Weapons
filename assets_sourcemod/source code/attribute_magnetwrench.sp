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
	version = "1.2",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

Handle hDroppedTouch;
Handle hAmmoPackTouch;
Handle hDispenseAmmo;

float g_flGrabCooler[ MAXPLAYERS+1 ] = { 0.0, ... };
bool g_bHasMagnetWrench[ MAXPLAYERS+1 ] = { false, ... };

ArrayList g_iAmmoSearchTable;

enum {
	AMMO_WORLD = 0,
	AMMO_DROPPED,
	AMMO_DISPENSER
}

public void OnPluginStart() {
	HookEvent( EVENT_POSTINVENTORY,	Event_PostInventory );

	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFAmmoPack::PackTouch" );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	hDroppedTouch = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CItem::ItemTouch" );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	hAmmoPackTouch = EndPrepSDKCall();

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

	g_bHasMagnetWrench[ iPlayer ] = AttribHookFloat( 0.0, iPlayer, "custom_magnet_grab_ammo" ) != 0.0;

	return Plugin_Continue;
}

public void OnEntityCreated( int iEntity ) {
	static char szEntityName[ 32 ];
	GetEntityClassname( iEntity, szEntityName, sizeof( szEntityName ) );
	if( StrEqual( szEntityName, "tf_ammo_pack", false ) ) {
		RequestFrame( SetAmmoOutline, EntIndexToEntRef( iEntity ) );
	} else if( StrContains( szEntityName, "item_ammopack_", false ) != -1 ) {
		RequestFrame( FixAmmoPacks, EntIndexToEntRef( iEntity ) );
	}
}

//remove the FSOLID_NOT_SOLID flag to allow traces to pick up ammo boxes
void FixAmmoPacks( int iEntity ) {
	iEntity = EntRefToEntIndex( iEntity );
	if( iEntity == -1 )
		return;
		
	SetSolidFlags( iEntity, FSOLID_TRIGGER );
}

void SetAmmoOutline( int iEntity ) {
	iEntity = EntRefToEntIndex( iEntity );
	if( iEntity == -1 )
		return;

	int iModelIndex = GetEntProp( iEntity, Prop_Send, "m_nModelIndex" );

	static char szModelName[256];
	FindModelString( iModelIndex, szModelName, sizeof( szModelName ) );

	//less than spectacular solution to exclude building gibs since they have issues with the ray trace i can't be bothered to fix
	if( StrContains( szModelName, "_gib" ) != -1 )
		return; 

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
	float vecAngles[3];
	float vecOrigin[3];
	GetClientEyePosition( iClient, vecOrigin );
	GetClientEyeAngles( iClient, vecAngles );

	float vecEndPos[3];
	GetAngleVectors( vecAngles, vecEndPos, NULL_VECTOR, NULL_VECTOR );
	ScaleVector( vecEndPos, 2000.0 );
	AddVectors( vecOrigin, vecEndPos, vecEndPos );

	TR_EnumerateEntitiesHull( vecOrigin, vecEndPos, { -RADIUS, -RADIUS, -RADIUS }, { RADIUS, RADIUS, RADIUS }, 0, EnumerateAmmo, iClient );

	int iClosest = -1;
	int iClosestType = -1;
	float flDist = 99999999.0;

	float vecTargetPos[3];
	float vecAngleToTarget[3];
	for( int i = 0; i < g_iAmmoSearchTable.Length; i++ ) {
		int iData[2];
		g_iAmmoSearchTable.GetArray( i, iData );

		GetEntPropVector( iData[0], Prop_Data, "m_vecAbsOrigin", vecTargetPos );
		MakeVectorFromPoints( vecOrigin, vecTargetPos, vecAngleToTarget );
		GetVectorAngles( vecAngleToTarget, vecAngleToTarget );

		float flNewDist = FloatAbs( GetVectorDistance( vecAngles, vecAngleToTarget ) );

		if( flNewDist < flDist ) {
			iClosest = iData[0];
			iClosestType = iData[1];
			flDist = flNewDist;
		}
	}

	g_iAmmoSearchTable.Clear();

	switch( iClosestType ) {
	case AMMO_DROPPED: {
		PickupDroppedWeapon( iClient, iClosest );
		return;
	}
	case AMMO_DISPENSER: {
		PickupAmmoDispenser( iClosest, iClient );
		return;
	}
	case AMMO_WORLD: {
		PickupAmmoBox( iClosest, iClient );
		return;
	}
	}

	EmitGameSoundToClient( iClient, "Player.DenyWeaponSelection" );
}

bool EnumerateAmmo( int iEntity, any data ) {
	if ( iEntity <= MaxClients ) return true;
	if( !IsValidEntity( iEntity ) ) return true;


	static char szClassname[ 64 ];
	GetEntityClassname( iEntity, szClassname, sizeof( szClassname ) );

	float vecOrigin[3];
	GetClientEyePosition( data, vecOrigin );

	if( StrEqual( "tf_ammo_pack", szClassname ) ) {
		return PushAmmo( vecOrigin, iEntity, AMMO_DROPPED );
	}
	else if( StrEqual( "obj_dispenser", szClassname ) ) {
		return PushAmmo( vecOrigin, iEntity, AMMO_DISPENSER );
	}
	else if( StrContains( szClassname, "item_ammopack_", false ) != -1 ) {
		return PushAmmo( vecOrigin, iEntity, AMMO_WORLD );
	}

	return true;
}

bool PushAmmo( const float vecOrigin[3], int iEntity, int iType ) {
	if( iType == AMMO_DROPPED ) {
		static char szModelName[256];
		FindModelString( GetEntProp( iEntity, Prop_Send, "m_nModelIndex" ), szModelName, sizeof( szModelName ) );

		//less than spectacular solution to exclude building gibs since they have issues with the ray trace i can't be bothered to fix
		if( StrContains( szModelName, "_gib" ) != -1 )
			return true; 
	}

	float vecTarget[3];
	GetEntPropVector( iEntity, Prop_Data, "m_vecAbsOrigin", vecTarget );

	if( !CheckLOS( vecOrigin, vecTarget, iEntity ) ) {
		//check the top of the dispenser
		if( iType == AMMO_DISPENSER ) {
			vecTarget[2] += 70.0;
			if( !CheckLOS( vecOrigin, vecTarget, iEntity ) )
				return true;
		}
		else if( iType == AMMO_WORLD ) {
			vecTarget[2] += 2.0;
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
	if( TR_GetEntityIndex( hTrace ) != iEntity ) return false;
	return true;
}

bool LOSFilter( int iEntity, int iMask, any data ) {
	return !(iEntity <= MaxClients);
}

void PickupAmmoBox( int iAmmo, int iClient ) {
	int iOldAmmo[ 6 ];

	for( int i = 0; i < sizeof( iOldAmmo ); i++ ) {
		iOldAmmo[ i ] = GetEntProp( iClient, Prop_Send, "m_iAmmo", 4, i );
	}

	SDKCall( hAmmoPackTouch, iAmmo, iClient );

	for( int i = 0; i < sizeof( iOldAmmo ); i++ ) {
		if( GetEntProp( iClient, Prop_Send, "m_iAmmo", 4, i ) > iOldAmmo[ i ] ) {
			CreateParticles( iClient, iAmmo );
			return;
		}
	}
}

void PickupDroppedWeapon( int iClient, int iAmmo ) {
	int iOldAmmo[ 6 ];

	for( int i = 0; i < sizeof( iOldAmmo ); i++ ) {
		iOldAmmo[ i ] = GetEntProp( iClient, Prop_Send, "m_iAmmo", 4, i );
	}

	SDKCall( hDroppedTouch, iAmmo, iClient );

	for( int i = 0; i < sizeof( iOldAmmo ); i++ ) {
		if( GetEntProp( iClient, Prop_Send, "m_iAmmo", 4, i ) > iOldAmmo[ i ] ) {
			CreateParticles( iClient, iAmmo );
			return;
		}
	}
}

bool PickupAmmoDispenser( int iDispenser, int iPlayer ) {
	if( GetEntProp( iDispenser, Prop_Send, "m_bDisabled" ) || GetEntProp( iDispenser, Prop_Send, "m_bBuilding" ) || GetEntProp( iDispenser, Prop_Send, "m_bPlacing" ) )
		return false;

	int iDispenserTeam = GetEntProp( iDispenser, Prop_Send, "m_iTeamNum" );
	int iPlayerTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" );

	if( iDispenserTeam != iPlayerTeam )
		return false;

	if( g_flGrabCooler[ iPlayer ] <= GetGameTime() && SDKCall( hDispenseAmmo, iDispenser, iPlayer ) ) {
		CreateParticles( iPlayer, iDispenser, AMMO_DISPENSER );
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

void CreateParticles( int iOrigin, int iTarget, int iType = 0 ) {
	int iTeam = GetEntProp( iOrigin, Prop_Send, "m_iTeamNum" ) - 2;

	int iParticles[2];
	iParticles[0] = CreateEntityByName( "info_particle_system" );
	iParticles[1] = CreateEntityByName( "info_particle_system" );

	DispatchKeyValue( iParticles[0], "effect_name", g_szBeamParticles[ iTeam ] );
	DispatchKeyValue( iParticles[1], "effect_name", g_szTeleportParticles[ iTeam ] );

	float vecTarget[3];
	GetEntPropVector( iTarget, Prop_Data, "m_vecAbsOrigin", vecTarget );

	if( iType == AMMO_DISPENSER ) {
		ParentModel( iParticles[0], iTarget, "build_point_0" );
	}
	else if( iType == AMMO_WORLD ) {
		vecTarget[2] += 25.0;
		TeleportEntity( iParticles[0], vecTarget );
	}
	else {
		TeleportEntity( iParticles[0], vecTarget );
	}

	SetEntPropEnt( iParticles[0], Prop_Send, "m_hControlPointEnts", iOrigin, 0 );
	DispatchSpawn( iParticles[0] );
	ActivateEntity( iParticles[0] );
	AcceptEntityInput( iParticles[0], "Start" );

	DispatchSpawn( iParticles[1] );
	ActivateEntity( iParticles[1] );
	AcceptEntityInput( iParticles[1], "Start" );
	TeleportEntity( iParticles[1], vecTarget );

	GetEntPropVector( iParticles[1], Prop_Data, "m_vecAbsOrigin", vecTarget );

	CreateTimer( 0.1, DeletThis, EntIndexToEntRef( iParticles[0] ), TIMER_FLAG_NO_MAPCHANGE );
	CreateTimer( 0.1, DeletThis, EntIndexToEntRef( iParticles[1] ), TIMER_FLAG_NO_MAPCHANGE );

	EmitSoundToAll( "weapons/teleporter_send.wav", iTarget );
	EmitSoundToAll( "weapons/teleporter_receive.wav", iOrigin );
}

Action DeletThis( Handle hTimer, int iDelete ) {
	iDelete = EntRefToEntIndex( iDelete );
	if( iDelete == -1 )
		return Plugin_Stop;
		
	RemoveEntity( iDelete );
	return Plugin_Stop;
}