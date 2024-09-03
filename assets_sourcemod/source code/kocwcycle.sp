#include <sourcemod>

#pragma newdecls required
#pragma semicolon 1

ArrayList	g_alBaseMapList;
ArrayList	g_alActiveMapList;

bool		g_bInChange;
bool		g_bRTVAllowed = false;	// True if RTV is available to players. Used to delay rtv votes.
int		g_iTotalVoters = 0;	// Total voters connected. Doesn't include fake clients.
int		g_iVotesNeeded = 0;	// Necessary votes before map vote begins. (voters * percent_needed)
int		g_iVotes = 0;		// Total number of "say rtv" votes
bool		g_bVoted[MAXPLAYERS+1] = { false, ... };

ConVar		g_cvRTVPlayersNeeded;
ConVar		g_cvRTVMinPlayers;
ConVar		g_cvRTVInitialDelay;

public void OnPluginStart() {
	int iArraySize = ByteCountToCells( PLATFORM_MAX_PATH );
	g_alBaseMapList = new ArrayList( iArraySize );
	g_alActiveMapList = new ArrayList( iArraySize );

	g_cvRTVPlayersNeeded =	CreateConVar( "sm_kocwcycle_needed", "0.60", "Percentage of players needed to rockthevote (Def 60%)", 0, true, 0.05, true, 1.0 );
	g_cvRTVMinPlayers =	CreateConVar( "sm_kocwcycle_minplayers", "0", "Number of players required before RTV will be enabled.", 0, true, 0.0, true, float( MAXPLAYERS ) );
	g_cvRTVInitialDelay =	CreateConVar( "sm_kocwcycle_initialdelay", "30.0", "Time (in seconds) before first RTV can be held", 0, true, 0.00 );

	LoadTranslations( "rockthevote.phrases" );
	AutoExecConfig( true, "kocwcycle" );
	OnMapEnd();
	RegConsoleCmd( "sm_rtv", Command_RTV );

	for( int i = 1; i <= MaxClients; i++ ) {
		if( IsClientConnected( i ) )
			OnClientConnected( i );		
	}
}

public void OnMapEnd() {
	g_bRTVAllowed = false;
	g_iTotalVoters = 0;
	g_iVotes = 0;
	g_iVotesNeeded = 0;
	g_bInChange = false;
}

public void OnClientConnected( int iClient ) {
	if( !IsFakeClient( iClient ) ) {
		g_iTotalVoters++;
		g_iVotesNeeded = RoundToCeil( g_cvRTVPlayersNeeded.FloatValue * g_iTotalVoters );
	}
}

public void OnClientDisconnect( int iClient ) {	
	if ( g_bVoted[iClient] ) {
		g_iVotes--;
		g_bVoted[iClient] = false;
	}
	
	if ( !IsFakeClient( iClient ) ) {
		g_iTotalVoters--;
		g_iVotesNeeded = RoundToCeil( g_cvRTVPlayersNeeded.FloatValue * g_iTotalVoters );
	}
	
	if ( g_iVotes && g_iTotalVoters && g_iVotes >= g_iVotesNeeded && g_bRTVAllowed )
		StartRTV();
}

public void OnConfigsExecuted() {
	int iMapListSerial = -1;
	if( ReadMapList( g_alBaseMapList, iMapListSerial, "randomcycle", MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_MAPSFOLDER ) == INVALID_HANDLE ) {
		if ( iMapListSerial == -1 )
			LogError( "Unable to create a valid map list." );
	}
	
	CreateTimer( g_cvRTVInitialDelay.FloatValue, Timer_DelayRTV, .flags = TIMER_FLAG_NO_MAPCHANGE );
	CreateTimer( 5.0, Timer_RandomizeNextmap, .flags = TIMER_FLAG_NO_MAPCHANGE ); // Small delay to give Nextmap time to complete OnMapStart()
}

Action Timer_DelayRTV( Handle hTimer ) {
	g_bRTVAllowed = true;
	return Plugin_Continue;
}
Action Timer_RandomizeNextmap( Handle hTimer ) {
	SelectNextMap();
	return Plugin_Stop;
}

//Copies contents of g_alBaseMapList into g_alActiveMapList in a random order, while avoiding consecutive gamemodes
void ResetActiveMapList() {
	ArrayList g_alTempList = g_alBaseMapList.Clone();
	g_alActiveMapList.Clear();
	
	static char szBuffer[PLATFORM_MAX_PATH];
	static char szPrefixBuffer[64];
	static char szLastPrefix[64];
	int iTries = 0;
	while( g_alTempList.Length > 0 ) {
		int iIndex = GetRandomInt( 0, g_alTempList.Length - 1 );
		g_alTempList.GetString( iIndex, szBuffer, sizeof( szBuffer ) );

		//try again if the prefix is the same as the last map, as long as there are more maps to check
		GetMapPrefix( szBuffer, szPrefixBuffer, sizeof( szPrefixBuffer ) );
		if( strcmp( szPrefixBuffer, szLastPrefix ) == 0 ) {
			if( iTries < g_alTempList.Length ) {
				iTries++;
				continue;
			} else { //if we run out of options just give up
				PrintToServer( "breaking" );
				break;
			}
		}

		g_alTempList.Erase( iIndex );
		g_alActiveMapList.PushString( szBuffer );
		strcopy( szLastPrefix, sizeof( szLastPrefix ), szPrefixBuffer );
		iTries = 0;

		PrintToServer( "%s", szBuffer );
	}

	delete g_alTempList;
}

void SelectNextMap() {
	static char szNewMap[PLATFORM_MAX_PATH];

	if( g_alActiveMapList.Length < 1 )
		ResetActiveMapList();

	g_alActiveMapList.GetString( 0, szNewMap, sizeof( szNewMap ) );
	g_alActiveMapList.Erase( 0 );
	SetNextMap( szNewMap );

	LogAction( -1, -1, "KOCWCycle has chosen %s for the nextmap.", szNewMap );
}

void GetMapPrefix( const char[] szMapName, char[] szBuffer, int iBufferSize ) {
	SplitString( szMapName, "_", szBuffer, iBufferSize );
}

public void OnClientSayCommand_Post( int iClient, const char[] command, const char[] sArgs ) {
	if( !iClient || IsChatTrigger() )
		return;
	
	if ( strcmp( sArgs, "rtv", false) == 0 || strcmp( sArgs, "rockthevote", false) == 0) {
		ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);
		
		AttemptRTV(iClient);
		
		SetCmdReplySource(old);
	}
}

Action Command_RTV( int iClient, int iArgs ) {
	if( !iClient ) {
		return Plugin_Handled;
	}
	
	AttemptRTV( iClient );
	
	return Plugin_Handled;
}

void AttemptRTV( int iClient )
{
	if( !g_bRTVAllowed ) {
		ReplyToCommand( iClient, "[SM] %t", "RTV Not Allowed" );
		return;
	}
	
	if( GetClientCount(true) < g_cvRTVMinPlayers.IntValue ) {
		ReplyToCommand( iClient, "[SM] %t", "Minimal Players Not Met" );
		return;			
	}
	
	if( g_bVoted[iClient] ) {
		ReplyToCommand( iClient, "[SM] %t", "Already Voted", g_iVotes, g_iVotesNeeded );
		return;
	}	
	
	static char szName[MAX_NAME_LENGTH];
	GetClientName( iClient, szName, sizeof( szName ) );
	
	g_iVotes++;
	g_bVoted[iClient] = true;
	
	PrintToChatAll( "[SM] %t", "RTV Requested", szName, g_iVotes, g_iVotesNeeded );
	
	if( g_iVotes >= g_iVotesNeeded )
		StartRTV();
}

void StartRTV() {
	if( g_bInChange )
		return;
	
	static char szMap[PLATFORM_MAX_PATH];
	if( GetNextMap( szMap, sizeof( szMap ) ) ) {
		GetMapDisplayName( szMap, szMap, sizeof( szMap ) );
		
		PrintToChatAll( "[SM] %t", "Changing Maps", szMap );
		CreateTimer( 5.0, Timer_ChangeMap, .flags = TIMER_FLAG_NO_MAPCHANGE );
		g_bInChange = true;
		
		ResetRTV();
		
		g_bRTVAllowed = false;
	}
}
Action Timer_ChangeMap( Handle hTimer ) {
	g_bInChange = false;
	
	LogMessage( "RTV changing map manually" );
	
	static char szMap[PLATFORM_MAX_PATH];
	if( GetNextMap( szMap, sizeof( szMap ) ) ) {	
		ForceChangeLevel( szMap, "RTV after mapvote" );
	}
	
	return Plugin_Stop;
}
void ResetRTV() {
	g_iVotes = 0;
	for( int i = 1; i <= MAXPLAYERS; i++ ) {
		g_bVoted[i] = false;
	}
}
