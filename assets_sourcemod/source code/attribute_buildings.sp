#pragma newdecls required
#pragma semicolon 1

#include <tf2c>
#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <kocwtools>
#include <dhooks>

public Plugin myinfo = {
	name = "Attribute: Buildings",
	author = "Noclue",
	description = "Attributes for sentries.",
	version = "1.2",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

static int g_iBaseHealth[][][] = {
	{ //dispenser
		{ 150, 180, 216 },	//normal
		{ 150, 150, 150 },	//mini
		{ 100, 100, 100 },	//dummy
		{ 100, 100, 100 },	//dummy
	},
	{ //teleporter
		{ 150, 180, 216 },	//normal
		{ 100, 100, 100 },	//mini
		{ 100, 100, 100 },	//dummy
		{ 100, 100, 100 },	//dummy
	},
	{ //sentry
		{ 150, 180, 216 },	//normal
		{ 100, 100, 100 },	//mini
		{ 150, 180, 216 },	//heavy
		{ 150, 188, 225 },	//clover
	}
};
static int g_iLevelCost[][][] = {
	{ //dispenser
		{ 200, 200 },	//normal 
		{ 000, 000 },	//mini
		{ 000, 000 },	//dummy
		{ 000, 000 },	//dummy
	},
	{ //teleporter
		{ 200, 200 },	//normal
		{ 000, 000 },	//mini
		{ 000, 000 },	//dummy
		{ 000, 000 },	//dummy
	},
	{ //sentry
		{ 200, 200 },	//normal
		{ 000, 000 },	//mini
		{ 200, 200 },	//heavy
		{ 200, 200 },	//clover
	},
};

static char g_sSirenParticles[][] = {
	"cart_flashinglight_red",
	"cart_flashinglight",
	"cart_flashinglight_green",
	"cart_flashinglight_yellow"
};

enum {
	OBJ_DISPENSER = 0,
	OBJ_TELEPORTER,
	OBJ_SENTRYGUN,

	OBJ_SAPPER,

	OBJ_JUMPPAD,
}

enum {
	DISPENSER_NORMAL = 0,
	DISPENSER_MINI,
}
enum {
	TELEPORT_NORMAL = 0,
	TELEPORT_MINI,
}
enum {
	SENTRY_NORMAL = 0,
	SENTRY_MINI,
	SENTRY_ARTILLERY,
	SENTRY_CLOVER,
}
enum {
	SAPPER_NORMAL = 0,
	SAPPER_INTERMISSION,
}

//building models, stored as type, override, level, is upgrading
int g_iBuildingModels[3][4][3][2];
//sapper models, stored as override
int g_iSapperModels[2];
//blueprint models, stored as type, override, mode
int g_iBuildingBlueprints[3][2];
//stores all player's current building types, updated on post inventory
int g_iBuildingTypes[MAXPLAYERS][3];
//list of info_particle_systems for mini-sentries
ArrayList g_hSirenList;

int g_iGoalBuildOffset = -1;

Handle hDetonateOwned;
Handle hGetObject;
Handle hObjectCount;
Handle hDestroyScreens;
DynamicHook hStartBuilding;
DynamicHook hStartUpgrade;
DynamicHook hFinishUpgrade;
DynamicHook hOnGoActive;
DynamicHook hMakeCarry;
DynamicHook hCanUpgrade;
DynamicDetour hDispHeal;

bool bLateLoad = false;
public APLRes AskPluginLoad2( Handle hMyself, bool bLate, char[] error, int err_max ) {
	bLateLoad = bLate;
	return APLRes_Success;
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	HookEvent( EVENT_POSTINVENTORY,		Event_PostInventory );

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayer::DetonateOwnedObjectsOfType" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //int - type
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //int - mode
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //bool - silent
	hDetonateOwned = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayer::GetObject" );
	PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //int - index
	hGetObject = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayer::GetObjectCount" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain ); //int - count
	hObjectCount = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CBaseObject::DestroyScreens" );
	hDestroyScreens = EndPrepSDKCall();

	hStartBuilding =	DynamicHook.FromConf( hGameConf, "CBaseObject::StartBuilding" );
	hOnGoActive =		DynamicHook.FromConf( hGameConf, "CBaseObject::OnGoActive" );
	hCanUpgrade =		DynamicHook.FromConf( hGameConf, "CBaseObject::CanBeUpgraded" );
	hStartUpgrade =		DynamicHook.FromConf( hGameConf, "CBaseObject::StartUpgrading" );
	hFinishUpgrade =	DynamicHook.FromConf( hGameConf, "CBaseObject::FinishUpgrading" );
	hMakeCarry =		DynamicHook.FromConf( hGameConf, "CBaseObject::MakeCarriedObject" );

	hDispHeal = DynamicDetour.FromConf( hGameConf, "CObjectDispenser::GetHealRate" );
	hDispHeal.Enable( Hook_Post, Detour_GetHealRate );

	g_iGoalBuildOffset = GameConfGetOffset( hGameConf, "CBaseObject::m_iGoalUpgradeLevel" );

	g_hSirenList = new ArrayList( 2 );

	if( bLateLoad )
		Lateload();

	delete hGameConf;
}

public void OnMapStart() {
	//sentry
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_MINI ][ 0 ][ 0 ] =		PrecacheModel( "models/buildables/sentry_mini.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_MINI ][ 0 ][ 1 ] =		PrecacheModel( "models/buildables/sentry_mini_build.mdl" );

	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_ARTILLERY ][ 0 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_heavy1.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_ARTILLERY ][ 1 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_heavy2.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_ARTILLERY ][ 2 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_heavy3.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_ARTILLERY ][ 0 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_heavy1_build.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_ARTILLERY ][ 1 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_heavy2_build.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_ARTILLERY ][ 2 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_heavy3_build.mdl" );

	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_CLOVER ][ 0 ][ 0 ] =		PrecacheModel( "models/buildables/sentry_clover1.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_CLOVER ][ 1 ][ 0 ] =		PrecacheModel( "models/buildables/sentry_clover2.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_CLOVER ][ 2 ][ 0 ] =		PrecacheModel( "models/buildables/sentry_clover3.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_CLOVER ][ 0 ][ 1 ] =		PrecacheModel( "models/buildables/sentry_clover1_build.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_CLOVER ][ 1 ][ 1 ] =		PrecacheModel( "models/buildables/sentry_clover2_build.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_CLOVER ][ 2 ][ 1 ] =		PrecacheModel( "models/buildables/sentry_clover3_build.mdl" );

	g_iBuildingBlueprints[ OBJ_SENTRYGUN ][ 0 ] =				PrecacheModel( "models/buildables/sentry1_blueprint.mdl" );

	//dispenser
	g_iBuildingModels[ OBJ_DISPENSER ][ DISPENSER_MINI ][ 0 ][ 0 ] = 	PrecacheModel( "models/buildables/minidispenser.mdl" );
	g_iBuildingModels[ OBJ_DISPENSER ][ DISPENSER_MINI ][ 0 ][ 1 ] = 	PrecacheModel( "models/buildables/minidispenser.mdl" );

	g_iBuildingBlueprints[ OBJ_DISPENSER ][ 0 ] =				PrecacheModel( "models/buildables/dispenser_blueprint.mdl" );

	//teleporter	

	g_iBuildingBlueprints[ OBJ_TELEPORTER ][ 0 ] =				PrecacheModel( "models/buildables/teleporter_blueprint_enter.mdl" );
	g_iBuildingBlueprints[ OBJ_TELEPORTER ][ 1 ] =				PrecacheModel( "models/buildables/teleporter_blueprint_exit.mdl" );

	//sapper
	g_iSapperModels[ SAPPER_INTERMISSION ] = 				PrecacheModel( "models/buildables/intermission_placed.mdl" );

	PrecacheSound( "weapons/sentry_shoot_mini.wav" );

	PrecacheSound( "weapons/buildings/Ironclad_Shoot1.wav" );
	PrecacheSound( "weapons/buildings/Ironclad_Shoot2.wav" );
	PrecacheSound( "weapons/buildings/Ironclad_Shoot3.wav" );
	PrecacheSound( "weapons/buildings/Ironclad_Scan1.wav" );
	PrecacheSound( "weapons/buildings/Ironclad_Scan2.wav" );
	PrecacheSound( "weapons/buildings/Ironclad_Scan3.wav" );
	PrecacheSound( "weapons/buildings/Ironclad_Spot.wav" );
	PrecacheSound( "weapons/buildings/Ironclad_Spot_Client.wav" );

	PrecacheSound( "weapons/buildings/LucyCharm_Shoot1.wav" );
	PrecacheSound( "weapons/buildings/LucyCharm_Shoot2.wav" );
	PrecacheSound( "weapons/buildings/LucyCharm_Shoot3.wav" );
	PrecacheSound( "weapons/buildings/LucyCharm_Scan1.wav" );
	PrecacheSound( "weapons/buildings/LucyCharm_Scan2.wav" );
	PrecacheSound( "weapons/buildings/LucyCharm_Scan3.wav" );
	PrecacheSound( "weapons/buildings/LucyCharm_Spot.wav" );
	PrecacheSound( "weapons/buildings/LucyCharm_Spot_Client.wav" );

	AddNormalSoundHook( Hook_BuildingSounds );
}

/*
	Building Callbacks
*/

//called when a building is created or placed from carry
MRESReturn Hook_StartBuilding( int iThis ) {
	int iType = GetEntProp( iThis, Prop_Send, "m_iObjectType" );

	if( iType == OBJ_JUMPPAD )
		return MRES_Handled;

	SetBuildingModel( iThis, true );
	UpdateBuilding( iThis );

	int iPlayer = GetEntPropEnt( iThis, Prop_Send, "m_hBuilder" );
	int iOverride = g_iBuildingTypes[ iPlayer ][ iType ];

	switch( iType ) {
	case OBJ_DISPENSER: {
		if( iOverride == DISPENSER_MINI ) {
			SetEntProp( iThis, Prop_Send, "m_iHighestUpgradeLevel", 0 );
			SetEntProp( iThis, Prop_Send, "m_bMiniBuilding", 1 );
		}
	}
	case OBJ_TELEPORTER: {
	}
	case OBJ_SENTRYGUN: {
		if( iOverride == SENTRY_MINI ) {
			SetEntProp( iThis, Prop_Send, "m_iHighestUpgradeLevel", 0 );
			SetEntProp( iThis, Prop_Send, "m_bMiniBuilding", 1 );	
		}
	}
	}

	return MRES_Handled;
}
//called when a building activates at level 1 only
MRESReturn Hook_OnGoActive( int iThis ) {
	int iType = GetEntProp( iThis, Prop_Send, "m_iObjectType" );

	if( iType == OBJ_JUMPPAD )
		return MRES_Handled;

	int iPlayer = GetEntPropEnt( iThis, Prop_Send, "m_hBuilder" );

	if( iType == OBJ_SENTRYGUN && g_iBuildingTypes[ iPlayer ][ iType ] == SENTRY_MINI )
		CreateSirenParticle( iThis );

	SetBuildingModel( iThis, false );
	return MRES_Handled;
}
//called when an upgrade animation starts
MRESReturn Hook_StartUpgrade( int iThis ) {
	SetBuildingModel( iThis, true );
	UpdateBuilding( iThis, true );
	return MRES_Handled;
}
//called when an upgrade animation ends
MRESReturn Hook_FinishUpgrade( int iThis ) {
	SetBuildingModel( iThis, false );
	UpdateBuilding( iThis );
	return MRES_Handled;
}
//called when a building is picked up
MRESReturn Hook_MakeCarry( int iThis ) {
	int iType = 	GetEntProp( iThis, Prop_Send, "m_iObjectType" );
	int iMode =	GetEntProp( iThis, Prop_Send, "m_iObjectMode" );

	int iModel = g_iBuildingBlueprints[ iType ][ iMode ];
	SetEntProp( iThis, Prop_Send, "m_nModelIndexOverrides", iModel, 4, 0 );

	int iPlayer = GetEntPropEnt( iThis, Prop_Send, "m_hBuilder" );
	if( iType == OBJ_SENTRYGUN && g_iBuildingTypes[ iPlayer ][ iType ] == SENTRY_MINI )
		DestroySirenParticle( iThis );

	return MRES_Handled;
}
//returns whether a building can be upgraded
MRESReturn Hook_CanBeUpgraded( int iThis, DHookReturn hReturn ) {
	if( IsBuildingMini( iThis ) ) {
		hReturn.Value = false;
		return MRES_ChangedOverride;
	}
	return MRES_Ignored;
}

//returns the health per second of a dispenser
MRESReturn Detour_GetHealRate( int iThis, DHookReturn hReturn ) {
	int iChanged = false;
	float flNewValue = hReturn.Value;
	if( IsBuildingMini( iThis ) ) {
		flNewValue = 15.0;
		iChanged++;
	}
	
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hBuilder" );
	if( IsValidPlayer( iOwner ) ) {
		float flOldValue = flNewValue;
		flNewValue = AttribHookFloat( flNewValue, iOwner, "custom_dispenser_healrate" );

		if( flNewValue != flOldValue )
			iChanged++;
	}
	
	if( iChanged ) {
		hReturn.Value = flNewValue;
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

Action Hook_BuildingSounds( int iClients[MAXPLAYERS], int& iNumClients, char sSample[PLATFORM_MAX_PATH], int& iEntity, int& iChannel, float& flVolume, int& iLevel, int& iPitch, int& iFlags, char sSoundEntry[PLATFORM_MAX_PATH], int &iSeed ) {
	if( !IsValidEntity( iEntity ) )
		return Plugin_Continue;

	static char sClassname[64];
	GetEntityClassname( iEntity, sClassname, sizeof( sClassname ) );
	if( StrContains( sClassname, "obj_", true ) != 0 ) 
		return Plugin_Continue;

	int iBuilder = GetEntPropEnt( iEntity, Prop_Send, "m_hBuilder" );
	if( !IsValidPlayer( iBuilder ) )
		return Plugin_Continue;

	int iType = GetEntProp( iEntity, Prop_Send, "m_iObjectType" );
	switch( iType ) {
	case OBJ_SENTRYGUN: 
		return SentrySoundHook( iEntity, sSample, iPitch, iLevel );
	}

	return Plugin_Continue;
}

Action SentrySoundHook( int iBuilding, char sSample[PLATFORM_MAX_PATH], int &iPitch, int &iLevel ) {
	switch( GetBuildingOverride( iBuilding ) ) {
	case SENTRY_MINI: {
		if( StrContains( sSample, "weapons/sentry_shoot", true ) != -1 ) {
			sSample = "weapons/sentry_shoot_mini.wav";
			return Plugin_Changed;
		} 
		else if( StrContains( sSample, "weapons/sentry_scan", true ) != -1 ) {
			iPitch = 120;
			return Plugin_Changed;
		}
	}
	case SENTRY_ARTILLERY: {
		if( StrContains( sSample, "weapons/sentry_shoot", true ) != -1 ) {
			sSample = "weapons/buildings/Ironclad_Shoot1.wav";
			return Plugin_Changed;
		} 
		else if( StrContains( sSample, "weapons/sentry_scan", true ) != -1 ) {
			Format( sSample, PLATFORM_MAX_PATH, "weapons/buildings/Ironclad_Scan%i.wav", GetEntProp( iBuilding, Prop_Send, "m_iUpgradeLevel" ) );
			return Plugin_Changed;
		}
		else if( StrEqual( sSample, "weapons/sentry_spot.wav", true ) ) {
			sSample = "weapons/buildings/Ironclad_Spot.wav";
			return Plugin_Changed;
		}
		else if( StrEqual( sSample, "weapons/sentry_spot_client.wav", true ) ) {
			sSample = "weapons/buildings/Ironclad_Spot_Client.wav";
			return Plugin_Changed;
		}
	}
	case SENTRY_CLOVER: {
		if( StrContains( sSample, "weapons/sentry_shoot", true ) != -1 ) {
			Format( sSample, PLATFORM_MAX_PATH, "weapons/buildings/LucyCharm_Shoot%i.wav", GetEntProp( iBuilding, Prop_Send, "m_iUpgradeLevel" ) );
			return Plugin_Changed;
		} 
		else if( StrContains( sSample, "weapons/sentry_scan", true ) != -1 ) {
			Format( sSample, PLATFORM_MAX_PATH, "weapons/buildings/LucyCharm_Scan%i.wav", GetEntProp( iBuilding, Prop_Send, "m_iUpgradeLevel" ) );
			return Plugin_Changed;
		}
		else if( StrEqual( sSample, "weapons/sentry_spot.wav", true ) ) {
			sSample = "weapons/buildings/LucyCharm_Spot.wav";
			return Plugin_Changed;
		}
		else if( StrEqual( sSample, "weapons/sentry_spot_client.wav", true ) ) {
			sSample = "weapons/buildings/LucyCharm_Spot_Client.wav";
			return Plugin_Changed;
		}
	}
	}

	return Plugin_Continue;
}

/*
	Other Callbacks
*/


public void OnEntityCreated( int iEntity, const char[] sClassname ) {
	if( StrContains( sClassname, "obj_", true ) != 0 ) 
		return;
	
	if( StrEqual( sClassname, "obj_attachment_sapper", true ) ) {
		//SetupSapper( iEntity );
		return;
	}
		
	SetupObjectHooks( iEntity );
}

Action Event_PostInventory( Event hEvent, const char[] sName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	CheckBuildings( iPlayer );
	return Plugin_Continue;
}


/*
	Building info functions
*/


//returns the target building level used while a building is redeployed
int BuildingTargetLevel( int iBuilding ) {
	return LoadFromEntity( iBuilding, g_iGoalBuildOffset );
}

int GetBuildingOverride( int iBuilding ) {
	int iBuilder =	GetEntPropEnt( iBuilding, Prop_Send, "m_hBuilder" );
	int iType = 	GetEntProp( iBuilding, Prop_Send, "m_iObjectType");

	return g_iBuildingTypes[ iBuilder ][ iType ];
}

bool IsBuildingMini( int iBuilding ) {
	return GetEntProp( iBuilding, Prop_Send, "m_bMiniBuilding" ) != 0;
}


/*
	Building management
*/


void UpdateBuilding( int iBuilding, bool bHeal = false ) {
	int iPlayer = GetEntPropEnt( iBuilding, Prop_Send, "m_hBuilder" );
	int iType = GetEntProp( iBuilding, Prop_Send, "m_iObjectType" );

	UpdateBuildingHealth( iPlayer, iBuilding, bHeal );
	UpdateBuildingCost( iPlayer, iBuilding, iType );

	if( iType == OBJ_SENTRYGUN && g_iBuildingTypes[ iPlayer ][ iType ] == SENTRY_MINI ) {
		int iSkin = GetEntProp( iBuilding, Prop_Send, "m_nSkin" );
		SetEntProp( iBuilding, Prop_Send, "m_nSkin", iSkin + 4 );
		SetEntPropFloat( iBuilding, Prop_Send, "m_flModelScale", 0.75 );
	}
	if( iType == OBJ_DISPENSER && g_iBuildingTypes[ iPlayer ][ iType ] == DISPENSER_MINI ) {
		DestroyScreens( iBuilding );
	}
}

static char g_szBuildingHealthAttribs[][] = {
	"mult_dispenser_health",
	"mult_teleporter_health",
	"mult_sentry_health",
	"mult_sapper_health"
};

void UpdateBuildingHealth( int iPlayer, int iBuilding, bool bHeal = false ) {
	int iBuildingType = GetEntProp( iBuilding, Prop_Send, "m_iObjectType" );
	if( iBuildingType == OBJ_JUMPPAD )
		return;

	int iBuildingLevel = GetEntProp( iBuilding, Prop_Send, "m_bCarryDeploy" ) ? 
		BuildingTargetLevel( iBuilding ) - 1 :
		GetEntProp( iBuilding, Prop_Send, "m_iUpgradeLevel" ) - 1;

	int iBaseHealth = g_iBaseHealth[ iBuildingType ][ g_iBuildingTypes[ iPlayer ][ iBuildingType ] ][ iBuildingLevel ];

	float flMultiplier = AttribHookFloat( 1.0, iPlayer, "mult_engy_building_health" );
	flMultiplier = AttribHookFloat( flMultiplier, iPlayer, g_szBuildingHealthAttribs[ iBuildingType ] );

	iBaseHealth = RoundFloat( float( iBaseHealth ) * flMultiplier );

	SetEntProp( iBuilding, Prop_Send, "m_iMaxHealth", iBaseHealth );
	if( bHeal )
		SetEntProp( iBuilding, Prop_Send, "m_iHealth", iBaseHealth );
	else 
		SetEntProp( iBuilding, Prop_Send, "m_iHealth", IntClamp( GetEntProp( iBuilding, Prop_Send, "m_iHealth" ) , 0, iBaseHealth ) );
}

void UpdateBuildingCost( int iPlayer, int iBuilding, int iType ) {
	int iBuildingLevel = GetEntProp( iBuilding, Prop_Send, "m_iUpgradeLevel" );
	int iNewCost = g_iLevelCost[ iType ][ g_iBuildingTypes[ iPlayer ][ iType ] ][ IntClamp( iBuildingLevel - 1, 0, 1 ) ];

	SetEntProp( iBuilding, Prop_Send, "m_iUpgradeMetalRequired", iNewCost );
}

void SetBuildingModel( int iBuilding, bool bIsUpgrading ) {
	int iBuilder =	GetEntPropEnt( iBuilding, Prop_Send, "m_hBuilder" );
	int iType = 	GetEntProp( iBuilding, Prop_Send, "m_iObjectType");
	int iLevel =	GetEntProp( iBuilding, Prop_Send, "m_iUpgradeLevel" );

	int iOverride = g_iBuildingTypes[ iBuilder ][ iType ];
	int iModel = g_iBuildingModels[ iType ][ iOverride ][ iLevel - 1 ][ view_as<int>( bIsUpgrading ) ];
	SetEntProp( iBuilding, Prop_Send, "m_nModelIndexOverrides", iModel, 4, 0 );
}

void CheckBuildings( int iPlayer ) {
	if( !IsValidPlayer( iPlayer ) )
		return;

	if( TF2_GetPlayerClass( iPlayer ) != TFClass_Engineer ) {
		g_iBuildingTypes[iPlayer] = { 0, 0, 0 };
		return;
	}

	int iSentryType = 	RoundToNearest( AttribHookFloat( 0.0, iPlayer, "custom_sentry_type" ) );
	int iDispenserType = 	RoundToNearest( AttribHookFloat( 0.0, iPlayer, "custom_dispenser_type" ) );
	int iTeleporterType = 	RoundToNearest( AttribHookFloat( 0.0, iPlayer, "custom_teleporter_type" ) );

	if( g_iBuildingTypes[iPlayer][OBJ_DISPENSER] != iDispenserType ) {
		DetonatedOwnedObjects( iPlayer, OBJ_DISPENSER );
	}
	if( g_iBuildingTypes[iPlayer][OBJ_TELEPORTER] != iTeleporterType ) {
		DetonatedOwnedObjects( iPlayer, OBJ_TELEPORTER, 0 );
		DetonatedOwnedObjects( iPlayer, OBJ_TELEPORTER, 1 );
	}
	if( g_iBuildingTypes[iPlayer][OBJ_SENTRYGUN] != iSentryType ) {
		DetonatedOwnedObjects( iPlayer, OBJ_SENTRYGUN );
	}

	g_iBuildingTypes[iPlayer][OBJ_TELEPORTER]	= iTeleporterType;
	g_iBuildingTypes[iPlayer][OBJ_DISPENSER]	= iDispenserType;
	g_iBuildingTypes[iPlayer][OBJ_SENTRYGUN]	= iSentryType;

	int iSize = GetObjectCount( iPlayer );
	for( int i = 0; i < iSize; i++) {
		int iBuilding = GetObject( iPlayer, i );
		if( iBuilding == -1 ) continue;

		UpdateBuildingHealth( iPlayer, iBuilding );
	}
}

void SetupObjectHooks( int iEntity ) {
	hStartBuilding.HookEntity( Hook_Post, iEntity, Hook_StartBuilding );
	hStartUpgrade.HookEntity( Hook_Post, iEntity, Hook_StartUpgrade );
	hFinishUpgrade.HookEntity( Hook_Post, iEntity, Hook_FinishUpgrade );
	hOnGoActive.HookEntity( Hook_Post, iEntity, Hook_OnGoActive );
	hMakeCarry.HookEntity( Hook_Post, iEntity, Hook_MakeCarry );
	hCanUpgrade.HookEntity( Hook_Pre, iEntity, Hook_CanBeUpgraded );
}

/*
	SDKCall wrappers
*/

//detonate objects belonging to a player
void DetonatedOwnedObjects( int iPlayer, int iType, int iMode = 0, bool bSilent = false ) {
	SDKCall( hDetonateOwned, iPlayer, iType, iMode, bSilent );
}

//get an object from player's internal list
int GetObject( int iPlayer, int iIndex ) {
	return SDKCall( hGetObject, iPlayer, iIndex );
}

//get the size of player's internal building list
int GetObjectCount( int iPlayer ) {
	return SDKCall( hObjectCount, iPlayer );
}

//destroy all the attached screens on an object
void DestroyScreens( int iBuilding ) {
	SDKCall( hDestroyScreens, iBuilding );
}


/*
	OTHER
*/

void CreateSirenParticle( int iBuilding ) {
	//todo: convert to a stock function

	int iParticle = CreateEntityByName( "info_particle_system" );
	int iTeam = GetEntProp( iBuilding, Prop_Send, "m_iTeamNum" );

	SetEntPropEnt( iParticle, Prop_Data, "m_hOwnerEntity", iBuilding );

	DispatchKeyValue( iParticle, "effect_name", g_sSirenParticles[ iTeam - 2 ] );

	SetVariantString( "!activator" );
	AcceptEntityInput( iParticle, "SetParent", iBuilding, iParticle, 0 );

	SetVariantString( "siren" );
	AcceptEntityInput( iParticle, "SetParentAttachment", iParticle , iParticle, 0 );

	DispatchSpawn( iParticle );

	AcceptEntityInput( iParticle, "start" );
	ActivateEntity( iParticle );

	int iLookup[ 2 ];
	iLookup[ 0 ] = iBuilding;
	iLookup[ 1 ] = iParticle;

	g_hSirenList.PushArray( iLookup );
}
void DestroySirenParticle( int iBuilding ) {
	int iLookup[2];
	for( int i = 0; i < g_hSirenList.Length; i++ ) {
		g_hSirenList.GetArray( i, iLookup );
		if( iLookup[ 0 ] == iBuilding ) {
			g_hSirenList.Erase( i );
			if( !IsValidEntity( iLookup[ 1 ] ) )
				return;
				
			AcceptEntityInput( iLookup[ 1 ], "stop" );
			RemoveEntity( iLookup[ 1 ] );
			
			return;
		}
	}
}

void Lateload() {
	for(int i = 1; i <= MaxClients; i++) {
		if( !IsClientInGame( i ) )
			continue;

		int iSentryType = 	RoundToNearest( AttribHookFloat( 0.0, i, "custom_sentry_type" ) );
		int iDispenserType = 	RoundToNearest( AttribHookFloat( 0.0, i, "custom_dispenser_type" ) );
		int iTeleporterType = 	RoundToNearest( AttribHookFloat( 0.0, i, "custom_teleporter_type" ) );

		g_iBuildingTypes[i][OBJ_TELEPORTER]	= iTeleporterType;
		g_iBuildingTypes[i][OBJ_DISPENSER]	= iDispenserType;
		g_iBuildingTypes[i][OBJ_SENTRYGUN]	= iSentryType;
	}

	//reconstruct the mini-sentry siren list
	int iIndex = 0;
	static char sClassname[ 96 ];
	static char sEffectName[ 96 ];
	while ( ( iIndex = FindEntityByClassname( iIndex, "info_particle_system" ) ) != -1 ) {
		int iParent = GetEntPropEnt( iIndex, Prop_Data, "m_hOwnerEntity" );
		if( iParent == -1 )
			continue;

		GetEntityClassname( iParent, sClassname, sizeof( sClassname ) );
		GetEntPropString( iIndex, Prop_Data, "m_iszEffectName", sEffectName, sizeof( sEffectName ) );
		if( StrContains( sClassname, "obj_", true ) != 0 && StrContains( sEffectName, "cart_flashinglight", true ) != 0 ) {
			int iLookup[ 2 ];
			iLookup[ 0 ] = iParent;
			iLookup[ 1 ] = iIndex;

			g_hSirenList.PushArray( iLookup );
		}
	}
}