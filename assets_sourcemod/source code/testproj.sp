#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <kocwtools>

Handle g_sdkGiveEconItem;
Handle g_sdkReapplyProvision;
//Handle g_sdkIterateAttributes;

bool g_bLateLoad;
public APLRes AskPluginLoad2( Handle myself, bool bLate, char[] error, int err_max ) {
	g_bLateLoad = bLate;
	return APLRes_Success;
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CEconEntity::ReapplyProvision" );
	g_sdkReapplyProvision = EndPrepSDKCallSafe( "CEconEntity::ReapplyProvision" );

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayer::GiveEconItem" );
	PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkGiveEconItem = EndPrepSDKCallSafe( "CTFPlayer::GiveEconItem" );

	/*StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CEconItemView::IterateAttributes" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain ); //CEconItemAttribute*
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //string_t
	g_sdkIterateAttributes = EndPrepSDKCallSafe( "CEconItemView::IterateAttributes" );*/

	delete hGameConf;

	RegConsoleCmd( "sm_attr_test", Command_Test );
}

Action Command_Test( int iClient, int iArgs ) {
	//constructing a ceconitemview doesn't work so this just gives the player the shit and gives it to the gun instead
	int iEcon = SDKCall( g_sdkGiveEconItem, iClient, "TF_TEST_ROF", 4, 0 );

	int iWeapon = GetEntPropEnt( iClient, Prop_Send, "m_hActiveWeapon" );
	if( iWeapon == -1 )
		return Plugin_Handled;

	//transfers ownership of attributes to the weapon
	SetEntPropEnt( iEcon, Prop_Send, "m_hOwnerEntity", iWeapon );
	SDKCall( g_sdkReapplyProvision, iEcon );

	return Plugin_Handled;

	//changes to attributes are not synced over the network
	//keeping this in case it's useful someday

	/*Address pItemView = GetEntityAddress( iEcon ) + view_as<Address>( GetEntSendPropOffs( iEcon, "m_Item", true ) );
	Address pAttribute = SDKCall( g_sdkIterateAttributes, pItemView, AllocPooledString( "mult_postfiredelay" ) );

	PrintToServer("1 %i", LoadFromAddressOffset(pAttribute,4)); //attrib index
	PrintToServer("2 %f", LoadFromAddressOffset(pAttribute,8)); //float value

	
	StoreToAddressOffset( pAttribute, 8, 1.0 );*/
}