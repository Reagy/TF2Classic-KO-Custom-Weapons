#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

ConVar cvMatchEnd;

public void OnPluginStart() {
	cvMatchEnd = FindConVar( "mp_match_end_at_timelimit" );
}

public void OnMapStart() {
	static char szMapName[32];
	GetCurrentMap( szMapName, sizeof( szMapName ) );

	static char szPrefix[8];
	SplitString( szMapName, "_", szPrefix, sizeof( szPrefix ) );

	int iSetVal = 0;
	if( 
		StrEqual( szPrefix, "cp" ) ||
		StrEqual( szPrefix, "ctf" ) ||
		StrEqual( szPrefix, "plr" )
	) {
		iSetVal = 1;
	}

	cvMatchEnd.IntValue = iSetVal;
}