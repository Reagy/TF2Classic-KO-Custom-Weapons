#pragma newdecls required
#pragma semicolon 1

#include <kocwtools>

public Plugin myinfo = {
	name = "Wearable Buffs",
	author = "Noclue",
	description = "Apply and remove wearables dynamically.",
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

ArrayList g_alPlayerBuffRefs[MAXPLAYERS+1];

Handle g_sdkGetItemSchema;
Handle g_sdkGetItemDefinition;

Handle g_hGiveEcon;

//#define DEBUG

public APLRes AskPluginLoad2( Handle hMyself, bool bLate, char[] szError, int iErrMax ) {
	CreateNative( "GiveEconItem", Native_GiveEconItem );
	CreateNative( "RemoveEconItem", Native_RemoveEconItem );

	return APLRes_Success;
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayer::GiveEconItem" );
	PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_hGiveEcon = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Static );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "GetItemSchema" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkGetItemSchema = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CEconItemSchema::GetItemDefinition" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkGetItemDefinition = EndPrepSDKCall();

	HookEvent( EVENT_POSTINVENTORY, Event_PostInventory );

	delete hGameConf;

	for( int i = 0; i < sizeof( g_alPlayerBuffRefs ); i++ ) {
		g_alPlayerBuffRefs[i] = new ArrayList();
	}

	RegConsoleCmd( "sm_devwep_give", Command_DevWep, "thanmks and haveasd fun" );

#if defined DEBUG
	RegConsoleCmd( "sm_attr_add", Command_Add, "test" );
	RegConsoleCmd( "sm_attr_remove", Command_Remove, "test" );
#endif
}

static char g_szDevList[][] = {
	"76561198069525597", //clue
	"76561198124781832", //vror (mentioned)
	"76561197973074856", //reagy
	"76561198045208572", //dan
	"76561198947729988", //daffy
	"76561198149855325", //colrot
	"76561198031608022", //kibbleknight
	"76561198071599417", //haau
	"76561198071732989", //majro
	"76561198302570978", //gabe
	"76561198167640066", //wonders

	"76561198038214360", //negative_chill
	"76561198014234943", //fluffypaws

	"76561197993638233", //trotim
	"76561198825918211", //azzy

	"76561198082886322", //panacek (for the funny)
};

Action Command_DevWep( int iClient, int iArgs ) {
	if( !IsValidPlayer( iClient ) || iArgs < 1 ) return Plugin_Handled;

	static char szAuthID[128];
	if( !GetClientAuthId( iClient, AuthId_SteamID64, szAuthID, sizeof(szAuthID) ) ) {
		PrintToConsole( iClient, "Authorization failed." );
		return Plugin_Continue;
	}	

	bool bIsDev = false;
	for( int i = 0; i < sizeof(g_szDevList); i++ ) {
		if( StrEqual( szAuthID, g_szDevList[i] ) ) {
			bIsDev = true;
			break;
		}
	}

	if( !bIsDev ) {
		PrintToConsole( iClient, "Authorization failed." );
		return Plugin_Handled;
	}

	int iItemID = GetCmdArgInt( 1 );

	Address aDefinition = SDKCall( g_sdkGetItemDefinition, SDKCall( g_sdkGetItemSchema ), iItemID );
	if( aDefinition == Address_Null ) {
		PrintToConsole( iClient, "Could not find item definition for ID %i.", iItemID );
		return Plugin_Handled;
	}

	static char szItemName[128];
	LoadStringFromAddress( LoadFromAddress( aDefinition + view_as<Address>( 4 ), NumberType_Int32 ), szItemName, sizeof( szItemName ) );
	SDKCall( g_hGiveEcon, iClient, szItemName, 0, -1 );

	return Plugin_Handled;
}

//native int GiveEconItem( int iPlayer, int iItemID );
public any Native_GiveEconItem( Handle hPlugin, int iParams ) {
	int iPlayer = GetNativeCell( 1 );
	int iItemID = GetNativeCell( 2 );

	if( !IsValidPlayer( iPlayer ) )
		return -1;

	return AddPlayerEcon( iPlayer, iItemID );
}

//native bool RemoveEconItem( int iPlayer, int iItemID );
public any Native_RemoveEconItem( Handle hPlugin, int iParams ) {
	int iPlayer = GetNativeCell( 1 );
	int iItemID = GetNativeCell( 2 );

	if( !IsValidPlayer( iPlayer ) )
		return -1;

	return RemovePlayerEcon( iPlayer, iItemID );
}

Action Event_PostInventory( Event hEvent, const char[] sName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	g_alPlayerBuffRefs[iPlayer].Clear();
	return Plugin_Continue;
}

int GetPlayerEconIndex( int iPlayer, int iItemID ) {
	for( int i = 0; i < g_alPlayerBuffRefs[iPlayer].Length; i++ ) {
		int iItem = EntRefToEntIndex( g_alPlayerBuffRefs[iPlayer].Get( i ) );
		if( iItem == -1 ) {
			g_alPlayerBuffRefs[iPlayer].Erase( i );
			i--;
			continue;
		}
		int iItemIDTemp = GetEntProp( iItem, Prop_Send, "m_iItemDefinitionIndex" );
		if( iItemIDTemp == iItemID )
			return i;
	}

	return -1;
}

bool PlayerHasEcon( int iPlayer, int iItemID ) {
	return GetPlayerEconIndex( iPlayer, iItemID ) != -1;
}

int AddPlayerEcon( int iPlayer, int iItemID ) {
	if( PlayerHasEcon( iPlayer, iItemID ) )
		return -1;

	Address aDefinition = SDKCall( g_sdkGetItemDefinition, SDKCall( g_sdkGetItemSchema ), iItemID );
	if( aDefinition == Address_Null ) {
		PrintToServer( "could not find item definition for id %i", iItemID );
		return -1;
	}

	static char szItemName[128];
	LoadStringFromAddress( LoadFromAddress( aDefinition + view_as<Address>( 4 ), NumberType_Int32 ), szItemName, sizeof( szItemName ) );
	int iWearable = SDKCall( g_hGiveEcon, iPlayer, szItemName, 4, 0 );

	g_alPlayerBuffRefs[iPlayer].Push( EntIndexToEntRef( iWearable ) );
	return iWearable;
}

bool RemovePlayerEcon( int iPlayer, int iItemID ) {
	int iBuffIndex = GetPlayerEconIndex( iPlayer, iItemID );
	if( iBuffIndex == -1 )
		return false;

	int iBuffItem = EntRefToEntIndex( g_alPlayerBuffRefs[iPlayer].Get( iBuffIndex ) );
	if( iBuffItem == -1 )
		return false;

	RemoveEntity( iBuffItem );
	g_alPlayerBuffRefs[iPlayer].Erase( iBuffIndex );

	return true;
}

#if defined DEBUG
Action Command_Add( int iClient, int iArgs ) {
	if( iArgs < 1 ) return Plugin_Handled;
	
	AddPlayerEcon( iClient, GetCmdArgInt( 1 ) );

	return Plugin_Handled;
}
Action Command_Remove( int iClient, int iArgs ) {
	if( iArgs < 1 ) return Plugin_Handled;
	
	RemovePlayerEcon( iClient, GetCmdArgInt( 1 ) );

	return Plugin_Handled;
}
#endif