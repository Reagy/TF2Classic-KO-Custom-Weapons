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
		{ 000, 000 },	//jump pad
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

enum { //dispenser
	OBJ_DISPENSER = 0,
	OBJ_TELEPORTER,
	OBJ_SENTRYGUN,

	OBJ_SAPPER,
}

enum {
	OBJ_LEVEL1 = 0,
	OBJ_LEVEL2 = 1,
	OBJ_LEVEL3 = 2,
}

enum { //dispensers
	DISPENSER_NORMAL = 0,
	DISPENSER_MINI,
}
enum { //teleporters
	TELEPORT_NORMAL = 0,
	TELEPORT_MINI,
	TELEPORT_JUMP,
}
enum { //sentries
	SENTRY_NORMAL = 0,
	SENTRY_MINI,
	SENTRY_ARTILLERY,
	SENTRY_CLOVER,
}
enum { //sappers
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

int iGoalBuildOffset = -1;
int iTurnSpeedOffset = -1;

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
//DynamicDetour hGetCost;
DynamicDetour hSentryAttack;
DynamicDetour hDispHeal;
DynamicDetour hTeleJump;

bool bLateLoad = false;
public APLRes AskPluginLoad2( Handle hMyself, bool bLate, char[] error, int err_max ) {
	bLateLoad = bLate;

	return APLRes_Success;
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	HookEvent( EVENT_POSTINVENTORY,		Event_PostInventory );

	g_hSirenList = new ArrayList( 2 );

	//TODO: move into kocw tools
	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetSignature( SDKLibrary_Server, "@_ZN9CTFPlayer26DetonateOwnedObjectsOfTypeEiib", 0 );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //int - type
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //int - mode
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //bool - silent
	hDetonateOwned = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetSignature( SDKLibrary_Server, "@_ZN9CTFPlayer9GetObjectEi", 0 );
	PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //int - index
	hGetObject = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetSignature( SDKLibrary_Server, "@_ZN9CTFPlayer14GetObjectCountEv", 0 );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain ); //int - count
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
	//
	hSentryAttack = DynamicDetour.FromConf( hGameConf, "CObjectSentrygun::Attack" );
	hSentryAttack.Enable( Hook_Pre, Hook_SentryAttackPre );
	hSentryAttack.Enable( Hook_Post, Hook_SentryAttack );
	//CObjectDispenser::GetHealRate()
	hDispHeal = DynamicDetour.FromConf( hGameConf, "CObjectDispenser::GetHealRate" );
	hDispHeal.Enable( Hook_Post, Hook_GetHealRate );
	//CObjectTeleporter::TeleporterDoJump( *CTFPlayer )
	hTeleJump = DynamicDetour.FromConf( hGameConf, "CObjectTeleporter::TeleporterDoJump" );
	hTeleJump.Enable( Hook_Post, Hook_TeleJump );
	//doesn't work properly; game will accept if build request is made through console but PDA refuses
	/*hGetCost = DynamicDetour.FromConf( hGameConf, "CTFPlayerShared::CalculateObjectCost" );
	hGetCost.Enable( Hook_Post, Hook_GetCost );*/

	
	if( bLateLoad ) {
		for(int i = 1; i < MaxClients; i++) {
			if( !IsClientInGame( i ) )
				continue;

			SDKHook( i, SDKHook_OnTakeDamage, Hook_OnTakeDamage );

			int iSentryType = 		RoundFloat( AttribHookFloat( 0.0, i, "custom_sentry_type" ) );
			int iDispenserType = 	RoundFloat( AttribHookFloat( 0.0, i, "custom_dispenser_type" ) );
			int iTeleporterType = 	RoundFloat( AttribHookFloat( 0.0, i, "custom_teleporter_type" ) );

			g_iBuildingTypes[i][OBJ_TELEPORTER]	= iTeleporterType;
			g_iBuildingTypes[i][OBJ_DISPENSER]	= iDispenserType;
			g_iBuildingTypes[i][OBJ_SENTRYGUN]	= iSentryType;

			//todo: this is causing segfaults

			//create object hooks
			/*int iSize = GetObjectCount( i );
			for( int j = 0; j < iSize; j++) {
				int iBuilding = GetObject( i, j );
				if( iBuilding == -1 ) 
					continue;

				RequestFrame( SetupObjectHooks, j );
			}

			//reconstruct the mini-sentry siren list
			int iIndex = 0;
			static char sClassname[ 96 ];
			static char sEffectName[ 96 ];
			while ( ( iIndex = FindEntityByClassname( iIndex, "info_particle_system" ) ) != -1 ) {
				int iParent = GetEntPropEnt( iIndex, Prop_Data, "m_hOwnerEntity" );

				GetEntityClassname( iParent, sClassname, sizeof( sClassname ) );
				GetEntPropString( iIndex, Prop_Data, "m_iszEffectName", sEffectName, sizeof( sEffectName ) );
				if( StrContains( sClassname, "obj_", true ) != 0 && StrContains( sEffectName, "cart_flashinglight", true ) != 0 ) {
					int iLookup[ 2 ];
					iLookup[ 0 ] = iParent;
					iLookup[ 1 ] = iIndex;

					g_hSirenList.PushArray( iLookup );
				}
			}*/
		}
	}

	delete hGameConf;
}

public void OnMapStart() {
	//sentry
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_MINI ][ OBJ_LEVEL1 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_mini.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_MINI ][ OBJ_LEVEL1 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_mini_build.mdl" );

	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_ARTILLERY ][ OBJ_LEVEL1 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_heavy1.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_ARTILLERY ][ OBJ_LEVEL2 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_heavy2.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_ARTILLERY ][ OBJ_LEVEL3 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_heavy3.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_ARTILLERY ][ OBJ_LEVEL1 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_heavy1_build.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_ARTILLERY ][ OBJ_LEVEL2 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_heavy2_build.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_ARTILLERY ][ OBJ_LEVEL3 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_heavy3_build.mdl" );

	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_CLOVER ][ OBJ_LEVEL1 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_clover1.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_CLOVER ][ OBJ_LEVEL2 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_clover2.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_CLOVER ][ OBJ_LEVEL3 ][ 0 ] =	PrecacheModel( "models/buildables/sentry_clover3.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_CLOVER ][ OBJ_LEVEL1 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_clover1_build.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_CLOVER ][ OBJ_LEVEL2 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_clover2_build.mdl" );
	g_iBuildingModels[ OBJ_SENTRYGUN ][ SENTRY_CLOVER ][ OBJ_LEVEL3 ][ 1 ] =	PrecacheModel( "models/buildables/sentry_clover3_build.mdl" );

	g_iBuildingBlueprints[ OBJ_SENTRYGUN ][ 0 ] =	PrecacheModel( "models/buildables/sentry1_blueprint.mdl" );

	//dispenser
	g_iBuildingModels[ OBJ_DISPENSER ][ DISPENSER_MINI ][ OBJ_LEVEL1 ][ 0 ] = PrecacheModel( "models/buildables/minidispenser.mdl" );
	g_iBuildingModels[ OBJ_DISPENSER ][ DISPENSER_MINI ][ OBJ_LEVEL1 ][ 1 ] = PrecacheModel( "models/buildables/minidispenser.mdl" );

	g_iBuildingBlueprints[ OBJ_DISPENSER ][ 0 ] =	PrecacheModel( "models/buildables/dispenser_blueprint.mdl" );

	//teleporter	
	g_iBuildingModels[ OBJ_TELEPORTER ][ TELEPORT_JUMP ][ OBJ_LEVEL3 ][ 0 ] = PrecacheModel( "models/buildables/custom/jumppad.mdl" );
	g_iBuildingModels[ OBJ_TELEPORTER ][ TELEPORT_JUMP ][ OBJ_LEVEL1 ][ 1 ] = PrecacheModel( "models/buildables/custom/jumppad.mdl" );

	g_iBuildingBlueprints[ OBJ_TELEPORTER ][ 0 ] =	PrecacheModel( "models/buildables/teleporter_blueprint_enter.mdl" );
	g_iBuildingBlueprints[ OBJ_TELEPORTER ][ 1 ] =	PrecacheModel( "models/buildables/teleporter_blueprint_exit.mdl" );

	//sapper
	g_iSapperModels[ SAPPER_INTERMISSION ] = PrecacheModel( "models/buildables/intermission_placed.mdl" );

	PrecacheSound( "weapons/sentry_shoot_mini.wav" );

	AddNormalSoundHook( Hook_BuildingSounds );
}

public void OnEntityCreated( int iEntity, const char[] sClassname ) {
	if( iEntity > 0 && iEntity <= MaxClients ) {
		SDKHook( iEntity, SDKHook_OnTakeDamage, Hook_OnTakeDamage );
	}

	if( StrContains( sClassname, "obj_", true ) != 0 ) 
		return;
	
	if( StrEqual( sClassname, "obj_attachment_sapper", true ) ) {
		//set sapper model here
		return;
	}
		
	SetupObjectHooks( iEntity );
}

Action Hook_OnTakeDamage( int iVictim, int& iAttacker, int& iInflictor, float& flDamage, int& iDamageType, int& iWeapon, float flDamageForce[3], float flDamagePosition[3], int iDamageCustom ) {
	if(iWeapon >= 4096) iWeapon -= 4096;
	if(iAttacker >= 4096) iAttacker -= 4096;
	if(iInflictor >= 4096) iInflictor -= 4096;

	if( !IsValidEntity( iWeapon ) ) 
		return Plugin_Changed;

	static char sClassname[64];
	GetEntityClassname( iWeapon, sClassname, sizeof( sClassname ) );
	if( !StrEqual( sClassname, "obj_sentrygun" ) )
		return Plugin_Changed;

	int iMini = GetEntProp( iWeapon, Prop_Send, "m_bMiniBuilding" );
	if( iMini ) {
		flDamage *= 0.5;
		//tried scaling damage force here, doesn't seem to work
	}

	int iBuilder = GetEntPropEnt( iWeapon, Prop_Send, "m_hBuilder" );
	flDamage = AttribHookFloat( flDamage, iBuilder, "custom_sentry_damage" );

	return Plugin_Changed;
}

Action Hook_BuildingSounds( int iClients[MAXPLAYERS], int& iNumClients, char sSample[PLATFORM_MAX_PATH], int& iEntity, int& iChannel, float& flVolume, int& iLevel, int& iPitch, int& iFlags, char sSoundEntry[PLATFORM_MAX_PATH], int &iSeed ) {
	static char sClassname[64];
	if( !IsValidEntity( iEntity ) )
		return Plugin_Continue;

	GetEntityClassname( iEntity, sClassname, sizeof( sClassname ) );
	if( StrContains( sClassname, "obj_", true ) != 0 ) 
		return Plugin_Continue;

	int iBuilder = GetEntPropEnt( iEntity, Prop_Send, "m_hBuilder" );
	if( iBuilder == -1 || iBuilder > MAXPLAYERS )
		return Plugin_Continue;

	int iType = GetEntProp( iEntity, Prop_Send, "m_iObjectType" );
	if( iType == OBJ_SENTRYGUN && GetBuildingOverride( iEntity ) == SENTRY_MINI ) {
		if( StrContains( sSample, "weapons/sentry_shoot", true ) != -1 ) {
			sSample = "weapons/sentry_shoot_mini.wav";
			return Plugin_Changed;
		} 
		else if( StrContains( sSample, "weapons/sentry_scan", true ) != -1 ) {
			iPitch = 120;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

Action Event_PostInventory( Event hEvent, const char[] sName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	CheckBuildings( iPlayer );
	return Plugin_Continue;
}

/*
	Building Callbacks
*/

//called when a building is created or placed from carry
MRESReturn Hook_StartBuilding( int iThis ) {
	SetBuildingModel( iThis, true );
	UpdateBuilding( iThis );

	int iType = GetEntProp( iThis, Prop_Send, "m_iObjectType" );
	int iPlayer = GetEntPropEnt( iThis, Prop_Send, "m_hBuilder" );
	int iOverride = g_iBuildingTypes[ iPlayer ][ iType ];

	if( iType == OBJ_DISPENSER ) {
		if( iOverride == DISPENSER_MINI ) {
			SetEntProp( iThis, Prop_Send, "m_iHighestUpgradeLevel", 0 );
			SetEntProp( iThis, Prop_Send, "m_bMiniBuilding", 1 );
		}
	}
	else if( iType == OBJ_TELEPORTER ) {

	}
	else if( iType == OBJ_SENTRYGUN ) {
		if( iOverride == SENTRY_MINI ) {
			SetEntProp( iThis, Prop_Send, "m_iHighestUpgradeLevel", 0 );
			SetEntProp( iThis, Prop_Send, "m_bMiniBuilding", 1 );
			SetSentryRotate( iThis, 8 );
		}
	}
	return MRES_Handled;
}
//called when a building activates at level 1 only
MRESReturn Hook_OnGoActive( int iThis ) {
	int iType = GetEntProp( iThis, Prop_Send, "m_iObjectType" );
	int iPlayer = GetEntPropEnt( iThis, Prop_Send, "m_hBuilder" );

	if( iType == OBJ_SENTRYGUN && g_iBuildingTypes[ iPlayer ][ iType ] == SENTRY_MINI ) {
		CreateSirenParticle( iThis );
	}
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

	int iPlayer = GetEntPropEnt( iThis, Prop_Send, "m_hBuilder" );
	if( iType == OBJ_SENTRYGUN && g_iBuildingTypes[ iPlayer ][ iType ] == SENTRY_MINI ) {
		DestroySirenParticle( iThis );
	}

	return MRES_Handled;
}

//called when a jump pad is used
MRESReturn Hook_TeleJump( int iThis, DHookParam hParams ) {
	//TODO: reverse engineer recharge times
	//SetEntPropFloat( iThis, Prop_Send, "m_flRechargeTime", GetGameTime() + 1.0 );
	return MRES_Handled;
}

//good thing multithreading was a joke in 2007
float flOldAttack;
MRESReturn Hook_SentryAttackPre( int iThis ) {
	float flNextAttack = LoadFromAddress( GetEntityAddress( iThis ) + view_as<Address>(2392), NumberType_Int32 );
	flOldAttack = flNextAttack;

	return MRES_Handled;
}
MRESReturn Hook_SentryAttack( int iThis ) {
	float flNextAttack = LoadFromAddress( GetEntityAddress( iThis ) + view_as<Address>(2392), NumberType_Int32 );

	if( flOldAttack != flNextAttack ) {
		float flNewInterval = GetEntProp( iThis, Prop_Send, "m_iUpgradeLevel" ) == 1 ? 0.2 : 0.1;
		if( GetEntProp( iThis, Prop_Send, "m_bMiniBuilding" ) ) {
			flNewInterval *= 0.75;
		}
		flNewInterval = AttribHookFloat( flNewInterval, iBuilder, "custom_sentry_firerate" );
		StoreToAddress( GetEntityAddress( iThis ) + view_as<Address>(2392), GetGameTime() + flNewInterval, NumberType_Int32 );
	}

	return MRES_Handled;
}

/*MRESReturn Hook_GetCost( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	hReturn.Value = 
	return MRES_ChangedOverride;
}*/

/*
	Building info functions
*/

//returns whether a building can be upgraded
MRESReturn Hook_CanBeUpgraded( int iThis, DHookReturn hReturn ) {
	if( GetEntProp( iThis, Prop_Send, "m_bMiniBuilding") ) {
		hReturn.Value = false;
		return MRES_ChangedOverride;
	}
	return MRES_Ignored;
}

//returns the health per second of a dispenser
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

/*
	Building management
*/

void UpdateBuilding( int iBuilding, bool bHeal = false ) {
	int iPlayer = GetEntPropEnt( iBuilding, Prop_Send, "m_hBuilder" );
	int iType = GetEntProp( iBuilding, Prop_Send, "m_iObjectType" );

	UpdateBuildingHealth( iPlayer, iBuilding, bHeal );
	UpdateBuildingCost( iPlayer, iBuilding, iType );

	if( iType == OBJ_SENTRYGUN && g_iBuildingTypes[ iPlayer ][ iType ] == SENTRY_MINI) {
		int iSkin = GetEntProp( iBuilding, Prop_Send, "m_nSkin" );
		SetEntProp( iBuilding, Prop_Send, "m_nSkin", iSkin + 4 );
		SetEntPropFloat( iBuilding, Prop_Send, "m_flModelScale", 0.75 );
	}
	if( iType == OBJ_DISPENSER && g_iBuildingTypes[ iPlayer ][ iType ] == DISPENSER_MINI) {
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
	if( !( iPlayer < MaxClients && IsPlayerAlive( iPlayer ) ) )
		return;

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

void SetupObjectHooks( int iEntity ) {
	hStartBuilding.HookEntity( Hook_Post, iEntity, Hook_StartBuilding );
	hStartUpgrade.HookEntity( Hook_Post, iEntity, Hook_StartUpgrade );
	hFinishUpgrade.HookEntity( Hook_Post, iEntity, Hook_FinishUpgrade );
	hOnGoActive.HookEntity( Hook_Post, iEntity, Hook_OnGoActive );
	hMakeCarry.HookEntity( Hook_Post, iEntity, Hook_MakeCarry );
	hCanUpgrade.HookEntity( Hook_Pre, iEntity, Hook_CanBeUpgraded );
	SDKHook( iEntity, SDKHook_OnTakeDamage, Hook_OnTakeDamage );
}

/*
	SDKCall wrappers
*/

/**
 * Detonate all buildings belonging to a player
 * 
 * @param iPlayer     Player to check against
 * @param iType       Type of building to destroy
 * @param iMode       Mode of building to destroy
 * @param bSilent     Destroy buildings silently
 */
void DetonatedOwnedObjects( int iPlayer, int iType, int iMode = 0, bool bSilent = false ) {
	PrintToServer( "[BUILDING]: DetonateOwnedObjects, Player: %i Type: %i Mode: %i", iPlayer, iType, iMode );
	SDKCall( hDetonateOwned, iPlayer, iType, iMode, bSilent );
}

/**
 * Get the object at the provided index in
 * the player's internal object list
 * 
 * @param iPlayer     Player to check
 * @param iIndex      Index to check
 * @return            Index of building at index
 */
int GetObject( int iPlayer, int iIndex ) {
	PrintToServer( "[BUILDING]: GetObject, Player: %i Building: %i", iPlayer, iIndex );
	return SDKCall( hGetObject, iPlayer, iIndex );
}

/**
 * Returns the amount of buildings a player has
 * 
 * @param iPlayer     Player to check
 * @return            Amount of buildings
 */
int GetObjectCount( int iPlayer ) {
	PrintToServer( "[BUILDING]: GetObjectCount, Player: %i", iPlayer );
	return SDKCall( hObjectCount, iPlayer );
}

/**
 * Destroy all the screens on an object
 * 
 * @param iBuilding     Building to kill screens on
 */
void DestroyScreens( int iBuilding ) {
	SDKCall( hDestroyScreens, iBuilding );
}

/*
	OTHER
*/

/**
 * Returns the target building level used
 * while a building is redeployed
 * 
 * @param iBuilding     Building to check
 * @return              Target building level
 */
int BuildingTargetLevel( int iBuilding ) {
	return LoadFromAddress( GetEntityAddress( iBuilding ) + view_as<Address>( 2044 ), NumberType_Int32 );
}

/**
 * Sets the rotation speed of a sentry gun
 * 
 * @param iBuilding     Building to edit
 * @param iSpeed        Speed to set
 */
void SetSentryRotate( int iBuilding, int iSpeed ) {
	StoreToAddress( GetEntityAddress( iBuilding ) + view_as<Address>( 2404 ), iSpeed, NumberType_Int32 );
}

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

int GetBuildingOverride( int iBuilding ) {
	int iBuilder =	GetEntPropEnt( iBuilding, Prop_Send, "m_hBuilder" );
	int iType = 	GetEntProp( iBuilding, Prop_Send, "m_iObjectType");

	return g_iBuildingTypes[ iBuilder ][ iType ];
}