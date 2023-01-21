#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <stocksoup/memory>

//inventory
Handle hEconGetAttributeManager;
Handle hPlayerGetAttributeManager;
Handle hPlayerGetAttributeContainer;
Handle hApplyAttributeFloat;

Handle hGetEntitySlot;
Handle hGetMedigunCharge;

//think
Handle hSetNextThink;

//damage
//DynamicHook hOnTakeDamage;

Address offs_CTFPlayerShared_pOuter;

StringMap g_AllocPooledStringCache;

public Plugin myinfo =
{
	name = "KOCW Tools",
	author = "Noclue",
	description = "Standard functions for custom weapons.",
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}


//bool bLateLoad = false;
public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max ) {

	//bLateLoad = late;

	//string functions
	CreateNative( "AllocPooledString", Native_AllocPooledString );

	//inventory functions
	CreateNative( "AttribHookFloat", Native_AttribHookFloat );
	//CreateNative( "AttribHookString", Native_AttribHookString );

	CreateNative( "GetMedigunCharge", Native_GetMedigunCharge );
	CreateNative( "GetEntityInSlot", Native_GetEntitySlot );

	//think functions
	CreateNative( "SetNextThink", Native_SetNextThink );
	//CreateNative( "GetNextThink", Native_GetNextThink );

	//memory functions
	CreateNative( "GetPlayerFromShared", Native_GetPlayerFromShared );

	return APLRes_Success;
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	/*
		INVENTORY FUNCTIONS
	*/

	//CEconEntity::GetAttributeManager(void)
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CEconEntity::GetAttributeManager");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hEconGetAttributeManager = EndPrepSDKCall();
	if(!hEconGetAttributeManager)
		PrintToServer("SDKCall setup for CEconEntity::GetAttributeManager failed");

	//CTFPlayer::GetAttributeManager(void)
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CTFPlayer::GetAttributeManager");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hPlayerGetAttributeManager = EndPrepSDKCall();
	if(!hPlayerGetAttributeManager)
		PrintToServer("SDKCall setup for CTFPlayer::GetAttributeManager failed");

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CTFPlayer::GetAttributeContainer");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hPlayerGetAttributeContainer = EndPrepSDKCall();
	if(!hPlayerGetAttributeContainer)
		PrintToServer("SDKCall setup for CTFPlayer::GetAttributeContainer failed");

	//CAttributeManager::ApplyAttributeFloat( float flValue, const CBaseEntity *pEntity, string_t strAttributeClass )
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CAttributeManager::ApplyAttributeFloat");
	PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain); //flvalue
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer); //pentity
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); //strattributeclass
	hApplyAttributeFloat = EndPrepSDKCall();
	if(!hApplyAttributeFloat)
		PrintToServer("SDKCall setup for CAttributeManager::ApplyAttributeFloat failed");

	//CEconEntity *CTFPlayer::GetEntityForLoadoutSlot( int iSlot )
	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayer::GetEntityForLoadoutSlot" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //int
	PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
	hGetEntitySlot = EndPrepSDKCall();
	if ( !hGetEntitySlot )
		SetFailState( "SDKCall setup for CTFPlayer::GetEntityForLoadoutSlot failed" );

	//float CTFPlayer::GetMedigunCharge( void )
	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayer::GetMedigunCharge" );
	PrepSDKCall_SetReturnInfo( SDKType_Float, SDKPass_Plain );
	hGetMedigunCharge = EndPrepSDKCall();
	if( !hGetMedigunCharge )
		SetFailState( "SDKCall setup for CTFPlayer::GetMedigunCharge failed" );

	/*
		THINK FUNCTIONS
	*/

	//CBaseEntity::SetNextThink( float thinkTime, const char *szContext )
	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CBaseEntity::SetNextThink" );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	hSetNextThink = EndPrepSDKCall();
	if ( !hSetNextThink )
		SetFailState( "SDKCall setup for CBaseEntity::SetNextThink failed" );

	/*
		STRING FUNCTIONS
	*/

	g_AllocPooledStringCache = new StringMap();

	/*
		MEMORY FUNCTIONS
	*/

	/*
		DAMAGE FUNCTIONS
	*/

	/*hOnTakeDamage = DynamicHook.FromConf( hGameConf, "CTFPlayer::OnTakeDamage" );
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);

	if( bLateLoad ) {
		for(int i = 1; i <= MaxClients; i++) {
			if( IsValidEntity( i ) && IsClientInGame( i ) ) {
				PrintToServer("%i", i);
				hOnTakeDamage.HookEntity( Hook_Pre, i, Hook_OnTakeDamagePre );
				hOnTakeDamage.HookEntity( Hook_Post, i, Hook_OnTakeDamagePost );
			}
		}
	}*/

	offs_CTFPlayerShared_pOuter = GameConfGetAddressOffset( hGameConf, "CTFPlayerShared::m_pOuter" );

	delete hGameConf;
}


public void OnMapEnd() {
	g_AllocPooledStringCache.Clear();
}

/*
	STRING FUNCTIONS
*/

public any Native_AllocPooledString( Handle hPlugin, int iParams ) {
	int iBuffer;
	GetNativeStringLength( 1, iBuffer );
	char[] sAllocPool = new char[ ++iBuffer ];
	GetNativeString( 1, sAllocPool, iBuffer );

	return AllocPooledString( sAllocPool );
}

//thanks tf2attributes, never would have figured this black magic out in a million years
stock Address AllocPooledString( const char[] sValue ) {
	Address aValue;
	if ( g_AllocPooledStringCache.GetValue( sValue, aValue ) ) {
		return aValue;
	}
	
	int iEntity = FindEntityByClassname( -1, "worldspawn" );
	if ( !IsValidEntity( iEntity ) ) {
		return Address_Null;
	}
	int iOffset = FindDataMapInfo( iEntity, "m_iName" );
	if ( iOffset <= 0 ) {
		return Address_Null;
	}
	Address pOrig = view_as<Address>( GetEntData( iEntity, iOffset ) );
	DispatchKeyValue( iEntity, "targetname", sValue );
	aValue = view_as<Address>( GetEntData( iEntity, iOffset ) );
	SetEntData( iEntity, iOffset, pOrig );
	
	g_AllocPooledStringCache.SetValue( sValue, aValue );
	return aValue;
}

/*
	ATTRIBUTE FLOAT FUNCTIONS

	AttribHookValue is the function internally used to get float attribute data.
	It simply locates the AttributeManager of the provided entity and calls it's ApplyAttributeFloat/ApplyAttributeString function.
	The function is a template function, and every version except the string_t version was inlined by the compiler, so it's behavior has to be recreated manually.
*/

//native float AttribHookFloat( float flValue, int iEntity, const char[] sAttributeClass );
public any Native_AttribHookFloat( Handle hPlugin, int iParams ) {
	float flValue = GetNativeCell( 1 );
	int iEntity = GetNativeCell( 2 );

	if( !( IsValidEdict( iEntity ) && HasEntProp( iEntity, Prop_Send, "m_AttributeManager" ) ) )
		return flValue;
	
	int iBuffer;
	GetNativeStringLength( 3, iBuffer );
	char[] sAttributeClass = new char[ ++iBuffer ];
	GetNativeString( 3, sAttributeClass, iBuffer );

	Address aStringAlloc = AllocPooledString( sAttributeClass ); //string needs to be allocated before the function will recognize it
	Address aManager;
	if( iEntity <= MaxClients )
		aManager = SDKCall( hPlayerGetAttributeManager, iEntity );
	else
		aManager = SDKCall( hEconGetAttributeManager, iEntity );
		
	return SDKCall( hApplyAttributeFloat, aManager, flValue, iEntity, aStringAlloc );
}

public any Native_GetEntitySlot( Handle hPlugin, int iParams ) {
	int iEntity = GetNativeCell( 1 );
	int iIndex = GetNativeCell( 2 );

	return SDKCall( hGetEntitySlot, iEntity, iIndex );
}

public any Native_GetMedigunCharge( Handle hPlugin, int iParams ) {
	int iEntity = GetNativeCell( 1 );
	return SDKCall( hGetMedigunCharge, iEntity );
}

/*
	THINK FUNCTIONS
*/
//native void SetNextThink( int iEntity, float flNextThink, const char[] sThinkContext );
public any Native_SetNextThink( Handle hPlugin, int iParams ) {
	int iEntity = GetNativeCell( 1 );
	float flNextThink = GetNativeCell( 2 );

	int iBuffer;
	GetNativeStringLength( 3, iBuffer );
	char[] sThinkContext = new char[ ++iBuffer ];
	GetNativeString( 3, sThinkContext, iBuffer );

	SDKCall( hSetNextThink, iEntity, flNextThink, sThinkContext );

	return 1;
}

/*
	MEMORY FUNCTIONS
*/

public int Native_GetPlayerFromShared( Handle hPlugin, int iParams ) {
	Address aShared = GetNativeCell( 1 );
	return GetPlayerFromSharedAddress( aShared );
}

int GetPlayerFromSharedAddress( Address pShared ) {
	Address pOuter = DereferencePointer( pShared + offs_CTFPlayerShared_pOuter );
	return GetEntityFromAddress( pOuter );
}

static Address GameConfGetAddressOffset(Handle hGamedata, const char[] sKey) {
	Address aOffs = view_as<Address>( GameConfGetOffset( hGamedata, sKey ) );
	if ( aOffs == view_as<Address>( -1 ) ) {
		SetFailState( "Failed to get member offset %s", sKey );
	}
	return aOffs;
}

any LoadFromEntity( int iEntity, int iOffset, NumberType iSize = NumberType_Int32 ) {
	return LoadFromAddress( GetEntityAddress( iEntity ) + view_as<Address>( iOffset ), iSize );
}
void StoreToEntity( int iEntity, int iOffset, any anValue, NumberType iSize = NumberType_Int32 ) {
	StoreToAddress( GetEntityAddress( iEntity ) + view_as<Address>( iOffset ), anValue, iSize );
}

/*
	DAMAGE FUNCTIONS
*/

/*
	trying to do custom damage handling, not ready yet
*/

//0/4/8: damage force vector
//12/16/20: damage source vector
//24/28/32/: damage reported vector

//36: inflictor
//40: attacker
//44: weapon

//48: damage
//52: max damage
//56: base damage

//60: m_bitsDamageType
//64: m_iDamageCustom
//72: m_iDamageStats appears to be unused
//76: m_iAmmoType appears to be unused
//80: m_iDamagedOtherPlayers appears to be unused
//84: m_iPlayerPenetrationCount appears to be unused
//88: m_flDamageBonus
//92: some sort of consecutive hit detection
//96: 0 always
//100: crit type, game never seems to change from zero

//104: null
//108: ???

//252/256/260: damage vectors
//264/268/272: damage source?
//276/280/284: damage vectors

//288 ???
//292/296/300: appears to be more coordinate data

/*enum {
	DMG_CRITICAL = 20,
	DMG_USEDISTANCEMOD = 21,

}

#define value 48
MRESReturn Hook_OnTakeDamagePre( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	
	Address aDamageInfo = hParams.GetAddress( 1 );
	
	//StoreToAddress( aDamageInfo + view_as<Address>(96), 1, NumberType_Int32 );
	//StoreToAddress( aDamageInfo + view_as<Address>(48), 69.0, NumberType_Int32 );
	int pls = LoadFromAddress( aDamageInfo + view_as<Address>(value) , NumberType_Int32 );
	PrintToServer("%i %f", pls, pls);

	return MRES_Ignored;
}
MRESReturn Hook_OnTakeDamagePost( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	
	Address aDamageInfo = hParams.GetAddress( 1 );
	
	int pls = LoadFromAddress( aDamageInfo + view_as<Address>(value) , NumberType_Int32 );
	PrintToServer("%i %f", pls, pls);

	return MRES_Ignored;
}*/