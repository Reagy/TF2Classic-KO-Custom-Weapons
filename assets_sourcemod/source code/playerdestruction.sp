#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <kocwtools>
#include <dhooks>

//TODO: implement refire limit

/* fixes
	fixed capture sounds
	fixed parser being shit hopefully
	fixed being able to cap past maximum score
	added outlines to pickups
	implemented domination hud
*/

public Plugin myinfo = {
	name = "Player Destruction Classic",
	author = "Noclue",
	description = "Wrapper to allow running PD maps in TF2C",
	version = "1.1",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

#define REDCOLOR { 184, 56, 59, 1 }
#define BLUCOLOR { 88, 133, 162, 1 }

//func_capturezone
//these already exist but need additional functionality

//stores PDCapZones using the object's entity reference for lookup
StringMap g_smCaptureZones;

#define PDZONE_SIZE sizeof( PDCapZone )
enum struct PDCapZone {
	float flCaptureDelay;
	float flCaptureDelayOffset; //this needs to be clamped
	bool bCanBlock;

	//the default m_hTouchingEntities property doesn't populate on monster mash for some reason
	//so it needs to be reimplemented manually
	ArrayList hPlayersTouching;

	ArrayList hCapOutputs[2]; //array of PDOutputs
}

enum {
	OUTCAP_REDCAP = 0,
	OUTCAP_BLUECAP,

	OUTCAP_LAST,
}

static char szOutputCapNames[][] = {
	"OnCapTeam1_PD",
	"OnCapTeam2_PD"
};

//tf_logic_player_destuction properties
//there should only ever be one of these so nothing complicated has to be done
//need to do a bunch of heavy lifting here since the engine discards the entity completely

char g_szLogicTargetname[2048];

char g_szPropModelName[128];
char g_szPropDropSound[128];
char g_szPropPickupSound[128];

float g_flBlueRespawnTime;
float g_flRedRespawnTime;

int g_iMinPoints;
int g_iPointsPerPlayer;

float g_flFinaleLength;

int g_iFlagResetDelay;
int g_iHealDistance;

//current gamemode info

int g_iLogicDummy; //dummy object to catch inputs

float g_flCountdownTimer;

int g_iPointsToWin;

int g_iRedScore;
int g_iBlueScore;

int g_iPlayerCarrying[ MAXPLAYERS+1 ];
float g_flNextCaptureTime[ MAXPLAYERS+1 ];

int g_iRedTeamLeader = -1;
int g_iRedLeaderDispenser = INVALID_ENT_REFERENCE;
int g_iRedLeaderGlow = INVALID_ENT_REFERENCE;

int g_iBlueTeamLeader = -1;
int g_iBlueLeaderDispenser = INVALID_ENT_REFERENCE;
int g_iBlueLeaderGlow = INVALID_ENT_REFERENCE;

int g_iRedTeamHolding = 0;
int g_iBlueTeamHolding = 0;

int g_iPointsOnPlayerDeath = 1;

bool g_bAllowMaxScoreUpdating = true;

enum struct PDOutput {
	char szTargetname[96];
	char szTargetInput[96];
	char szParameter[96];
	float flDelay;
	int iRefires;
}

enum {
	OUT_ONBLUEHITMAXPOINTS = 0,
	OUT_ONREDHITMAXPOINTS,

	OUT_ONBLUELEAVEMAXPOINTS,
	OUT_ONREDLEAVEMAXPOINTS,

	OUT_ONBLUEHITZEROPOINTS,
	OUT_ONREDHITZEROPOINTS,

	OUT_ONBLUEHASPOINTS,
	OUT_ONREDHASPOINTS,

	OUT_ONBLUEFINALEPERIODEND,
	OUT_ONREDFINALEPERIODEND,

	OUT_ONBLUEFIRSTFLAGSTOLEN,
	OUT_ONREDFIRSTFLAGSTOLEN,

	OUT_ONBLUEFLAGSTOLEN,
	OUT_ONREDFLAGSTOLEN,

	OUT_ONBLUELASTFLAGRETURNED,
	OUT_ONREDLASTFLAGRETURNED,

	OUT_ONBLUESCORECHANGED,
	OUT_ONREDSCORECHANGED,

	OUT_ONCOUNTDOWNTIMEREXPIRED,

	OUT_LAST,
}

static char szOutputNames[][] = {
	"OnBlueHitMaxPoints",
	"OnRedHitMaxPoints",

	"OnBlueLeaveMaxPoints",
	"OnRedLeaveMaxPoints",

	"OnBlueHitZeroPoints",
	"OnRedHitZeroPoints",

	"OnBlueHasPoints",
	"OnRedHasPoints",

	"OnBlueFinalePeriodEnd",
	"OnRedFinalePeriodEnd",

	//can pd even use these?
	"OnBlueFirstFlagStolen",
	"OnRedFirstFlagStolen",

	"OnBlueFlagStolen",
	"OnRedFlagStolen",

	"OnBlueLastFlagReturned",
	"OnRedLastFlagReturned",

	"OnBlueScoreChanged",
	"OnRedScoreChanged",

	"OnCountdownTimerExpired"
};

//array of all the outputs that the logic ent can fire
ArrayList g_alOutputs[OUT_LAST];

/*
	PICKUPS
*/

StringMap g_smPickups;

#define PDPICKUP_SIZE 2
enum struct PDPickup {
	int iAmount;
	float flExpireTime;

	int iGlowRef;
}

float g_flPickupCooler[ MAXPLAYERS+1 ];

#define OUTPUT_CELLSIZE sizeof( PDOutput )
#define HUD_UPDATEINTERVAL 0.5

DynamicDetour g_dtParseEntity;
DynamicDetour g_dtRespawnTouch;
DynamicDetour g_dtDispenserRadius;
DynamicDetour g_dtDropFlag;
DynamicDetour g_dtGetDominationPointRate;
DynamicHook g_dhAcceptInput;
DynamicHook g_dhTouch;
Handle g_sdkExtractValue;
Handle g_sdkFindByName;
Handle g_sdkInRespawnRoom;
Handle g_sdkSetWinningTeam;
Handle g_sdkLookupSequence;
Handle g_sdkGetTeam;
Handle g_sdkSetRoundScore;

Handle g_hsHudSyncMiddle;

//#define DEBUG

Address g_pCTFGameRules = Address_Null;
Address g_pCTFLogicDomination = Address_Null;
int g_iCTFObjectiveResource = -1;

public void OnPluginStart() {
	g_hsHudSyncMiddle = CreateHudSynchronizer();

	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	g_dtParseEntity = DynamicDetour.FromConf( hGameConf, "MapEntity_ParseEntity" );
	g_dtParseEntity.Enable( Hook_Pre, Detour_ParseEntity );
	g_dtParseEntity.Enable( Hook_Post, Detour_ParseEntityPost );

	g_dtRespawnTouch = DynamicDetour.FromConf( hGameConf, "CFuncRespawnRoom::RespawnRoomTouch" );
	g_dtRespawnTouch.Enable( Hook_Pre, Detour_RespawnTouch );

	g_dhAcceptInput = DynamicHook.FromConf( hGameConf, "CBaseEntity::AcceptInput" );
	g_dhTouch = DynamicHook.FromConf( hGameConf, "CBaseEntity::Touch" );

	g_dtDispenserRadius = DynamicDetour.FromConf( hGameConf, "CObjectDispenser::GetDispenserRadius" );
	g_dtDispenserRadius.Enable( Hook_Pre, Detour_GetDispenserRadius );

	g_dtDropFlag = DynamicDetour.FromConf( hGameConf, "CTFPlayer::DropFlag" );
	g_dtDropFlag.Enable( Hook_Pre, Detour_DropFlag );

	g_dtGetDominationPointRate = DynamicDetour.FromConf( hGameConf, "CTFTeam::GetDominationPointRate" );
	g_dtGetDominationPointRate.Enable( Hook_Pre, Hook_PointRate );

	StartPrepSDKCall( SDKCall_Static );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "PointInRespawnRoom" );
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByRef );
	g_sdkInRespawnRoom = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Static );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "MapEntity_ExtractValue" );
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer, VDECODE_FLAG_BYREF );
	g_sdkExtractValue = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_GameRules );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFGameRules::SetWinningTeam" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkSetWinningTeam = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CBaseAnimating::LookupSequence" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	g_sdkLookupSequence = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_EntityList );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CGlobalEntityList::FindEntityByName" );
	PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain, VDECODE_FLAG_ALLOWNULL );
	g_sdkFindByName = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Static );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "GetGlobalTeam" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkGetTeam = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFTeam::SetRoundScore" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkSetRoundScore = EndPrepSDKCall();

	HookEvent( "player_spawn", Event_PlayerSpawn );
	HookEvent( "player_disconnect", Event_PlayerDisconnect );
	HookEvent( "player_death", Event_PlayerDeath );

#if defined DEBUG
	RegConsoleCmd( "sm_pd_test", Command_Test, "test" );
#endif

	

	delete hGameConf;
}

bool g_bMapIsPD;
public void OnMapInit( const char[] szMapName ) {
	g_bMapIsPD = StrContains( szMapName, "pd_", true ) == 0;

	for( int i = 0; i < OUT_LAST; i++) {
		g_alOutputs[i] = new ArrayList( OUTPUT_CELLSIZE );
	}

	g_smCaptureZones = new StringMap();
	g_smPickups = new StringMap();
}

public void OnMapStart() {
	if( !g_bMapIsPD )
		return;

	CreateTimer( HUD_UPDATEINTERVAL, Timer_HudThink, 0, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT );
	RequestFrame( SpawnLogicDummy );

	CheckFillLogicSingleton();

	PrecacheSound("ui/chime_rd_2base_pos.wav");
	PrecacheSound("ui/chime_rd_2base_neg.wav");
}

/*
	MAP DATA PARSING
*/

MRESReturn Detour_ParseEntity( DHookReturn hReturn, DHookParam hParams ) {
	if( !g_bMapIsPD )
		return MRES_Ignored;

	static char szEntData[2048];
	static char szKeyBuffer[2048];

	hParams.GetString( 2, szEntData, sizeof( szEntData ) );

	if( !SDKCall( g_sdkExtractValue, szEntData, "classname", szKeyBuffer ) )
		return MRES_Handled;
	if( StrEqual( szKeyBuffer, "tf_logic_player_destruction" ) )
		ParseLogicEntity( szEntData );

	return MRES_Handled;
}

MRESReturn Detour_ParseEntityPost( DHookReturn hReturn, DHookParam hParams ) {
	if( !g_bMapIsPD )
		return MRES_Ignored;

	static char szEntData[2048];
	static char szKeyBuffer[2048];

	//trying to pass in as a cbaseentity causes sourcemod to have a stroke so just get by address
	Address aEntity = hParams.GetAddress( 1 );
	aEntity = LoadFromAddress( aEntity, NumberType_Int32 );
	if( aEntity == Address_Null )
		return MRES_Handled;
	
	int iEntity = GetEntityFromAddress( aEntity );
	if( iEntity == -1 )
		return MRES_Handled;

	GetEntityClassname( iEntity, szKeyBuffer, 2048 );
	
	if( StrEqual( szKeyBuffer, "func_capturezone" ) ) {
		hParams.GetString( 2, szEntData, sizeof( szEntData ) );
		ParseCaptureZone( iEntity, szEntData );
	}

	return MRES_Handled;
}

void ParseLogicEntity( char szEntData[2048] ) {
	static char szKeyBuffer[2048];
	
	g_iHealDistance = 450;
	g_iFlagResetDelay = 60;

	SDKCall( g_sdkExtractValue, szEntData, "targetname", g_szLogicTargetname );

	int iIndex = GetNextKey( szEntData, sizeof( szEntData ), szKeyBuffer, sizeof( szKeyBuffer ) );
	while( iIndex != -1 ) {
		if( StrEqual( szKeyBuffer, "}" ) )
			break;

		if( StrEqual( szKeyBuffer, "prop_model_name" ) )	GetNextKey( szEntData, sizeof( szEntData ), g_szPropModelName, sizeof( g_szPropModelName ) );
		if( StrEqual( szKeyBuffer, "prop_drop_sound" ) )	GetNextKey( szEntData, sizeof( szEntData ), g_szPropDropSound, sizeof( g_szPropDropSound ) );
		if( StrEqual( szKeyBuffer, "prop_pickup_sound" ) )	GetNextKey( szEntData, sizeof( szEntData ), g_szPropPickupSound, sizeof( g_szPropPickupSound ) );

		if( StrEqual( szKeyBuffer, "blue_respawn_time" ) )	TryPushNextFloat( szEntData, sizeof( szEntData ), g_flBlueRespawnTime );
		if( StrEqual( szKeyBuffer, "red_respawn_time" ) )	TryPushNextFloat( szEntData, sizeof( szEntData ), g_flRedRespawnTime );

		if( StrEqual( szKeyBuffer, "min_points" ) )		TryPushNextInt( szEntData, sizeof( szEntData ), g_iMinPoints );
		if( StrEqual( szKeyBuffer, "points_per_player" ) )	TryPushNextInt( szEntData, sizeof( szEntData ), g_iPointsPerPlayer );

		if( StrEqual( szKeyBuffer, "finale_length" ) )		TryPushNextFloat( szEntData, sizeof( szEntData ), g_flFinaleLength );

		if( StrEqual( szKeyBuffer, "flag_reset_delay" ) )	TryPushNextInt( szEntData, sizeof( szEntData ), g_iFlagResetDelay );
		if( StrEqual( szKeyBuffer, "heal_distance" ) )		TryPushNextInt( szEntData, sizeof( szEntData ), g_iHealDistance );

		for( int i = 0; i < OUT_LAST; i++) {
			if( StrEqual( szOutputNames[i], szKeyBuffer ) )		TryPushNextOutput( szEntData, sizeof( szEntData ), g_alOutputs[ i ] );
		}

		iIndex = GetNextKey( szEntData, sizeof( szEntData ), szKeyBuffer, sizeof( szKeyBuffer ) );
	}

	g_iRedScore = 0;
	g_iBlueScore = 0;

	if( g_iCTFObjectiveResource != -1 ) {
		SetEntProp( g_iCTFObjectiveResource, Prop_Send, "m_iDominationRate", 0, 4, 0 );
		SetEntProp( g_iCTFObjectiveResource, Prop_Send, "m_iDominationRate", 0, 4, 1 );
	}

	RequestFrame( Frame_Logic );

	SetTeamLeader( -1, 2 );
	SetTeamLeader( -1, 3 );

	g_iPointsOnPlayerDeath = 1;
	g_bAllowMaxScoreUpdating = true;

	g_flCountdownTimer = 0.0;

	#if defined DEBUG
		PrintToChatAll( "[PD:C] DEBUG MODE IS ENABLED" );
	#endif

	for( int i = 0; i < MAXPLAYERS+1; i++ ) {
		g_iPlayerCarrying[i] = 0;
		g_flNextCaptureTime[i] = 0.0;
		g_flPickupCooler[i] = GetGameTime();
	}

	CalculateMaxPoints();

	if( !StrEqual( g_szPropModelName, "" ) )
		PrecacheModel( g_szPropModelName );
	if( !StrEqual( g_szPropDropSound, "" ) )
		PrecacheSound( g_szPropDropSound );
	if( !StrEqual( g_szPropPickupSound, "" ) )
		PrecacheSound( g_szPropPickupSound );
}
void Frame_Logic() {
	CheckFillLogicSingleton();
}

void ParseCaptureZone( int iEntity, char szEntData[2048] ) {
	#if defined DEBUG
		PrintToServer("pasing capture zone");
	#endif

	static char szKeyBuffer[2048];

	PDCapZone pdZone;

	pdZone.hPlayersTouching = new ArrayList();
	pdZone.hCapOutputs[0] = new ArrayList( sizeof( PDOutput ) );
	pdZone.hCapOutputs[1] = new ArrayList( sizeof( PDOutput ) );

	if( SDKCall( g_sdkExtractValue, szEntData, "capture_delay", szKeyBuffer ) ) {
		pdZone.flCaptureDelay = StringToFloat( szKeyBuffer );
	}
	if( SDKCall( g_sdkExtractValue, szEntData, "capture_delay_offset", szKeyBuffer ) ) {
		pdZone.flCaptureDelayOffset = StringToFloat( szKeyBuffer );
	}
	if( SDKCall( g_sdkExtractValue, szEntData, "shouldBlock", szKeyBuffer ) ) {
		pdZone.bCanBlock = view_as<bool>( StringToInt( szKeyBuffer ) );
	}

	int iIndex = GetNextKey( szEntData, sizeof( szEntData ), szKeyBuffer, sizeof( szKeyBuffer ) );
	while( iIndex != -1 ) {
		if( StrEqual( szKeyBuffer, "}" ) )
			break;

		for( int i = 0; i < OUTCAP_LAST; i++) {
			if( StrEqual( szOutputCapNames[i], szKeyBuffer ) ) {
				TryPushNextOutput( szEntData, sizeof( szEntData ), pdZone.hCapOutputs[i] );
			}
		}

		iIndex = GetNextKey( szEntData, sizeof( szEntData ), szKeyBuffer, sizeof( szKeyBuffer ) );
	}

	int iRef = EntIndexToEntRef( iEntity );
	IntToString( iRef, szKeyBuffer, sizeof( szKeyBuffer ) );
	g_smCaptureZones.SetArray( szKeyBuffer, pdZone, PDZONE_SIZE );

	SDKHook( iEntity, SDKHook_StartTouch, TestTouchStart );
	SDKHook( iEntity, SDKHook_EndTouch, TestTouchEnd );

	CreateTimer( 0.1, Timer_PDZoneThink, iRef, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT );
}

int GetNextKey( char[] szString, int iLength, char[] szBuffer, int iBufferLen ) {
	int iIndex = BreakString( szString, szBuffer, iBufferLen );
	StrReduce( szString, iLength, iIndex );
	return iIndex;
}

void TryPushNextInt( char[] szString, int iSize, int &iValue ) {
	static char szBuffer[256];
	int iIndex = GetNextKey( szString, iSize, szBuffer, sizeof( szBuffer ) );

	if( iIndex == -1 || StrEqual( szBuffer, "}" ) )
		return;

	iValue = StringToInt( szBuffer );

	#if defined DEBUG
		PrintToServer("KEYPUSHINT69: %s", szBuffer);
	#endif
}

void TryPushNextFloat( char[] szString, int iSize, float &flValue ) {
	static char szBuffer[256];
	int iIndex = GetNextKey( szString, iSize, szBuffer, sizeof( szBuffer ) );

	if( iIndex == -1 || StrEqual( szBuffer, "}" ) )
		return;

	flValue = StringToFloat( szBuffer );

	#if defined DEBUG
		PrintToServer("KEYPUSHFLOAT: %s", szBuffer);
	#endif
}

void TryPushNextOutput( char[] szString, int iSize, ArrayList &hCapzone ) {
	static char szBuffer[256];
	int iIndex = GetNextKey( szString, iSize, szBuffer, sizeof( szBuffer ) );

	if( iIndex == -1 || StrEqual( szBuffer, "}" ) )
		return;

	PDOutput pOutput;
	static char szBuffer2[5][256]; //targetname, input, parameter, delay, refires 

	ReplaceString( szBuffer, iSize, "\e", "," ); //selbyen uses the escape character instead of commas i guess?
	ExplodeString( szBuffer, ",", szBuffer2, 5, 256 );

	/*PrintToServer( "0: %s", szBuffer2[0] );
	PrintToServer( "1: %s", szBuffer2[1] );
	PrintToServer( "2: %s", szBuffer2[2] );
	PrintToServer( "3: %s", szBuffer2[3] );
	PrintToServer( "4: %s", szBuffer2[4] );*/

	strcopy( pOutput.szTargetname, sizeof( pOutput.szTargetname ), szBuffer2[0] );
	strcopy( pOutput.szTargetInput, sizeof( pOutput.szTargetInput ), szBuffer2[1] );
	strcopy( pOutput.szParameter, sizeof( pOutput.szParameter ), szBuffer2[2] );

	pOutput.flDelay = StringToFloat( szBuffer2[3] );
	pOutput.iRefires = StringToInt( szBuffer2[4] );

	hCapzone.PushArray( pOutput );
}

void SpawnLogicDummy() {
	if( g_iLogicDummy != -1 && EntRefToEntIndex( g_iLogicDummy ) > 0 ) {
		RemoveEntity( g_iLogicDummy );
	}

	g_iLogicDummy = EntIndexToEntRef( CreateEntityByName( "info_target" ) );
	SetEntPropString( g_iLogicDummy, Prop_Data, "m_iName", g_szLogicTargetname );
	DispatchSpawn( g_iLogicDummy );
	g_dhAcceptInput.HookEntity( Hook_Pre, g_iLogicDummy, Hook_AcceptInput );

	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	//prevent segfault when CTFGameRules::PlayerKilled tries to look up tf_logic_domination singleton

	g_pCTFLogicDomination = GameConfGetAddress( hGameConf, "CTFLogicDomination" );

	g_pCTFGameRules = LoadFromAddress( GameConfGetAddress( hGameConf, "CTFGameRules" ), NumberType_Int32 );
	g_iCTFObjectiveResource = GetEntityFromAddress( LoadFromAddress( GameConfGetAddress( hGameConf, "CTFObjectiveResource" ), NumberType_Int32 ) );

	delete hGameConf;

	if( g_pCTFGameRules == Address_Null || g_iCTFObjectiveResource == -1 ) {
		PrintToServer("[PD:C] could not dereference address of singleton %i %i", g_pCTFGameRules, g_iCTFObjectiveResource);
		return;
	}

	StoreToAddressOffset( g_pCTFGameRules, 2804, 4, NumberType_Int32 ); //m_nHudType
	StoreToAddressOffset( g_pCTFGameRules, 2816, 1, NumberType_Int8 ); //m_bPlayingDomination

	SetEntProp( g_iCTFObjectiveResource, Prop_Send, "m_iNumControlPoints", 2 );
	SetEntProp( g_iCTFObjectiveResource, Prop_Send, "m_bCPIsVisible", 0, 1, 0 );
	SetEntProp( g_iCTFObjectiveResource, Prop_Send, "m_bCPIsVisible", 0, 1, 1 );

	SetEntProp( g_iCTFObjectiveResource, Prop_Send, "m_iOwner", 2, 1, 0 );
	SetEntProp( g_iCTFObjectiveResource, Prop_Send, "m_iOwner", 3, 1, 1 );

	SetEntProp( g_iCTFObjectiveResource, Prop_Send, "m_iDominationRate", 0, 4, 0 );
	SetEntProp( g_iCTFObjectiveResource, Prop_Send, "m_iDominationRate", 0, 4, 1 );
}

//not fast but we only need this at map load so fuck it
void StrReduce( char[] szString, int iLength, int iStrip ) {
	for( int i = 0; i < iLength; i++ ) {
		if(i-iStrip < 0)
			continue;

		szString[i-iStrip] = szString[i];

		if( szString[i] == 0 )
			break;
	}
}

/*
	GAMEMODE LOGIC
*/

Action Event_PlayerSpawn( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	if( !g_bMapIsPD )
		return Plugin_Continue;

	CalculateMaxPoints();
	return Plugin_Continue;
}
Action Event_PlayerDisconnect( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	if( !g_bMapIsPD )
		return Plugin_Continue;

	CalculateMaxPoints();

	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	DropPickup( iPlayer, false );

	return Plugin_Continue;
}

public void OnGameFrame() {
	if( g_flCountdownTimer != 0.0 && GetGameTime() > g_flCountdownTimer )
		FireFakeEvent( OUT_ONCOUNTDOWNTIMEREXPIRED );
}

MRESReturn Hook_AcceptInput( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	static char szInputName[256];
	hParams.GetString( 1, szInputName, sizeof( szInputName ) );
	#if defined DEBUG
		PrintToServer( "recieved event: %s", szInputName );
	#endif

	static char szString[128];

	if( StrEqual( szInputName, "ScoreRedPoints" ) )
		SetPoints( 2, g_iRedScore+1 );
	if( StrEqual( szInputName, "ScoreBluePoints" ) )
		SetPoints( 3, g_iBlueScore+1 );

	if( StrEqual( szInputName, "EnableMaxScoreUpdating" ) )
		g_bAllowMaxScoreUpdating = true;
	if( StrEqual( szInputName, "DisableMaxScoreUpdating" ) )
		g_bAllowMaxScoreUpdating = false;
	if( StrEqual( szInputName, "SetCountdownTimer" ) ) {
		Address aStringTPointer = LoadFromAddress( hParams.GetAddress( 4 ), NumberType_Int32 );
		LoadStringFromAddress( aStringTPointer, szString, sizeof( szString ) );
		#if defined DEBUG
			PrintToServer("new timer: %s", szString);
		#endif
		g_flCountdownTimer = GetGameTime() + StringToFloat( szString );
	}
	if( StrEqual( szInputName, "SetFlagResetDelay" ) ) {
		Address aStringTPointer = LoadFromAddress( hParams.GetAddress( 4 ), NumberType_Int32 );
		LoadStringFromAddress( aStringTPointer, szString, sizeof( szString ) );
		#if defined DEBUG
			PrintToServer("new flag reset delay: %s", szString);
		#endif
		g_iFlagResetDelay = StringToInt( szString );
	}
	if( StrEqual( szInputName, "SetPointsOnPlayerDeath" ) ) {
		Address aStringTPointer = LoadFromAddress( hParams.GetAddress( 4 ), NumberType_Int32 );
		LoadStringFromAddress( aStringTPointer, szString, sizeof( szString ) );
		#if defined DEBUG
			PrintToServer("new points per player death: %s", szString);
		#endif
		g_iPointsOnPlayerDeath = StringToInt( szString );
	}


	return MRES_Handled;
}

void FireFakeEvent( int iEvent, float flOverride = -1.0 ) {
	PDOutput pOutput;
	for( int j = 0; j < g_alOutputs[ iEvent ].Length; j++ ) {
		g_alOutputs[ iEvent ].GetArray( j, pOutput );

		if( pOutput.flDelay > 0.0 ) {
			DataPack dPack = new DataPack();

			dPack.WriteString( pOutput.szTargetname );
			dPack.WriteString( pOutput.szTargetInput );
			dPack.WriteString( pOutput.szParameter );
			dPack.WriteFloat( pOutput.flDelay );
			dPack.WriteCell( pOutput.iRefires );
			dPack.WriteFloat( flOverride );

			CreateTimer( pOutput.flDelay, Timer_FireFakeEvent, dPack, TIMER_FLAG_NO_MAPCHANGE );
		} 
		else
			CallEvent( pOutput, flOverride );
	}
}

void FireFakeEventZone( PDCapZone pdZone, int iEvent ) {
	PDOutput pOutput;
	for( int j = 0; j < pdZone.hCapOutputs[ iEvent ].Length; j++ ) {
		pdZone.hCapOutputs[ iEvent ].GetArray( j, pOutput );

		if( pOutput.flDelay > 0.0 ) {
			DataPack dPack = new DataPack();

			dPack.WriteString( pOutput.szTargetname );
			dPack.WriteString( pOutput.szTargetInput );
			dPack.WriteString( pOutput.szParameter );
			dPack.WriteFloat( pOutput.flDelay );
			dPack.WriteCell( pOutput.iRefires );
			dPack.WriteFloat( -1.0 );

			CreateDataTimer( pOutput.flDelay, Timer_FireFakeEvent, dPack, TIMER_FLAG_NO_MAPCHANGE );
		} 
		else
			CallEvent( pOutput );
	}
}

Action Timer_FireFakeEvent( Handle hTimer, DataPack dPack ) {
	static char szBuffer[96];
	PDOutput pOutput;

	dPack.Reset();

	dPack.ReadString( szBuffer, 96 );
	strcopy( pOutput.szTargetname, 96, szBuffer );
	dPack.ReadString( szBuffer, 96 );
	strcopy( pOutput.szTargetInput, 96, szBuffer );
	dPack.ReadString( szBuffer, 96 );
	strcopy( pOutput.szParameter, 96, szBuffer );
	pOutput.flDelay = dPack.ReadFloat();
	pOutput.iRefires = dPack.ReadCell();
	float flOverride = dPack.ReadFloat();

	CallEvent( pOutput, flOverride );

	CloseHandle( dPack );

	return Plugin_Stop;
}

//TODO: respect refire
void CallEvent( PDOutput pOutput, float flOverride = -1.0 ) {
	static char szTest[64];
	int iDummy = EntRefToEntIndex( g_iLogicDummy );
	GetEntPropString( iDummy, Prop_Data, "m_iName", szTest, 64 );

	int iEntity = SDKCall( g_sdkFindByName, -1, pOutput.szTargetname, -1, -1, -1, Address_Null );
	while( iEntity != -1 ) {
		#if defined DEBUG
			PrintToServer( "calling event: %s", pOutput.szTargetInput );
		#endif

		if( flOverride == -1.0 )
			SetVariantString( pOutput.szParameter );
		else
			SetVariantFloat( flOverride );

		AcceptEntityInput( iEntity, pOutput.szTargetInput, -1, -1, -1 );

		iEntity = SDKCall( g_sdkFindByName, iEntity, pOutput.szTargetname, -1, -1, -1, Address_Null );
	}
}

void SetPoints( int iTeam, int iAmount = 1 ) {
	int iOldAmount;

	if( iTeam == 2 ) {
		iOldAmount = g_iRedScore;
		g_iRedScore = iAmount;

		Address aTeam = SDKCall( g_sdkGetTeam, 2 );
		SDKCall( g_sdkSetRoundScore, aTeam, g_iRedScore );

		if( iOldAmount == 0 && g_iRedScore > 0 )
			FireFakeEvent( OUT_ONREDHASPOINTS );

		if( iOldAmount == g_iPointsToWin && g_iRedScore < g_iPointsToWin )
			FireFakeEvent( OUT_ONREDLEAVEMAXPOINTS );

		if( iOldAmount != 0 && g_iRedScore == 0 )
			FireFakeEvent( OUT_ONREDHITZEROPOINTS );

		if( g_iRedScore != iOldAmount )
			FireFakeEvent( OUT_ONREDSCORECHANGED, float( g_iRedScore ) / float( g_iPointsToWin ) );

		if( g_iRedScore == g_iPointsToWin ) {
			FireFakeEvent( OUT_ONREDHITMAXPOINTS );
			SetFinale( 2 );
		}
			
	}
	else {
		iOldAmount = g_iBlueScore;
		g_iBlueScore = iAmount;

		Address aTeam = SDKCall( g_sdkGetTeam, 3 );
		SDKCall( g_sdkSetRoundScore, aTeam, g_iBlueScore );

		if( iOldAmount == 0 && g_iBlueScore > 0 )
			FireFakeEvent( OUT_ONBLUEHASPOINTS );

		if( iOldAmount == g_iPointsToWin && g_iBlueScore < g_iPointsToWin )
			FireFakeEvent( OUT_ONBLUELEAVEMAXPOINTS );

		if( iOldAmount != 0 && g_iBlueScore == 0 )
			FireFakeEvent( OUT_ONBLUEHITZEROPOINTS );

		if( g_iBlueScore != iOldAmount )
			FireFakeEvent( OUT_ONBLUESCORECHANGED, float( g_iBlueScore ) / float( g_iPointsToWin ) );

		if( g_iBlueScore == g_iPointsToWin ) {
			FireFakeEvent( OUT_ONBLUEHITMAXPOINTS );
			SetFinale( 3 );
		}
	}
}

void SetFinale( int iTeam ) {
	CreateTimer( g_flFinaleLength, Timer_EndFinale, iTeam, TIMER_FLAG_NO_MAPCHANGE );
}

Action Timer_EndFinale( Handle hTimer, int iTeam ) {
	FireFakeEvent( iTeam == 2 ? OUT_ONREDFINALEPERIODEND : OUT_ONBLUEFINALEPERIODEND );
	SetWinningTeam( iTeam );
	return Plugin_Continue;
}

void CalculateMaxPoints() {
	if( !g_bAllowMaxScoreUpdating )
		return;

	g_iPointsToWin = MaxInt( g_iMinPoints, GetClientCount( true ) * g_iPointsPerPlayer );

	if( g_pCTFLogicDomination == Address_Null )
		return;

	Address aLogicDomination = LoadFromAddress( g_pCTFLogicDomination, NumberType_Int32 );
	if( aLogicDomination == Address_Null )
		return;

	int iLogic = GetEntityFromAddress( aLogicDomination );
	if( iLogic != -1 ) {
		SetEntProp( iLogic, Prop_Data, "m_iPointLimitMap", g_iPointsToWin );
	}

	if( g_pCTFGameRules != Address_Null ) {
		StoreToAddressOffset( g_pCTFGameRules, 2856, g_iPointsToWin, NumberType_Int32 );
	}
}

void CalculateTeamLeader( int iTeam ) {
	int iHighest = -1;
	int iHighestAmount = 0;
	for( int i = 1; i <= MaxClients; i++ ) {
		if( !IsClientInGame( i ) )
			continue;

		if( GetEntProp( i, Prop_Send, "m_iTeamNum" ) != iTeam )
			continue;

		if( GetEntProp( i, Prop_Send, "m_iClass" ) == 8 ) //spy cannot be team leader
			continue;

		if( g_iPlayerCarrying[i] > iHighestAmount ) {
			iHighest = i;
			iHighestAmount = g_iPlayerCarrying[i];
		}
	}

	SetTeamLeader( iHighest, iTeam );
}

void SetTeamLeader( int iPlayer, int iTeam ) {
	if( iTeam == 2 ) {
		if( g_iRedTeamLeader == iPlayer )
			return;

		g_iRedTeamLeader = iPlayer;
	}
	else {
		if( g_iBlueTeamLeader == iPlayer )
			return;

		g_iBlueTeamLeader = iPlayer;
	}

	int iDispenser = EntRefToEntIndex( iTeam == 2 ? g_iRedLeaderDispenser : g_iBlueLeaderDispenser );
	if( iDispenser > 0 ) {
		RemoveEntity( iDispenser );
		if( iTeam == 2 ) {
			g_iRedLeaderDispenser = INVALID_ENT_REFERENCE;
		}
		else {
			g_iBlueLeaderDispenser = INVALID_ENT_REFERENCE;
		}
	}

	int iGlow = EntRefToEntIndex( iTeam == 2 ? g_iRedLeaderGlow : g_iBlueLeaderGlow );
	if( iGlow > 0 ) {
		int iOld = GetEntPropEnt( iGlow, Prop_Send, "m_hTarget" );
		SetEntProp( iOld, Prop_Send, "m_bGlowEnabled", false );
		RemoveEntity( iGlow );
		if( iTeam == 2 )
			g_iRedLeaderGlow = INVALID_ENT_REFERENCE;
		else
			g_iBlueLeaderGlow = INVALID_ENT_REFERENCE;
	}

	if( iPlayer == -1 )
		return;

	iDispenser = CreateEntityByName( "mapobj_cart_dispenser" );
	SetEntProp( iDispenser, Prop_Send, "m_iTeamNum", iTeam );
	SetEntPropEnt( iDispenser, Prop_Send, "m_hOwnerEntity", iPlayer );
	DispatchSpawn( iDispenser );

	float vecPos[3];
	GetEntPropVector( iPlayer, Prop_Send, "m_vecOrigin", vecPos );
	TeleportEntity( iDispenser, vecPos );
	ActivateEntity( iDispenser );

	ParentModel( iDispenser, iPlayer );
	SetEntityMoveType( iDispenser, MOVETYPE_NONE );
	
	RequestFrame( Frame_SetupDispenserZone, EntIndexToEntRef( iDispenser ) );

	SetPlayerOutline( iPlayer );

	if( iTeam == 2 ) {
		g_iRedLeaderDispenser = EntIndexToEntRef( iDispenser );
	}
	else {
		g_iBlueLeaderDispenser = EntIndexToEntRef( iDispenser );
	}
}

void SetPlayerOutline( int iPlayer ) {
	int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" );
	int iGlow = CreateEntityByName( "tf_glow" );

	static char szOldName[ 64 ];
	GetEntPropString( iPlayer, Prop_Data, "m_iName", szOldName, sizeof(szOldName) );

	char szNewName[ 128 ], szClassname[ 64 ];
	GetEntityClassname( iPlayer, szClassname, sizeof( szClassname ) );
	Format( szNewName, sizeof( szNewName ), "%s%i", szClassname, iPlayer );
	DispatchKeyValue( iPlayer, "targetname", szNewName );

	DispatchKeyValue( iGlow, "target", szNewName );
	DispatchSpawn( iGlow );
	
	SetEntPropString( iPlayer, Prop_Data, "m_iName", szOldName );
	
	ParentModel( iGlow, iPlayer );

	SetEdictFlags( iGlow, 0 );
	SetVariantColor( iTeam == 2 ? REDCOLOR : BLUCOLOR );
	AcceptEntityInput( iGlow, "SetGlowColor" );

	SetEntProp( iPlayer, Prop_Send, "m_bGlowEnabled", true );

	if( iTeam == 2 )
		g_iRedLeaderGlow = EntIndexToEntRef( iGlow );
	else
		g_iBlueLeaderGlow = EntIndexToEntRef( iGlow );
}

//Action Timer_SetupDispenserZone( Handle hTimer, int iDispenser ) {
void Frame_SetupDispenserZone( int iDispenser ) {
	iDispenser = EntRefToEntIndex( iDispenser );
	if( iDispenser == -1 )
		return;

	int iTriggerZone = LoadEntityHandleFromAddress( GetEntityAddress( iDispenser ) + view_as<Address>(2456) );
	if( iTriggerZone == -1 )
		return;

	ParentModel( iTriggerZone, iDispenser );
	SetEntityMoveType( iTriggerZone, MOVETYPE_NONE );

	float vecMins[3];
	float vecMaxs[3];

	vecMins[0] = float( -g_iHealDistance );
	vecMins[1] = float( -g_iHealDistance );
	vecMins[2] = float( -g_iHealDistance );
	vecMaxs[0] = float( g_iHealDistance );
	vecMaxs[1] = float( g_iHealDistance );
	vecMaxs[2] = float( g_iHealDistance );

	SetSize( iTriggerZone, vecMins, vecMaxs );

	return;
}

MRESReturn Detour_GetDispenserRadius( int iThis, DHookReturn hReturn ) {
	int iThisRef = EntIndexToEntRef( iThis );
	int iThisTeam = GetEntProp( iThis, Prop_Send, "m_iTeamNum" );
	if( iThisRef != ( iThisTeam == 2 ? g_iRedLeaderDispenser : g_iBlueLeaderDispenser ) )
		return MRES_Ignored;

	hReturn.Value = float( g_iHealDistance );
	return MRES_Supercede;
}

void CalculateTeamHolding( int iTeam ) {
	int iAmount = 0;
	for( int i = 1; i < MaxClients; i++ ) {
		if( !IsClientInGame( i ) )
			continue;

		if( GetEntProp( i, Prop_Send, "m_iTeamNum" ) != iTeam )
			continue;

		iAmount += g_iPlayerCarrying[i];
	}

	if( iTeam == 2 ) {
		g_iRedTeamHolding = iAmount;
		if( g_iCTFObjectiveResource != -1 )
			SetEntProp( g_iCTFObjectiveResource, Prop_Send, "m_iDominationRate", iAmount, 4, 0 );
	}
	else {
		g_iBlueTeamHolding = iAmount;
		if( g_iCTFObjectiveResource != -1 )
			SetEntProp( g_iCTFObjectiveResource, Prop_Send, "m_iDominationRate", iAmount, 4, 1 );
	}
}

Action TestTouchStart( int iEntity, int iOther ) {
	if( !IsValidPlayer( iOther ) )
		return Plugin_Continue;

	int iRef = EntIndexToEntRef( iEntity );
	
	PDCapZone pdZone;
	FindCaptureZone( iRef, pdZone );

	int iOtherRef = EntIndexToEntRef( iOther );
	if( pdZone.hPlayersTouching.FindValue( iOtherRef ) == -1 ) {
		pdZone.hPlayersTouching.Push( iOtherRef );
	}

	return Plugin_Continue;
}
Action TestTouchEnd( int iEntity, int iOther ) {
	if( !IsValidPlayer( iOther ) )
		return Plugin_Continue;

	int iRef = EntIndexToEntRef( iEntity );
	
	PDCapZone pdZone;
	FindCaptureZone( iRef, pdZone );

	int iOtherRef = EntIndexToEntRef( iOther );
	int iIndex = pdZone.hPlayersTouching.FindValue( iOtherRef );
	if( iIndex != -1 ) {
		pdZone.hPlayersTouching.Erase( iIndex );
	}

	return Plugin_Continue;
}

bool FindCaptureZone( int iRef, PDCapZone pdZone ) {
	static char szRefString[128];

	IntToString( iRef, szRefString, sizeof( szRefString ) );
	return g_smCaptureZones.GetArray( szRefString, pdZone, PDZONE_SIZE );
}

#define EMITTARGET -2

//manually read out the contents of m_hTouchingEntities
Action Timer_PDZoneThink( Handle hTimer, int iData ) {
	PDCapZone pdZone;
	FindCaptureZone( iData, pdZone );

	int iIndex = EntRefToEntIndex( iData );
	if( iIndex == -1 )
		return Plugin_Stop;

	if( GetEntProp( iIndex, Prop_Data, "m_bDisabled" ) )
		return Plugin_Continue;

	bool bRedInZone = false;
	bool bBlueInZone = false;

	int iInRed[MAXPLAYERS+1];
	int iRedNext = 0;
	int iInBlue[MAXPLAYERS+1];
	int iBlueNext = 0;

	for( int i = 0; i < pdZone.hPlayersTouching.Length; i++ ) {
		int iPlayer = pdZone.hPlayersTouching.Get( i );
		iPlayer = EntRefToEntIndex( iPlayer );

		if( iPlayer == -1)
			continue;

		int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" );
		if( iTeam == 2 ) {
			bRedInZone = true;
		}
		else if( iTeam == 3 ) {
			bBlueInZone = true;
		}
	}

	if( pdZone.hPlayersTouching.Length > 0 )
		for( int i = 1; i <= MaxClients; i++ ) {
			if( !IsClientInGame( i ) )
				continue;

			int iTeam = GetEntProp( i, Prop_Send, "m_iTeamNum" );
			if( iTeam == 2 ) {
				iInRed[ iRedNext ] = i;
				iRedNext++;
			}
			else if( iTeam == 3 ) {
				iInBlue[ iBlueNext ] = i;
				iBlueNext++;
			}
		}

	if( pdZone.bCanBlock && bRedInZone && bBlueInZone )
		return Plugin_Continue;

	float flCapDelay = pdZone.flCaptureDelay - ( pdZone.flCaptureDelayOffset * GetClientCount( true ) );
	for( int i = 0; i < pdZone.hPlayersTouching.Length; i++ ) {
		int iPlayer = pdZone.hPlayersTouching.Get( i );
		iPlayer = EntRefToEntIndex( iPlayer );
		
		if( iPlayer == -1)
			continue;

		if( g_iPlayerCarrying[ iPlayer ] == 0 || GetGameTime() < g_flNextCaptureTime[ iPlayer ] )
			continue;


		int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" );
		if( ( iTeam == 2 ? g_iRedScore : g_iBlueScore ) >= g_iPointsToWin )
			continue;

		int iPointTeam = GetEntProp( iIndex, Prop_Data, "m_iTeamNum" );
		if( iPointTeam != 0 && iPointTeam != iTeam )
			continue;

		if( iTeam == 2 ) {
			FireFakeEventZone( pdZone, OUTCAP_REDCAP );
			float flNewPitch = RemapValClamped( float( g_iRedScore ), 0.0, float( g_iPointsToWin ), 100.0, 120.0 ); 
			EmitSound( iInRed, iRedNext, "ui/chime_rd_2base_pos.wav", EMITTARGET, SNDCHAN_AUTO, SNDLEVEL_MINIBIKE, SND_CHANGEPITCH | SND_CHANGEVOL, 0.5, RoundToNearest( flNewPitch ) );
			EmitSound( iInBlue, iBlueNext, "ui/chime_rd_2base_neg.wav", EMITTARGET, SNDCHAN_AUTO, SNDLEVEL_MINIBIKE, SND_CHANGEPITCH | SND_CHANGEVOL, 0.5, RoundToNearest( flNewPitch ) );
		}
		else if( iTeam == 3 ) {
			FireFakeEventZone( pdZone, OUTCAP_BLUECAP );
			float flNewPitch = RemapValClamped( float( g_iBlueScore ), 0.0, float( g_iPointsToWin ), 100.0, 120.0 ); 
			EmitSound( iInBlue, iBlueNext, "ui/chime_rd_2base_pos.wav", EMITTARGET, SNDCHAN_AUTO, SNDLEVEL_MINIBIKE, SND_CHANGEPITCH | SND_CHANGEVOL, 0.5, RoundToNearest( flNewPitch ) );
			EmitSound( iInRed, iRedNext, "ui/chime_rd_2base_neg.wav", EMITTARGET, SNDCHAN_AUTO, SNDLEVEL_MINIBIKE, SND_CHANGEPITCH | SND_CHANGEVOL, 0.5, RoundToNearest( flNewPitch ) );
		}

		SetPlayerPoints( iPlayer, g_iPlayerCarrying[ iPlayer ] - 1 );
		g_flNextCaptureTime[ iPlayer ] = GetGameTime() + flCapDelay;
	}

	return Plugin_Continue;
}

void SetPlayerPoints( int iPlayer, int iPoints ) {
	int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" );
	g_iPlayerCarrying[ iPlayer ] = MaxInt( 0, iPoints );

	CalculateTeamHolding( iTeam );
	CalculateTeamLeader( iTeam );
} 

Action Timer_HudThink( Handle hTimer ) {
	for ( int i = 1; i <= MaxClients; i++ ) {
		if ( IsClientInGame( i ) && !IsFakeClient( i )  ) {
			Hud_Display( i );
		}
	}
	return Plugin_Continue;
}

void Hud_Display( int iPlayer ) {
	static char szFinal[256];
	static char szBuffer[64];
	szFinal = "";
	szBuffer = "";

	Format( szBuffer, sizeof( szBuffer ), "Holding: %i\n", g_iPlayerCarrying[iPlayer] );
	StrCat( szFinal, sizeof( szFinal ), szBuffer );

	if( g_flCountdownTimer > GetGameTime() ) {
		Format( szBuffer, sizeof( szBuffer ), "       %-.0f", g_flCountdownTimer - GetGameTime() );
		StrCat( szFinal, sizeof( szFinal ), szBuffer );
	}
	SetHudTextParamsEx( 0.475, 0.91, 20.0, { 255, 255, 255, 1}, {255,255,255,0}, 0, 6.0, 0.0, 0.0 );
	ShowSyncHudText( iPlayer, g_hsHudSyncMiddle, szFinal );	
}

/*
	PICKUPS
*/

Action Event_PlayerDeath( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	if( !g_bMapIsPD )
		return Plugin_Continue;

	int iVictim = hEvent.GetInt( "userid" );
	iVictim = GetClientOfUserId( iVictim );
	int iAttacker = hEvent.GetInt( "attacker" );
	iAttacker = GetClientOfUserId( iAttacker );

	//don't drop extra points on suicide
	bool bSuicide = ( iVictim == iAttacker );
	DropPickup( iVictim, !bSuicide );

	return Plugin_Continue;
}

int DropPickup( int iPlayer, bool bAddPoints ) {
	int iPointsToDrop = g_iPlayerCarrying[ iPlayer ];
	if( bAddPoints )
		iPointsToDrop+=g_iPointsOnPlayerDeath;
	if( iPointsToDrop <= 0 )
		return -1;

	float vecPlayerPos[3];
	GetEntPropVector( iPlayer, Prop_Send, "m_vecOrigin", vecPlayerPos );

	g_iPlayerCarrying[ iPlayer ] = 0;
	CalculateTeamHolding( GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) );
	CalculateTeamLeader( GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) );
	int iEntity = CreatePickup( iPointsToDrop );
	TeleportEntity( iEntity, vecPlayerPos );

	return iEntity;
}

int CreatePickup( int iAmount ) {
	PDPickup pdPickup;
	pdPickup.iAmount = iAmount;
	pdPickup.flExpireTime = GetGameTime() + float( g_iFlagResetDelay );

	int iEntity = CreateEntityByName( "prop_dynamic" );
	SetSolidFlags( iEntity, FSOLID_TRIGGER );
	SetEntityModel( iEntity, g_szPropModelName );
	DispatchSpawn( iEntity );

	EmitPDSoundToAll( g_szPropDropSound, iEntity );

	int iSequence = SDKCall( g_sdkLookupSequence, iEntity, "spin" );
	if( iSequence != -1 ) {
		SetVariantString( "spin" );
		AcceptEntityInput( iEntity, "SetAnimation" );
	} else {
		iSequence = SDKCall( g_sdkLookupSequence, iEntity, "idle" );
		if( iSequence != -1 ) {
			SetVariantString( "idle" );
			AcceptEntityInput( iEntity, "SetAnimation" );
		}
	}

	pdPickup.iGlowRef = EntIndexToEntRef( SetPickupGlow( iEntity ) );

	static char szRefBuffer[48];
	int iRef = EntIndexToEntRef( iEntity );
	IntToString( iRef, szRefBuffer, sizeof( szRefBuffer ) );
	g_smPickups.SetArray( szRefBuffer, pdPickup, PDPICKUP_SIZE );

	CreateTimer( float( g_iFlagResetDelay ), Timer_PickupThink, iRef, TIMER_FLAG_NO_MAPCHANGE );
	g_dhTouch.HookEntity( Hook_Pre, iEntity, Hook_PickupTouch );

	return iEntity;
}
int SetPickupGlow( int iPickup ) {
	int iGlow = CreateEntityByName( "tf_glow" );

	static char szOldName[ 64 ];
	GetEntPropString( iPickup, Prop_Data, "m_iName", szOldName, sizeof(szOldName) );

	char szNewName[ 128 ], szClassname[ 64 ];
	GetEntityClassname( iPickup, szClassname, sizeof( szClassname ) );
	Format( szNewName, sizeof( szNewName ), "%s%i", szClassname, iPickup );
	DispatchKeyValue( iPickup, "targetname", szNewName );

	DispatchKeyValue( iGlow, "target", szNewName );
	DispatchSpawn( iGlow );
	
	SetEntPropString( iPickup, Prop_Data, "m_iName", szOldName );
	
	ParentModel( iGlow, iPickup );

	int iColor[4] = { 255,255,255,255 };
	SetVariantColor( iColor );
	AcceptEntityInput( iGlow, "SetGlowColor" );
	
	return iGlow;
}

bool FindPickup( int iRef, PDPickup pdPickup ) {
	static char szRefString[128];
	IntToString( iRef, szRefString, sizeof( szRefString ) );
	return g_smPickups.GetArray( szRefString, pdPickup, PDPICKUP_SIZE );
}

void RemovePickup( int iPickupReference ) {
	static char szRefString[128];
	IntToString( iPickupReference, szRefString, sizeof( szRefString ) );

	PDPickup pdPickup;
	if( FindPickup( iPickupReference, pdPickup ) ) {
		int iGlowIndex = EntRefToEntIndex( pdPickup.iGlowRef );
		if( iGlowIndex > 0 )
			RemoveEntity( iGlowIndex );
	}

	g_smPickups.Remove( szRefString );

	int iIndex = EntRefToEntIndex( iPickupReference );
	if( iIndex > 0 )
		RemoveEntity( iIndex );
}

Action Timer_PickupThink( Handle hTimer, int iRef ) {
	RemovePickup( iRef );
	return Plugin_Stop;
}

MRESReturn Hook_PickupTouch( int iThis, DHookParam hParams ) {
	int iToucher = hParams.Get( 1 );

	if( !IsValidPlayer( iToucher ) )
		return MRES_Ignored;

	if( GetGameTime() < g_flPickupCooler[ iToucher ] )
		return MRES_Ignored;

	if( TF2_IsPlayerInCondition( iToucher, TFCond_Cloaked ) || TF2_IsPlayerInCondition( iToucher, TFCond_Disguised ) )
		return MRES_Ignored;

	float vecPos[3];
	GetEntPropVector( iToucher, Prop_Send, "m_vecOrigin", vecPos );
	if( SDKCall( g_sdkInRespawnRoom, iToucher, vecPos ) )
		return MRES_Ignored;

	int iTeam = GetEntProp( iToucher, Prop_Send, "m_iTeamNum" );
	PDPickup pdPickup;

	int iRef = EntIndexToEntRef( iThis );
	if( !FindPickup( iRef, pdPickup ) ) {
		PrintToServer("[PD:C] could not find data for pickup, this should not happen");
		return MRES_Ignored;
	}

	EmitPDSoundToAll( g_szPropPickupSound, iToucher );
	g_iPlayerCarrying[ iToucher ] += pdPickup.iAmount;
	CalculateTeamHolding( iTeam );
	CalculateTeamLeader( iTeam );

	RemovePickup( iRef );

	return MRES_Handled;
}

MRESReturn Detour_DropFlag( int iThis ) {
	if( g_iPlayerCarrying[ iThis ] < 1 )
		return MRES_Handled;

	DropPickup( iThis, false );
	g_flPickupCooler[ iThis ] = GetGameTime() + 2.0;

	return MRES_Handled;
}

MRESReturn Detour_RespawnTouch( int iThis, DHookParam hParams ) {
	int iEntity = hParams.Get( 1 );

	if( !IsValidPlayer( iEntity ) )
		return MRES_Ignored;

	if( g_iPlayerCarrying[ iEntity ] <= 0 )
		return MRES_Ignored;

	DropPickup( iEntity, false );
	g_flPickupCooler[ iEntity ] = GetGameTime() + 1.0;

	return MRES_Handled;
}

#if defined DEBUG
Action Command_Test( int iClient, int iArgs ) {
	if(iArgs < 4) return Plugin_Handled;

	int iMode = GetCmdArgInt( 1 );
	int iSecond = GetCmdArgInt( 2 );
	int iThird = GetCmdArgInt( 3 );
	int iFourth = GetCmdArgInt( 4 );
	
	switch( iMode ) {
	case 0: {
		int iEntity = CreatePickup( 1 );
		float vecPos[3];
		GetEntPropVector( iSecond, Prop_Send, "m_vecOrigin", vecPos );
		TeleportEntity( iEntity, vecPos );
		return Plugin_Handled;
	}
	case 1: {
		if( LoadFromAddress( g_pCTFLogicDomination, NumberType_Int32 ) == Address_Null ) {
			int iLogic = CreateEntityByName( "tf_logic_domination" );
			DispatchSpawn( iLogic );
			
			Address aAddress2 = GetEntityAddress( iLogic );

			PrintToServer( "%i %i", g_pCTFLogicDomination, aAddress2 );
			StoreToAddress( g_pCTFLogicDomination, aAddress2, NumberType_Int32 );
		}

		PrintToServer("%i", GetEntityFromAddress( LoadFromAddress( g_pCTFLogicDomination, NumberType_Int32 ) ) );
	}
	}
	
	return Plugin_Handled;
}
#endif

void SetWinningTeam( int iTeam ) {
	SDKCall( g_sdkSetWinningTeam, iTeam, 13, true, false, false, false );
}

void EmitPDSoundToAll( char[] szString, int iSource ) {
	if( StrContains( szString, ".wav" ) || StrContains( szString, ".mp3" ) )
		EmitSoundToAll( szString, iSource );
	else
		EmitGameSoundToAll( szString, iSource );
}

//CTFGameRules::PlayerKilled checks for a domination logic when the hud is enabled so i need to fill it so it doesn't segfault
void CheckFillLogicSingleton() {
	if( g_pCTFLogicDomination != Address_Null && LoadFromAddress( g_pCTFLogicDomination, NumberType_Int32 ) == Address_Null ) {
		int iLogic = CreateEntityByName( "tf_logic_domination" );
		DispatchKeyValueInt( iLogic, "point_limit", g_iPointsToWin );
		DispatchKeyValueInt( iLogic, "win_on_limit", 0 );
		DispatchSpawn( iLogic );
		
		Address aAddress2 = GetEntityAddress( iLogic );

		StoreToAddress( g_pCTFLogicDomination, aAddress2, NumberType_Int32 );
	}
}

MRESReturn Hook_PointRate( Address aThis, DHookReturn hReturn ) {
	if( g_bMapIsPD ) {
		hReturn.Value = 0;
		return MRES_Supercede;
	}

	return MRES_Ignored;
}