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

DynamicDetour hParseEntity;
DynamicHook hAcceptInput;
Handle hExtractValue;
Handle hFindByName;

//func_capturezone
//these already exist but need additional functionality

//stores PDCapZones using the object's entity reference for lookup
StringMap smCaptureZones;

enum struct PDCapZone {
	float flCaptureDelay;
	float flCaptureDelayOffset; //this needs to be clamped
	bool bCanBlock;

	ArrayList hCapOutputs[2]; //array of PDOutputs
}

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
int iRedTeamLeader = -1;
int iBlueTeamLeader = -1;

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

enum {
	OUTCAP_REDCAP = 0,
	OUTCAP_BLUECAP,

	OUTCAP_LAST,
}

static char szOutputCapNames[][] = {
	"OnCapTeam1_PD",
	"OnCapTeam2_PD"
};

//array of all the outputs that the logic ent can fire
ArrayList hOutputs[OUT_LAST];

#define OUTPUT_CELLSIZE sizeof( PDOutput )

//bool MapEntity_ExtractValue( const char *pEntData, const char *keyName, char Value[MAPKEY_MAXLENGTH] )
public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	hParseEntity = DynamicDetour.FromConf( hGameConf, "MapEntity_ParseEntity" );
	hParseEntity.Enable( Hook_Pre, Detour_ParseEntity );

	hAcceptInput = DynamicHook.FromConf( hGameConf, "CBaseEntity::AcceptInput" );

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

	delete hGameConf;
}

/*
	MAP DATA PARSING
*/

MRESReturn Detour_ParseEntity( DHookReturn hReturn, DHookParam hParams ) {
	static char szEntData[2048];
	static char szKeyBuffer[2048];

	hParams.GetString( 2, szEntData, sizeof( szEntData ) );
	
	if( !SDKCall( hExtractValue, szEntData, "classname", szKeyBuffer ) )
		return MRES_Handled;
	//TODO: read in capture areas
	if( !StrEqual( szKeyBuffer, "tf_logic_player_destruction" ) )
		return MRES_Handled;

	for( int i = 0; i < OUT_LAST; i++) {
		hOutputs[i] = new ArrayList( OUTPUT_CELLSIZE );
	}

	RequestFrame( SpawnLogicDummy );

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
			if( StrEqual( szOutputNames[i], szKeyBuffer ) )	TryPushNextOutput( szEntData, sizeof( szEntData ), i );
		}

		iIndex = GetNextKey( szEntData, sizeof( szEntData ), szKeyBuffer, sizeof( szKeyBuffer ) );
	}
	return MRES_Handled;
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

void TryPushNextOutput( char[] szString, int iSize, int iArray ) {
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

	hOutputs[ iArray ].PushArray( pOutput );
}

void SpawnLogicDummy() {
	if( EntRefToEntIndex( g_iLogicDummy ) != -1 ) {
		RemoveEntity( g_iLogicDummy );
	}

	g_iLogicDummy = EntIndexToEntRef( CreateEntityByName("info_target") );
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
		PrintToServer( "newtimer: %s", szString);
		flCountdownTimer = StringToFloat( szString );
	}
	//if( StrEqual( szInputName, "SetFlagResetDelay" ) )
	if( StrEqual( szInputName, "SetPointsOnPlayerDeath" ) ) {
		Address aStringTPointer = LoadFromAddress( hParams.GetAddress( 4 ), NumberType_Int32 );
		LoadStringFromAddress( aStringTPointer, szString, sizeof( szString ) );
		PrintToServer( "newpointsperdeath: %s", szString);
		iPointsOnPlayerDeath = StringToInt( szString );
	}


	return MRES_Handled;
}

void SetPoints( int iTeam, int iAmount = 1 ) {
	int iOldAmount;

	if( iTeam == 2 ) {
		iOldAmount = iRedScore;
		iRedScore = iAmount;

		if( iOldAmount == 0 && iRedScore > 0 )
			FireFakeEventVoid( OUT_ONREDHASPOINTS );

		if( iOldAmount == iPointsToWin && iRedScore < iPointsToWin )
			FireFakeEventVoid( OUT_ONREDLEAVEMAXPOINTS );

		if( iOldAmount != 0 && iRedScore == 0 )
			FireFakeEventVoid( OUT_ONREDHITZEROPOINTS );

		if( iRedScore != iOldAmount )
			FireFakeEventFloat( OUT_ONREDSCORECHANGED, float( iRedScore ) / float( iPointsToWin ) );

		if( iRedScore == iPointsToWin )
			FireFakeEventVoid( OUT_ONREDHITMAXPOINTS );
	}
	else {
		iOldAmount = iBlueScore;
		iBlueScore = iAmount;

		if( iOldAmount == 0 && iBlueScore > 0 )
			FireFakeEventVoid( OUT_ONBLUEHASPOINTS );

		if( iOldAmount == iPointsToWin && iBlueScore < iPointsToWin )
			FireFakeEventVoid( OUT_ONBLUELEAVEMAXPOINTS );

		if( iOldAmount != 0 && iBlueScore == 0 )
			FireFakeEventVoid( OUT_ONBLUEHITZEROPOINTS );

		if( iBlueScore != iOldAmount )
			FireFakeEventFloat( OUT_ONBLUESCORECHANGED, float( iBlueScore ) / float( iPointsToWin ) );

		if( iBlueScore == iPointsToWin )
			FireFakeEventVoid( OUT_ONBLUEHITMAXPOINTS );
	}
}

void CalculateMaxPoints() {
	iPointsToWin = MaxInt( iMinPoints, GetClientCount( true ) * iPointsPerPlayer );
}

void CalculateTeamLeader( int iTeam ) {
	int iHighest = -1;
	int iHighestAmount = 0;
	for( int i = 1; i < MAXPLAYERS; i++ ) {
		if( !IsClientInGame( i ) )
			return;

		if( GetEntProp( i, Prop_Send, "m_iTeamNum" ) != iTeam )
			return;

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

void FireFakeEventVoid( int iEvent ) {
	PDOutput pOutput;
	for( int j = 0; j < hOutputs[ iEvent ].Length; j++ ) {
		hOutputs[ iEvent ].GetArray( j, pOutput );
		CallEvent( pOutput );
	}
}

//TODO: respect parameter delay and refire
void CallEvent( PDOutput pOutput, float flInput = -1.0 ) {
	int iEntity = SDKCall( hFindByName, -1, pOutput.szTargetname, -1, -1, -1, Address_Null );
	while( iEntity != -1 ) {
		if( flInput != -1.0 )
			SetVariantFloat( flInput );

		AcceptEntityInput( iEntity, pOutput.szTargetInput, -1, -1, -1 );

		iEntity = SDKCall( hFindByName, iEntity, pOutput.szTargetname, -1, -1, -1, Address_Null );
	}
}

void FireFakeEventFloat( int iEvent, float flValue ) {
	PDOutput pOutput;
	for( int j = 0; j < hOutputs[ iEvent ].Length; j++ ) {
		hOutputs[ iEvent ].GetArray( j, pOutput );
		CallEvent( pOutput, flValue );
	}
}