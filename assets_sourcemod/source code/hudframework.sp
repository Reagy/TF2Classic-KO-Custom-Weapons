#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <tf2c>
#include <kocwtools>

public Plugin myinfo =
{
	name = "HUD Framework",
	author = "Noclue",
	description = "HUD Framework for Custom Weapons.",
	version = "1.2",
	url = "no"
}

ArrayList hResources[MAXPLAYERS+1];
Handle hHudSync;

enum {
	RTF_PERCENTAGE = 1 << 1,	//display value as a percentage
	RTF_DING = 1 << 2,		//play sound when fully charged
	RTF_RECHARGES = 1 << 3,
	RTF_NOOVERWRITE = 1 << 4,	//do not overwrite existing tracker
	RTF_CLEARONSPAWN = 1 << 5,	//reset on respawning
}

enum struct ResourceTracker {
	int iFlags;
	char sName[32];
	float flValue;
	float flMax;
	float flRechargeRate;

	bool HasFlags( int iCheckFlags ) {
		return ( this.iFlags & iCheckFlags ) == iCheckFlags;
	}
}
#define TRACKERMAXSIZE sizeof(ResourceTracker)
#define UPDATEINTERVAL 0.2

public void OnPluginStart() {
	hHudSync = CreateHudSynchronizer();

	HookEvent( "player_spawn", Event_Spawned );

	for(int i = 0; i < sizeof(hResources); i++) {
		if( hResources[i] )
			hResources[i].Clear();
			
		hResources[i] = new ArrayList(TRACKERMAXSIZE);
	}

#if defined DEBUG
	RegConsoleCmd("sm_hf_test", Command_Test, "test");
#endif
}

void Event_Spawned( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	ResourceTracker hTracker;
	for( int i = 0; i < hResources[ iPlayer ].Length; i++ ) {
		hResources[ iPlayer ].GetArray( i, hTracker );
		if( hTracker.iFlags & RTF_CLEARONSPAWN ) {
			hTracker.flValue = 0.0;
			hResources[ iPlayer ].SetArray( i, hTracker );
		}
			
	}
}

public void OnMapStart() {
	CreateTimer( UPDATEINTERVAL, Timer_TrackerThink, 0, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT );

	for(int i = 0; i < sizeof(hResources); i++) {
		if( hResources[i] )
			hResources[i].Clear();

		hResources[i] = new ArrayList(TRACKERMAXSIZE);
	}
}

public APLRes AskPluginLoad2( Handle hMyself, bool bLate, char[] sError, int iErrorMax ) {
	CreateNative( "Tracker_Create", Native_TrackerCreate );
	CreateNative( "Tracker_Remove", Native_TrackerRemove );
	CreateNative( "Tracker_GetValue", Native_TrackerGetValue );
	CreateNative( "Tracker_SetValue", Native_TrackerSetValue );

	return APLRes_Success;
}

public void OnClientDisconnect( int iClient ) {
	if( iClient >= 0 && iClient < sizeof( hResources ) )
		hResources[iClient].Clear();
}

Action Timer_TrackerThink( Handle hTimer ) {
	for ( int i = 1; i <= MaxClients; i++ ) {
		if ( IsClientInGame( i ) ) {
			for( int j = 0; j < hResources[i].Length; j++ ) {
				Tracker_Recharge( i, j );
			}
			if( !IsFakeClient( i ) ) 
				Tracker_Display( i );
		}
	}
	return Plugin_Continue;
}

//Tracker_Create
public any Native_TrackerCreate( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell( 1 );
	static char sName[32]; GetNativeString( 2, sName, 32 );
	float flStartAt = GetNativeCell( 3 );
	float flRechargeTime = GetNativeCell( 4 );
	int iFlags = GetNativeCell( 5 );

	Tracker_Create( iPlayer, sName, flStartAt, flRechargeTime, iFlags );

	return 0;
}
void Tracker_Create( int iPlayer, const char sName[32], float flStartAt, float flRechargeTime = 0.0, int iFlags = 0 ) {
	ResourceTracker hTracker;

	hTracker.iFlags = iFlags;
	hTracker.sName = sName;
	hTracker.flValue = flStartAt;

	if( flRechargeTime == 0.0 ) hTracker.flRechargeRate = 0.0;
	else hTracker.flRechargeRate = flRechargeTime * UPDATEINTERVAL;

	int iIndex = Tracker_Find( iPlayer, sName );
	if( iIndex == -1 )
		hResources[iPlayer].PushArray( hTracker );
	else if( !( iFlags & RTF_NOOVERWRITE ) )
		hResources[iPlayer].SetArray( iIndex, hTracker );
	
}

//Tracker_Remove
public any Native_TrackerRemove( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell( 1 );
	static char sName[32]; GetNativeString( 2, sName, 32 );

	Tracker_Remove( iPlayer, sName );

	return 0;
}
void Tracker_Remove( int iPlayer, const char sName[32] ) {
	int iLoc = Tracker_Find( iPlayer, sName );
	if( iLoc == -1 ) return;

	hResources[iPlayer].Erase( iLoc );
}

//Tracker_GetValue
public any Native_TrackerGetValue( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell( 1 );
	static char sName[32]; GetNativeString( 2, sName, 32 );

	return Tracker_GetValue( iPlayer, sName );
}
float Tracker_GetValue( int iPlayer, const char sName[32] ) {
	int iLoc = Tracker_Find( iPlayer, sName );
	if( iLoc == -1 ) return 0.0;

	ResourceTracker hTracker;
	hResources[iPlayer].GetArray( iLoc, hTracker );

	return hTracker.flValue;
}

//Tracker_SetValue
public any Native_TrackerSetValue( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell( 1 );
	static char sName[32]; GetNativeString( 2, sName, 32 );
	float flValue = GetNativeCell( 3 );

	Tracker_SetValue( iPlayer, sName, flValue );
	return 0;
}
void Tracker_SetValue( int iPlayer, const char sName[32], float flValue ) {
	int iLoc = Tracker_Find( iPlayer, sName );
	if( iLoc == -1 ) return;

	ResourceTracker hTracker;
	hResources[iPlayer].GetArray( iLoc, hTracker );
	if( flValue >= 100.0 && hTracker.HasFlags( RTF_DING ) ) EmitGameSoundToClient( iPlayer, "TFPlayer.Recharged" );
	hTracker.flValue = flValue;
	hResources[iPlayer].SetArray( iLoc, hTracker );
}

int Tracker_Find( int iPlayer, const char sName[32] ) {
	for( int i = 0 ; i < hResources[ iPlayer ].Length; i++ ) {
		ResourceTracker hTracker;
		hResources[ iPlayer ].GetArray( i, hTracker );

		if( strcmp( hTracker.sName, sName) == 0 )
			return i;
	}
	return -1;
}

//performs final batching and display of player's trackers
void Tracker_Display( int iPlayer ) {
	static char sFinal[256];
	static char sBuffer[64];
	sFinal = "";

	for( int i = 0; i < hResources[iPlayer].Length; i++ ) {
		ResourceTracker hTracker;
		hResources[iPlayer].GetArray( i, hTracker );

		Tracker_CreateString( hTracker, sBuffer );

		StrCat( sFinal, sizeof(sFinal), sBuffer );

		if( hTracker.HasFlags( RTF_PERCENTAGE ) )
			StrCat( sFinal, sizeof(sFinal), "%");

		StrCat( sFinal, sizeof(sFinal), "\n");
	}

	SetHudTextParamsEx( 0.88, 0.85 - ( 0.038 * ( hResources[iPlayer].Length - 1 ) ), 0.2, {255, 255, 255, 1} );
	ShowSyncHudText( iPlayer, hHudSync, sFinal );
}

void Tracker_Recharge( int iPlayer, int iIndex ) {
	ResourceTracker hTracker;

	hResources[iPlayer].GetArray(iIndex, hTracker );
	if(hTracker.flValue != 100.0 && hTracker.flValue + hTracker.flRechargeRate >= 100.0 && hTracker.HasFlags( RTF_DING ) ) EmitGameSoundToClient( iPlayer, "TFPlayer.Recharged" );
	hTracker.flValue = FloatClamp( hTracker.flValue + hTracker.flRechargeRate, 0.0, 100.0 );
	
	hResources[iPlayer].SetArray(iIndex, hTracker );
}

//generates the string for a single tracker entry
void Tracker_CreateString( ResourceTracker hTracker, char sBuffer[64] ) {
	Format( sBuffer, sizeof( sBuffer ), "%s: %-.0f", hTracker.sName, hTracker.flValue );
	if( hTracker.HasFlags(RTF_PERCENTAGE) ) StrCat( sBuffer, sizeof( sBuffer ), "%%");
}

#if defined DEBUG
Action Command_Test(int client, int args)
{
	if(args < 1) return Plugin_Handled;
	char sBuffer[32];
	GetCmdArg( 1, sBuffer, sizeof(sBuffer) );

	Tracker_Create( client, sBuffer, 0.0, 10.0 );

	return Plugin_Handled;
}
#endif