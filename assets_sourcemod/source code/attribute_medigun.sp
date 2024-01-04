#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <kocwtools>
#include <condhandler>
#include <hudframework>

#define MEDIGUN_THINK_INTERVAL 0.2
#define FLAMEKEYNAME "Pressure"

//guardian angel
#define ANGEL_UBER_COST 0.33 //uber cost to grant bubble
#define ANGEL_SELF_BUBBLE false //whether medic receives a bubble when using uber

DynamicHook	hMedigunSecondary;

DynamicDetour	hFireCollide;
DynamicDetour	hFireCollideTeam;

DynamicHook	hWeaponPostframe;
DynamicHook	hWeaponHolster;

//DynamicHook	hGiveAmmo;
//DynamicDetour	hSetAmmo;

//DynamicDetour 	hCollideTeamReset;

Handle		hAddFlameTouchList;

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
	version = "1.3.2",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

int g_iOldTargets[MAXPLAYERS+1] = { 69420, ... };

//int g_iRocketDamageOffset = -1; //1204
//int g_iCollideWithTeamOffset = -1; //1168

bool bLateLoad;
public APLRes AskPluginLoad2( Handle myself, bool bLate, char[] error, int err_max ) {
	bLateLoad = bLate;

	return APLRes_Success;
}

public void OnPluginStart() {
	HookEvent( EVENT_POSTINVENTORY,	Event_PostInventory );

	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "fuckme" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_ByRef );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	hAddFlameTouchList = EndPrepSDKCall();

	hMedigunSecondary = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::SecondaryAttack" );
	
	/*hCollideTeamReset = DynamicDetour.FromConf( hGameConf, "CBaseProjectile::ResetCollideWithTeammates" );
	if( !hCollideTeamReset.Enable( Hook_Pre, Detour_CollideTeamReset ) ) {
		SetFailState( "Detour setup for CBaseProjectile::ResetCollideWithTeammates failed" );
	}*/

	hFireCollide = DynamicDetour.FromConf( hGameConf, "CTFFlameEntity::OnCollide" );
	if( !hFireCollide.Enable( Hook_Pre, Detour_FireTouch ) ) {
		SetFailState( "Detour setup for CTFFlameEntity::OnCollide failed" );
	}
	hFireCollideTeam = DynamicDetour.FromConf( hGameConf, "CTFFlameEntity::OnCollideWithTeammate" );
	if( !hFireCollideTeam.Enable( Hook_Pre, Detour_FireTouchTeam ) ) {
		SetFailState( "Detour setup for CTFFlameEntity::OnCollideWithTeammate failed" );
	}

	//g_iCollideWithTeamOffset = GameConfGetOffset( hGameConf, "CBaseProjectile::m_bCollideWithTeammates" );

	hWeaponHolster = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::Holster" );
	hWeaponPostframe = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::ItemPostFrame" );

	//hGiveAmmo = DynamicHook.FromConf( hGameConf, "CBaseCombatCharacter::GiveAmmo" );
	//hSetAmmo = DynamicDetour.FromConf( hGameConf, "CBaseCombatCharacter::SetAmmoCount" );
	//hSetAmmo.Enable( Hook_Pre, Detour_SetAmmo );

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

	/*for( int i = 1; i <= MaxClients; i++ ) {
		if( IsClientInGame( i ) )
			hGiveAmmo.HookEntity( Hook_Pre, i, Hook_GiveAmmo );
	}*/
}

public void OnMapStart() {
	PrecacheSound( "weapons/angel_shield_on.wav" );
}

//todo: restore this to prevent hydro pump from picking up ammo
/*public void OnClientConnected( int iClient ) {
	RequestFrame( Frame_Hook, iClient );
}

void Frame_Hook( int iClient ) {
	hGiveAmmo.HookEntity( Hook_Pre, iClient, Hook_GiveAmmo );
}*/

public void OnEntityCreated( int iThis, const char[] szClassname ) {
	if( strcmp( szClassname, "tf_weapon_medigun", false ) == 0 )
		HookMedigun( iThis );

	if( strcmp( szClassname, "tf_weapon_flamethrower", false ) == 0 )
		RequestFrame( Frame_SetupFlamethrower, iThis ); //attributes don't seem to be setup yet
}

Action Event_PostInventory( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	if( IsValidPlayer( iPlayer ) ) {
		if( RoundToNearest( AttribHookFloat( 0.0, iPlayer, "custom_medigun_type" ) ) == CMEDI_FLAME ) {
			Tracker_Create( iPlayer, FLAMEKEYNAME, false );
			Tracker_SetMax( iPlayer, FLAMEKEYNAME, 100.0 );
			Tracker_SetFlags( iPlayer, FLAMEKEYNAME, RTF_CLEARONSPAWN );
		}
		else {
			Tracker_Remove( iPlayer, FLAMEKEYNAME );
		}
	}
	return Plugin_Continue;
}

MRESReturn Hook_MedigunHolster( int iThis ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );

	if( IsValidPlayer( iOwner ) ) {
		if( HasCustomCond( iOwner, TFCC_ANGELSHIELD ) && GetCustomCondSourcePlayer( iOwner, TFCC_ANGELSHIELD ) == iOwner ) {
			SetCustomCondLevel( iOwner, TFCC_ANGELSHIELD, 0 );
			RemoveCustomCond( iOwner, TFCC_ANGELSHIELD );
		}

		SetEntPropEnt( iThis, Prop_Send, "m_hHealingTarget", -1 );
		g_iOldTargets[iOwner] = 69420;
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

void HookMedigun( int iMedigun ) {
	hMedigunSecondary.HookEntity( Hook_Pre, iMedigun, Hook_MedigunSecondaryPre );
	hWeaponPostframe.HookEntity( Hook_Post, iMedigun, Hook_ItemPostFrame );
	hWeaponHolster.HookEntity( Hook_Post, iMedigun, Hook_MedigunHolster );
}

MRESReturn Hook_ItemPostFrame( int iMedigun ) {
	int iTarget = GetEntPropEnt( iMedigun, Prop_Send, "m_hHealingTarget" );
	int iOwner = GetEntPropEnt( iMedigun, Prop_Send, "m_hOwnerEntity" );

	g_iOldTargets[ iOwner ] = iTarget;
	
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
		EmitSoundToAll( "weapons/angel_shield_on.wav", iOwner, SNDCHAN_WEAPON, 85 );
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

	EmitSoundToAll( "weapons/angel_shield_on.wav", iOwner, SNDCHAN_WEAPON, 85 );
	SetEntPropFloat( iMedigun, Prop_Send, "m_flChargeLevel", flChargeLevel - ANGEL_UBER_COST );
	return;
#endif
}

/*
	UBERDOSIS
*/

/*MRESReturn Detour_CollideTeamReset( int iThis ) {
	int iLauncher = GetEntPropEnt( iThis, Prop_Send, "m_hOriginalLauncher" );
	if( RoundToFloor( AttribHookFloat( 0.0, iLauncher, "custom_medigun_type" ) ) == CMEDI_BOW ) {
		StoreToEntity( iThis, g_iCollideWithTeamOffset, true, NumberType_Int8 );
		return MRES_Supercede;
	}

	return MRES_Ignored;
}*/

/*
	FLAMETHROWER MEDIGUN
*/

/*
//need this to manage ammo on the hydro pump
MRESReturn Hook_GiveAmmo( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	//int iAmount = hParams.Get( 1 );
	int iType = hParams.Get( 2 );

	if( iType == 2 && RoundToNearest( AttribHookFloat( 0.0, iThis, "custom_medigun_type" ) ) == CMEDI_FLAME ) {
		hReturn.Value = 0;
		return MRES_Supercede;
	}

	return MRES_Ignored;
}
MRESReturn Detour_SetAmmo( int iThis, DHookParam hParams ) {
	//int iAmount = hParams.Get( 1 );
	int iType = hParams.Get( 2 );

	if( iType == 2 && RoundToNearest( AttribHookFloat( 0.0, iThis, "custom_medigun_type" ) ) == CMEDI_FLAME ) {
		SetEntProp( iThis, Prop_Send, "m_iAmmo", 1, 4, 2 );
		return MRES_Supercede;
	}
	return MRES_Ignored;
}
*/
void Frame_SetupFlamethrower( int iThis ) {
	int iMode = RoundToNearest( AttribHookFloat( 0.0, iThis, "custom_medigun_type" ) );
	if( iMode == CMEDI_FLAME ) {
		hWeaponPostframe.HookEntity( Hook_Pre, iThis, Hook_PostFrameFlame );
	}
}

//standard dhook entity parameter doesn't seem to work with flames so they're passed by address instead
MRESReturn Detour_FireTouch( Address aThis, DHookParam hParams ) {
	int iCollide = hParams.Get( 1 );
	return FireTouchHandle( aThis, iCollide );
}

MRESReturn Detour_FireTouchTeam( Address aThis, DHookParam hParams ) {
	int iCollide = hParams.Get( 1 );
	return FireTouchHandle( aThis, iCollide );
}

MRESReturn FireTouchHandle( Address aThis, int iCollide ) {
	int iOwner = LoadEntityHandleFromAddress( aThis + address( 112 ) );
	if( !IsValidPlayer( iOwner ) )
		return MRES_Ignored;

	int iWeapon = GetEntityInSlot( iOwner, 1 );
	if( RoundToNearest( AttribHookFloat( 0.0, iWeapon, "custom_medigun_type" ) ) != CMEDI_FLAME )
		return MRES_Ignored;

	if( GetEntProp( iOwner, Prop_Send, "m_iTeamNum" ) == TeamSeenBy( iOwner, iCollide ) )
		FireTouchHeal( aThis, iCollide, iOwner, iWeapon );

	return MRES_Supercede;
}

void FireTouchHeal( Address aThis, int iCollide, int iOwner, int iWeapon ) {
	if( !IsValidPlayer( iCollide ) )
		return;

	if( !HasCustomCond( iCollide, TFCC_FLAMEHEAL ) ) {
		AddCustomCond( iCollide, TFCC_FLAMEHEAL );
		SetCustomCondSourcePlayer( iCollide, TFCC_FLAMEHEAL, iOwner );
		SetCustomCondSourceWeapon( iCollide, TFCC_FLAMEHEAL, iWeapon );
	}

	int iLevel = GetCustomCondLevel( iCollide, TFCC_FLAMEHEAL );
	SetCustomCondLevel( iCollide, TFCC_FLAMEHEAL, iLevel + 75 );

	//this appends to the flame's internal list that keeps track of who it has hit
	Address aVector = aThis + address( 120 );
	Address aSize = aThis + address( 132 );
	Address aEHandle = GetEntityAddress( iCollide ) + address( 836 );
	SDKCall( hAddFlameTouchList, aVector, LoadFromAddress( aSize, NumberType_Int32 ), LoadFromAddress( aEHandle, NumberType_Int32 ) );
}

int g_iOldWeaponState[MAXPLAYERS+1];
MRESReturn Hook_PostFrameFlame( int iThis ) {
	int iWeaponState = GetEntProp( iThis, Prop_Send, "m_iWeaponState" );
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwner" );

	if( Tracker_GetValue( iOwner, FLAMEKEYNAME ) >= 20.0 )
		SetEntProp( iOwner, Prop_Send, "m_iAmmo", 20, 4, 2 );
	else
		SetEntProp( iOwner, Prop_Send, "m_iAmmo", 1, 4, 2 );

	if( iWeaponState != g_iOldWeaponState[ iOwner ] ) {
		if( iWeaponState == 3 ) {
			float flNewValue = FloatClamp( Tracker_GetValue( iOwner, FLAMEKEYNAME ) - 20.0, 0.0, 100.0 );
			Tracker_SetValue( iOwner, FLAMEKEYNAME, flNewValue );
		}
	}
	g_iOldWeaponState[ iOwner ] = iWeaponState;

	return MRES_Handled;
}

/*static char g_szFlameParticleName[][] = {
	"mediflame_red",
	"mediflame_blue",
	"mediflame_green",
	"mediflame_yellow"
};

static char g_szAirblastParticleName[][] = {
	"mediflame_airblast_red",
	"mediflame_airblast_blue",
	"mediflame_airblast_green",
	"mediflame_airblast_yellow"
};*/