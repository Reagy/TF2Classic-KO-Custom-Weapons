#pragma newdecls required
#pragma semicolon 1

#include <sm_anymap>
#include <sdkhooks>

public Plugin myinfo = {
	name = "Custom Entity Properties",
	author = "Noclue",
	description = "Assign custom properties to entities.",
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

AnyMap g_amEntities;

public void OnPluginStart() {
	g_amEntities = new AnyMap();
}

public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max ) {
	CreateNative( "SetCustomProp", Native_SetCustomProp );
	CreateNative( "GetCustomProp", Native_GetCustomProp );

	return APLRes_Success;
}

public void OnEntityDestroyed( int iEntity ) {
	if( iEntity >= 0 && iEntity < 4096 ) {
		iEntity = EntIndexToEntRef( iEntity );
	}
	
	g_amEntities.Remove( iEntity );
}

//native void SetCustomProp( int iEntityID, const char[] szPropertyName, any data )
public int Native_SetCustomProp( Handle hPlugin, int iParams ) {
	int iEntityID = GetNativeCell( 1 );
	int iEntityRef = EntIndexToEntRef( iEntityID );
	if( iEntityRef == -1 )
		ThrowNativeError( 0, "Invalid Entity ID %i for custom propery lookup", iEntityID );

	int iBufferLen;
	GetNativeStringLength( 2, iBufferLen );
	char[] szPropertyName = new char[ ++iBufferLen ];
	GetNativeString( 1, szPropertyName, iBufferLen );

	any data = GetNativeCell( 3 );

	SetCustomProp( iEntityRef, szPropertyName, data );
	return 0;
}

void SetCustomProp( int iEntityRef, const char[] szPropertyName, any data ) {
	StringMap smProps;
	if( g_amEntities.GetValue( iEntityRef, smProps ) ) {
		smProps.SetValue( szPropertyName, data, true );
		return;
	}

	RegisterEntity( iEntityRef );
	SetCustomProp( iEntityRef, szPropertyName, data );
}

//native any GetCustomProp( int iEntityID, const char[] szPropertyName );
public any Native_GetCustomProp( Handle hPlugin, int iParams ) {
	int iEntityID = GetNativeCell( 1 );
	int iEntityRef = EntIndexToEntRef( iEntityID );
	if( iEntityRef == -1 )
		ThrowNativeError( 0, "Invalid Entity ID %i for custom propery lookup", iEntityID );

	int iBufferLen;
	GetNativeStringLength( 2, iBufferLen );
	char[] szPropertyName = new char[ ++iBufferLen ];
	GetNativeString( 1, szPropertyName, iBufferLen );

	return GetCustomProp( iEntityRef, szPropertyName );
}
any GetCustomProp( int iEntityRef, const char[] szPropertyName ) {
	StringMap smProps;
	if( g_amEntities.GetValue( iEntityRef, smProps ) ) {
		any returnVal;
		smProps.GetValue( szPropertyName, returnVal );
		return returnVal;
	}

	return 0;
}

void RegisterEntity( int iEntityRef ) {
	StringMap smEntProps = new StringMap();
	g_amEntities.SetValue( iEntityRef, smEntProps, true );
}