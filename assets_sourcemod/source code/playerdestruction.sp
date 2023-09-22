#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <kocwtools>
#include <dhooks>

//TODO: implement refire limit

/* MAP CHECKLIST
	pd_watergate: working
	pd_selbyen: working
	pd_monster_bash: working
	pd_suijin_event: working
*/

public Plugin myinfo = {
	name = "Player Destruction Classic",
	author = "Noclue",
	description = "Wrapper to allow running PD maps in TF2C",
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

#define REDCOLOR { 184, 56, 59, 1 }
#define BLUCOLOR { 88, 133, 162, 1 }

//func_capturezone
//these already exist but need additional functionality

//stores PDCapZones using the object's entity reference for lookup
StringMap smCaptureZones;

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

char szLogicTargetname[128];

char szPropModelName[128];
char szPropDropSound[128];
char szPropPickupSound[128];

float flBlueRespawnTime;
float flRedRespawnTime;

int iMinPoints;
int iPointsPerPlayer;

float flFinaleLength;

int iFlagResetDelay;
int iHealDistance;

//current gamemode info

int g_iLogicDummy; //dummy object to catch inputs

float flCountdownTimer;

int iPointsToWin;

int iRedScore;
int iBlueScore;

int iPlayerCarrying[MAXPLAYERS+1];
float flNextCaptureTime[MAXPLAYERS+1];

int iRedTeamLeader = -1;
int iRedLeaderDispenser = INVALID_ENT_REFERENCE;
int iRedLeaderGlow = INVALID_ENT_REFERENCE;

int iBlueTeamLeader = -1;
int iBlueLeaderDispenser = INVALID_ENT_REFERENCE;
int iBlueLeaderGlow = INVALID_ENT_REFERENCE;

int iRedTeamHolding = 0;
int iBlueTeamHolding = 0;

int iPointsOnPlayerDeath = 1;

bool bAllowMaxScoreUpdating = true;

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
ArrayList hOutputs[OUT_LAST];

/*
	PICKUPS
*/

StringMap smPickups;

#define PDPICKUP_SIZE 2
enum struct PDPickup {
	int iAmount;
	float flExpireTime;
}

float flPickupCooler[MAXPLAYERS+1];

#define OUTPUT_CELLSIZE sizeof( PDOutput )
#define HUD_UPDATEINTERVAL 0.5

DynamicDetour hParseEntity;
DynamicDetour hRespawnTouch;
DynamicDetour hDispenserRadius;
DynamicDetour hDropFlag;
DynamicHook hAcceptInput;
DynamicHook hTouch;
Handle hExtractValue;
Handle hFindByName;
Handle hInRespawnRoom;
Handle hSetWinningTeam;
Handle hLookupSequence;

Handle hHudSyncRed;
Handle hHudSyncBlue;
Handle hHudSyncMiddle;

#define DEBUG

public void OnPluginStart() {
	hHudSyncRed = CreateHudSynchronizer();
	hHudSyncBlue = CreateHudSynchronizer();
	hHudSyncMiddle = CreateHudSynchronizer();

	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	hParseEntity = DynamicDetour.FromConf( hGameConf, "MapEntity_ParseEntity" );
	hParseEntity.Enable( Hook_Pre, Detour_ParseEntity );
	hParseEntity.Enable( Hook_Post, Detour_ParseEntityPost );

	hRespawnTouch = DynamicDetour.FromConf( hGameConf, "CFuncRespawnRoom::RespawnRoomTouch" );
	hRespawnTouch.Enable( Hook_Pre, Detour_RespawnTouch );

	hAcceptInput = DynamicHook.FromConf( hGameConf, "CBaseEntity::AcceptInput" );
	hTouch = DynamicHook.FromConf( hGameConf, "CBaseEntity::Touch" );

	hDispenserRadius = DynamicDetour.FromConf( hGameConf, "CObjectDispenser::GetDispenserRadius" );
	hDispenserRadius.Enable( Hook_Pre, Detour_GetDispenserRadius );

	hDropFlag = DynamicDetour.FromConf( hGameConf, "CTFPlayer::DropFlag" );
	hDropFlag.Enable( Hook_Pre, Detour_DropFlag );

	StartPrepSDKCall( SDKCall_Static );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "PointInRespawnRoom" );
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByRef );
	hInRespawnRoom = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Static );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "MapEntity_ExtractValue" );
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	hExtractValue = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_GameRules );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFGameRules::SetWinningTeam" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	hSetWinningTeam = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CBaseAnimating::LookupSequence" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	hLookupSequence = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_EntityList );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CGlobalEntityList::FindEntityByName" );
	PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain, VDECODE_FLAG_ALLOWNULL );
	hFindByName = EndPrepSDKCall();

	HookEvent( "player_spawn", Event_PlayerSpawn );
	HookEvent( "player_disconnect", Event_PlayerDisconnect );
	HookEvent( "player_death", Event_PlayerDeath );

#if defined DEBUG
	RegConsoleCmd( "sm_pd_test", Command_Test, "test" );
#endif
	delete hGameConf;
}

bool bMapIsPD;
public void OnMapInit( const char[] szMapName ) {
	bMapIsPD = StrContains( szMapName, "pd_", true ) == 0;

	for( int i = 0; i < OUT_LAST; i++) {
		hOutputs[i] = new ArrayList( OUTPUT_CELLSIZE );
	}

	smCaptureZones = new StringMap();
	smPickups = new StringMap();
}

public void OnMapStart() {
	if( !bMapIsPD )
		return;

	CreateTimer( HUD_UPDATEINTERVAL, Timer_HudThink, 0, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT );
	RequestFrame( SpawnLogicDummy );

	PrecacheSound("ui/chime_rd_2base_pos.wav");
	PrecacheSound("ui/chime_rd_2base_neg.wav");
}

/*
	MAP DATA PARSING
*/

MRESReturn Detour_ParseEntity( DHookReturn hReturn, DHookParam hParams ) {
	if( !bMapIsPD )
		return MRES_Ignored;

	static char szEntData[2048];
	static char szKeyBuffer[2048];

	hParams.GetString( 2, szEntData, sizeof( szEntData ) );
	
	if( !SDKCall( hExtractValue, szEntData, "classname", szKeyBuffer ) )
		return MRES_Handled;
	if( StrEqual( szKeyBuffer, "tf_logic_player_destruction" ) )
		ParseLogicEntity( szEntData );

	return MRES_Handled;
}

MRESReturn Detour_ParseEntityPost( DHookReturn hReturn, DHookParam hParams ) {
	if( !bMapIsPD )
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

	iHealDistance = 450;
	iFlagResetDelay = 60;

	int iIndex = GetNextKey( szEntData, sizeof( szEntData ), szKeyBuffer, sizeof( szKeyBuffer ) );
	while( iIndex != -1 ) {
		if( StrEqual( szKeyBuffer, "}" ) )
			break;

		//lord please forgive me
		if( StrEqual( szKeyBuffer, "targetname" ) )		GetNextKey( szEntData, sizeof( szEntData ), szLogicTargetname, sizeof( szLogicTargetname ) );

		if( StrEqual( szKeyBuffer, "prop_model_name" ) )	GetNextKey( szEntData, sizeof( szEntData ), szPropModelName, sizeof( szPropModelName ) );
		if( StrEqual( szKeyBuffer, "prop_drop_sound" ) )	GetNextKey( szEntData, sizeof( szEntData ), szPropDropSound, sizeof( szPropDropSound ) );
		if( StrEqual( szKeyBuffer, "prop_pickup_sound" ) )	GetNextKey( szEntData, sizeof( szEntData ), szPropPickupSound, sizeof( szPropPickupSound ) );

		if( StrEqual( szKeyBuffer, "blue_respawn_time" ) )	TryPushNextFloat( szEntData, sizeof( szEntData ), flBlueRespawnTime );
		if( StrEqual( szKeyBuffer, "red_respawn_time" ) )	TryPushNextFloat( szEntData, sizeof( szEntData ), flRedRespawnTime );

		if( StrEqual( szKeyBuffer, "min_points" ) )		TryPushNextInt( szEntData, sizeof( szEntData ), iMinPoints );
		if( StrEqual( szKeyBuffer, "points_per_player" ) )	TryPushNextInt( szEntData, sizeof( szEntData ), iPointsPerPlayer );

		if( StrEqual( szKeyBuffer, "finale_length" ) )		TryPushNextFloat( szEntData, sizeof( szEntData ), flFinaleLength );

		if( StrEqual( szKeyBuffer, "flag_reset_delay" ) )	TryPushNextInt( szEntData, sizeof( szEntData ), iFlagResetDelay );
		if( StrEqual( szKeyBuffer, "heal_distance" ) )		TryPushNextInt( szEntData, sizeof( szEntData ), iHealDistance );

		for( int i = 0; i < OUT_LAST; i++) {
			if( StrEqual( szOutputNames[i], szKeyBuffer ) )		TryPushNextOutput( szEntData, sizeof( szEntData ), hOutputs[ i ] );
		}

		iIndex = GetNextKey( szEntData, sizeof( szEntData ), szKeyBuffer, sizeof( szKeyBuffer ) );
	}

	iRedScore = 0;
	iRedTeamHolding = 0;
	iBlueScore = 0;
	iBlueTeamHolding = 0;

	SetTeamLeader( -1, 2 );
	SetTeamLeader( -1, 3 );

	iPointsOnPlayerDeath = 1;
	bAllowMaxScoreUpdating = true;

	flCountdownTimer = 0.0;

	#if defined DEBUG
		PrintToChatAll( "[PD:C] DEBUG MODE IS ENABLED" );
	#endif

	for( int i = 0; i < MAXPLAYERS+1; i++ ) {
		iPlayerCarrying[i] = 0;
		flNextCaptureTime[i] = 0.0;
		flPickupCooler[i] = GetGameTime();
	}

	CalculateMaxPoints();

	if( !StrEqual( szPropModelName, "" ) )
		PrecacheModel( szPropModelName );
	if( !StrEqual( szPropDropSound, "" ) )
		PrecacheSound( szPropDropSound );
	if( !StrEqual( szPropPickupSound, "" ) )
		PrecacheSound( szPropPickupSound );
}

void ParseCaptureZone( int iEntity, char szEntData[2048] ) {
	static char szKeyBuffer[2048];

	PDCapZone pdZone;

	pdZone.hPlayersTouching = new ArrayList();
	pdZone.hCapOutputs[0] = new ArrayList( sizeof( PDOutput ) );
	pdZone.hCapOutputs[1] = new ArrayList( sizeof( PDOutput ) );

	int iIndex = GetNextKey( szEntData, sizeof( szEntData ), szKeyBuffer, sizeof( szKeyBuffer ) );
	#if defined DEBUG
		PrintToServer("pasing capture zone");
	#endif
	while( iIndex != -1 ) {
		if( StrEqual( szKeyBuffer, "}" ) )
			break;

		//lord please forgive me
		if( StrEqual( szKeyBuffer, "capture_delay" ) )		TryPushNextFloat( szEntData, sizeof( szEntData ), pdZone.flCaptureDelay );
		if( StrEqual( szKeyBuffer, "capture_delay_offset" ) )	TryPushNextFloat( szEntData, sizeof( szEntData ), pdZone.flCaptureDelayOffset );
		if( StrEqual( szKeyBuffer, "shouldBlock" ) )		TryPushNextInt( szEntData, sizeof( szEntData ), pdZone.bCanBlock );

		for( int i = 0; i < OUTCAP_LAST; i++) {
			if( StrEqual( szOutputCapNames[i], szKeyBuffer ) ) {
				TryPushNextOutput( szEntData, sizeof( szEntData ), pdZone.hCapOutputs[i] );
			}
		}

		iIndex = GetNextKey( szEntData, sizeof( szEntData ), szKeyBuffer, sizeof( szKeyBuffer ) );
	}

	int iRef = EntIndexToEntRef( iEntity );
	IntToString( iRef, szKeyBuffer, sizeof( szKeyBuffer ) );
	smCaptureZones.SetArray( szKeyBuffer, pdZone, PDZONE_SIZE );

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
		PrintToServer("KEYPUSHINT: %s", szBuffer);
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
	SetEntPropString( g_iLogicDummy, Prop_Data, "m_iName", szLogicTargetname );
	DispatchSpawn( g_iLogicDummy );
	hAcceptInput.HookEntity( Hook_Pre, g_iLogicDummy, Hook_AcceptInput );
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
	if( !bMapIsPD )
		return Plugin_Continue;

	CalculateMaxPoints();
	return Plugin_Continue;
}
Action Event_PlayerDisconnect( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	if( !bMapIsPD )
		return Plugin_Continue;

	CalculateMaxPoints();

	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	DropPickup( iPlayer, false );

	return Plugin_Continue;
}

public void OnGameFrame() {
	if( flCountdownTimer != 0.0 && GetGameTime() > flCountdownTimer )
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
		SetPoints( 2, iRedScore+1 );
	if( StrEqual( szInputName, "ScoreBluePoints" ) )
		SetPoints( 3, iBlueScore+1 );

	if( StrEqual( szInputName, "EnableMaxScoreUpdating" ) )
		bAllowMaxScoreUpdating = true;
	if( StrEqual( szInputName, "DisableMaxScoreUpdating" ) )
		bAllowMaxScoreUpdating = false;
	if( StrEqual( szInputName, "SetCountdownTimer" ) ) {
		Address aStringTPointer = LoadFromAddress( hParams.GetAddress( 4 ), NumberType_Int32 );
		LoadStringFromAddress( aStringTPointer, szString, sizeof( szString ) );
		#if defined DEBUG
			PrintToServer("new timer: %s", szString);
		#endif
		flCountdownTimer = GetGameTime() + StringToFloat( szString );
	}
	if( StrEqual( szInputName, "SetFlagResetDelay" ) ) {
		Address aStringTPointer = LoadFromAddress( hParams.GetAddress( 4 ), NumberType_Int32 );
		LoadStringFromAddress( aStringTPointer, szString, sizeof( szString ) );
		#if defined DEBUG
			PrintToServer("new flag reset delay: %s", szString);
		#endif
		iFlagResetDelay = StringToInt( szString );
	}
	if( StrEqual( szInputName, "SetPointsOnPlayerDeath" ) ) {
		Address aStringTPointer = LoadFromAddress( hParams.GetAddress( 4 ), NumberType_Int32 );
		LoadStringFromAddress( aStringTPointer, szString, sizeof( szString ) );
		#if defined DEBUG
			PrintToServer("new points per player death: %s", szString);
		#endif
		iPointsOnPlayerDeath = StringToInt( szString );
	}


	return MRES_Handled;
}

void FireFakeEvent( int iEvent, float flOverride = -1.0 ) {
	PDOutput pOutput;
	for( int j = 0; j < hOutputs[ iEvent ].Length; j++ ) {
		hOutputs[ iEvent ].GetArray( j, pOutput );

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

//TODO: respect delay and refire
void CallEvent( PDOutput pOutput, float flOverride = -1.0 ) {
	int iEntity = SDKCall( hFindByName, -1, pOutput.szTargetname, -1, -1, -1, Address_Null );
	while( iEntity != -1 ) {
		#if defined DEBUG
			PrintToServer( "calling event: %s", pOutput.szTargetInput );
		#endif

		if( flOverride == -1.0 )
			SetVariantString( pOutput.szParameter );
		else
			SetVariantFloat( flOverride );

		AcceptEntityInput( iEntity, pOutput.szTargetInput, -1, -1, -1 );

		iEntity = SDKCall( hFindByName, iEntity, pOutput.szTargetname, -1, -1, -1, Address_Null );
	}
}

void SetPoints( int iTeam, int iAmount = 1 ) {
	int iOldAmount;

	if( iTeam == 2 ) {
		iOldAmount = iRedScore;
		iRedScore = iAmount;

		if( iOldAmount == 0 && iRedScore > 0 )
			FireFakeEvent( OUT_ONREDHASPOINTS );

		if( iOldAmount == iPointsToWin && iRedScore < iPointsToWin )
			FireFakeEvent( OUT_ONREDLEAVEMAXPOINTS );

		if( iOldAmount != 0 && iRedScore == 0 )
			FireFakeEvent( OUT_ONREDHITZEROPOINTS );

		if( iRedScore != iOldAmount )
			FireFakeEvent( OUT_ONREDSCORECHANGED, float( iRedScore ) / float( iPointsToWin ) );

		if( iRedScore == iPointsToWin ) {
			FireFakeEvent( OUT_ONREDHITMAXPOINTS );
			SetFinale( 2 );
		}
			
	}
	else {
		iOldAmount = iBlueScore;
		iBlueScore = iAmount;

		if( iOldAmount == 0 && iBlueScore > 0 )
			FireFakeEvent( OUT_ONBLUEHASPOINTS );

		if( iOldAmount == iPointsToWin && iBlueScore < iPointsToWin )
			FireFakeEvent( OUT_ONBLUELEAVEMAXPOINTS );

		if( iOldAmount != 0 && iBlueScore == 0 )
			FireFakeEvent( OUT_ONBLUEHITZEROPOINTS );

		if( iBlueScore != iOldAmount )
			FireFakeEvent( OUT_ONBLUESCORECHANGED, float( iBlueScore ) / float( iPointsToWin ) );

		if( iBlueScore == iPointsToWin ) {
			FireFakeEvent( OUT_ONBLUEHITMAXPOINTS );
			SetFinale( 3 );
		}
	}
}

void SetFinale( int iTeam ) {
	CreateTimer( flFinaleLength, Timer_EndFinale, iTeam, TIMER_FLAG_NO_MAPCHANGE );
}

Action Timer_EndFinale( Handle hTimer, int iTeam ) {
	FireFakeEvent( iTeam == 2 ? OUT_ONREDFINALEPERIODEND : OUT_ONBLUEFINALEPERIODEND );
	SetWinningTeam( iTeam );
	return Plugin_Continue;
}

void CalculateMaxPoints() {
	if( !bAllowMaxScoreUpdating )
		return;

	iPointsToWin = MaxInt( iMinPoints, GetClientCount( true ) * iPointsPerPlayer );
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

		if( iPlayerCarrying[i] > iHighestAmount ) {
			iHighest = i;
			iHighestAmount = iPlayerCarrying[i];
		}
	}

	SetTeamLeader( iHighest, iTeam );
}

void SetTeamLeader( int iPlayer, int iTeam ) {
	if( iTeam == 2 ) {
		if( iRedTeamLeader == iPlayer )
			return;

		iRedTeamLeader = iPlayer;
	}
	else {
		if( iBlueTeamLeader == iPlayer )
			return;

		iBlueTeamLeader = iPlayer;
	}

	int iDispenser = EntRefToEntIndex( iTeam == 2 ? iRedLeaderDispenser : iBlueLeaderDispenser );
	if( iDispenser > 0 ) {
		RemoveEntity( iDispenser );
		if( iTeam == 2 ) {
			iRedLeaderDispenser = INVALID_ENT_REFERENCE;
		}
		else {
			iBlueLeaderDispenser = INVALID_ENT_REFERENCE;
		}
	}

	int iGlow = EntRefToEntIndex( iTeam == 2 ? iRedLeaderGlow : iBlueLeaderGlow );
	if( iGlow > 0 ) {
		int iOld = GetEntPropEnt( iGlow, Prop_Send, "m_hTarget" );
		SetEntProp( iOld, Prop_Send, "m_bGlowEnabled", false );
		RemoveEntity( iGlow );
		if( iTeam == 2 )
			iRedLeaderGlow = INVALID_ENT_REFERENCE;
		else
			iBlueLeaderGlow = INVALID_ENT_REFERENCE;
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
		iRedLeaderDispenser = EntIndexToEntRef( iDispenser );
	}
	else {
		iBlueLeaderDispenser = EntIndexToEntRef( iDispenser );
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
		iRedLeaderGlow = EntIndexToEntRef( iGlow );
	else
		iBlueLeaderGlow = EntIndexToEntRef( iGlow );
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

	vecMins[0] = float( -iHealDistance );
	vecMins[1] = float( -iHealDistance );
	vecMins[2] = float( -iHealDistance );
	vecMaxs[0] = float( iHealDistance );
	vecMaxs[1] = float( iHealDistance );
	vecMaxs[2] = float( iHealDistance );

	SetSize( iTriggerZone, vecMins, vecMaxs );

	return;
}

MRESReturn Detour_GetDispenserRadius( int iThis, DHookReturn hReturn ) {
	int iThisRef = EntIndexToEntRef( iThis );
	int iThisTeam = GetEntProp( iThis, Prop_Send, "m_iTeamNum" );
	if( iThisRef != ( iThisTeam == 2 ? iRedLeaderDispenser : iBlueLeaderDispenser ) )
		return MRES_Ignored;

	hReturn.Value = float( iHealDistance );
	return MRES_Supercede;
}

void CalculateTeamHolding( int iTeam ) {
	int iAmount = 0;
	for( int i = 1; i < MaxClients; i++ ) {
		if( !IsClientInGame( i ) )
			continue;

		if( GetEntProp( i, Prop_Send, "m_iTeamNum" ) != iTeam )
			continue;

		iAmount += iPlayerCarrying[i];
	}

	if( iTeam == 2 )
		iRedTeamHolding = iAmount;
	else
		iBlueTeamHolding = iAmount;
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
	return smCaptureZones.GetArray( szRefString, pdZone, PDZONE_SIZE );
}

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

	int iInRed[MAXPLAYERS];
	int iRedNext = 0;
	int iInBlue[MAXPLAYERS];
	int iBlueNext = 0;

	for( int i = 0; i < pdZone.hPlayersTouching.Length; i++ ) {
		int iPlayer = pdZone.hPlayersTouching.Get( i );
		iPlayer = EntRefToEntIndex( iPlayer );

		if( iPlayer == -1)
			continue;

		int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" );
		if( iTeam == 2 ) {
			bRedInZone = true;
			iInRed[ iRedNext ] = iPlayer;
			iRedNext++;
		}
		else if( iTeam == 3 ) {
			bBlueInZone = true;
			iInBlue[ iBlueNext ] = iPlayer;
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

		if( iPlayerCarrying[ iPlayer ] == 0 || GetGameTime() < flNextCaptureTime[ iPlayer ] )
			continue;


		int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" );
		int iPointTeam = GetEntProp( iIndex, Prop_Data, "m_iTeamNum" );
		if( iPointTeam != 0 && iPointTeam != iTeam )
			continue;

		if( iTeam == 2 ) {
			FireFakeEventZone( pdZone, OUTCAP_REDCAP );
			float flNewPitch = RemapValClamped( float( iRedScore ), 0.0, float( iPointsToWin ), 100.0, 120.0 ); 
			EmitSound( iInRed, iRedNext, "ui/chime_rd_2base_pos.wav", -2, SNDCHAN_AUTO, SNDLEVEL_MINIBIKE, SND_CHANGEPITCH | SND_CHANGEVOL, 0.4, RoundToNearest( flNewPitch ) );
			EmitSound( iInBlue, iBlueNext, "ui/chime_rd_2base_neg.wav", -2, SNDCHAN_AUTO, SNDLEVEL_MINIBIKE, SND_CHANGEPITCH | SND_CHANGEVOL, 0.4, RoundToNearest( flNewPitch ) );
		}
		else if( iTeam == 3 ) {
			FireFakeEventZone( pdZone, OUTCAP_BLUECAP );
			float flNewPitch = RemapValClamped( float( iBlueScore ), 0.0, float( iPointsToWin ), 100.0, 120.0 ); 
			EmitSound( iInBlue, iBlueNext, "ui/chime_rd_2base_pos.wav", -2, SNDCHAN_AUTO, SNDLEVEL_MINIBIKE, SND_CHANGEPITCH | SND_CHANGEVOL, 0.4, RoundToNearest( flNewPitch ) );
			EmitSound( iInRed, iRedNext, "ui/chime_rd_2base_neg.wav", -2, SNDCHAN_AUTO, SNDLEVEL_MINIBIKE, SND_CHANGEPITCH | SND_CHANGEVOL, 0.4, RoundToNearest( flNewPitch ) );
		}

		SetPlayerPoints( iPlayer, iPlayerCarrying[ iPlayer ] - 1 );
		flNextCaptureTime[ iPlayer ] = GetGameTime() + flCapDelay;
	}

	return Plugin_Continue;
}

void SetPlayerPoints( int iPlayer, int iPoints ) {
	int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" );
	iPlayerCarrying[ iPlayer ] = MaxInt( 0, iPoints );

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

	Format( szBuffer, sizeof( szBuffer ), "Red Score: %i/%i\n", iRedScore, iPointsToWin );
	StrCat( szFinal, sizeof( szFinal ), szBuffer );
	Format( szBuffer, sizeof( szBuffer ), "Holding: %i\n", iRedTeamHolding );
	StrCat( szFinal, sizeof( szFinal ), szBuffer );

	SetHudTextParamsEx( 0.23, 0.95, 20.0, REDCOLOR, {255,255,255,0}, 0, 6.0, 0.0, 0.0 );
	ShowSyncHudText( iPlayer, hHudSyncRed, szFinal );
	szFinal = "";

	Format( szBuffer, sizeof( szBuffer ), "Blue Score: %i/%i\n", iBlueScore, iPointsToWin );
	StrCat( szFinal, sizeof( szFinal ), szBuffer );
	Format( szBuffer, sizeof( szBuffer ), "Holding: %i\n", iBlueTeamHolding );
	StrCat( szFinal, sizeof( szFinal ), szBuffer );

	SetHudTextParamsEx( 0.70, 0.95, 20.0, BLUCOLOR, {255,255,255,0}, 0, 6.0, 0.0, 0.0 );
	ShowSyncHudText( iPlayer, hHudSyncBlue, szFinal );
	szFinal = "";

	Format( szBuffer, sizeof( szBuffer ), "Holding: %i\n", iPlayerCarrying[iPlayer] );
	StrCat( szFinal, sizeof( szFinal ), szBuffer );

	if( flCountdownTimer > GetGameTime() ) {
		Format( szBuffer, sizeof( szBuffer ), "       %-.0f", flCountdownTimer - GetGameTime() );
		StrCat( szFinal, sizeof( szFinal ), szBuffer );
	}
	SetHudTextParamsEx( 0.475, 0.91, 20.0, { 255, 255, 255, 1}, {255,255,255,0}, 0, 6.0, 0.0, 0.0 );
	ShowSyncHudText( iPlayer, hHudSyncMiddle, szFinal );	
}

/*
	PICKUPS
*/

Action Event_PlayerDeath( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	if( !bMapIsPD )
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
	int iPointsToDrop = iPlayerCarrying[ iPlayer ];
	if( bAddPoints )
		iPointsToDrop+=iPointsOnPlayerDeath;
	if( iPointsToDrop <= 0 )
		return -1;

	float vecPlayerPos[3];
	GetEntPropVector( iPlayer, Prop_Send, "m_vecOrigin", vecPlayerPos );

	iPlayerCarrying[ iPlayer ] = 0;
	CalculateTeamHolding( GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) );
	CalculateTeamLeader( GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) );
	int iEntity = CreatePickup( iPointsToDrop );
	TeleportEntity( iEntity, vecPlayerPos );

	return iEntity;
}

int CreatePickup( int iAmount ) {
	PDPickup pdPickup;
	pdPickup.iAmount = iAmount;
	pdPickup.flExpireTime = GetGameTime() + float( iFlagResetDelay );

	int iEntity = CreateEntityByName( "prop_dynamic" );
	SetSolidFlags( iEntity, FSOLID_TRIGGER );
	SetEntityModel( iEntity, szPropModelName );
	DispatchSpawn( iEntity );

	static char szRefBuffer[48];
	int iRef = EntIndexToEntRef( iEntity );
	IntToString( iRef, szRefBuffer, sizeof( szRefBuffer ) );
	smPickups.SetArray( szRefBuffer, pdPickup, PDPICKUP_SIZE );

	EmitPDSoundToAll( szPropDropSound, iEntity );

	int iSequence = SDKCall( hLookupSequence, iEntity, "spin" );
	if( iSequence != -1 ) {
		SetVariantString( "spin" );
		AcceptEntityInput( iEntity, "SetAnimation" );
	} else {
		iSequence = SDKCall( hLookupSequence, iEntity, "idle" );
		if( iSequence != -1 ) {
			SetVariantString( "idle" );
			AcceptEntityInput( iEntity, "SetAnimation" );
		}
	}

	CreateTimer( float( iFlagResetDelay ), Timer_PickupThink, iRef, TIMER_FLAG_NO_MAPCHANGE );
	hTouch.HookEntity( Hook_Pre, iEntity, Hook_PickupTouch );

	return iEntity;
}

bool FindPickup( int iRef, PDPickup pdPickup ) {
	static char szRefString[128];
	IntToString( iRef, szRefString, sizeof( szRefString ) );
	return smPickups.GetArray( szRefString, pdPickup, PDPICKUP_SIZE );
}

void RemovePickup( int iPickupReference ) {
	static char szRefString[128];
	IntToString( iPickupReference, szRefString, sizeof( szRefString ) );

	smPickups.Remove( szRefString );

	int iIndex = EntRefToEntIndex( iPickupReference );
	if( iIndex > 0 )
		RemoveEntity( iIndex );
}

Action Timer_PickupThink( Handle hTimer, int iRef ) {
	RemovePickup( iRef );
	return Plugin_Stop;
}

MRESReturn Hook_PickupTouch( int iThis, DHookParam hParams ) {
	int iEntity = hParams.Get( 1 );

	if( !IsValidPlayer( iEntity ) )
		return MRES_Ignored;

	if( GetGameTime() < flPickupCooler[ iEntity ] )
		return MRES_Ignored;

	float vecPos[3];
	GetEntPropVector( iEntity, Prop_Send, "m_vecOrigin", vecPos );
	if( SDKCall( hInRespawnRoom, iEntity, vecPos ) )
		return MRES_Ignored;

	int iTeam = GetEntProp( iEntity, Prop_Send, "m_iTeamNum" );
	PDPickup pdPickup;

	int iRef = EntIndexToEntRef( iThis );
	if( !FindPickup( iRef, pdPickup ) ) {
		PrintToServer("could not find data for pickup, this should not happen");
		return MRES_Ignored;
	}

	EmitPDSoundToAll( szPropPickupSound, iEntity );
	iPlayerCarrying[ iEntity ] += pdPickup.iAmount;
	CalculateTeamHolding( iTeam );
	CalculateTeamLeader( iTeam );

	RemovePickup( iRef );

	return MRES_Handled;
}

MRESReturn Detour_DropFlag( int iThis ) {
	if( iPlayerCarrying[ iThis ] < 1 )
		return MRES_Handled;

	DropPickup( iThis, false );
	flPickupCooler[ iThis ] = GetGameTime() + 2.0;

	return MRES_Handled;
}

MRESReturn Detour_RespawnTouch( int iThis, DHookParam hParams ) {
	int iEntity = hParams.Get( 1 );

	if( !IsValidPlayer( iEntity ) )
		return MRES_Ignored;

	if( iPlayerCarrying[ iEntity ] <= 0 )
		return MRES_Ignored;

	DropPickup( iEntity, false );
	flPickupCooler[ iEntity ] = GetGameTime() + 1.0;

	return MRES_Handled;
}

Action Command_Test( int iClient, int iArgs ) {
	if(iArgs < 1) return Plugin_Handled;

	int iMode = GetCmdArgInt( 1 );
	switch( iMode ) {
	case 0: {
		int iEntity = CreatePickup( 1 );
		float vecPos[3];
		GetEntPropVector( iClient, Prop_Send, "m_vecOrigin", vecPos );
		TeleportEntity( iEntity, vecPos );
		return Plugin_Handled;
	}
	}
	
	return Plugin_Handled;
}

void SetWinningTeam( int iTeam ) {
	SDKCall( hSetWinningTeam, iTeam, 13, true, false, false, false );
}

void EmitPDSoundToAll( char[] szString, int iSource ) {
	if( StrContains( szString, ".wav" ) || StrContains( szString, ".mp3" ) )
		EmitSoundToAll( szString, iSource );
	else
		EmitGameSoundToAll( szString, iSource );
}