#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <kocwtools>
#include <condhandler>
#include <hudframework>

static char g_szHydropumpTrackerName[32] = "Pressure";
static char g_szHydropumpHealSound[] = "weapons/HPump_Hit.wav";

//guardian angel
#define ANGEL_UBER_COST 0.33 //uber cost to grant bubble
#define ANGEL_SELF_BUBBLE false //whether medic receives a bubble when using uber
static char g_szAngelShieldSound[] = "weapons/angel_shield_on.wav";

DynamicHook	g_dhWeaponSecondary;

DynamicDetour	g_dtFireCollide;
DynamicDetour	g_dtFireCollideTeam;

DynamicHook	g_dhWeaponPostframe;
DynamicHook	g_dhWeaponHolster;

Handle		g_sdkAddFlameTouchList;

int g_iRefEHandleOffset = -1;
int g_iFlameBurnedVectorOffset = -1;
int g_iFlameOwnerOffset = -1;
int g_iCUtlVectorSizeOffset = -1;
int g_iHealerVecOffset = -1;

PlayerFlags g_pfPlayingSound;
float g_flEndHealSoundTime[MAXPLAYERS+1] = { 0.0, ... };
float g_flHealAccumulator[MAXPLAYERS+1] = { 0.0, ... };

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
	HookEvent( "post_inventory_application", Event_PostInventory );

	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "m_hEntitiesBurnt::InsertBefore" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_ByRef );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkAddFlameTouchList = EndPrepSDKCallSafe( "m_hEntitiesBurnt::InsertBefore" );

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

public void OnMapStart() {
	PrecacheSound( g_szAngelShieldSound );
	PrecacheSound( g_szHydropumpHealSound );

	g_pfPlayingSound.SetDirect( 0, 0 );
	g_pfPlayingSound.SetDirect( 1, 0 );
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
		Tracker_SetFlags( iPlayer, g_szHydropumpTrackerName, RTF_CLEARONSPAWN );
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
		g_dhWeaponSecondary.HookEntity( Hook_Pre, iFlamethrower, Hook_HydropumpSecondaryPre );
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

#define FLAMETHROWER_FIRING_INTERVAL 0.04
#define FLAMETHROWER_HEAL_RATE 36.0
#define FLAMETHROWER_IMMEDIATE_PERCENTAGE 0.75

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
	AddPlayerHealerTimed( iCollide, iOwner, FLAMETHROWER_HEAL_RATE * ( 1.0 - FLAMETHROWER_IMMEDIATE_PERCENTAGE ), 5.0, true, true );
	
	//scuffed code to force crit heals on timed healer
	//todo: move to gamedata
	const int iHealerStructSize = 48;
	const int iCritHealsOffset = 33;

	Address aShared = GetSharedFromPlayer( iCollide );
	Address aVectorStart = LoadFromAddressOffset( aShared, g_iHealerVecOffset, NumberType_Int32 );
	int iSize = LoadFromAddressOffset( aShared, g_iHealerVecOffset + g_iCUtlVectorSizeOffset, NumberType_Int32 );
	Address aHealer = aVectorStart + view_as<Address>( iHealerStructSize * ( iSize - 1 ) );
	StoreToAddressOffset( aHealer, iCritHealsOffset, true, NumberType_Int8 );
	//end scuffed

	float flRate = ( FLAMETHROWER_HEAL_RATE * FLAMETHROWER_IMMEDIATE_PERCENTAGE * FLAMETHROWER_FIRING_INTERVAL ) + g_flHealAccumulator[ iCollide ];
	flRate = AttribHookFloat( flRate, iOwner, "mult_medigun_healrate" );
	float flRateRounded = float( RoundToFloor( flRate ) );
	g_flHealAccumulator[ iCollide ] = flRate - flRateRounded;

	HealPlayer( iCollide, flRateRounded, iOwner );

	SetFlameHealSoundTime( iOwner );

	if( !HasCustomCond( iCollide, TFCC_HYDROPUMPHEAL ) )
		AddCustomCond( iCollide, TFCC_HYDROPUMPHEAL, iOwner, iWeapon );

	SetCustomCondDuration( iCollide, TFCC_HYDROPUMPHEAL, 0.3, false );

	//this appends to the flame's internal list that keeps track of who it has hit
	SDKCall( g_sdkAddFlameTouchList, 
		aThis + view_as<Address>( g_iFlameBurnedVectorOffset ),
		LoadFromAddressOffset( aThis, g_iFlameBurnedVectorOffset + g_iCUtlVectorSizeOffset, NumberType_Int32 ),
		LoadFromEntity( iCollide, g_iRefEHandleOffset ) );
}

void SetFlameHealSoundTime( int iOwner ) {
	g_flEndHealSoundTime[ iOwner ] = GetGameTime() + 0.105;

	if( !g_pfPlayingSound.Get( iOwner ) ) {
		g_pfPlayingSound.Set( iOwner, true );
		CreateTimer( 0.1, Timer_ManageFlameHealSound, EntIndexToEntRef( iOwner ), TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT );

		EmitSoundToAll( g_szHydropumpHealSound, iOwner );
		//EmitSoundToAll( g_szHydropumpHealSound, iOwner, .flags = SND_CHANGEVOL, .volume = 0.75 );
	}
}

Action Timer_ManageFlameHealSound( Handle hTimer, int iOwnerRef ) {
	int iOwner = EntRefToEntIndex( iOwnerRef );
	if( iOwner == -1 )
		return Plugin_Stop;

	if( g_flEndHealSoundTime[ iOwner ] != 0.0 && g_flEndHealSoundTime[ iOwner ] <= GetGameTime() ) {
		g_flEndHealSoundTime[ iOwner ] = 0.0;
		g_pfPlayingSound.Set( iOwner, false );
		StopSound( iOwner, 0, g_szHydropumpHealSound );

		return Plugin_Stop;
	}

	return Plugin_Continue;
}

MRESReturn Hook_HydropumpSecondaryPre( int iThis, DHookParam hParams ) {
	return MRES_Ignored;
}