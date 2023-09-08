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
	description = "Allows loading of PD maps in TF2C",
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

DynamicDetour hParseEntity;
Handle hExtractValue;
Handle hFindByName;

//tf_logic_player_destuction properties
//there should only ever be one of these so nothing complicated has to be done
char szPropModelName[128];
char szPropDropSound[128];
char szPropPickupSound[128];

char szTargetName[128];

float flBlueRespawnTime;
float flRedRespawnTime;

int iMinPoints;
int iPointsPerPlayer;

float flFinaleLength;

int iFlagResetDelay;
int iHealDistance;

enum struct PDOutput {
	int iTargetRef;
	char szTargetInput[64];
	char szParameter[64];
	float flDelay;
	int iRefires;
}

//outputs
ArrayList hOnBlueHitMaxPoints;
ArrayList hOnRedHitMaxPoints;

ArrayList hOnBlueLeaveMaxPoints;
ArrayList hOnRedLeaveMaxPoints;

ArrayList hOnBlueHitZeroPoints;
ArrayList hOnRedHitZeroPoints;

ArrayList hOnBlueHasPoints;
ArrayList hOnRedHasPoints;

ArrayList hOnBlueFinalePeriodEnd;
ArrayList hOnRedFinalePeriodEnd;

ArrayList hOnBlueFirstFlagStolen;
ArrayList hOnRedFirstFlagStolen;

ArrayList hOnBlueFlagStolen;
ArrayList hOnRedFlagStolen;

ArrayList hOnBlueLastFlagReturned;
ArrayList hOnRedLastFlagReturned;

ArrayList hOnBlueScoreChanged;
ArrayList hOnRedScoreChanged;

ArrayList hOnCountdownTimerExpired;

#define OUTPUT_CELLSIZE sizeof( PDOutput )

//bool MapEntity_ExtractValue( const char *pEntData, const char *keyName, char Value[MAPKEY_MAXLENGTH] )
public void OnPluginStart() {
	static char szTest[32] = "test";
	StrReduce( szTest, sizeof( szTest ), 2 );
	//PrintToServer( szTest );

	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	hParseEntity = DynamicDetour.FromConf( hGameConf, "MapEntity_ParseEntity" );
	hParseEntity.Enable( Hook_Pre, Detour_ParseEntity );

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

	hOnBlueHitMaxPoints = new ArrayList( OUTPUT_CELLSIZE, 0 );
	hOnRedHitMaxPoints  = new ArrayList( OUTPUT_CELLSIZE, 0 );

	hOnBlueLeaveMaxPoints = new ArrayList( OUTPUT_CELLSIZE, 0 );
	hOnRedLeaveMaxPoints = new ArrayList( OUTPUT_CELLSIZE, 0 );

	hOnBlueHitZeroPoints = new ArrayList( OUTPUT_CELLSIZE, 0 );
	hOnRedHitZeroPoints = new ArrayList( OUTPUT_CELLSIZE, 0 );

	hOnBlueHasPoints = new ArrayList( OUTPUT_CELLSIZE, 0 );
	hOnRedHasPoints = new ArrayList( OUTPUT_CELLSIZE, 0 );

	hOnBlueFinalePeriodEnd = new ArrayList( OUTPUT_CELLSIZE, 0 );
	hOnRedFinalePeriodEnd = new ArrayList( OUTPUT_CELLSIZE, 0 );

	hOnBlueFirstFlagStolen = new ArrayList( OUTPUT_CELLSIZE, 0 );
	hOnRedFirstFlagStolen = new ArrayList( OUTPUT_CELLSIZE, 0 );

	hOnBlueFlagStolen = new ArrayList( OUTPUT_CELLSIZE, 0 );
	hOnRedFlagStolen = new ArrayList( OUTPUT_CELLSIZE, 0 );

	hOnBlueLastFlagReturned = new ArrayList( OUTPUT_CELLSIZE, 0 );
	hOnRedLastFlagReturned = new ArrayList( OUTPUT_CELLSIZE, 0 );

	hOnBlueScoreChanged = new ArrayList( OUTPUT_CELLSIZE, 0 );
	hOnRedScoreChanged = new ArrayList( OUTPUT_CELLSIZE, 0 );

	hOnCountdownTimerExpired = new ArrayList( OUTPUT_CELLSIZE, 0 );
}

MRESReturn Detour_ParseEntity( DHookReturn hReturn, DHookParam hParams ) {
	RequestFrame(TestFunc);
	static char szEntData[2048];
	static char szKeyBuffer[2048];

	hParams.GetString( 2, szEntData, sizeof( szEntData ) );
	//StripQuotes( szEntData );

	if( !SDKCall( hExtractValue, szEntData, "classname", szKeyBuffer ) )
		return MRES_Handled;
	if( !StrEqual( szKeyBuffer, "tf_logic_player_destruction" ) )
		return MRES_Handled;

	PrintToServer("test1");

	int iIndex = 0;
	int iStrLen = strlen( szEntData );
	do {
		iIndex = GetNextKey( szEntData, sizeof( szEntData ), szKeyBuffer, sizeof( szKeyBuffer ) );

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

		//lord please forgive me
		if( StrEqual( szKeyBuffer, "OnBlueHitMaxPoints" ) )
			TryPushNextOutput( szEntData, sizeof( szEntData ), hOnBlueHitMaxPoints );
		/*if( StrEqual( szKeyBuffer, "OnBlueFinalePeriodEnd" ) )
			TryPushNextOutput( szEntData, sizeof( szEntData ), hOnBlueFinalePeriodEnd );*/
		/*if( StrEqual( szKeyBuffer, "OnBlueHitMaxPoints" ) )
			TryPushNextOutput( szEntData, sizeof( szEntData ), hOnBlueHitMaxPoints );
		if( StrEqual( szKeyBuffer, "OnBlueHitMaxPoints" ) )
			TryPushNextOutput( szEntData, sizeof( szEntData ), hOnBlueHitMaxPoints );
		if( StrEqual( szKeyBuffer, "OnBlueHitMaxPoints" ) )
			TryPushNextOutput( szEntData, sizeof( szEntData ), hOnBlueHitMaxPoints );
		if( StrEqual( szKeyBuffer, "OnBlueHitMaxPoints" ) )
			TryPushNextOutput( szEntData, sizeof( szEntData ), hOnBlueHitMaxPoints );*/

		PrintToServer("KEY: %s", szKeyBuffer);

		if( iIndex == -1 || StrEqual( szKeyBuffer, "}" ) )
			break;
	}
	while( iIndex < iStrLen );

	return MRES_Handled;
}

void TestFunc() {
	int iEntity = SDKCall( hFindByName, -1, "ufo_drunk_compare_*", -1, -1, -1, Address_Null );
	while( iEntity != -1 ) {
		static char szTest[64];
		GetEntPropString( iEntity, Prop_Data, "m_iName", szTest, 64 );
		PrintToServer("%i %s", EntRefToEntIndex(iEntity), szTest);
		iEntity = SDKCall( hFindByName, iEntity, "ufo_drunk_compare_*", -1, -1, -1, Address_Null );
		//pOutput.iTargetRef = EntIndexToEntRef( iEntity );
		
	}
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

	PrintToServer("KEYPUSHINT: %s", szBuffer);
}

void TryPushNextOutput( char[] szString, int iSize, ArrayList hList ) {
	static char szBuffer[256];
	int iIndex = GetNextKey( szString, iSize, szBuffer, sizeof( szBuffer ) );

	if( iIndex == -1 || StrEqual( szBuffer, "}" ) )
		return;

	PDOutput pOutput;
	
	static char szBuffer2[5][256]; //targetname, input, parameter, delay, refires 
	ExplodeString( szBuffer, ",", szBuffer2, 5, 256 );

	PrintToServer( "0: %s", szBuffer2[0] );
	PrintToServer( "1: %s", szBuffer2[1] );
	PrintToServer( "2: %s", szBuffer2[2] );
	PrintToServer( "3: %s", szBuffer2[3] );
	PrintToServer( "4: %s", szBuffer2[4] );

	int iEntity = SDKCall( hFindByName, -1, szBuffer2[0], -1, -1, -1, Address_Null );
	while( iEntity != -1 ) {
		PrintToServer("%i", iEntity);
		iEntity = SDKCall( hFindByName, iEntity, szBuffer2[0], -1, -1, -1, Address_Null );
		//pOutput.iTargetRef = EntIndexToEntRef( iEntity );
		
	}

	strcopy( pOutput.szTargetInput, sizeof( pOutput.szTargetInput ), szBuffer2[1] );
	strcopy( pOutput.szParameter, sizeof( pOutput.szParameter ), szBuffer2[2] );

	pOutput.flDelay = StringToFloat( szBuffer2[3] );
	pOutput.iRefires = StringToInt( szBuffer2[4] );
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