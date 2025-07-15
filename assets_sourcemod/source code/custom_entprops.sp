#pragma newdecls required
#pragma semicolon 1

#include <sm_anymap>
#include <sdkhooks>

public Plugin myinfo = {
	name = "Custom Entity Properties",
	author = "Noclue",
	description = "Assign custom properties to entities.",
	version = "1.1",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

AnyMap g_amEntities;
AnyMap g_amHandles;

public void OnPluginStart() {
	g_amEntities = new AnyMap();
	g_amHandles = new AnyMap();
}

public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max ) {
	CreateNative( "SetCustomProp", Native_SetCustomProp );
	CreateNative( "SetCustomPropHandle", Native_SetCustomPropHandle );
	CreateNative( "GetCustomProp", Native_GetCustomProp );
	//CreateNative( "GetCustomPropHandle", Native_GetCustomPropHandle );
	CreateNative( "HasCustomProp", Native_HasCustomProp );

	return APLRes_Success;
}

public void OnEntityDestroyed( int iEntity ) {
	if( iEntity >= 0 && iEntity < 4096 ) {
		iEntity = EntIndexToEntRef( iEntity );
	}
	
	StringMap smEntProps;
	if( g_amEntities.GetValue( iEntity, smEntProps ) && smEntProps )
		CloseHandle( smEntProps );

	g_amEntities.Remove( iEntity );

	//close all handles inside the list
	if( g_amHandles.GetValue( iEntity, smEntProps ) && smEntProps ) {
		StringMapSnapshot snap = smEntProps.Snapshot();
		for( int i = 0; i < snap.Length; i++ ) {
			static char szBuffer[64];
			snap.GetKey( i, szBuffer, sizeof(szBuffer) );
			Handle hData = view_as<Handle>( StringToInt( szBuffer ) );
			if( hData )
				CloseHandle( hData );
		}

		CloseHandle( smEntProps );
		CloseHandle( snap );
	}
	g_amHandles.Remove( iEntity );
}

void RegisterEntity( int iEntityRef ) {
	StringMap smEntProps = new StringMap();
	g_amEntities.SetValue( iEntityRef, smEntProps, true );
	smEntProps = new StringMap();
	g_amHandles.SetValue( iEntityRef, smEntProps, true );
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
	StringMap smTemp;
	if( g_amEntities.GetValue( iEntityRef, smTemp ) ) {
		smTemp.SetValue( szPropertyName, data, true );
		return;
	}

	RegisterEntity( iEntityRef );
	SetCustomProp( iEntityRef, szPropertyName, data );
}

//native void SetCustomPropHandle( int iEntityID, const char[] szPropertyName, Handle hData );
public any Native_SetCustomPropHandle( Handle hPlugin, int iParams ) {
	int iEntityID = GetNativeCell( 1 );
	int iEntityRef = EntIndexToEntRef( iEntityID );
	if( iEntityRef == -1 )
		ThrowNativeError( 0, "Invalid Entity ID %i for custom propery lookup", iEntityID );

	int iBufferLen;
	GetNativeStringLength( 2, iBufferLen );
	char[] szPropertyName = new char[ ++iBufferLen ];
	GetNativeString( 1, szPropertyName, iBufferLen );

	Handle data = GetNativeCell( 3 );

	return SetCustomPropHandle( iEntityRef, szPropertyName, data );
}
void SetCustomPropHandle( int iEntityRef, const char[] szPropertyName, Handle hData ) {
	StringMap smTemp;
	if( g_amHandles.GetValue( iEntityRef, smTemp ) ) {
		smTemp.SetValue( szPropertyName, hData, true );
		return;
	}

	RegisterEntity( iEntityRef );
	SetCustomPropHandle( iEntityRef, szPropertyName, hData );
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

	any data;
	bool bReturn = GetCustomProp( iEntityRef, szPropertyName, data );
	if( bReturn )
		SetNativeCellRef( 3, data );

	return bReturn;
}
bool GetCustomProp( int iEntityRef, const char[] szPropertyName, any &data ) {
	StringMap smTemp;
	if( g_amEntities.GetValue( iEntityRef, smTemp ) ) {
		return smTemp.GetValue( szPropertyName, data );
	}
	return false;
}

public any Native_HasCustomProp( Handle hPlugin, int iParams ) {
	int iEntityID = GetNativeCell( 1 );
	int iEntityRef = EntIndexToEntRef( iEntityID );
	if( iEntityRef == -1 )
		ThrowNativeError( 0, "Invalid Entity ID %i for custom propery lookup", iEntityID );

	int iBufferLen;
	GetNativeStringLength( 2, iBufferLen );
	char[] szPropertyName = new char[ ++iBufferLen ];
	GetNativeString( 1, szPropertyName, iBufferLen );

	return HasCustomProp( iEntityRef, szPropertyName );
}
bool HasCustomProp( int iEntityRef, const char[] szPropertyName ) {
	StringMap smTemp;
	if( g_amEntities.GetValue( iEntityRef, smTemp ) ) {
		return smTemp.ContainsKey( szPropertyName );
	}
	return false;
}