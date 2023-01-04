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
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

//type, override, level, is upgrading
int g_iBuildingModels[3][4][3][2];
//type, override, mode
int g_iBuildingBlueprints[3][2];

//used to detect when the user changes attributes related to buildings
int g_iBuildingTypes[MAXPLAYERS][3];

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
		{ 216, 216, 216 },	//jump pad
		{ 100, 100, 100 },	//dummy
	},
	{ //sentry
		{ 150, 180, 216 },	//normal
		{ 100, 100, 100 },	//mini
		{ 175, 220, 330 },	//heavy
		{ 200, 300, 500 },	//clover
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
		{ 000, 000 },	//jump pad
		{ 000, 000 },	//dummy
	},
	{ //sentry
		{ 200, 200 },	//normal
		{ 000, 000 },	//mini
		{ 200, 275 },	//heavy
		{ 200, 400 },	//clover
	},
};

enum {
	OBJ_DISPENSER = 0,
	OBJ_TELEPORTER,
	OBJ_SENTRYGUN,

	OBJ_SAPPER,
}

enum {
	OBJ_STATIC = 0,
	OBJ_BUILDING = 1,
}

enum {
	OBJ_LEVEL1 = 0,
	OBJ_LEVEL2 = 1,
	OBJ_LEVEL3 = 2,
}

enum { //dispensers
	DT_NORMAL = 0,
	DT_MINIDI,
	DT_REPAIR,
}
enum { //teleporters
	TT_NORMAL = 0,
	TT_MINITE,
	TT_JUMPPA,
}
enum { //sentries
	ST_NORMAL = 0,
	ST_MINISE,
	ST_ARTILL,
	ST_CLOVER,
}

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
DynamicDetour hTeleJump;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	HookEvent( EVENT_POSTINVENTORY,		Event_PostInventory );

	//TODO: move into kocw tools
	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetSignature( SDKLibrary_Server, "@_ZN9CTFPlayer26DetonateOwnedObjectsOfTypeEiib", 0 );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //int type
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //int mode
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //bool silent
	hDetonateOwned = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetSignature( SDKLibrary_Server, "@_ZN9CTFPlayer9GetObjectEi", 0 );
	PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //int index
	hGetObject = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetSignature( SDKLibrary_Server, "@_ZN9CTFPlayer14GetObjectCountEv", 0 );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	hObjectCount = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetSignature( SDKLibrary_Server, "@_ZN11CBaseObject14DestroyScreensEv", 0 );
	hDestroyScreens = EndPrepSDKCall();

	//CBaseObject::StartBuilding( CBaseEntity* pBuilder )
	hStartBuilding = new DynamicHook( 328, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity );
	hStartBuilding.AddParam( HookParamType_CBaseEntity );
	//CBaseObject::OnGoActive()
	hOnGoActive = new DynamicHook( 340, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity );
	//CBaseObject::CanBeUpgraded( CTFPlayer *pPlayer )
	hCanUpgrade = new DynamicHook( 345, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity );
	hCanUpgrade.AddParam( HookParamType_CBaseEntity );
	//CBaseObject::StartUpgrading()
	hStartUpgrade = new DynamicHook( 346, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity );
	//CBaseObject::FinishUpgrading()
	hFinishUpgrade = new DynamicHook( 347, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity );
	//CBaseObject::DropCarriedObject( CTFPlayer *pPlayer )
	hMakeCarry = new DynamicHook( 350, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity );
	hMakeCarry.AddParam( HookParamType_CBaseEntity );
	//CObjectDispenser::GetHealRate()
	hDispHeal = DynamicDetour.FromConf( hGameConf, "CObjectDispenser::GetHealRate" );
	hDispHeal.Enable( Hook_Post, Hook_GetHealRate );

	//CObjectTeleporter::TeleporterDoJump( *CTFPlayer )
	hTeleJump = DynamicDetour.FromConf( hGameConf, "CObjectTeleporter::TeleporterDoJump" );
	hTeleJump.Enable( Hook_Post, Hook_TeleJump );

	delete hGameConf;
}

public void OnMapStart() {
	//sentry
	g_iBuildingModels[ OBJ_SENTRYGUN ][ ST_ARTILL ][ OBJ_LEVEL1 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_heavy1.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ ST_ARTILL ][ OBJ_LEVEL2 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_heavy2.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ ST_ARTILL ][ OBJ_LEVEL3 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_heavy3.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ ST_ARTILL ][ OBJ_LEVEL1 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_heavy1_build.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ ST_ARTILL ][ OBJ_LEVEL2 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_heavy2_build.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ ST_ARTILL ][ OBJ_LEVEL3 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_heavy3_build.mdl" );

	g_iBuildingModels[ OBJ_SENTRYGUN ][ ST_CLOVER ][ OBJ_LEVEL1 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_clover1.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ ST_CLOVER ][ OBJ_LEVEL2 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_clover2.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ ST_CLOVER ][ OBJ_LEVEL3 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_clover3.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ ST_CLOVER ][ OBJ_LEVEL1 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_clover1_build.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ ST_CLOVER ][ OBJ_LEVEL2 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_clover2_build.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ ST_CLOVER ][ OBJ_LEVEL3 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_clover3_build.mdl" );

	g_iBuildingBlueprints[ OBJ_SENTRYGUN  ][ 0 ] =	PrecacheModel( "models/buildables/sentry1_blueprint.mdl" );

	//dispenser
	g_iBuildingModels[ OBJ_DISPENSER ][ DT_MINIDI ][ OBJ_LEVEL1 ][ 0 ] = PrecacheModel( "models/buildables/minidispenser.mdl" );
	g_iBuildingModels[ OBJ_DISPENSER ][ DT_MINIDI ][ OBJ_LEVEL1 ][ 1 ] = PrecacheModel( "models/buildables/minidispenser.mdl" );

	g_iBuildingBlueprints[ OBJ_DISPENSER  ][ 0 ] =	PrecacheModel( "models/buildables/dispenser_blueprint.mdl" );

	//teleporter	
	g_iBuildingModels[ OBJ_TELEPORTER ][ TT_JUMPPA ][ OBJ_LEVEL3 ][ 0 ] = PrecacheModel( "models/buildables/custom/jumppad.mdl" );
	g_iBuildingModels[ OBJ_TELEPORTER ][ TT_JUMPPA ][ OBJ_LEVEL1 ][ 1 ] = PrecacheModel( "models/buildables/custom/jumppad.mdl" );

	g_iBuildingBlueprints[ OBJ_TELEPORTER ][ 0 ] =	PrecacheModel( "models/buildables/teleporter_blueprint_enter.mdl" );
	g_iBuildingBlueprints[ OBJ_TELEPORTER ][ 1 ] =	PrecacheModel( "models/buildables/teleporter_blueprint_exit.mdl" );

	//sapper
	

	for(int i = 0; i < MAXPLAYERS; i++ )
		g_iBuildingTypes[i] = { 0, 0, 0 };
}

public void OnEntityCreated( int iEntity, const char[] sClassname ) {
	if( StrContains( sClassname, "obj_", true ) == 0 ) {
		if( strcmp( sClassname, "obj_attachment_sapper", true ) == 0 )
			return;

		hStartBuilding.HookEntity( Hook_Post, iEntity, Hook_StartBuilding );
		hStartUpgrade.HookEntity( Hook_Post, iEntity, Hook_StartUpgrade );
		hFinishUpgrade.HookEntity( Hook_Post, iEntity, Hook_FinishUpgrade );
		hOnGoActive.HookEntity( Hook_Post, iEntity, Hook_OnGoActive );
		hMakeCarry.HookEntity( Hook_Post, iEntity, Hook_MakeCarry );
		hCanUpgrade.HookEntity( Hook_Pre, iEntity, Hook_CanBeUpgraded );
	}
}

//called when a building is created or placed from carry
MRESReturn Hook_StartBuilding( int iThis ) {
	SetBuildingModel( iThis, true );
	UpdateBuilding( iThis );

	int iType = GetEntProp( iThis, Prop_Send, "m_iObjectType" );
	int iPlayer = GetEntPropEnt( iThis, Prop_Send, "m_hBuilder" );
	int iOverride = g_iBuildingTypes[ iPlayer ][ iType ];

	if( iType == OBJ_DISPENSER ) {
		if( iOverride == DT_MINIDI ) {
			SetEntProp( iThis, Prop_Send, "m_iHighestUpgradeLevel", 0 );
			SetEntProp( iThis, Prop_Send, "m_bMiniBuilding", 1 );
		}
	}
	if( iType == OBJ_TELEPORTER ) {
		if( iOverride == TT_JUMPPA ) {
			SetEntProp( iThis, Prop_Send, "m_iHighestUpgradeLevel", 0 );
			SetEntProp( iThis, Prop_Send, "m_bMiniBuilding", 1 );
		}
	}
	return MRES_Handled;
}
//called when a building activates at level 1 only
MRESReturn Hook_OnGoActive( int iThis ) {
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
	int iMode =		GetEntProp( iThis, Prop_Send, "m_iObjectMode" );

	int iModel = g_iBuildingBlueprints[ iType ][ iMode ];
	SetEntProp( iThis, Prop_Send, "m_nModelIndexOverrides", iModel, 4, 0 );
	return MRES_Handled;
}

MRESReturn Hook_CanBeUpgraded( int iThis, DHookReturn hReturn ) {
	if( GetEntProp( iThis, Prop_Send, "m_bMiniBuilding") ) {
		hReturn.Value = false;
		return MRES_ChangedOverride;
	}
	return MRES_Ignored;
}

MRESReturn Hook_GetHealRate( int iThis, DHookReturn hReturn ) {
	if( GetEntProp( iThis, Prop_Send, "m_bMiniBuilding") ) {
		hReturn.Value = 15.0;
	}
	
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hBuilder" );
	if( iOwner > 0 && iOwner < MaxClients ) {
		hReturn.Value = AttribHookFloat( hReturn.Value, iOwner, "custom_dispenser_healrate" );
	}
	return MRES_Supercede;
}

MRESReturn Hook_TeleJump( int iThis, DHookParam hParams ) {
	//TODO: reverse engineer recharge times
	//SetEntPropFloat( iThis, Prop_Send, "m_flRechargeTime", GetGameTime() + 1.0 );
	SetEntProp( iThis, Prop_Send, "m_iTimesUsed", GetEntProp( iThis, Prop_Send, "m_iTimesUsed") + 1 );
	return MRES_Handled;
}

Action Event_PostInventory( Event hEvent, const char[] sName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	CheckBuildings( iPlayer );
	return Plugin_Continue;
}

/*
	Building management
*/

void UpdateBuilding( int iBuilding, bool bHeal = false ) {
	int iPlayer = GetEntPropEnt( iBuilding, Prop_Send, "m_hBuilder" );
	int iType = GetEntProp( iBuilding, Prop_Send, "m_iObjectType" );

	UpdateBuildingHealth( iPlayer, iBuilding, bHeal );
	UpdateBuildingCost( iPlayer, iBuilding, iType );

	if( iType == OBJ_DISPENSER && g_iBuildingTypes[ iPlayer ][ iType ] == DT_MINIDI) {
		DestroyScreens( iBuilding );
	}
}

void UpdateBuildingHealth( int iPlayer, int iBuilding, bool bHeal = false ) {
	int iBuildingType = GetEntProp( iBuilding, Prop_Send, "m_iObjectType" );
	int iBuildingLevel = GetEntProp( iBuilding, Prop_Send, "m_bCarryDeploy" ) ? 
		BuildingTargetLevel( iBuilding ) - 1 :
		GetEntProp( iBuilding, Prop_Send, "m_iUpgradeLevel" ) - 1;

	int iBaseHealth = g_iBaseHealth[ iBuildingType ][ g_iBuildingTypes[ iPlayer ][ iBuildingType ] ][ iBuildingLevel ];
	float flMultiplier = AttribHookFloat( 1.0, iPlayer, "mult_engy_building_health" );
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
	if( TF2_GetPlayerClass( iPlayer ) != TFClass_Engineer ) {
		g_iBuildingTypes[iPlayer] = { 0, 0, 0 };
		return;
	}

	int iSentryType = 		RoundFloat( AttribHookFloat( 0.0, iPlayer, "custom_sentry_type" ) );
	int iDispenserType = 	RoundFloat( AttribHookFloat( 0.0, iPlayer, "custom_dispenser_type" ) );
	int iTeleporterType = 	RoundFloat( AttribHookFloat( 0.0, iPlayer, "custom_teleporter_type" ) );

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

/*
	SDKCall wrappers
*/

void DetonatedOwnedObjects( int iPlayer, int iType, int iMode = 0, bool bSilent = false ) {
	SDKCall( hDetonateOwned, iPlayer, iType, iMode, bSilent );
}

int GetObject( int iPlayer, int iIndex ) {
	return SDKCall( hGetObject, iPlayer, iIndex );
}

//returns the size of the internal list of buildings stored on a player
int GetObjectCount( int iPlayer ) {
	return SDKCall( hObjectCount, iPlayer );
}

void DestroyScreens( int iBuilding ) {
	SDKCall( hDestroyScreens, iBuilding );
}

/*
	OTHER
*/

//returns the un-networked property "m_iGoalUpgradeLevel"
int BuildingTargetLevel( int iThis ) {
	return LoadFromAddress( GetEntityAddress( iThis ) + view_as<Address>( 2044 ), NumberType_Int32 );
}