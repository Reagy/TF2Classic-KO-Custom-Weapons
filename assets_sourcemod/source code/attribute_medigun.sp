#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <kocwtools>
#include <condhandler>
#include <hudframework>
#include <custom_entprops>

//hydro pump
#define HYDRO_PUMP_HEAL_RATE 36.0
#define HYDRO_PUMP_AFTERHEAL_RATE 5.0
#define HYDRO_PUMP_AFTERHEAL_MAX_LENGTH 4.0
#define HYDRO_PUMP_CHARGE_TIME 40.0
static char g_szHydropumpTrackerName[32] = "Ubercharge";
static char g_szHydropumpHealSound[] = "weapons/HPump_Hit.wav";

#define FLAMETHROWER_FIRING_INTERVAL 0.04

//guardian angel
#define ANGEL_UBER_COST 0.33 //uber cost to grant bubble
#define ANGEL_SELF_BUBBLE false //whether medic receives a bubble when using uber
static char g_szAngelShieldSound[] = "weapons/angel_shield_on.wav";

DynamicHook	g_dhWeaponSecondary;

DynamicDetour	g_dtFireCollide;
DynamicDetour	g_dtFireCollideTeam;

DynamicHook	g_dhWeaponPostframe;
DynamicHook	g_dhWeaponHolster;
DynamicHook	g_dhWeaponDeploy;

Handle		g_sdkAddFlameTouchList;
Handle		g_sdkGetBuffedMaxHealth;
Handle		g_sdkSpeakIfAllowed;

int g_iRefEHandleOffset = -1;
int g_iFlameBurnedVectorOffset = -1;
int g_iFlameOwnerOffset = -1;
int g_iCUtlVectorSizeOffset = -1;
int g_iHealerVecOffset = -1;

PlayerFlags g_pfPlayingSound;
float g_flEndHealSoundTime[MAXPLAYERS+1] = { 0.0, ... };
int g_iHydroPumpBarrelChargedEmitters[MAXPLAYERS+1][2];

Address g_pCTFGameRules = Address_Null;
int	g_iSetupOffset = -1;

ConVar g_cvMedigunCritBoost; int g_iMedigunCritBoostVal;

enum {
	CMEDI_ANGEL = 1,
	CMEDI_DUMMY1 = 2,
	CMEDI_QFIX = 3,
	CMEDI_DUMMY2 = 4,
	CMEDI_DUMMY3 = 5,
	CMEDI_FLAME = 6,
}

public Plugin myinfo =
{
	name = "Attribute: Mediguns",
	author = "Noclue",
	description = "Atributes for Mediguns.",
	version = "1.4",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

bool bLateLoad;
public APLRes AskPluginLoad2( Handle myself, bool bLate, char[] error, int err_max ) {
	bLateLoad = bLate;

	return APLRes_Success;
}

public void OnPluginStart() {
	for( int i = 1; i < MAXPLAYERS+1; i++ ) {
		g_iHydroPumpBarrelChargedEmitters[i][0] = INVALID_ENT_REFERENCE;
		g_iHydroPumpBarrelChargedEmitters[i][1] = INVALID_ENT_REFERENCE;
	}

	HookEvent( "post_inventory_application", Event_PostInventory );
	HookEvent( "player_death", Event_PlayerDeath );

	g_cvMedigunCritBoost = FindConVar( "tf2c_medigun_critboostable" );
	g_cvMedigunCritBoost.AddChangeHook( OnCritMedigunChange );

	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "m_hEntitiesBurnt::InsertBefore" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_ByRef );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkAddFlameTouchList = EndPrepSDKCallSafe( "m_hEntitiesBurnt::InsertBefore" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayerShared::GetBuffedMaxHealth" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkGetBuffedMaxHealth = EndPrepSDKCallSafe( "CTFPlayerShared::GetBuffedMaxHealth" );

	//int iConcept, const char *modifiers = NULL, char *pszOutResponseChosen = NULL, size_t bufsize = 0, IRecipientFilter *filter = NULL
	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayer::SpeakConceptIfAllowed" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //size_t is 64 bit so we need to do this
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL );
	g_sdkSpeakIfAllowed = EndPrepSDKCallSafe( "CTFPlayer::SpeakConceptIfAllowed" );

	g_dhWeaponSecondary = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::SecondaryAttack" );

	g_dtFireCollide = DynamicDetourFromConfSafe( hGameConf, "CTFFlameEntity::OnCollide" );
	g_dtFireCollide.Enable( Hook_Pre, Detour_FireTouch );
	g_dtFireCollideTeam = DynamicDetourFromConfSafe( hGameConf, "CTFFlameEntity::OnCollideWithTeammate" );
	g_dtFireCollideTeam.Enable( Hook_Pre, Detour_FireTouchTeam );

	g_iRefEHandleOffset = GameConfGetOffsetSafe( hGameConf, "CBaseEntity::m_RefEHandle" );
	g_iHealerVecOffset = GameConfGetOffsetSafe( hGameConf, "CTFPlayerShared::m_vecHealers" );
	g_iFlameBurnedVectorOffset = GameConfGetOffsetSafe( hGameConf, "CTFFlameEntity::m_hEntitiesBurnt" );
	g_iFlameOwnerOffset = GameConfGetOffsetSafe( hGameConf, "CTFFlameEntity::m_hOwner" );
	g_iCUtlVectorSizeOffset = GameConfGetOffsetSafe( hGameConf, "CUtlVector::m_Size" );
	g_pCTFGameRules = GameConfGetAddress( hGameConf, "CTFGameRules" );
	g_iSetupOffset = FindSendPropInfo( "CTFGameRulesProxy", "m_bInSetup" );

	g_dhWeaponDeploy = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::Deploy" );
	g_dhWeaponHolster = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::Holster" );
	g_dhWeaponPostframe = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::ItemPostFrame" );

	delete hGameConf;

	if( bLateLoad ) {
		int iIndex = MaxClients + 1;
		while( ( iIndex = FindEntityByClassname( iIndex, "tf_weapon_medigun" ) ) != -1 ) {
			HookMedigun( iIndex );
		}

		iIndex = MaxClients + 1;
		while( ( iIndex = FindEntityByClassname( iIndex, "tf_weapon_flamethrower" ) ) != -1 ) {
			Frame_SetupFlamethrower( iIndex );
		}
	}
}

public void OnPluginEnd() {
	for( int i = 1; i < MAXPLAYERS+1; i++ ) {
		DestroyPumpChargedMuzzle( i );
	}
}

void OnCritMedigunChange( ConVar cvChanged, char[] szOld, char[] szNew ) {
	int iNew = StringToInt( szNew );
	g_iMedigunCritBoostVal = iNew;
}

public void OnMapStart() {
	PrecacheSound( g_szAngelShieldSound );
	PrecacheSound( g_szHydropumpHealSound );

	g_pfPlayingSound.SetDirect( 0, 0 );
	g_pfPlayingSound.SetDirect( 1, 0 );

	for( int i = 1; i < MAXPLAYERS+1; i++ ) {
		g_flEndHealSoundTime[ i ] = 0.0;
	}
}

public void OnEntityCreated( int iThis, const char[] szClassname ) {
	if( strcmp( szClassname, "tf_weapon_medigun", false ) == 0 )
		HookMedigun( iThis );
	else if( strcmp( szClassname, "tf_weapon_flamethrower", false ) == 0 )
		RequestFrame( Frame_SetupFlamethrower, EntIndexToEntRef( iThis ) ); //attributes don't seem to be setup yet
}

Action Event_PostInventory( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	if( !IsValidPlayer( iPlayer ) )
		return Plugin_Continue;

	if( RoundToFloor( AttribHookFloat( 0.0, iPlayer, "custom_medigun_type" ) ) == CMEDI_FLAME ) {
		Tracker_Create( iPlayer, g_szHydropumpTrackerName, false );
		Tracker_SetMax( iPlayer, g_szHydropumpTrackerName, 100.0 );
		Tracker_SetFlags( iPlayer, g_szHydropumpTrackerName, RTF_CLEARONSPAWN | RTF_PERCENTAGE );
	}
	else {
		Tracker_Remove( iPlayer, g_szHydropumpTrackerName );
	}

	return Plugin_Continue;
}

void Frame_SetupFlamethrower( int iFlamethrower ) {
	iFlamethrower = EntRefToEntIndex( iFlamethrower );
	if( iFlamethrower == -1 )
		return;

	int iAttrib = RoundToFloor( AttribHookFloat( 0.0, iFlamethrower, "custom_medigun_type" ) );
	if( iAttrib == CMEDI_FLAME ) {
		g_dhWeaponPostframe.HookEntity( Hook_Pre, iFlamethrower, Hook_HydroPumpPostFrame );
		g_dhWeaponDeploy.HookEntity( Hook_Pre, iFlamethrower, Hook_HydroPumpDeploy );
		g_dhWeaponHolster.HookEntity( Hook_Pre, iFlamethrower, Hook_HydroPumpHolster );
	}
}

void HookMedigun( int iMedigun ) {
	g_dhWeaponSecondary.HookEntity( Hook_Pre, iMedigun, Hook_MedigunSecondaryPre );
	g_dhWeaponPostframe.HookEntity( Hook_Post, iMedigun, Hook_ItemPostFrame );
	g_dhWeaponHolster.HookEntity( Hook_Post, iMedigun, Hook_MedigunHolster );
}

MRESReturn Hook_MedigunHolster( int iThis ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );

	if( IsValidPlayer( iOwner ) ) {
		if( HasCustomCond( iOwner, TFCC_ANGELSHIELD ) && GetCustomCondSourcePlayer( iOwner, TFCC_ANGELSHIELD ) == iOwner ) {
			SetCustomCondLevel( iOwner, TFCC_ANGELSHIELD, 0 );
			RemoveCustomCond( iOwner, TFCC_ANGELSHIELD );
		}

		SetEntPropEnt( iThis, Prop_Send, "m_hHealingTarget", -1 );
	}
	return MRES_Handled;
}

MRESReturn Hook_MedigunSecondaryPre( int iThis ) {
	switch( RoundToNearest( AttribHookFloat( 0.0, iThis, "custom_medigun_type" ) ) ) {
	case CMEDI_ANGEL: {
		AngelGunUber( iThis );
		return MRES_Supercede;
	}	
	}

	return MRES_Ignored;
}

MRESReturn Hook_ItemPostFrame( int iMedigun ) {
	int iTarget = GetEntPropEnt( iMedigun, Prop_Send, "m_hHealingTarget" );
	int iOwner = GetEntPropEnt( iMedigun, Prop_Send, "m_hOwnerEntity" );

	if( !GetEntProp( iMedigun, Prop_Send, "m_bChargeRelease" ) )
		return MRES_Handled;

	//uber handling
	int iMediType = RoundToFloor( AttribHookFloat( 0.0, iMedigun, "custom_medigun_type" ) );
	switch( iMediType ) {
		case CMEDI_QFIX: {
			PulseCustomUber( iMedigun, TFCC_QUICKUBER, iTarget, iOwner );
		}
	}

	return MRES_Handled;
}

void PulseCustomUber( int iMedigun, int iType, int iTarget, int iOwner ) {
	int iPlayers[2];
	iPlayers[ 0 ] = iOwner;
	iPlayers[ 1 ] = iTarget;
	for( int i = 0; i < 2; i++ ) {
		if( iPlayers[ i ] == -1 )
			continue;

		if( !HasCustomCond( iPlayers[ i ], iType ) )
			AddCustomCond( iPlayers[ i ], iType );

		SetCustomCondDuration( iPlayers[ i ], iType, 0.1, false );

		SetCustomCondSourcePlayer( iPlayers[ i ], iType, iOwner );
		SetCustomCondSourceWeapon( iPlayers[ i ], iType, iMedigun );
	}
}

/*
	GUARDIAN ANGEL
*/

void AngelGunUber( int iMedigun ) {
	float flChargeLevel = GetEntPropFloat( iMedigun, Prop_Send, "m_flChargeLevel" );
	if( flChargeLevel < ANGEL_UBER_COST )
		return;

	SetEntProp( iMedigun, Prop_Send, "m_bChargeRelease", false );
	
	int iOwner = GetEntPropEnt( iMedigun, Prop_Send, "m_hOwnerEntity" );
	int iTarget = GetEntPropEnt( iMedigun, Prop_Send, "m_hHealingTarget" );

#if ANGEL_SELF_BUBBLE == true
	int iApplyTo[2];
	iApplyTo[0] = iOwner;
	iApplyTo[1] = iTarget;

	bool bApplied = false;

	for( int i = 0; i < 2; i++ ) {
		int iGive = iApplyTo[i];
		if( iGive == -1 )
			continue;

		if( HasCustomCond( iGive, TFCC_ANGELSHIELD ) || HasCustomCond( iGive, TFCC_ANGELINVULN ) )
			continue;

		AddCustomCond( iGive, TFCC_ANGELSHIELD );
		SetCustomCondSourcePlayer( iGive, TFCC_ANGELSHIELD, iOwner );
		SetCustomCondSourceWeapon( iGive, TFCC_ANGELSHIELD, iMedigun );
		
		bApplied = true;
	}

	if( bApplied ) {
		EmitSoundToAll( g_szAngelShieldSound, iOwner, SNDCHAN_WEAPON, 85 );
		SetEntPropFloat( iMedigun, Prop_Send, "m_flChargeLevel", flChargeLevel - ANGEL_UBER_COST );
		return;
	}

	return;
#else
	if( iTarget == -1 )
		return;

	if( HasCustomCond( iTarget, TFCC_ANGELSHIELD ) || HasCustomCond( iTarget, TFCC_ANGELINVULN ) )
		return;

	AddCustomCond( iTarget, TFCC_ANGELSHIELD );
	SetCustomCondSourcePlayer( iTarget, TFCC_ANGELSHIELD, iOwner );
	SetCustomCondSourceWeapon( iTarget, TFCC_ANGELSHIELD, iMedigun );

	EmitSoundToAll( g_szAngelShieldSound, iOwner, SNDCHAN_WEAPON, 85 );
	SetEntPropFloat( iMedigun, Prop_Send, "m_flChargeLevel", flChargeLevel - ANGEL_UBER_COST );
	return;
#endif
}

/*
	HYDRO PUMP
*/

int g_iOldButtons[MAXPLAYERS+1];
MRESReturn Hook_HydroPumpPostFrame( int iThis ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	if( iOwner == -1 )
		return MRES_Ignored;

	int iWeaponMode = GetEntProp( iThis, Prop_Send, "m_iWeaponState" );

	bool bNotFiring = iWeaponMode == 0;
	bool bTimeToEnd = g_flEndHealSoundTime[ iOwner ] != 0.0 && g_flEndHealSoundTime[ iOwner ] <= GetGameTime();
	if( bNotFiring || bTimeToEnd ) {
		EndHydropumpHitSound( iOwner );
	}

	int iButtons = GetClientButtons( iOwner );
	if( iButtons & IN_ATTACK2 && !( g_iOldButtons[ iOwner ] & IN_ATTACK2 ) ) {
		if( !HasCustomCond( iOwner, TFCC_HYDROUBER ) )
			Tracker_SetValue( iOwner, g_szHydropumpTrackerName, 100.0 );

		if( Tracker_GetValue( iOwner, g_szHydropumpTrackerName ) >= 100.0 && !HasCustomCond( iOwner, TFCC_HYDROUBER ) ) {
			AddCustomCond( iOwner, TFCC_HYDROUBER, iOwner, iThis );

			SpeakConceptIfAllowed( iOwner, 38 ); //38 = MP_CONCEPT_MEDIC_CHARGEDEPLOYED
		}
	}
	g_iOldButtons[ iOwner ] = iButtons;

	return MRES_Handled;
}
MRESReturn Hook_HydroPumpDeploy( int iThis, DHookReturn hReturn ) {
	RequestFrame( Frame_Test, iThis );
	return MRES_Handled;
}
void Frame_Test( int iThis ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	if( iOwner != -1 && Tracker_GetValue( iOwner, g_szHydropumpTrackerName ) >= 100.0 )
		CreatePumpChargedMuzzle( iThis, iOwner );
}
MRESReturn Hook_HydroPumpHolster( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	if( iOwner != -1 ) {
		DestroyPumpChargedMuzzle( iOwner );
		EndHydropumpHitSound( iOwner );
	}

	return MRES_Handled;
}

//apparently tf2c flame particles aren't even derived from cbaseentity so they're passed by address instead
MRESReturn Detour_FireTouch( Address aThis, DHookParam hParams ) {
	int iCollide = hParams.Get( 1 );
	return FireTouchHandle( aThis, iCollide );
}
MRESReturn Detour_FireTouchTeam( Address aThis, DHookParam hParams ) {
	int iCollide = hParams.Get( 1 );
	return FireTouchHandle( aThis, iCollide );
}

MRESReturn FireTouchHandle( Address aThis, int iCollide ) {
	int iOwner = LoadEntityHandleFromAddress( aThis + view_as<Address>( g_iFlameOwnerOffset ) );
	if( !IsValidPlayer( iOwner ) )
		return MRES_Ignored;

	int iWeapon = GetEntityInSlot( iOwner, 1 );
	if( RoundToNearest( AttribHookFloat( 0.0, iWeapon, "custom_medigun_type" ) ) != CMEDI_FLAME )
		return MRES_Ignored;

	if( IsValidPlayer( iCollide ) && GetEntProp( iOwner, Prop_Send, "m_iTeamNum" ) == TeamSeenBy( iOwner, iCollide ) )
		FireTouchHeal( aThis, iCollide, iOwner, iWeapon );

	return MRES_Supercede;
}
void FireTouchHeal( Address aThis, int iCollide, int iOwner, int iWeapon ) {
	//AddPlayerHealerTimed( iCollide, iOwner, FLAMETHROWER_HEAL_RATE * ( 1.0 - FLAMETHROWER_IMMEDIATE_PERCENTAGE ), 5.0, true, true );
	
	//scuffed code to force crit heals on timed healer
	//todo: move to gamedata
	/*const int iHealerStructSize = 48;
	const int iCritHealsOffset = 33;

	Address aShared = GetSharedFromPlayer( iCollide );
	Address aVectorStart = LoadFromAddressOffset( aShared, g_iHealerVecOffset, NumberType_Int32 );
	int iSize = LoadFromAddressOffset( aShared, g_iHealerVecOffset + g_iCUtlVectorSizeOffset, NumberType_Int32 );
	Address aHealer = aVectorStart + view_as<Address>( iHealerStructSize * ( iSize - 1 ) );
	StoreToAddressOffset( aHealer, iCritHealsOffset, true, NumberType_Int8 );*/
	//end scuffed

	//float flRate = ( HYDRO_PUMP_HEAL_RATE * FLAMETHROWER_FIRING_INTERVAL );
	float flRate = 1.44; //precalculated
	
	flRate = AttribHookFloat( flRate, iOwner, "mult_medigun_healrate" );

	if( g_iMedigunCritBoostVal ) {
		if( g_iMedigunCritBoostVal == 2 && IsPlayerCritBoosted( iOwner ) ) {
			flRate *= 3.0;
		}
		else if( IsPlayerMiniCritBoosted( iOwner ) ) {
			flRate *= 1.35;
		}
	}

	HealPlayer( iCollide, flRate, iOwner );

	SetFlameHealSoundTime( iOwner, iWeapon );

	if( !HasCustomCond( iOwner, TFCC_HYDROUBER ) )
		HydroPumpBuildUber( iOwner, iCollide, iWeapon );

	AddCustomCond( iCollide, TFCC_HYDROPUMPHEAL, iOwner, iWeapon );
	
	//precalculated
	//float flNewDuration = FloatClamp( GetCustomCondDuration( iCollide, TFCC_HYDROPUMPHEAL ) + ( FLAMETHROWER_FIRING_INTERVAL * 2.5 ), 0.5, HYDRO_PUMP_AFTERHEAL_MAX_LENGTH );
	float flNewDuration = FloatClamp( GetCustomCondDuration( iCollide, TFCC_HYDROPUMPHEAL ) + 0.1, 0.5, HYDRO_PUMP_AFTERHEAL_MAX_LENGTH );
	float flNewLevel = MaxFloat( HYDRO_PUMP_AFTERHEAL_RATE, GetCustomCondLevel( iCollide, TFCC_HYDROPUMPHEAL ) );

	SetCustomCondDuration( iCollide, TFCC_HYDROPUMPHEAL, flNewDuration, false );
	SetCustomCondLevel( iCollide, TFCC_HYDROPUMPHEAL, flNewLevel );

	//this appends to the flame's internal list that keeps track of who it has hit
	SDKCall( g_sdkAddFlameTouchList, 
		aThis + view_as<Address>( g_iFlameBurnedVectorOffset ),
		LoadFromAddressOffset( aThis, g_iFlameBurnedVectorOffset + g_iCUtlVectorSizeOffset, NumberType_Int32 ),
		LoadFromEntity( iCollide, g_iRefEHandleOffset ) );
}

void HydroPumpBuildUber( int iOwner, int iTarget, int iWeapon ) {
	//float flChargeAmount = (FLAMETHROWER_FIRING_INTERVAL / HYDRO_PUMP_CHARGE_TIME) * 100.0;
	float flChargeAmount = 0.1; //precalculated version of above because the compiler does not precalculate float constants (not a constant expression?)
	//float flChargeAmount = 100.0; //for testing

	int iTargetHealth = GetClientHealth( iTarget );
	int iTargetBuffedHealth = SDKCall( g_sdkGetBuffedMaxHealth, GetSharedFromPlayer( iTarget ) );
	if( iTargetHealth >= RoundToFloor( iTargetBuffedHealth * 0.95 ) )
		flChargeAmount *= 0.5;

	bool bIsInSetup;
	Address g_aCTFGameRules = LoadFromAddress( g_pCTFGameRules, NumberType_Int32 );
	if( g_aCTFGameRules != Address_Null ) {
		bIsInSetup = LoadFromAddressOffset( g_aCTFGameRules, g_iSetupOffset, NumberType_Int8 );
		if( bIsInSetup )
			flChargeAmount *= 3.0;
	}

	if( g_iMedigunCritBoostVal ) {
		if( g_iMedigunCritBoostVal == 2 && IsPlayerCritBoosted( iOwner ) ) {
			flChargeAmount *= 3.0;
		}
		else if( IsPlayerMiniCritBoosted( iOwner ) ) {
			flChargeAmount *= 1.35;
		}
	}

	int iHealerCount = GetEntProp( iTarget, Prop_Send, "m_nNumHumanHealers" );
	if( !bIsInSetup && iHealerCount > 1 ) {
		flChargeAmount /= iHealerCount;
	}

	int iOwnerHealingCount = 0;
	GetCustomProp( iOwner, "m_iHydroHealing", iOwnerHealingCount );
	float flMult = iOwnerHealingCount > 1 ? Pow( 0.9, float( iOwnerHealingCount ) ) : 1.0;
	flChargeAmount *= flMult;

	float flOldValue = Tracker_GetValue( iOwner, g_szHydropumpTrackerName );
	float flNewValue = flOldValue + flChargeAmount;
	if( flOldValue < 100.0 && flNewValue >= 100.0 ) {
		CreatePumpChargedMuzzle( iWeapon, iOwner );
		SpeakConceptIfAllowed( iOwner, 36 ); //36 = MP_CONCEPT_MEDIC_CHARGEREADY
	}

	Tracker_SetValue( iOwner, g_szHydropumpTrackerName, flNewValue );
}

void SetFlameHealSoundTime( int iOwner, int iWeapon ) {
	g_flEndHealSoundTime[ iOwner ] = GetGameTime() + 0.2;

	if( !g_pfPlayingSound.Get( iOwner ) && GetEntProp( iWeapon, Prop_Send, "m_iWeaponState" ) != 0 ) {
		g_pfPlayingSound.Set( iOwner, true );
		EmitSoundToAll( g_szHydropumpHealSound, iOwner );
		//EmitSoundToAll( g_szHydropumpHealSound, iOwner, .flags = SND_CHANGEVOL, .volume = 0.75 );
	}
}

void EndHydropumpHitSound( int iOwner ) {
	g_flEndHealSoundTime[ iOwner ] = 0.0;
	g_pfPlayingSound.Set( iOwner, false );
	StopSound( iOwner, 0, g_szHydropumpHealSound );
}

static char g_szHydropumpMuzzleParticles[][] = {
	"mediflame_muzzle_red",
	"mediflame_muzzle_blue",
	"mediflame_muzzle_green",
	"mediflame_muzzle_yellow"
};

void CreatePumpChargedMuzzle( int iWeapon, int iOwner ) {
	int iTeam = GetEntProp( iOwner, Prop_Send, "m_iTeamNum" ) - 2;
	DestroyPumpChargedMuzzle( iOwner );

	//first person
	int iParticle = CreateParticle( g_szHydropumpMuzzleParticles[ iTeam ] );
	ParentParticleToViewmodelEX( iParticle, iWeapon, "weapon_bone" );
	SetEntPropEnt( iParticle, Prop_Send, "m_hOwnerEntity", iOwner );
	SDKHook( iParticle, SDKHook_SetTransmit, Hook_EmitterTransmitFP );
	SetEdictFlags( iParticle, 0 );
	g_iHydroPumpBarrelChargedEmitters[iOwner][0] = EntIndexToEntRef( iParticle );

	//third person

	iParticle = CreateParticle( g_szHydropumpMuzzleParticles[ iTeam ] );
	ParentModel( iParticle, iWeapon, "weapon_bone" ); //i have no idea why weapon bone works for this i hate this fucking engine so much
	SetEntPropEnt( iParticle, Prop_Send, "m_hOwnerEntity", iOwner );
	SDKHook( iParticle, SDKHook_SetTransmit, Hook_EmitterTransmitTP );
	SetEdictFlags( iParticle, 0 );
	g_iHydroPumpBarrelChargedEmitters[iOwner][1] = EntIndexToEntRef( iParticle );

	CreateTimer( 0.2, Timer_RemoveChargedMuzzle, EntRefToEntIndex( iOwner ), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );

	//EmitSound( iOwner, "" );
}

Action Timer_RemoveChargedMuzzle( Handle hTimer, int iOwnerRef ) {
	int iOwner = EntRefToEntIndex( iOwnerRef );
	if( iOwner == -1 ) {
		return Plugin_Stop;
	}

	if( Tracker_GetValue( iOwner, g_szHydropumpTrackerName ) <= 0.0 ) {
		DestroyPumpChargedMuzzle( iOwner );
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

void DestroyPumpChargedMuzzle( int iOwner ) {
	for( int i = 0; i < 2; i++ ) {
		int iEntity = EntRefToEntIndex( g_iHydroPumpBarrelChargedEmitters[iOwner][i] );
		if( iEntity == -1 )
			continue;

		RemoveEntity( iEntity );
		g_iHydroPumpBarrelChargedEmitters[iOwner][i] = INVALID_ENT_REFERENCE;

		//EmitSound( iOwner, "" );
	}
}

Action Hook_EmitterTransmitFP( int iEntity, int iClient ) {
	SetEdictFlags( iEntity, 0 );
	return iClient == GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" ) ? Plugin_Continue : Plugin_Handled;
}
Action Hook_EmitterTransmitTP( int iEntity, int iClient ) {
	SetEdictFlags( iEntity, 0 );
	return iClient != GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" ) ? Plugin_Continue : Plugin_Handled;
}

static char g_szHydropumpDropChargeParticles[][] = {
	"mediflame_charged_death_red",
	"mediflame_charged_death_blue",
	"mediflame_charged_death_green",
	"mediflame_charged_death_yellow"
};
Action Event_PlayerDeath( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );
	
	//if( RoundToFloor( AttribHookFloat( 0.0, iPlayer, "custom_medigun_type" ) ) == CMEDI_FLAME && Tracker_GetValue( iPlayer, g_szHydropumpTrackerName ) >= 100.0 ) {
	if( true ) {
		float vecPos[3]; GetEntPropVector( iPlayer, Prop_Data, "m_vecAbsOrigin", vecPos );
		vecPos[2] += 40.0;

		//todo: use tempent dispatch for this
		int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) - 2;
		CreateParticle( g_szHydropumpDropChargeParticles[ iTeam ], vecPos, .flDuration = 1.0 );

		//EmitSound( iPlayer, "" );
	}

	return Plugin_Continue;
}

//todo: move to kocwtools
void SpeakConceptIfAllowed( int iPlayer, int iConcept ) {
	SDKCall( g_sdkSpeakIfAllowed, iPlayer, iConcept, Address_Null, Address_Null, 0, 0, Address_Null );
}