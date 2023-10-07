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

ArrayList g_rtResources[MAXPLAYERS+1];
Handle hHudSync;

enum {
	RTF_PERCENTAGE = 1 << 1,	//display value as a percentage
	RTF_DING = 1 << 2,		//play sound when fully charged
	RTF_RECHARGES = 1 << 3,
	RTF_NOOVERWRITE = 1 << 4,	//do not overwrite existing tracker
	RTF_CLEARONSPAWN = 1 << 5,	//reset on respawning
	RTF_FORWARDONFULL = 1 << 6,	//send a global forward when recharged
}

enum struct ResourceTracker {
	char szName[32];
	float flValue;
	int iFlags;
	float flMax;
	float flRechargeRate;

	bool HasFlags( int iCheckFlags ) {
		return ( this.iFlags & iCheckFlags ) == iCheckFlags;
	}
}
#define TRACKERMAXSIZE sizeof(ResourceTracker)
#define UPDATEINTERVAL 0.2

GlobalForward g_OnRecharge;

public void OnPluginStart() {
	hHudSync = CreateHudSynchronizer();

	HookEvent( "player_spawn", Event_Spawned );

	for(int i = 0; i < sizeof(g_rtResources); i++) {
		if( g_rtResources[i] )
			g_rtResources[i].Clear();
			
		g_rtResources[i] = new ArrayList(TRACKERMAXSIZE);
	}

	g_OnRecharge = new GlobalForward( "Tracker_OnRecharge", ET_Ignore, Param_Cell, Param_String, Param_Float );

#if defined DEBUG
	RegConsoleCmd("sm_hf_test", Command_Test, "test");
#endif
}

void Event_Spawned( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	ResourceTracker hTracker;
	for( int i = 0; i < g_rtResources[ iPlayer ].Length; i++ ) {
		g_rtResources[ iPlayer ].GetArray( i, hTracker );
		if( hTracker.iFlags & RTF_CLEARONSPAWN ) {
			hTracker.flValue = 0.0;
			g_rtResources[ iPlayer ].SetArray( i, hTracker );
		}
			
	}
}

public void OnMapStart() {
	CreateTimer( UPDATEINTERVAL, Timer_TrackerThink, 0, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT );

	for(int i = 0; i < sizeof(g_rtResources); i++) {
		if( g_rtResources[i] )
			g_rtResources[i].Clear();

		g_rtResources[i] = new ArrayList(TRACKERMAXSIZE);
	}
}

public APLRes AskPluginLoad2( Handle hMyself, bool bLate, char[] sError, int iErrorMax ) {
	CreateNative( "Tracker_Create", Native_TrackerCreate );
	CreateNative( "Tracker_Remove", Native_TrackerRemove );
	CreateNative( "Tracker_GetValue", Native_TrackerGetValue );
	CreateNative( "Tracker_SetValue", Native_TrackerSetValue );
	CreateNative( "Tracker_SetRechargeRate", Native_TrackerSetRechargeRate );
	CreateNative( "Tracker_SetFlags", Native_TrackerSetFlags );
	CreateNative( "Tracker_SetMax", Native_TrackerSetMax );

	return APLRes_Success;
}

public void OnClientDisconnect( int iClient ) {
	if( iClient >= 0 && iClient < sizeof( g_rtResources ) )
		g_rtResources[iClient].Clear();
}

Action Timer_TrackerThink( Handle hTimer ) {
	for ( int i = 1; i <= MaxClients; i++ ) {
		if ( IsClientInGame( i ) ) {
			for( int j = 0; j < g_rtResources[i].Length; j++ ) {
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
	static char szName[32]; GetNativeString( 2, szName, 32 );
	bool bOverwrite = GetNativeCell( 3 );

	Tracker_Create( iPlayer, szName, bOverwrite );

	return 0;
}
void Tracker_Create( int iPlayer, const char szName[32], bool bOverwrite = true ) {
	ResourceTracker hTracker;

	hTracker.iFlags = 0;
	hTracker.szName = szName;
	hTracker.flMax = 0.0;

	int iIndex = Tracker_Find( iPlayer, szName );
	if( iIndex == -1 )
		g_rtResources[iPlayer].PushArray( hTracker );
	else if( bOverwrite )
		g_rtResources[iPlayer].SetArray( iIndex, hTracker );
	
}

//Tracker_Remove
public any Native_TrackerRemove( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell( 1 );
	static char szName[32]; GetNativeString( 2, szName, 32 );

	Tracker_Remove( iPlayer, szName );

	return 0;
}
void Tracker_Remove( int iPlayer, const char szName[32] ) {
	int iLoc = Tracker_Find( iPlayer, szName );
	if( iLoc == -1 ) return;

	g_rtResources[iPlayer].Erase( iLoc );
}

//Tracker_GetValue
public any Native_TrackerGetValue( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell( 1 );
	static char szName[32]; GetNativeString( 2, szName, 32 );

	return Tracker_GetValue( iPlayer, szName );
}
float Tracker_GetValue( int iPlayer, const char szName[32] ) {
	int iLoc = Tracker_Find( iPlayer, szName );
	if( iLoc == -1 ) return 0.0;

	ResourceTracker rtTracker;
	g_rtResources[iPlayer].GetArray( iLoc, rtTracker );

	return rtTracker.flValue;
}

//Tracker_SetMax( int iPlayer, const char szName[32], float flMax );
public any Native_TrackerSetMax( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell( 1 );
	static char szName[32]; GetNativeString( 2, szName, sizeof( szName ) );
	float flValue = GetNativeCell( 3 );

	int iLoc = Tracker_Find( iPlayer, szName );
	if( iLoc == -1 ) return 0;

	Tracker_SetMaxIndex( iPlayer, iLoc, flValue );
	return 0;
}
void Tracker_SetMaxIndex( int iPlayer, int iIndex, float flNewMax ) {
	ResourceTracker rtTracker;
	g_rtResources[ iPlayer ].GetArray( iIndex, rtTracker );

	rtTracker.flMax = flNewMax;
	Tracker_SetValueIndex( iPlayer, iIndex, rtTracker.flValue );
	g_rtResources[ iPlayer ].SetArray( iIndex, rtTracker );
}

//Tracker_SetFlags( int iPlayer, const char szName[32], int iFlags );
public any Native_TrackerSetFlags( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell( 1 );
	static char szName[32]; GetNativeString( 2, szName, sizeof( szName ) );
	int iFlags = GetNativeCell( 3 );

	int iLoc = Tracker_Find( iPlayer, szName );
	if( iLoc == -1 ) return 0;

	Tracker_SetFlagsIndex( iPlayer, iLoc, iFlags );
	return 0;
}
void Tracker_SetFlagsIndex( int iPlayer, int iIndex, int iFlags ) {
	ResourceTracker rtTracker;
	g_rtResources[ iPlayer ].GetArray( iIndex, rtTracker );

	rtTracker.iFlags = iFlags;
	g_rtResources[ iPlayer ].SetArray( iIndex, rtTracker );
}

//Tracker_SetRechargeRate( int iPlayer, const char szName[32], float flRechargeRate );
public any Native_TrackerSetRechargeRate( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell( 1 );
	static char szName[32]; GetNativeString( 2, szName, sizeof( szName ) );
	float flRechargeRate = GetNativeCell( 3 );

	int iLoc = Tracker_Find( iPlayer, szName );
	if( iLoc == -1 )
		return 0;

	Tracker_SetRechargeRateIndex( iPlayer, iLoc, flRechargeRate * UPDATEINTERVAL );
	return 0;
}
void Tracker_SetRechargeRateIndex( int iPlayer, int iIndex, float flRechargeRate ) {
	ResourceTracker rtTracker;
	g_rtResources[ iPlayer ].GetArray( iIndex, rtTracker );
	rtTracker.flRechargeRate = flRechargeRate;
	g_rtResources[ iPlayer ].SetArray( iIndex, rtTracker );
}

//Tracker_SetValue( int iPlayer, const char sName[32], float flValue );
public any Native_TrackerSetValue( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell( 1 );
	static char szName[32]; GetNativeString( 2, szName, 32 );
	float flValue = GetNativeCell( 3 );

	Tracker_SetValue( iPlayer, szName, flValue );
	return 0;
}
void Tracker_SetValue( int iPlayer, const char szName[32], float flValue ) {
	int iLoc = Tracker_Find( iPlayer, szName );
	if( iLoc == -1 ) return;

	Tracker_SetValueIndex( iPlayer, iLoc, flValue );
}
void Tracker_SetValueIndex( int iPlayer, int iIndex, float flNewValue ) {
	ResourceTracker rtTracker;
	g_rtResources[iPlayer].GetArray( iIndex, rtTracker );
	flNewValue = FloatClamp( flNewValue, 0.0, rtTracker.flMax );
	if( rtTracker.flValue < rtTracker.flMax && flNewValue >= rtTracker.flMax ) {
		if( rtTracker.HasFlags( RTF_DING ) )
			EmitGameSoundToClient( iPlayer, "TFPlayer.Recharged" );

		if( rtTracker.HasFlags( RTF_FORWARDONFULL ) )
			Tracker_OnRecharge( iPlayer, rtTracker.szName, flNewValue );
	}
	rtTracker.flValue = flNewValue;
	g_rtResources[ iPlayer ].SetArray( iIndex, rtTracker );
}

int Tracker_Find( int iPlayer, const char szName[32] ) {
	for( int i = 0 ; i < g_rtResources[ iPlayer ].Length; i++ ) {
		ResourceTracker hTracker;
		g_rtResources[ iPlayer ].GetArray( i, hTracker );

		if( strcmp( hTracker.szName, szName) == 0 )
			return i;
	}
	return -1;
}

//performs final batching and display of player's trackers
void Tracker_Display( int iPlayer ) {
	static char sFinal[256];
	static char sBuffer[64];
	sFinal = "";

	for( int i = 0; i < g_rtResources[iPlayer].Length; i++ ) {
		ResourceTracker hTracker;
		g_rtResources[iPlayer].GetArray( i, hTracker );

		Tracker_CreateString( hTracker, sBuffer );

		StrCat( sFinal, sizeof(sFinal), sBuffer );

		if( hTracker.HasFlags( RTF_PERCENTAGE ) )
			StrCat( sFinal, sizeof(sFinal), "%");

		StrCat( sFinal, sizeof(sFinal), "\n");
	}

	SetHudTextParamsEx( 0.88, 0.85 - ( 0.038 * ( g_rtResources[iPlayer].Length - 1 ) ), 20.0, {255, 255, 255, 1}, {255,255,255,0}, 0, 6.0, 0.0, 0.0 );
	ShowSyncHudText( iPlayer, hHudSync, sFinal );
}

void Tracker_Recharge( int iPlayer, int iIndex ) {
	ResourceTracker hTracker;

	g_rtResources[iPlayer].GetArray( iIndex, hTracker );
	if( !( hTracker.iFlags & RTF_RECHARGES ) )
		return;

	Tracker_SetValueIndex( iPlayer, iIndex, hTracker.flValue + hTracker.flRechargeRate );
}

//generates the string for a single tracker entry
void Tracker_CreateString( ResourceTracker hTracker, char sBuffer[64] ) {
	Format( sBuffer, sizeof( sBuffer ), "%s: %-.0f", hTracker.szName, hTracker.flValue );
	if( hTracker.HasFlags(RTF_PERCENTAGE) ) StrCat( sBuffer, sizeof( sBuffer ), "%%");
}


/*
Call_StartForward( g_OnTakeDamageTF );

	Call_PushCell( iThis );
	Call_PushCell( hParams.GetAddress( 1 ) );

	Call_Finish();
*/


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

//forward void Tracker_OnRecharge( int iPlayer, const char szTrackerName[32], float flValue );
void Tracker_OnRecharge( int iPlayer, char szName[32], float flNewValue ) {
	Call_StartForward( g_OnRecharge );

	Call_PushCell( iPlayer );
	Call_PushString( szName );
	Call_PushFloat( flNewValue );

	Call_Finish();
}