#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <kocwtools>
#include <dhooks>

public Plugin myinfo = {
	name = "Player Destruction Classic",
	author = "Noclue",
	description = "Wrapper to allow running PD maps in TF2C",
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

//func_capturezone
//these already exist but need additional functionality

//stores PDCapZones using the object's entity reference for lookup
StringMap smCaptureZones;

#define PDZONE_SIZE 5

enum struct PDCapZone {
	float flCaptureDelay;
	float flCaptureDelayOffset; //this needs to be clamped
	bool bCanBlock;

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

int iPlayerCarrying[MAXPLAYERS+1] = { 100, ... };
float flNextCaptureTime[MAXPLAYERS+1];
int iRedTeamLeader = -1;
int iBlueTeamLeader = -1;

int iRedTeamHolding = 0;
int iBlueTeamHolding = 0;

int iPointsOnPlayerDeath = 1;

bool bAllowMaxScoreUpdating = true;

//TODO: convert to use targetname instead of ref
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

#define OUTPUT_CELLSIZE sizeof( PDOutput )
#define HUD_UPDATEINTERVAL 0.1

DynamicDetour hParseEntity;
DynamicHook hAcceptInput;
DynamicHook hTouch;
Handle hExtractValue;
Handle hFindByName;

Handle hHudSyncRed;
Handle hHudSyncBlue;
Handle hHudSyncMiddle;

//bool MapEntity_ExtractValue( const char *pEntData, const char *keyName, char Value[MAPKEY_MAXLENGTH] )
public void OnPluginStart() {
	hHudSyncRed = CreateHudSynchronizer();
	hHudSyncBlue = CreateHudSynchronizer();
	hHudSyncMiddle = CreateHudSynchronizer();

	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	hParseEntity = DynamicDetour.FromConf( hGameConf, "MapEntity_ParseEntity" );
	hParseEntity.Enable( Hook_Pre, Detour_ParseEntity );
	hParseEntity.Enable( Hook_Post, Detour_ParseEntityPost );

	hAcceptInput = DynamicHook.FromConf( hGameConf, "CBaseEntity::AcceptInput" );
	hTouch = DynamicHook.FromConf( hGameConf, "CBaseEntity::Touch" );

	StartPrepSDKCall( SDKCall_Static );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "MapEntity_ExtractValue" );
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	hExtractValue = EndPrepSDKCall();

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

	HookEvent( "player_spawn", Hook_PlayerSpawned );
	HookEvent( "player_disconnect", Hook_PlayerDisconnected );

	delete hGameConf;
}

bool bMapIsPD;
public void OnMapInit( const char[] szMapName ) {
	if( StrContains( szMapName, "pd_", true ) == 0 )
		bMapIsPD = true;
	else
		bMapIsPD = false;
}

public void OnMapStart() {
	if( !bMapIsPD )
		return;

	CreateTimer( HUD_UPDATEINTERVAL, Timer_HudThink, 0, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT );
	RequestFrame( SpawnLogicDummy );

	for( int i = 0; i < OUT_LAST; i++) {
		hOutputs[i] = new ArrayList( OUTPUT_CELLSIZE );
	}

	smCaptureZones = new StringMap();

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
	//TODO: read in capture areas
	if( StrEqual( szKeyBuffer, "tf_logic_player_destruction" ) )
		ParseLogicEntity( szEntData );
	/*else if( StrEqual( szKeyBuffer, "func_capturezone" ) )
		ParseCaptureZone( szEntData );*/

	return MRES_Handled;
}

MRESReturn Detour_ParseEntityPost( DHookReturn hReturn, DHookParam hParams ) {
	if( !bMapIsPD )
		return MRES_Ignored;

	static char szEntData[2048];
	static char szKeyBuffer[2048];

	Address aEntity = hParams.GetAddress( 1 );
	aEntity = LoadFromAddress( aEntity, NumberType_Int32 );
	//PrintToServer("testing parser: %i", aEntity);
	if( aEntity == Address_Null )
		return MRES_Handled;
	
	int iEntity = GetEntityFromAddress( aEntity );

	if( iEntity == -1 )
		return MRES_Handled;

	GetEntityClassname( iEntity, szKeyBuffer, 2048 );
	//PrintToServer("entname: %s", szKeyBuffer);
	
	if( StrEqual( szKeyBuffer, "func_capturezone" ) ) {
		hParams.GetString( 2, szEntData, sizeof( szEntData ) );
		ParseCaptureZone( iEntity, szEntData );
	}

	return MRES_Handled;
}

void ParseLogicEntity( char szEntData[2048] ) {
	static char szKeyBuffer[2048];

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
	iBlueTeamHolding = 0;
	iBlueScore = 0;

	iRedTeamLeader = -1;
	iBlueTeamLeader = -1;

	iPointsOnPlayerDeath = 1;
	bAllowMaxScoreUpdating = true;

	flCountdownTimer = 0.0;

	for( int i = 0; i < MAXPLAYERS+1; i++ ) {
		//iPlayerCarrying[i] = 0;
		flNextCaptureTime[i] = 0.0;
	}

	CalculateMaxPoints();

	if( !StrEqual( szPropModelName, "" ) )
		PrecacheModel( szPropModelName );
	if( !StrEqual( szPropDropSound, "" ) )
		PrecacheSound( szPropDropSound );
	if( !StrEqual( szPropPickupSound, "" ) )
		PrecacheModel( szPropPickupSound );
}

void ParseCaptureZone( int iEntity, char szEntData[2048] ) {
	static char szKeyBuffer[2048];

	PDCapZone pdZone;

	pdZone.hCapOutputs[0] = new ArrayList( sizeof( PDOutput ) );
	pdZone.hCapOutputs[1] = new ArrayList( sizeof( PDOutput ) );

	int iIndex = GetNextKey( szEntData, sizeof( szEntData ), szKeyBuffer, sizeof( szKeyBuffer ) );
	PrintToServer("parsing capture zone");
	while( iIndex != -1 ) {
		if( StrEqual( szKeyBuffer, "}" ) )
			break;

		//lord please forgive me
		if( StrEqual( szKeyBuffer, "capture_delay" ) )		TryPushNextFloat( szEntData, sizeof( szEntData ), pdZone.flCaptureDelay );
		if( StrEqual( szKeyBuffer, "capture_delay_offset" ) )	TryPushNextFloat( szEntData, sizeof( szEntData ), pdZone.flCaptureDelayOffset );
		if( StrEqual( szKeyBuffer, "shouldBlock" ) )		TryPushNextInt( szEntData, sizeof( szEntData ), pdZone.bCanBlock );

		for( int i = 0; i < OUTCAP_LAST; i++) {
			if( StrEqual( szOutputCapNames[i], szKeyBuffer ) )	TryPushNextOutput( szEntData, sizeof( szEntData ), pdZone.hCapOutputs[i] );
		}

		iIndex = GetNextKey( szEntData, sizeof( szEntData ), szKeyBuffer, sizeof( szKeyBuffer ) );
	}

	int iRef = EntIndexToEntRef( iEntity );
	//hTouch.HookEntity( Hook_Pre, iEntity, Hook_CaptureTouch );
	IntToString( iRef, szKeyBuffer, sizeof( szKeyBuffer ) );
	smCaptureZones.SetArray( szKeyBuffer, pdZone, PDZONE_SIZE );

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

	PrintToServer("KEYPUSHINT: %s", szBuffer);
}

void TryPushNextFloat( char[] szString, int iSize, float &flValue ) {
	static char szBuffer[256];
	int iIndex = GetNextKey( szString, iSize, szBuffer, sizeof( szBuffer ) );

	if( iIndex == -1 || StrEqual( szBuffer, "}" ) )
		return;

	flValue = StringToFloat( szBuffer );

	PrintToServer("KEYPUSHFLOAT: %s", szBuffer);
}

void TryPushNextOutput( char[] szString, int iSize, ArrayList &hCapzone ) {
	static char szBuffer[256];
	int iIndex = GetNextKey( szString, iSize, szBuffer, sizeof( szBuffer ) );

	if( iIndex == -1 || StrEqual( szBuffer, "}" ) )
		return;

	PDOutput pOutput;
	static char szBuffer2[5][256]; //targetname, input, parameter, delay, refires 

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
	PrintToServer("%i, %i", g_iLogicDummy, EntRefToEntIndex( g_iLogicDummy ) );
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

Action Hook_PlayerSpawned( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	CalculateMaxPoints();
	return Plugin_Continue;
}
Action Hook_PlayerDisconnected( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	CalculateMaxPoints();
	return Plugin_Continue;
}

public void OnGameFrame() {
	if( flCountdownTimer != 0.0 && GetGameTime() > flCountdownTimer )
		FireFakeEvent( OUT_ONCOUNTDOWNTIMEREXPIRED );
}

MRESReturn Hook_AcceptInput( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	static char szInputName[256];
	hParams.GetString( 1, szInputName, sizeof( szInputName ) );
	PrintToServer("received event: %s", szInputName);

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
		PrintToServer( "newtimer: %s", szString );
		flCountdownTimer = GetGameTime() + StringToFloat( szString );
	}
	if( StrEqual( szInputName, "SetFlagResetDelay" ) ) {
		Address aStringTPointer = LoadFromAddress( hParams.GetAddress( 4 ), NumberType_Int32 );
		LoadStringFromAddress( aStringTPointer, szString, sizeof( szString ) );
		PrintToServer( "newpointsperdeath: %s", szString );
		iFlagResetDelay = StringToInt( szString );
	}
	if( StrEqual( szInputName, "SetPointsOnPlayerDeath" ) ) {
		Address aStringTPointer = LoadFromAddress( hParams.GetAddress( 4 ), NumberType_Int32 );
		LoadStringFromAddress( aStringTPointer, szString, sizeof( szString ) );
		PrintToServer( "newpointsperdeath: %s", szString );
		iPointsOnPlayerDeath = StringToInt( szString );
	}


	return MRES_Handled;
}

void FireFakeEvent( int iEvent, float flOverride = -1.0 ) {
	PDOutput pOutput;
	for( int j = 0; j < hOutputs[ iEvent ].Length; j++ ) {
		hOutputs[ iEvent ].GetArray( j, pOutput );

		//PrintToServer( "%f", pOutput.flDelay );
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

		//PrintToServer( "%f", pOutput.flDelay );
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
		PrintToServer("firing event: %s", pOutput.szTargetInput );

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

		if( iRedScore == iPointsToWin )
			FireFakeEvent( OUT_ONREDHITMAXPOINTS );
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

		if( iBlueScore == iPointsToWin )
			FireFakeEvent( OUT_ONBLUEHITMAXPOINTS );
	}
}

void CalculateMaxPoints() {
	if( !bAllowMaxScoreUpdating )
		return;

	//iPointsToWin = 100;
	iPointsToWin = MaxInt( iMinPoints, GetClientCount( true ) * iPointsPerPlayer );
}

void CalculateTeamLeader( int iTeam ) {
	int iHighest = -1;
	int iHighestAmount = 0;
	for( int i = 1; i < MAXPLAYERS; i++ ) {
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

	if( iHighest == -1 )
		return;

	if( iTeam == 2 )
		iRedTeamLeader = iHighest;
	else
		iBlueTeamLeader = iHighest;
}

//manually read out the contents of m_hTouchingEntities
Action Timer_PDZoneThink( Handle hTimer, int iData ) {
	PDCapZone pdZone;
	static char szRefString[128];

	IntToString( iData, szRefString, sizeof( szRefString ) );
	smCaptureZones.GetArray( szRefString, pdZone, PDZONE_SIZE );

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

	int iVectorSize = LoadFromEntity( iIndex, 1148 );
	for( int i = 0; i < iVectorSize; i++ ) {
		Address aPointer = LoadFromEntity( iIndex, 1136 + (i * 4) );
		int iPointer = LoadEntityHandleFromAddress( aPointer );

		if( !IsValidPlayer( iPointer ) )
			continue;

		int iTeam = GetEntProp( iPointer, Prop_Send, "m_iTeamNum" );
		if( iTeam == 2 ) {
			bRedInZone = true;
			iInRed[iRedNext] = iPointer;
			iRedNext++;
		}
		else if( iTeam == 3 ) {
			bBlueInZone = true;
			iInBlue[iBlueNext] = iPointer;
			iBlueNext++;
		}
	}

	if( pdZone.bCanBlock && bRedInZone && bBlueInZone )
		return Plugin_Continue;

	float flCapDelay = pdZone.flCaptureDelay - ( pdZone.flCaptureDelayOffset * GetClientCount( true ) );
	for( int i = 0; i < iVectorSize; i++ ) {
		Address aPointer = LoadFromEntity( iIndex, 1136 + (i * 4) );
		int iPointer = LoadEntityHandleFromAddress( aPointer );

		if( !IsValidPlayer( iPointer ) )
			continue;

		if( iPlayerCarrying[ iPointer ] == 0 || GetGameTime() < flNextCaptureTime[ iPointer ] )
			continue;

		int iTeam = GetEntProp( iPointer, Prop_Send, "m_iTeamNum" );
		int iPointTeam = GetEntProp( iIndex, Prop_Data, "m_iTeamNum" );
		if( iPointTeam != 0 && iPointTeam != iTeam )
			continue;

		PrintToServer("%i %i", iTeam, iPointTeam );

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

		iPlayerCarrying[ iPointer ]--;
		flNextCaptureTime[ iPointer ] = GetGameTime() + flCapDelay;

		
	}

	return Plugin_Continue;
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

	SetHudTextParamsEx( 0.23, 0.95, 20.0, {184, 56, 59, 1}, {255,255,255,0}, 0, 6.0, 0.0, 0.0 );
	ShowSyncHudText( iPlayer, hHudSyncRed, szFinal );
	szFinal = "";

	Format( szBuffer, sizeof( szBuffer ), "Blue Score: %i/%i\n", iBlueScore, iPointsToWin );
	StrCat( szFinal, sizeof( szFinal ), szBuffer );
	Format( szBuffer, sizeof( szBuffer ), "Holding: %i\n", iBlueTeamHolding );
	StrCat( szFinal, sizeof( szFinal ), szBuffer );

	SetHudTextParamsEx( 0.70, 0.95, 20.0, { 88, 133, 162, 1}, {255,255,255,0}, 0, 6.0, 0.0, 0.0 );
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