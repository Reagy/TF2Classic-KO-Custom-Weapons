#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <dhooks>

#include <kocwtools>
#include <sourcescramble>

DynamicHook g_dhWantsLagCompensation;

//inventory
Handle g_sdkApplyAttributeFloat;
Handle g_sdkIterateAttributes;

Handle g_sdkGetEntitySlot;
Handle g_sdkGetMedigunCharge;

//think
Handle g_sdkSetNextThink;

Handle g_sdkFindInRadius;

//damage
DynamicHook g_dhOnTakeDamage;
DynamicHook g_dhOnTakeDamageAlive;
DynamicDetour g_dtModifyRules;

GlobalForward g_fwdOnTakeDamageTF;
GlobalForward g_fwdOnTakeDamagePostTF;
GlobalForward g_fwdOnTakeDamageAliveTF;
GlobalForward g_fwdOnTakeDamageAlivePostTF;
GlobalForward g_fwdOnTakeDamageBuilding;

Handle g_sdkApplyPushFromDamage;

Address offs_CTFPlayerShared_pOuter;
Address offs_CTFPlayer_mShared;
Address offs_CTFPlayer_pCurrentCommand;
Address g_iCTFGameStats;

Handle g_sdkCreateLagCompensation;
Handle g_sdkDestroyLagCompensation;

StringMap g_smAllocPooledStringCache;

Handle g_sdkTakeHealth;
Handle g_sdkTakeDisguiseHealth;
Handle g_sdkGetMaxHealth;

Handle g_sdkSetSolid;
Handle g_sdkSetSolidFlags;
Handle g_sdkSetGroup;
Handle g_sdkSetSize;

Handle g_sdkHeal;
Handle g_sdkHealTimed;
Handle g_sdkStopHealing;
Handle g_sdkPlayerHealedOther;
Handle g_sdkPlayerLeachedHealth;

public Plugin myinfo =
{
	name = "KOCW Tools",
	author = "Noclue",
	description = "Standard functions for custom weapons.",
	version = "1.8",
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

	//memory functions
	CreateNative( "GetPlayerFromShared", Native_GetPlayerFromShared );
	CreateNative( "GetSharedFromPlayer", Native_GetSharedFromPlayer );

	//damage functions
	CreateNative( "ApplyPushFromDamage", Native_ApplyPushFromDamage );

	CreateNative( "FindEntityInSphere", Native_EntityInRadius );

	CreateNative( "SetSolid", Native_SetSolid );
	CreateNative( "SetSolidFlags", Native_SetSolidFlags );
	CreateNative( "SetCollisionGroup", Native_SetCollisionGroup );
	CreateNative( "SetSize", Native_SetSize );

	CreateNative( "HealPlayer", Native_HealPlayer );
	CreateNative( "AddPlayerHealer", Native_AddPlayerHealer );
	CreateNative( "AddPlayerHealerTimed", Native_AddPlayerHealerTimed );
	CreateNative( "RemovePlayerHealer", Native_RemovePlayerHealer );

	CreateNative( "SetForceLagCompensation", Native_SetForceLagComp );
	CreateNative( "StartLagCompensation", Native_StartLagComp );
	CreateNative( "FinishLagCompensation", Native_EndLagComp );

	RegPluginLibrary( "kocwtools" );

	return APLRes_Success;

	
}

public void OnPluginStart() {
	HookEvent( EVENT_POSTINVENTORY, Event_PostInventory, EventHookMode_Post );
	
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	/*
		OBJECT FUNCTIONS
	*/

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CBaseEntity::SetCollisionGroup" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkSetGroup = EndPrepSDKCallSafe( "CBaseEntity::SetCollisionGroup" );

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CBaseEntity::SetSize" );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByRef );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByRef );
	g_sdkSetSize = EndPrepSDKCallSafe( "CBaseEntity::SetSize" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CCollisionProperty::SetSolid" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkSetSolid = EndPrepSDKCallSafe( "CCollisionProperty::SetSolid" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CCollisionProperty::SetSolidFlags" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkSetSolidFlags = EndPrepSDKCallSafe( "CCollisionProperty::SetSolidFlags" );

	/*
		INVENTORY FUNCTIONS
	*/

	//CAttributeManager::ApplyAttributeFloat( float flValue, const CBaseEntity *pEntity, string_t strAttributeClass )
	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CAttributeManager::ApplyAttributeFloat" );
	PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain); //flvalue
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer); //pentity
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); //strattributeclass
	g_sdkApplyAttributeFloat = EndPrepSDKCallSafe( "CAttributeManager::ApplyAttributeFloat" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CEconItemView::IterateAttributes" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkIterateAttributes = EndPrepSDKCallSafe( "CEconItemView::IterateAttributes" );

	//CEconEntity *CTFPlayer::GetEntityForLoadoutSlot( int iSlot )
	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayer::GetEntityForLoadoutSlot" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //int
	PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
	g_sdkGetEntitySlot = EndPrepSDKCallSafe( "CTFPlayer::GetEntityForLoadoutSlot" );

	//float CTFPlayer::GetMedigunCharge( void )
	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayer::GetMedigunCharge" );
	PrepSDKCall_SetReturnInfo( SDKType_Float, SDKPass_Plain );
	g_sdkGetMedigunCharge = EndPrepSDKCallSafe( "CTFPlayer::GetMedigunCharge" );

	/*
		THINK FUNCTIONS
	*/

	//CBaseEntity::SetNextThink( float thinkTime, const char *szContext )
	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CBaseEntity::SetNextThink" );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	g_sdkSetNextThink = EndPrepSDKCallSafe( "CBaseEntity::SetNextThink" );

	/*
		STRING FUNCTIONS
	*/

	g_smAllocPooledStringCache = new StringMap();

	/*
		MEMORY FUNCTIONS
	*/

	g_iCTFGameStats = GameConfGetAddress( hGameConf, "CTFGameStats" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CEnableLagCompensation::CEnableLagCompensation" );
	PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Pointer );
	g_sdkCreateLagCompensation = EndPrepSDKCallSafe( "CEnableLagCompensation::CEnableLagCompensation" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CEnableLagCompensation::~CEnableLagCompensation" );
	g_sdkDestroyLagCompensation = EndPrepSDKCallSafe( "CEnableLagCompensation::~CEnableLagCompensation" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFGameStats::Event_PlayerHealedOther" );
	PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	g_sdkPlayerHealedOther = EndPrepSDKCallSafe( "CTFGameStats::Event_PlayerHealedOther" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFGameStats::Event_PlayerLeachedHealth" );
	PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	g_sdkPlayerLeachedHealth = EndPrepSDKCallSafe( "CTFGameStats::Event_PlayerHealedOther" );

	/*
		DAMAGE FUNCTIONS
	*/

	g_dhOnTakeDamage = DynamicHookFromConfSafe( hGameConf, "CBaseEntity::OnTakeDamage" );
	g_dhOnTakeDamageAlive = DynamicHookFromConfSafe( hGameConf, "CTFPlayer::OnTakeDamageAlive" );
	g_dtModifyRules = DynamicDetourFromConfSafe( hGameConf, "CTFGameRules::ApplyOnDamageModifyRules" );

	g_dtModifyRules.Enable( Hook_Pre, Detour_ApplyOnDamageModifyRulesPre );
	g_dtModifyRules.Enable( Hook_Post, Detour_ApplyOnDamageModifyRulesPost );

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayer::ApplyPushFromDamage" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByValue );
	g_sdkApplyPushFromDamage = EndPrepSDKCallSafe( "CTFPlayer::ApplyPushFromDamage" );

	g_dhWantsLagCompensation = DynamicHookFromConfSafe( hGameConf, "CTFPlayer::WantsLagCompensationOnEntity" );

	if( bLateLoad ) {
		for(int i = 1; i <= MaxClients; i++) {
			if( IsValidEntity( i ) && IsClientInGame( i ) ) {
				DoPlayerHooks( i );
			}
		}
	}

	offs_CTFPlayerShared_pOuter = GameConfGetAddressOffset( hGameConf, "CTFPlayerShared::m_pOuter" );
	offs_CTFPlayer_mShared = view_as<Address>( FindSendPropInfo( "CTFPlayer", "m_Shared" ) ); //GameConfGetAddressOffset( hGameConf, "CTFPlayer::m_Shared" );
	offs_CTFPlayer_pCurrentCommand = GameConfGetAddressOffset( hGameConf, "CTFPlayer::m_pCurrentCommand" );

	StartPrepSDKCall( SDKCall_EntityList );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CGlobalEntityList::FindEntityInSphere" );
	PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByRef );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	g_sdkFindInRadius = EndPrepSDKCallSafe( "CGlobalEntityList::FindEntityInSphere" );

	/*
		PLAYER FUNCTIONS
	*/

	//float int player bool
	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFPlayer::TakeHealth" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL );
	PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );
	g_sdkTakeHealth = EndPrepSDKCallSafe( "CTFPlayer::TakeHealth" );

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayer::TakeDisguiseHealth" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkTakeDisguiseHealth = EndPrepSDKCallSafe( "CTFPlayer::TakeDisguiseHealth" );

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFPlayer::GetMaxHealth" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkGetMaxHealth = EndPrepSDKCallSafe( "CTFPlayer::GetMaxHealth" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayerShared::Heal" );
	PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL );
	PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );
	g_sdkHeal = EndPrepSDKCallSafe( "CTFPlayerShared::Heal" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayerShared::StopHealing" );
	PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkStopHealing = EndPrepSDKCallSafe( "CTFPlayerShared::StopHealing" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayerShared::HealTimed" );
	PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL );
	g_sdkHealTimed = EndPrepSDKCallSafe( "CTFPlayerShared::HealTimed" );

	delete hGameConf;

	g_fwdOnTakeDamageTF = new GlobalForward( "OnTakeDamageTF", ET_Ignore, Param_Cell, Param_Cell );
	g_fwdOnTakeDamagePostTF = new GlobalForward( "OnTakeDamagePostTF", ET_Ignore, Param_Cell, Param_Cell );
	g_fwdOnTakeDamageAliveTF = new GlobalForward( "OnTakeDamageAliveTF", ET_Ignore, Param_Cell, Param_Cell );
	g_fwdOnTakeDamageAlivePostTF = new GlobalForward( "OnTakeDamageAlivePostTF", ET_Ignore, Param_Cell, Param_Cell );

	g_fwdOnTakeDamageBuilding = new GlobalForward( "OnTakeDamageBuilding", ET_Ignore, Param_Cell, Param_Cell );
}


public void OnMapEnd() {
	g_smAllocPooledStringCache.Clear();
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
	g_dhOnTakeDamage.HookEntity( Hook_Pre, iPlayer, Hook_OnTakeDamagePre );
	g_dhOnTakeDamage.HookEntity( Hook_Post, iPlayer, Hook_OnTakeDamagePost );
	g_dhOnTakeDamageAlive.HookEntity( Hook_Pre, iPlayer, Hook_OnTakeDamageAlivePre );
	g_dhOnTakeDamageAlive.HookEntity( Hook_Post, iPlayer, Hook_OnTakeDamageAlivePost );

	g_dhWantsLagCompensation.HookEntity( Hook_Pre, iPlayer, Hook_ForceLagCompForPlayer );
}

public void OnEntityCreated( int iEntity ) {
	static char szEntityName[ 32 ];
	GetEntityClassname( iEntity, szEntityName, sizeof( szEntityName ) );
	if( StrContains( szEntityName, "obj_", false ) == 0 )
		g_dhOnTakeDamage.HookEntity( Hook_Pre, iEntity, Hook_OnTakeDamageBuilding );
}

public any Native_EntityInRadius( Handle hPlugin, int iParams ) {
	int iStart = GetNativeCell( 1 );
	float vecSource[3]; GetNativeArray( 2, vecSource, 3 );
	float flRadius = GetNativeCell( 3 );	

	return SDKCall( g_sdkFindInRadius, iStart, vecSource, flRadius );
}

/*
	OBJECT FUNCTIONS
*/

//CreateNative( "StartLagCompensation", Native_StartLagComp );
//CreateNative( "FinishLagCompensation", Native_EndLagComp );

//lagcompensation->StartLagCompensation( pOwner, pOwner->GetCurrentCommand() );
//lagcompensation->FinishLagCompensation( pOwner );

/*could not get lag compensation functions to work, the classic team created a class in which lagcomp is started
in the class's constructor and lagcomp is ended in the class's destructor so lagcomp would always clean itself up
when the class went out of scope. just going to allocate some memory and instantiate one because i can't be bothered to
figure out why this isn't working*/
bool g_bForceLagComp = false;

MemoryBlock mbFuckThis;
public any Native_StartLagComp( Handle hPlugin, int iParams ) {
	int iPlayer = GetNativeCell( 1 );
	if( !IsValidPlayer( iPlayer ) )
		return 0;

	Address aUserCmd = LoadFromEntity( iPlayer, view_as<int>( offs_CTFPlayer_pCurrentCommand ) );
	mbFuckThis = new MemoryBlock( 3 );

	SDKCall( g_sdkCreateLagCompensation, mbFuckThis.Address, iPlayer, aUserCmd, true );

	return 0;
}

public any Native_SetForceLagComp( Handle hPlugin, int iParams ) {
	g_bForceLagComp = GetNativeCell( 1 );
	return 0;
}

MRESReturn Hook_ForceLagCompForPlayer( int iPlayer, DHookReturn hReturn, DHookParam hParams ) {
	if( !g_bForceLagComp )
		return MRES_Ignored;

	hReturn.Value = true;
	return MRES_Supercede;
}


public any Native_EndLagComp( Handle hPlugin, int iParams ) {
	int iPlayer = GetNativeCell( 1 );
	if( !IsValidPlayer( iPlayer ) )
		return 0;

	SDKCall( g_sdkDestroyLagCompensation, mbFuckThis.Address );
	delete mbFuckThis;

	return 0;
}


//native void	SetSolid( int iEntity, iSolid );
public any Native_SetSolid( Handle hPlugin, int iParams ) {
	int iEntity, iSolid;
	iEntity = GetNativeCell( 1 );
	iSolid = GetNativeCell( 2 );

	Address aCollision = GetEntityAddress( iEntity ) + address( GetEntSendPropOffs( iEntity, "m_Collision", true ) );
	SDKCall( g_sdkSetSolid, aCollision, iSolid );

	return 0;
}
//native void	SetSolidFlags( int iEntity, int iFlags );
public any Native_SetSolidFlags( Handle hPlugin, int iParams ) {
	int iEntity, iFlags;
	iEntity = GetNativeCell( 1 );
	iFlags = GetNativeCell( 2 );

	Address aCollision = GetEntityAddress( iEntity ) + address( GetEntSendPropOffs( iEntity, "m_Collision", true ) );
	SDKCall( g_sdkSetSolidFlags, aCollision, iFlags );

	return 0;
}
//native void	SetCollisionGroup( int iEntity, int iGroup );
public any Native_SetCollisionGroup( Handle hPlugin, int iParams ) {
	int iEntity, iGroup;
	iEntity = GetNativeCell( 1 );
	iGroup = GetNativeCell( 2 );

	SDKCall( g_sdkSetGroup, iEntity, iGroup );

	return 0;
}
//native void	SetSize( int iEntity, const float vecSizeMin[3], const float vecSizeMax[3] );
public any Native_SetSize( Handle hPlugin, int iParams ) {
	int iEntity;
	float vecSizeMin[3], vecSizeMax[3];
	iEntity = GetNativeCell( 1 );
	GetNativeArray( 2, vecSizeMin, 3 );
	GetNativeArray( 3, vecSizeMax, 3 );

	SDKCall( g_sdkSetSize, iEntity, vecSizeMin, vecSizeMax );

	return 0;
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
	if ( g_smAllocPooledStringCache.GetValue( sValue, aValue ) ) {
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
	Address pOrig = address( GetEntData( iEntity, iOffset ) );
	DispatchKeyValue( iEntity, "targetname", sValue );
	aValue = address( GetEntData( iEntity, iOffset ) );
	SetEntData( iEntity, iOffset, pOrig );
	
	g_smAllocPooledStringCache.SetValue( sValue, aValue );
	return aValue;
}

/*
	ATTRIBUTE FLOAT FUNCTIONS

	AttribHookValue is the function internally used to get float attribute data.
	It simply locates the AttributeManager of the provided entity and calls it's ApplyAttributeFloat/ApplyAttributeString function.
	The function is a template function, and every version except the string_t version was inlined by the compiler, so it's behavior has to be recreated manually.
*/

//todo: these appear to no longer be inlined

//native float AttribHookFloat( float flValue, int iEntity, const char[] sAttributeClass );
public any Native_AttribHookFloat( Handle hPlugin, int iParams ) {
	float flValue = GetNativeCell( 1 );
	int iEntity = GetNativeCell( 2 );
	if( !IsValidEdict( iEntity ) )
		return flValue;

	int iManagerOffset = GetEntSendPropOffs( iEntity, "m_AttributeManager", true );
	if( iManagerOffset == -1 )
		return flValue;
	
	int iBuffer;
	GetNativeStringLength( 3, iBuffer );
	char[] sAttributeClass = new char[ ++iBuffer ];
	GetNativeString( 3, sAttributeClass, iBuffer );

	Address aStringAlloc = AllocPooledString( sAttributeClass ); //string needs to be allocated before the function will recognize it
	Address aManager = GetEntityAddress( iEntity ) + view_as<Address>( iManagerOffset );
		
	return SDKCall( g_sdkApplyAttributeFloat, aManager, flValue, iEntity, aStringAlloc );
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

	//todo: get offset from netprops
	int iItemOffset = 1168; //offset of m_Item
	if( !HasEntProp( iEntity, Prop_Send, "m_Item") ) {
		SetNativeString( 1, "", GetNativeCell( 2 ) );
		return 0;
	}
		
	Address aStringAlloc = AllocPooledString( szAttributeClass );
	Address aAttribute = SDKCall( g_sdkIterateAttributes, aWeapon + address( iItemOffset ), aStringAlloc );

	if( aAttribute == Address_Null ) {
		SetNativeString( 1, "", GetNativeCell( 2 ) );
		return 0;
	}

	static char szValue[64];
	LoadStringFromAddress( aAttribute + address( 12 ), szValue, 64 );

	SetNativeString( 1, szValue, GetNativeCell( 2 ) );
	return 1;
}

public any Native_GetEntitySlot( Handle hPlugin, int iParams ) {
	int iEntity = GetNativeCell( 1 );
	int iIndex = GetNativeCell( 2 );

	return SDKCall( g_sdkGetEntitySlot, iEntity, iIndex );
}

public any Native_GetMedigunCharge( Handle hPlugin, int iParams ) {
	int iEntity = GetNativeCell( 1 );
	return SDKCall( g_sdkGetMedigunCharge, iEntity );
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

	SDKCall( g_sdkSetNextThink, iEntity, flNextThink, sThinkContext );

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

	return SDKCall( g_sdkApplyPushFromDamage, iPlayer, aDamageInfo, vecDir );
} 

static Address GameConfGetAddressOffset(Handle hGamedata, const char[] sKey) {
	Address aOffs = view_as<Address>( GameConfGetOffset( hGamedata, sKey ) );
	if ( aOffs == address( -1 ) ) {
		SetFailState( "Failed to get member offset %s", sKey );
	}
	return aOffs;
}

/*
	DAMAGE FUNCTIONS
*/

//0/4/8: m_vecDamageForce
//12/16/20: m_vecDamagePosition
//24/28/32/: m_vecReportedPosition

//48: damage
//52: some kind of "base damage"

//88: m_flDamageBonus

//player
//6048:	bSeeCrit
//6049:	bMiniCrit
//6050: bShowDisguisedCrit

//6502: effect types

//forward void OnTakeDamageTF( int iTarget, TFDamageInfo tfDamageInfo );
MRESReturn Hook_OnTakeDamagePre( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	if( !IsValidPlayer( iThis ) )
		return MRES_Handled;

	Call_StartForward( g_fwdOnTakeDamageTF );

	Call_PushCell( iThis );
	Call_PushCell( TFDamageInfo( hParams.GetAddress( 1 ) ) );

	Call_Finish();

	return MRES_Handled;
}
//forward void OnTakeDamagePostTF( int iTarget, TFDamageInfo tfDamageInfo );
MRESReturn Hook_OnTakeDamagePost( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	if( !IsValidPlayer( iThis ) )
		return MRES_Handled;

	Call_StartForward( g_fwdOnTakeDamagePostTF );

	Call_PushCell( iThis );
	Call_PushCell( TFDamageInfo( hParams.GetAddress( 1 ) ) );

	Call_Finish();

	return MRES_Handled;
}
//forward void OnTakeDamageAliveTF( int iTarget, TFDamageInfo tfDamageInfo );
MRESReturn Hook_OnTakeDamageAlivePre( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	if( !IsValidPlayer( iThis ) )
		return MRES_Handled;

	Call_StartForward( g_fwdOnTakeDamageAliveTF );

	Call_PushCell( iThis );
	Call_PushCell( TFDamageInfo( hParams.GetAddress( 1 ) ) );

	Call_Finish();

	return MRES_Handled;
}
//forward void OnTakeDamageAlivePostTF( int iTarget, TFDamageInfo tfDamageInfo );
MRESReturn Hook_OnTakeDamageAlivePost( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	if( !IsValidPlayer( iThis ) )
		return MRES_Handled;

	Call_StartForward( g_fwdOnTakeDamageAlivePostTF );

	Call_PushCell( iThis );
	Call_PushCell( TFDamageInfo( hParams.GetAddress( 1 ) ) );

	Call_Finish();

	return MRES_Handled;
}

//forward void OnTakeDamageBuilding( int iBuilding, TFDamageInfo tfDamageInfo );
MRESReturn Hook_OnTakeDamageBuilding( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	Call_StartForward( g_fwdOnTakeDamageBuilding );

	Call_PushCell( iThis );
	Call_PushCell( TFDamageInfo( hParams.GetAddress( 1 ) ) );

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
		//todo: move to gamedata
		StoreToEntity( iTarget, 6049, 1, NumberType_Int8 ); //6248?
		StoreToEntity( iTarget, 6502, 1, NumberType_Int32 ); //6252?
	}

	return MRES_Handled;
	
}

//native void AddPlayerHealer( int iReciever, int iSource, float flRate, bool bAllowCritHeals = true )
public any Native_AddPlayerHealer( Handle hPlugin, int iParams ) {
	int iReceiver = GetNativeCell( 1 );
	int iSource = GetNativeCell( 2 );
	float flRate = GetNativeCell( 3 );
	bool bAllowCritHeals = GetNativeCell( 4 );

	if( !IsValidPlayer( iReceiver ) || !IsValidPlayer( iSource ) )
		return 0;

	SDKCall( g_sdkHeal, GetSharedFromPlayer( iReceiver ), iSource, flRate, -1, false, bAllowCritHeals );

	return 0;
}
//native void AddPlayerHealerTimed( int iReciever, int iSource, float flRate, float flDuration, bool bReset, bool bOverheal )
public any Native_AddPlayerHealerTimed( Handle hPlugin, int iParams ) {
	int iReceiver = GetNativeCell( 1 );
	int iSource = GetNativeCell( 2 );
	float flRate = GetNativeCell( 3 );
	float flDuration = GetNativeCell( 4 );
	bool bResetDuration = GetNativeCell( 5 );
	bool bAllowOverheal = GetNativeCell( 6 );

	if( !IsValidPlayer( iReceiver ) || !IsValidPlayer( iSource ) )
		return 0;

	SDKCall( g_sdkHealTimed, GetSharedFromPlayer( iReceiver ), iSource, flRate, flDuration, bResetDuration, bAllowOverheal, -1 );

	return 0;
}

//native void RemovePlayerHealer( int iReceiver, int iSource, int iHealerType )
public any Native_RemovePlayerHealer( Handle hPlugin, int iParams ) {
	int iReceiver = GetNativeCell( 1 );
	int iSource = GetNativeCell( 2 );
	int iHealerType = GetNativeCell( 3 );

	if( !IsValidPlayer( iReceiver ) || !IsValidPlayer( iSource ) )
		return 0;

	SDKCall( g_sdkStopHealing, GetSharedFromPlayer( iReceiver ), iSource, iHealerType );

	return 0;
}

//native void HealPlayer( int iPlayer, float flAmount, int iSource = -1, int iFlags = 0 );
float g_flHealAccumulator[MAXPLAYERS+1] = { 0.0, ... };
public any Native_HealPlayer( Handle hPlugin, int iParams ) {
	int iPlayer = GetNativeCell( 1 );
	float flHealAmount = GetNativeCell( 2 );
	int iSource = GetNativeCell( 3 );
	int iFlags = GetNativeCell( 4 );

	int iMaxHealth = SDKCall( g_sdkGetMaxHealth, iPlayer );
	int iHealth = GetClientHealth( iPlayer );

	float flOverhealMult = AttribHookFloat( 0.5, iPlayer, "mult_patient_overheal_penalty" );
	int iWeapon = GetEntPropEnt( iPlayer, Prop_Send, "m_hActiveWeapon" );
	if( iWeapon != -1 ) {
		flOverhealMult = AttribHookFloat( flOverhealMult, iWeapon, "mult_patient_overheal_penalty_active" );
	}
	flOverhealMult += 1.0;

	float flBuffedMax = flOverhealMult * iMaxHealth;
	int iBuffedMax = RoundToFloor( flBuffedMax / 5.0 ) * 5;

	if( !( iFlags & HF_NOCRITHEAL ) ) {
		float flTimeSinceDamage = GetGameTime() - GetEntPropFloat( iPlayer, Prop_Send, "m_flLastDamageTime" );
		flHealAmount *= RemapValClamped( flTimeSinceDamage, 10.0, 15.0, 1.0, 3.0 );
	}

	flHealAmount += g_flHealAccumulator[ iPlayer ];
	float flHealRounded = float( RoundToFloor( flHealAmount ) );
	g_flHealAccumulator[ iPlayer ] = flHealAmount - flHealRounded;
	//PrintToServer("%f %f %f", flHealAmount, flHealRounded, g_flHealAccumulator[ iPlayer ] );

	flHealRounded = MinFloat( float( iBuffedMax - iHealth ), flHealAmount );

	int iNewFlags = 0;
	if( !( iFlags & HF_NOOVERHEAL ) )
		iNewFlags = 1 << 1;

	int iReturn = SDKCall( g_sdkTakeHealth, iPlayer, flHealRounded, iNewFlags, iSource, false );

	if( iSource != -1 ) {
		SDKCall( g_sdkPlayerHealedOther, g_iCTFGameStats, iSource, float( iReturn ) );

		if( GetEntProp( iSource, Prop_Send, "m_iTeamNum" ) != GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) ) {
			SDKCall( g_sdkTakeDisguiseHealth, iPlayer, flHealRounded, false );
			SDKCall( g_sdkPlayerLeachedHealth, g_iCTFGameStats, iPlayer, false, float( iReturn ) );
		}
	}

	return iReturn;
}