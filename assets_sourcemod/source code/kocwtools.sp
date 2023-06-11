#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <dhooks>

#include <kocwtools>

//inventory
Handle hEconGetAttributeManager;
Handle hPlayerGetAttributeManager;
Handle hPlayerGetAttributeContainer;
Handle hApplyAttributeFloat;
Handle hIterateAttributes;

Handle hGetEntitySlot;
Handle hGetMedigunCharge;

//think
Handle hSetNextThink;

Handle hFindInRadius;

//damage
DynamicHook hOnTakeDamage;
DynamicHook hOnTakeDamageAlive;
DynamicDetour hModifyRules;

GlobalForward g_OnTakeDamageTF;
GlobalForward g_OnTakeDamagePostTF;
GlobalForward g_OnTakeDamageAliveTF;
GlobalForward g_OnTakeDamageAlivePostTF;

Handle hApplyPushFromDamage;

Address offs_CTFPlayerShared_pOuter;
Address offs_CTFPlayer_mShared;
Address g_iCTFGameStats;

StringMap g_AllocPooledStringCache;

Handle hTakeHealth;
Handle hGetMaxHealth;
Handle hGetBuffedMaxHealth;

Handle hPlayerHealedOther;

public Plugin myinfo =
{
	name = "KOCW Tools",
	author = "Noclue",
	description = "Standard functions for custom weapons.",
	version = "1.2.1",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}


bool bLateLoad = false;
public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max ) {

	bLateLoad = late;

	//string functions
	CreateNative( "AllocPooledString", Native_AllocPooledString );

	//inventory functions
	CreateNative( "AttribHookFloat", Native_AttribHookFloat );
	CreateNative( "AttribHookString", Native_AttribHookString );

	CreateNative( "GetMedigunCharge", Native_GetMedigunCharge );
	CreateNative( "GetEntityInSlot", Native_GetEntitySlot );

	//think functions
	CreateNative( "SetNextThink", Native_SetNextThink );
	//CreateNative( "GetNextThink", Native_GetNextThink );

	//memory functions
	CreateNative( "GetPlayerFromShared", Native_GetPlayerFromShared );
	CreateNative( "GetSharedFromPlayer", Native_GetSharedFromPlayer );

	//damage functions
	CreateNative( "ApplyPushFromDamage", Native_ApplyPushFromDamage );

	CreateNative( "FindEntityInSphere", Native_EntityInRadius );

	CreateNative( "HealPlayer", Native_HealPlayer );

	RegPluginLibrary( "kocwtools" );

	return APLRes_Success;

	
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	HookEvent( EVENT_POSTINVENTORY, Event_PostInventory, EventHookMode_Post );

	/*
		INVENTORY FUNCTIONS
	*/

	//CEconEntity::GetAttributeManager(void)
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CEconEntity::GetAttributeManager");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hEconGetAttributeManager = EndPrepSDKCall();
	if(!hEconGetAttributeManager)
		SetFailState("SDKCall setup for CEconEntity::GetAttributeManager failed");

	//CTFPlayer::GetAttributeManager(void)
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CTFPlayer::GetAttributeManager");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hPlayerGetAttributeManager = EndPrepSDKCall();
	if(!hPlayerGetAttributeManager)
		SetFailState("SDKCall setup for CTFPlayer::GetAttributeManager failed");

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CTFPlayer::GetAttributeContainer");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hPlayerGetAttributeContainer = EndPrepSDKCall();
	if(!hPlayerGetAttributeContainer)
		SetFailState("SDKCall setup for CTFPlayer::GetAttributeContainer failed");

	//CAttributeManager::ApplyAttributeFloat( float flValue, const CBaseEntity *pEntity, string_t strAttributeClass )
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CAttributeManager::ApplyAttributeFloat");
	PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain); //flvalue
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer); //pentity
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); //strattributeclass
	hApplyAttributeFloat = EndPrepSDKCall();
	if(!hApplyAttributeFloat)
		SetFailState("SDKCall setup for CAttributeManager::ApplyAttributeFloat failed");

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CEconItemView::IterateAttributes" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	hIterateAttributes = EndPrepSDKCall();

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

	g_iCTFGameStats = GameConfGetAddress( hGameConf, "CTFGameStats" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFGameStats::Event_PlayerHealedOther" );
	PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	hPlayerHealedOther = EndPrepSDKCall();

	/*
		DAMAGE FUNCTIONS
	*/

	hOnTakeDamage = DynamicHook.FromConf( hGameConf, "CTFPlayer::OnTakeDamage" );
	hOnTakeDamageAlive = DynamicHook.FromConf( hGameConf, "CTFPlayer::OnTakeDamageAlive" );
	hModifyRules = DynamicDetour.FromConf( hGameConf, "CTFGameRules::ApplyOnDamageModifyRules" );

	hModifyRules.Enable( Hook_Pre, Detour_ApplyOnDamageModifyRulesPre );
	hModifyRules.Enable( Hook_Post, Detour_ApplyOnDamageModifyRulesPost );

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayer::ApplyPushFromDamage" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByValue );
	hApplyPushFromDamage = EndPrepSDKCall();
	if ( !hApplyPushFromDamage )
		SetFailState( "SDKCall setup for CTFPlayer::ApplyPushFromDamage failed" );

	if( bLateLoad ) {
		for(int i = 1; i <= MaxClients; i++) {
			if( IsValidEntity( i ) && IsClientInGame( i ) ) {
				DoPlayerHooks( i );
			}
		}
	}

	offs_CTFPlayerShared_pOuter = GameConfGetAddressOffset( hGameConf, "CTFPlayerShared::m_pOuter" );
	offs_CTFPlayer_mShared = GameConfGetAddressOffset( hGameConf, "CTFPlayer::m_Shared" );

	StartPrepSDKCall( SDKCall_EntityList );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CGlobalEntityList::FindEntityInSphere" );
	PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByRef );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	hFindInRadius = EndPrepSDKCall();

	/*
		PLAYER FUNCTIONS
	*/

	//float int player bool
	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFPlayer::TakeHealth" );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL );
	PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	hTakeHealth = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFPlayer::GetMaxHealth" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	hGetMaxHealth = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayerShared::GetBuffedMaxHealth" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	hGetBuffedMaxHealth = EndPrepSDKCall();

	delete hGameConf;

	g_OnTakeDamageTF = new GlobalForward( "OnTakeDamageTF", ET_Ignore, Param_Cell, Param_Cell );
	g_OnTakeDamagePostTF = new GlobalForward( "OnTakeDamagePostTF", ET_Ignore, Param_Cell, Param_Cell );
	g_OnTakeDamageAliveTF = new GlobalForward( "OnTakeDamageAliveTF", ET_Ignore, Param_Cell, Param_Cell );
	g_OnTakeDamageAlivePostTF = new GlobalForward( "OnTakeDamageAlivePostTF", ET_Ignore, Param_Cell, Param_Cell );
}


public void OnMapEnd() {
	g_AllocPooledStringCache.Clear();
}

bool g_bPlayerHooked[MAXPLAYERS+1] = { false, ... };

Action Event_PostInventory( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	if( !g_bPlayerHooked[ iPlayer ] ) {
		DoPlayerHooks( iPlayer );
		g_bPlayerHooked[ iPlayer ] = true;
	}

	return Plugin_Continue;
}
public void OnClientConnected( int iClient ) {
	g_bPlayerHooked[iClient] = false;
}
void DoPlayerHooks( int iPlayer ) {
	hOnTakeDamage.HookEntity( Hook_Pre, iPlayer, Hook_OnTakeDamagePre );
	hOnTakeDamage.HookEntity( Hook_Post, iPlayer, Hook_OnTakeDamagePost );
	hOnTakeDamageAlive.HookEntity( Hook_Pre, iPlayer, Hook_OnTakeDamageAlivePre );
	hOnTakeDamageAlive.HookEntity( Hook_Post, iPlayer, Hook_OnTakeDamageAlivePost );
}

public any Native_EntityInRadius( Handle hPlugin, int iParams ) {
	int iStart = GetNativeCell( 1 );
	float vecSource[3]; GetNativeArray( 2, vecSource, 3 );
	float flRadius = GetNativeCell( 3 );	

	return SDKCall( hFindInRadius, iStart, vecSource, flRadius );
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

	if( !( IsValidEdict( iEntity ) && HasEntProp( iEntity, Prop_Send, "m_AttributeManager" ) ) ){
		return flValue;
	}
	
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


/*
	i tried for several hours to try and read string attributes like a normal person but it always had bizarre issues i couldn't figure out
	so we're down to the most basic level and manually scanning the attribute list
	honestly this was a hail-mary last resort so i'm glad it works
	this will probably break if you try to scan a non-string attribute and it can't be used on the player but whatever it works
*/

//native int AttribHookString( char[] szOutput, int iMaxLen, int iEntity, const char[] szAttribute );
public any Native_AttribHookString( Handle hPlugin, int iParams ) {
	int iEntity = GetNativeCell( 3 );
	
	int iBufferLength;
	GetNativeStringLength( 4, iBufferLength );
	char[] szAttributeClass = new char[ ++iBufferLength ];
	GetNativeString( 4, szAttributeClass, iBufferLength );
	
	Address aWeapon = GetEntityAddress( iEntity );

	int iItemOffset = 1168; //offset of m_Item
	if( !HasEntProp( iEntity, Prop_Send, "m_Item") ) {
		SetNativeString( 1, "", GetNativeCell( 2 ) );
		return 0;
	}
		
	Address aStringAlloc = AllocPooledString( szAttributeClass );
	Address aAttribute = SDKCall( hIterateAttributes, aWeapon + view_as<Address>( iItemOffset ), aStringAlloc );

	if( aAttribute == Address_Null ) {
		SetNativeString( 1, "", GetNativeCell( 2 ) );
		return 0;
	}

	static char szValue[64];
	LoadStringFromAddress( aAttribute + view_as<Address>( 12 ), szValue, 64 );

	SetNativeString( 1, szValue, GetNativeCell( 2 ) );
	return 1;
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

public any Native_GetSharedFromPlayer( Handle hPlugin, int iParams ) {
	int iPlayer = GetNativeCell( 1 );
	return GetEntityAddress( iPlayer ) + view_as<Address>( offs_CTFPlayer_mShared );
}

public any Native_ApplyPushFromDamage( Handle hPlugin, int iParams ) {
	int iPlayer = GetNativeCell( 1 );
	Address aDamageInfo = GetNativeCell( 2 );
	float vecDir[3]; 
	GetNativeArray( 3, vecDir, 3 );

	return SDKCall( hApplyPushFromDamage, iPlayer, aDamageInfo, vecDir );
} 

static Address GameConfGetAddressOffset(Handle hGamedata, const char[] sKey) {
	Address aOffs = view_as<Address>( GameConfGetOffset( hGamedata, sKey ) );
	if ( aOffs == view_as<Address>( -1 ) ) {
		SetFailState( "Failed to get member offset %s", sKey );
	}
	return aOffs;
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

//48: damage
//52: some kind of "base damage"

//72: appears to be unused
//76: appears to be unused
//80: appears to be unused
//84: appears to be unused
//88: m_flDamageBonus
//92: some sort of consecutive hit detection
//96: 0 always

//104: null
//108: ???

//252/256/260: damage vectors
//264/268/272: damage source?
//276/280/284: damage vectors

//288 ???
//292/296/300: appears to be more coordinate data

//player
//6048:	bSeeCrit
//6049:	bMiniCrit
//6050: bShowDisguisedCrit

//6502: effect types

//TakeDamageInfo offsets

enum {
	DMG_CRITICAL = 20,
	DMG_USEDISTANCEMOD = 21,

}

//forward void OnTakeDamageTF( int iTarget, Address aTakeDamageInfo );
MRESReturn Hook_OnTakeDamagePre( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	Call_StartForward( g_OnTakeDamageTF );

	Call_PushCell( iThis );
	Call_PushCell( hParams.GetAddress( 1 ) );

	Call_Finish();

	return MRES_Handled;
}
//forward void OnTakeDamagePostTF( int iTarget, Address aTakeDamageInfo );
MRESReturn Hook_OnTakeDamagePost( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	Call_StartForward( g_OnTakeDamagePostTF );

	Call_PushCell( iThis );
	Call_PushCell( hParams.GetAddress( 1 ) );

	Call_Finish();

	return MRES_Handled;
}
//forward void OnTakeDamageAliveTF( int iTarget, Address aTakeDamageInfo );
MRESReturn Hook_OnTakeDamageAlivePre( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	Call_StartForward( g_OnTakeDamageAliveTF );

	Call_PushCell( iThis );
	Call_PushCell( hParams.GetAddress( 1 ) );

	Call_Finish();

	return MRES_Handled;
}
//forward void OnTakeDamageAlivePostTF( int iTarget, Address aTakeDamageInfo );
MRESReturn Hook_OnTakeDamageAlivePost( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	Call_StartForward( g_OnTakeDamageAlivePostTF );

	Call_PushCell( iThis );
	Call_PushCell( hParams.GetAddress( 1 ) );

	Call_Finish();

	return MRES_Handled;
}


MRESReturn Detour_ApplyOnDamageModifyRulesPre( Address aThis, DHookReturn hReturn, DHookParam hParams ) {
	//TFDamageInfo tfInfo = TFDamageInfo( hParams.GetAddress( 1 ) );
	//tfInfo.iCritType = CT_MINI;

	return MRES_Handled;
}
MRESReturn Detour_ApplyOnDamageModifyRulesPost( Address aThis, DHookReturn hReturn, DHookParam hParams ) {
	TFDamageInfo tfInfo = TFDamageInfo( hParams.GetAddress( 1 ) );
	int iTarget = hParams.Get( 2 );
	//bool bCanDamage = hParams.Get( 3 );

	if( tfInfo.iCritType == CT_MINI ) {
		tfInfo.iFlags = tfInfo.iFlags & ~( 1 << 20 );
		StoreToEntity( iTarget, 6049, 1, NumberType_Int8 ); //6248?
		StoreToEntity( iTarget, 6502, 1, NumberType_Int32 ); //6252?
	}

	return MRES_Handled;
	
}

//native void HealPlayer( int iPlayer, float flAmount, int iSource = -1, int iFlags = 0 );
public any Native_HealPlayer( Handle hPlugin, int iParams ) {
	int iPlayer = GetNativeCell( 1 );
	float flAmount = GetNativeCell( 2 );
	int iSource = GetNativeCell( 3 );
	int iFlags = GetNativeCell( 4 );

	int iMaxHealth = SDKCall( hGetMaxHealth, iPlayer );
	int iHealth = GetClientHealth( iPlayer );

	float flMult = 0.5;

	//TODO: pass weapon as parameter instead of getting activeweapon
	flMult = AttribHookFloat( flMult, iPlayer, "mult_patient_overheal_penalty" );
	int iWeapon = GetEntPropEnt( iPlayer, Prop_Send, "m_hActiveWeapon" );
	if( iWeapon != -1 ) {
		flMult = AttribHookFloat( flMult, iWeapon, "mult_patient_overheal_penalty_active" );
	}

	if( iSource != -1 ) {
		flMult = AttribHookFloat( flMult, iSource, "mult_medigun_overheal_amount" );
	}
	flMult += 1.0;

	int iBuffedMax = RoundFloat( float(iMaxHealth) * flMult );

	if( !( iFlags & HF_NOCRITHEAL ) ) {
		float flTimeSinceDamage = GetGameTime() - GetEntPropFloat( iPlayer, Prop_Send, "m_flLastDamageTime" );
		flAmount *= RemapValClamped( flTimeSinceDamage, 10.0, 15.0, 1.0, 3.0 );
	}
	
	flAmount = MinFloat( float( iBuffedMax - iHealth ), flAmount );

	int iNewFlags = 0;
	if( !( iFlags & HF_NOOVERHEAL ) )
		iNewFlags = 1 << 1;

	int iReturn = SDKCall( hTakeHealth, iPlayer, flAmount, iNewFlags, iSource, false );

	//TODO: account for spy leech event
	if( iSource != -1 ) {
		SDKCall( hPlayerHealedOther, g_iCTFGameStats, iSource, float( iReturn ) );
	}

	return iReturn;
}