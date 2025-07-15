/*
	This doesn't work in any capacity, only included in case it's useful down the line
*/

#pragma newdecls required
#pragma semicolon 1

#include <kocwtools>
#include <sourcescramble>
#include <midhook>

public Plugin myinfo = {
	name = "Dynamic Attributes",
	author = "Noclue",
	description = "Apply and remove attributes dynamically.",
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

//tf2c generates a single set of attributes for each item ID, changing the properties of one changes them for all instances.
//my solution is to generate dummy items and swap their CEconItemView pointers with a custom malloc'd block courtesy of source scramble
MemoryBlock g_mbEconItemViews[MAXPLAYERS+1];

ArrayList g_alAttributes[MAXPLAYERS+1];

//dummy tf_wearables used to provide attributes to players
int g_iDummyRefs[MAXPLAYERS+1] = { INVALID_ENT_REFERENCE, ... };

Handle g_sdkEconItemViewConstructor;
Handle g_sdkEconItemAttributeInitFloat;
Handle g_sdkEconItemAttributeInitString;
Handle g_sdkAddAttribute;
Handle g_sdkProvideTo;
Handle g_sdkAddToTail;
Handle g_sdkGetAttributeManager;

#define ECONITEMVIEW_SIZE 72
#define ECONITEMATTRIBUTE_SIZE 272

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CEconItemView::AddToTail" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Pointer );
	g_sdkAddToTail = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CEconItemView::CEconItemView" );
	g_sdkEconItemViewConstructor = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CEconItemAttribute::InitFloat" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	g_sdkEconItemAttributeInitFloat = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CEconItemAttribute::InitString" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	g_sdkEconItemAttributeInitString = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CEconItemView::AddAttribute" );
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Pointer );
	g_sdkAddAttribute = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CAttributeManager::ProvideTo" );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	g_sdkProvideTo = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CEconEntity::GetAttributeManager" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkGetAttributeManager = EndPrepSDKCall();

	delete hGameConf;

	for( int i = 1; i < MAXPLAYERS; i++ ) {
		g_mbEconItemViews[i] = new MemoryBlock( ECONITEMVIEW_SIZE );
		SDKCall( g_sdkEconItemViewConstructor, g_mbEconItemViews[i].Address );

		g_alAttributes[i] = new ArrayList();
	}

	RegConsoleCmd( "sm_attr_add", Command_Add, "test" );
	RegConsoleCmd( "sm_attr_remove", Command_Remove, "test" );
}

Address g_aAttributeVTable = Address_Null;

/*public void OnEntityCreated( int iClient ) {
	
	if( !IsValidPlayer( iClient ) )
		return;

	int iDummy = CreateEntityByName( "tf_wearable" );
	g_iDummyRefs[iClient] = EntIndexToEntRef( iDummy );

	//g_mbEconItemViews[iClient].StoreToOffset(  )

	StoreToEntity( iDummy, 1168, g_mbEconItemViews[iClient].Address );
	//SetEntProp( iDummy, Prop_Send, "m_Item", g_mbEconItemViews[iClient].Address );

	Address aManager = SDKCall( g_sdkGetAttributeManager, iDummy );
	PrintToServer("%i", aManager);

	PrintToServer("test50");
	SDKCall( g_sdkProvideTo, aManager, iClient );
	ChangeEdictState( iDummy );
	ChangeEdictState( iClient );
}

public void OnClientDisconnect( int iClient ) {
	int iDummy = EntRefToEntIndex( g_iDummyRefs[iClient] );
	if( iDummy == -1 )
		return;

	RemoveEntity( iDummy );

	for( int i = 0; i < g_alAttributes[iClient].Length; i++ ) {
		MemoryBlock mbMemory = g_alAttributes[iClient].Get( i );
		delete mbMemory;
	}

	g_alAttributes[iClient].Clear();
}

MemoryBlock CreateAttributeFloat( float flValue, int iAttribID, const char[] szAttribClass = "" ) {
	MemoryBlock mbAttribute = new MemoryBlock( ECONITEMATTRIBUTE_SIZE );
	PrintToServer( "vtable %i %i", mbAttribute.Address, g_aAttributeVTable );

	mbAttribute.StoreToOffset( 0, view_as<int>( g_aAttributeVTable ), NumberType_Int32 );

	SDKCall( g_sdkEconItemAttributeInitFloat, mbAttribute.Address, iAttribID, flValue, szAttribClass );

	return mbAttribute;
}

void AddAttributeFloat( int iPlayer, float flValue, int iAttribID, const char[] szAttribClass = "" ) {
	MemoryBlock mbAttribute = CreateAttributeFloat( flValue, iAttribID, szAttribClass );
	g_alAttributes[iPlayer].Push( mbAttribute );

	PrintToServer("%i %i", g_mbEconItemViews[iPlayer].Address, LoadFromEntity( EntRefToEntIndex( g_iDummyRefs[iPlayer] ), 1168 ) );

	int iWeapon = GetEntPropEnt( iPlayer, Prop_Send, "m_hActiveWeapon" );

	bool bTest = SDKCall( g_sdkAddAttribute, GetEntityAddress( iWeapon ) + view_as<Address>( 1168 ), mbAttribute.Address );
	PrintToServer("%i", bTest );
	//SDKCall( g_sdkAddToTail,  GetEntityAddress( iWeapon ) + view_as<Address>( 1168 ) + view_as<Address>( 56 ), g_mbEconItemViews[iPlayer].LoadFromOffset( 68, NumberType_Int32 ), mbAttribute.Address );
	//PrintToServer("%i", g_mbEconItemViews[iPlayer].LoadFromOffset( 68, NumberType_Int32 ));
}

void RemoveAttribute( int iPlayer, const char[] szAttribClass ) {

}*/


Action Command_Add( int iClient, int iArgs ) {
	//if(iArgs < 1) return Plugin_Handled;
	
	//AddAttributeFloat( iClient, 10.0, 6, "mult_postfiredelay" );

	return Plugin_Handled;
}
Action Command_Remove( int iClient, int iArgs ) {
	if(iArgs < 1) return Plugin_Handled;
	
	return Plugin_Handled;
}