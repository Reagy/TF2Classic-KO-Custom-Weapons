#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <kocwtools>
#include <condhandler>
#include <hudframework>
#include <midhook>

#define MP_CONCEPT_MEDIC_CHARGEREADY 36
#define MP_CONCEPT_MEDIC_CHARGEDEPLOYED 38
#define MP_CONCEPT_HEALTARGET_CHARGEDEPLOYED 55

//hydro pump
#define HYDRO_PUMP_HEAL_RATE 30.0
#define HYDRO_PUMP_AFTERHEAL_RATE 6.0
#define HYDRO_PUMP_AFTERHEAL_MAX_LENGTH 4.0
#define HYDRO_PUMP_CHARGE_TIME 35.0
static char g_szHydropumpTrackerName[32]	= "Ubercharge";
static char g_szHydropumpHealSound[]		= "weapons/HPump_Hit.wav";
static char g_szHydropumpChargedSound[]		= "weapons/HPump_Charged.wav";
static char g_szHydropumpDropChargeSound[]	= "weapons/HPump_ChargedDeath.wav";
static char g_szHydropumpMuzzleParticles[][] = {
	"mediflame_muzzle_red",
	"mediflame_muzzle_blue",
	"mediflame_muzzle_green",
	"mediflame_muzzle_yellow"
};
static char g_szHydropumpDropChargeParticles[][] = {
	"mediflame_charged_death_red",
	"mediflame_charged_death_blue",
	"mediflame_charged_death_green",
	"mediflame_charged_death_yellow"
};

static char g_szPaintballHitSound[] = "weapons/Paintball_Hit.wav";
static char g_szPaintballHealEffect[][] = {
	"paintball_hit_red",
	"paintball_hit_blue",
	"paintball_hit_green",
	"paintball_hit_yellow"
};

#define FLAMETHROWER_FIRING_INTERVAL 0.04

//guardian angel
#define ANGEL_UBER_COST 0.3333 //uber cost to grant bubble
#define ANGEL_SELF_BUBBLE false //whether medic receives a bubble when using uber
static char g_szAngelShieldSound[] = "weapons/angel_shield_on.wav";
static char g_szAngelShieldChargedSound[] = "weapons/healing/medigun_overheal_max.wav";

DynamicDetour	g_dtFireCollide;
DynamicDetour	g_dtFireCollideTeam;
DynamicDetour	g_dtApplyOnHitAttributes;
DynamicDetour	g_dtPaintballRifleHitAlly;
DynamicDetour	g_dtAddBurstHealer;
DynamicDetour	g_dtSimulateFlames;

DynamicHook	g_dhWeaponPostframe;
DynamicHook	g_dhWeaponPrimary;
DynamicHook	g_dhWeaponSecondary;
DynamicHook	g_dhWeaponHolster;
DynamicHook	g_dhWeaponDeploy;

MidHook		g_mhPaintballUberFix;

Handle		g_sdkAddFlameTouchList;
Handle		g_sdkGetBuffedMaxHealth;
Handle		g_sdkSpeakIfAllowed;

int 		g_iRefEHandleOffset = -1;
int 		g_iFlameBurnedVectorOffset = -1;
int 		g_iFlameOwnerOffset = -1;
int 		g_iCUtlVectorSizeOffset = -1;
//int g_iHealerVecOffset = -1;

PlayerFlags 	g_pfIsPlayingSound;
float 		g_flHealSoundEndTime[MAXPLAYERS+1] = { 0.0, ... };
int 		g_iHydroPumpBarrelChargedEmitters[MAXPLAYERS+1][2];
ArrayList 	g_alHydroPumpHealing[MAXPLAYERS+1];

enum struct HydroPumpHealing {
	int iPlayer;
	float flRemoveTime;
}

//uber_build_rate_on_hit is a part of the medigun so i emulated it for the hydro pump
int		g_iUberStacks[MAXPLAYERS+1] = { 0, ... };
float		g_flUberBonusRate[MAXPLAYERS+1] = { 0.0, ... };
float		g_flUberBonusExpireTime[MAXPLAYERS+1] = { 0.0, ... };

Address 	g_pCTFGameRules;
int		g_iSetupOffset = -1;

ConVar		g_cvMedigunCritBoost;	 int g_iMedigunCritBoostVal;
ConVar		g_cvUberStackMax;	 int g_iUberStackMax = -1;
ConVar		g_cvUberStackExpireTime; float g_flUberStackExpireTime = -1.0;

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
	version = "1.5",
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

	char szBuffer[64];

	g_cvMedigunCritBoost = FindConVar( "tf2c_medigun_critboostable" );
	g_cvMedigunCritBoost.AddChangeHook( OnCritMedigunChange );
	g_cvMedigunCritBoost.GetString( szBuffer, sizeof( szBuffer ) );
	g_iMedigunCritBoostVal = StringToInt( szBuffer );

	g_cvUberStackMax = FindConVar( "tf2c_uberratestacks_max" );
	g_cvUberStackMax.AddChangeHook( OnUberStackMaxChange );
	g_cvUberStackMax.GetString( szBuffer, sizeof( szBuffer ) );
	g_iUberStackMax = StringToInt( szBuffer );

	g_cvUberStackExpireTime = FindConVar( "tf2c_uberratestacks_removetime" );
	g_cvUberStackExpireTime.AddChangeHook( OnUberStackExpireChange );
	g_cvUberStackExpireTime.GetString( szBuffer, sizeof( szBuffer ) );
	g_flUberStackExpireTime = StringToFloat( szBuffer );

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

	//size_t is 64 bit so we need to do this, frankly i'm surprised it was this easy
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); 
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );

	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL );
	g_sdkSpeakIfAllowed = EndPrepSDKCallSafe( "CTFPlayer::SpeakConceptIfAllowed" );

	g_dtFireCollide = DynamicDetourFromConfSafe( hGameConf, "CTFFlameEntity::OnCollide" );
	g_dtFireCollide.Enable( Hook_Pre, Detour_FireTouch );
	g_dtFireCollideTeam = DynamicDetourFromConfSafe( hGameConf, "CTFFlameEntity::OnCollideWithTeammate" );
	g_dtFireCollideTeam.Enable( Hook_Pre, Detour_FireTouch );

	g_dtApplyOnHitAttributes = DynamicDetourFromConfSafe( hGameConf, "CTFWeaponBase::ApplyOnHitAttributes" );
	g_dtApplyOnHitAttributes.Enable( Hook_Post, Detour_ApplyOnHitAttributes );

	g_dtPaintballRifleHitAlly = DynamicDetourFromConfSafe( hGameConf, "CTFPaintballRifle::HitAlly" );
	g_dtPaintballRifleHitAlly.Enable( Hook_Post, Detour_PaintballRifleHitAlly );

	g_iRefEHandleOffset = GameConfGetOffsetSafe( hGameConf, "CBaseEntity::m_RefEHandle" );
	//g_iHealerVecOffset = GameConfGetOffsetSafe( hGameConf, "CTFPlayerShared::m_vecHealers" );
	g_iFlameBurnedVectorOffset = GameConfGetOffsetSafe( hGameConf, "CTFFlameEntity::m_hEntitiesBurnt" );
	g_iFlameOwnerOffset = GameConfGetOffsetSafe( hGameConf, "CTFFlameEntity::m_hOwner" );
	g_iCUtlVectorSizeOffset = GameConfGetOffsetSafe( hGameConf, "CUtlVector::m_Size" );
	g_pCTFGameRules = GameConfGetAddress( hGameConf, "CTFGameRules" );
	g_iSetupOffset = FindSendPropInfo( "CTFGameRulesProxy", "m_bInSetup" );

	g_dhWeaponPrimary = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::PrimaryAttack" );
	g_dhWeaponSecondary = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::SecondaryAttack" );
	g_dhWeaponDeploy = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::Deploy" );
	g_dhWeaponHolster = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::Holster" );
	g_dhWeaponPostframe = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::ItemPostFrame" );

	g_mhPaintballUberFix = new MidHook( GameConfGetAddress( hGameConf, "CTFPaintballRifle::TertiaryAttack_StartLagCompensation" ), MidHook_PaintballRifleUber, false );
	g_mhPaintballUberFix.Enable();
	
	g_dtAddBurstHealer = DynamicDetourFromConfSafe( hGameConf, "CTFPlayerShared::AddBurstHealer" );
	g_dtAddBurstHealer.Enable( Hook_Pre, Detour_AddBurstHealer );

	g_dtSimulateFlames = DynamicDetourFromConfSafe( hGameConf, "CTFFlameThrower::SimulateFlames" );
	g_dtSimulateFlames.Enable( Hook_Pre, Detour_SimulateFlamesPre );
	g_dtSimulateFlames.Enable( Hook_Post, Detour_SimulateFlamesPost );

	delete hGameConf;

	if( bLateLoad ) {
		int iIndex = MaxClients + 1;
		while( ( iIndex = FindEntityByClassname( iIndex, "tf_weapon_medigun" ) ) != -1 ) {
			Frame_SetupMedigun( iIndex );
		}
		iIndex = MaxClients + 1;
		while( ( iIndex = FindEntityByClassname( iIndex, "tf_weapon_flamethrower" ) ) != -1 ) {
			Frame_SetupFlamethrower( iIndex );
		}
		iIndex = MaxClients + 1;
		while( ( iIndex = FindEntityByClassname( iIndex, "tf_weapon_paintballrifle" ) ) != -1 ) {
			Frame_SetupPaintball( iIndex );
		}
	}
}
public void OnPluginEnd() {
	for( int i = 1; i < MAXPLAYERS+1; i++ ) {
		DestroyPumpChargedMuzzle( i );
	}
}

public void OnMapStart() {
	PrecacheSound( g_szAngelShieldSound );
	PrecacheSound( g_szAngelShieldChargedSound );
	
	PrecacheSound( g_szHydropumpHealSound );
	PrecacheSound( g_szHydropumpChargedSound );
	PrecacheSound( g_szHydropumpDropChargeSound );

	PrecacheSound( g_szPaintballHitSound );

	for( int i = 0; i < 4; i++ ) {
		PrecacheParticleSystem( g_szHydropumpDropChargeParticles[i] );
	}

	g_pfIsPlayingSound.SetDirect( 0, 0 );
	g_pfIsPlayingSound.SetDirect( 1, 0 );

	for( int i = 1; i < MAXPLAYERS+1; i++ ) {
		g_flHealSoundEndTime[i] = 0.0;
		if( g_alHydroPumpHealing[i] != INVALID_HANDLE )
			g_alHydroPumpHealing[i].Clear();
		else
			g_alHydroPumpHealing[i] = new ArrayList( sizeof( HydroPumpHealing ) );
	}
}

void OnCritMedigunChange( ConVar cvChanged, char[] szOld, char[] szNew ) {
	int iNew = StringToInt( szNew );
	g_iMedigunCritBoostVal = iNew;
}
void OnUberStackMaxChange( ConVar cvChanged, char[] szOld, char[] szNew ) {
	int iNew = StringToInt( szNew );
	g_iUberStackMax = iNew;
}
void OnUberStackExpireChange( ConVar cvChanged, char[] szOld, char[] szNew ) {
	float flNew = StringToFloat( szNew );
	g_flUberStackExpireTime = flNew;
}

MRESReturn Detour_ApplyOnHitAttributes( int iWeapon, DHookParam hParams ) {
	if( hParams.IsNull( 1 ) )
		return MRES_Ignored;

	int iAttacker = hParams.Get( 1 );
	//int iVictim = hParams.Get( 2 );

	if( GetCustomMedigunType( iAttacker ) == CMEDI_FLAME ) {
		float flUberOnHit = AttribHookFloat( 0.0, iWeapon, "add_onhit_ubercharge" );
		if( flUberOnHit ) {
			float flOld = Tracker_GetValue( iAttacker, "Ubercharge" );
			Tracker_SetValue( iAttacker, "Ubercharge", flOld + ( flUberOnHit * 100.0 ) );
		}
		
		float flBuildUberOnHit = AttribHookFloat( 0.0, iWeapon, "uber_build_rate_on_hit" );
		if( flBuildUberOnHit ) {
			AddUberStacks( iAttacker, flBuildUberOnHit );
		}
	}

	return MRES_Handled;	
}

void AddUberStacks( int iOwner, float flRate ) {
	HandleUberStacks( iOwner );

	if( g_iUberStacks[iOwner] < g_iUberStackMax )
		g_iUberStacks[iOwner] += 1;

	g_flUberBonusExpireTime[iOwner] = GetGameTime() + g_flUberStackExpireTime;
	g_flUberBonusRate[iOwner] = flRate * g_iUberStacks[iOwner];
}
void HandleUberStacks( int iOwner ) {
	if( g_flUberBonusExpireTime[iOwner] < GetGameTime() ) {
		g_iUberStacks[iOwner] = 0;
		g_flUberBonusRate[iOwner] = 0.0;
	}
}

int GetCustomMedigunType( int iTarget ) {
	return RoundToFloor( AttribHookFloat( 0.0, iTarget, "custom_medigun_type" ) );
}

public void OnEntityCreated( int iThis, const char[] szClassname ) {
	if( strcmp( szClassname, "tf_weapon_medigun", false ) == 0 )
		RequestFrame( Frame_SetupMedigun, EntIndexToEntRef( iThis ) );
	else if( strcmp( szClassname, "tf_weapon_flamethrower", false ) == 0 )
		RequestFrame( Frame_SetupFlamethrower, EntIndexToEntRef( iThis ) ); //attributes don't seem to be setup yet
	else if( strcmp( szClassname, "tf_weapon_paintballrifle", false ) == 0 )
		RequestFrame( Frame_SetupPaintball, EntIndexToEntRef( iThis ) ); //attributes don't seem to be setup yet
}

Action Event_PostInventory( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	if( !IsValidPlayer( iPlayer ) )
		return Plugin_Continue;

	if( GetCustomMedigunType( iPlayer ) == CMEDI_FLAME ) {
		Tracker_Create( iPlayer, g_szHydropumpTrackerName, false );
		Tracker_SetMax( iPlayer, g_szHydropumpTrackerName, 100.0 );
		Tracker_SetFlags( iPlayer, g_szHydropumpTrackerName, RTF_CLEARONSPAWN | RTF_PERCENTAGE );
	}
	else {
		Tracker_Remove( iPlayer, g_szHydropumpTrackerName );
	}

	return Plugin_Continue;
}

void Frame_SetupMedigun( int iMedigun ) {
	iMedigun = EntRefToEntIndex( iMedigun );
	if( iMedigun == -1 )
		return;

	g_dhWeaponSecondary.HookEntity( Hook_Pre, iMedigun, Hook_MedigunSecondaryPre );
	g_dhWeaponPostframe.HookEntity( Hook_Post, iMedigun, Hook_MedigunItemPostFrame );
	g_dhWeaponHolster.HookEntity( Hook_Post, iMedigun, Hook_MedigunHolster );
}

void Frame_SetupFlamethrower( int iFlamethrower ) {
	iFlamethrower = EntRefToEntIndex( iFlamethrower );
	if( iFlamethrower == -1 )
		return;

	if( GetCustomMedigunType( iFlamethrower ) == CMEDI_FLAME ) {
		g_dhWeaponPostframe.HookEntity( Hook_Pre, iFlamethrower, Hook_HydroPumpPostFrame );
		g_dhWeaponDeploy.HookEntity( Hook_Pre, iFlamethrower, Hook_HydroPumpDeploy );
		g_dhWeaponHolster.HookEntity( Hook_Pre, iFlamethrower, Hook_HydroPumpHolster );
	}
}

void Frame_SetupPaintball( int iPaintball ) {
	iPaintball = EntRefToEntIndex( iPaintball );
	if( iPaintball == -1 )
		return;

	g_dhWeaponPrimary.HookEntity( Hook_Pre, iPaintball, Hook_PaintballPrimaryAttackPre );
	g_dhWeaponPrimary.HookEntity( Hook_Post, iPaintball, Hook_PaintballPrimaryAttackPost );
}

MRESReturn Hook_MedigunHolster( int iMedigun ) {
	int iOwner = GetEntPropEnt( iMedigun, Prop_Send, "m_hOwnerEntity" );

	if( IsValidPlayer( iOwner ) ) {
		if( HasCustomCond( iOwner, TFCC_ANGELSHIELD ) && GetCustomCondSourcePlayer( iOwner, TFCC_ANGELSHIELD ) == iOwner ) {
			RemoveCustomCond( iOwner, TFCC_ANGELSHIELD );
		}

		SetEntPropEnt( iMedigun, Prop_Send, "m_hHealingTarget", -1 );
	}
	return MRES_Handled;
}

MRESReturn Hook_MedigunSecondaryPre( int iMedigun ) {
	switch( GetCustomMedigunType( iMedigun ) ) {
	case CMEDI_ANGEL: {
		AngelGunUber( iMedigun );
		return MRES_Supercede;
	}	
	}

	return MRES_Ignored;
}

float g_flOldChargeLevel[MAXPLAYERS+1] = { 0.0, ... };
MRESReturn Hook_MedigunItemPostFrame( int iMedigun ) {
	int iTarget = GetEntPropEnt( iMedigun, Prop_Send, "m_hHealingTarget" );
	int iOwner = GetEntPropEnt( iMedigun, Prop_Send, "m_hOwnerEntity" );

	int iMediType = GetCustomMedigunType( iMedigun );
	float flChargeLevel = GetEntPropFloat( iMedigun, Prop_Send, "m_flChargeLevel" );
	if( iMediType == CMEDI_ANGEL ) {
		float flNextTarget = 0.01 * ( RoundToFloor( ( g_flOldChargeLevel[iOwner] + 0.33 ) * 100.0 ) / 33 ) * 33;
		if( flNextTarget > 0.98 && flNextTarget < 1.0 )
			flNextTarget = 1.0;

		if( g_flOldChargeLevel[iOwner] < flNextTarget && flChargeLevel >= flNextTarget ) {
			EmitSoundToAll( g_szAngelShieldChargedSound, iOwner, .level = SNDLEVEL_NORMAL, .flags = SND_CHANGEPITCH, .pitch = 100 + RoundToFloor( flChargeLevel * 15.0 ) );
		}
	}
	g_flOldChargeLevel[iOwner] = flChargeLevel;

	if( !GetEntProp( iMedigun, Prop_Send, "m_bChargeRelease" ) )
		return MRES_Handled;

	//uber handling
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

		if( HasCustomCond( iGive, TFCC_ANGELSHIELD ) )
			continue;

		AddCustomCond( iGive, TFCC_ANGELSHIELD, iOwner, iMedigun );
		
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

	if( HasCustomCond( iTarget, TFCC_ANGELSHIELD ) )
		return;

	AddCustomCond( iTarget, TFCC_ANGELSHIELD, iOwner, iMedigun );

	SpeakConceptIfAllowed( iOwner, MP_CONCEPT_MEDIC_CHARGEDEPLOYED );
	SpeakConceptIfAllowed( iTarget, MP_CONCEPT_HEALTARGET_CHARGEDEPLOYED );

	EmitSoundToAll( g_szAngelShieldSound, iOwner, SNDCHAN_WEAPON, 85 );
	SetEntPropFloat( iMedigun, Prop_Send, "m_flChargeLevel", flChargeLevel - ANGEL_UBER_COST );
	return;
#endif
}

/*
	HYDRO PUMP
*/

int g_iOldButtons[MAXPLAYERS+1];
MRESReturn Hook_HydroPumpPostFrame( int iWeapon ) {
	int iOwner = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwnerEntity" );
	if( iOwner == -1 )
		return MRES_Ignored;

	bool bNotFiring = GetEntProp( iWeapon, Prop_Send, "m_iWeaponState" ) == 0;
	bool bTimeToEnd = g_flHealSoundEndTime[ iOwner ] != 0.0 && g_flHealSoundEndTime[ iOwner ] <= GetGameTime();
	if( bNotFiring || bTimeToEnd )
		EndHydropumpHitSound( iOwner );

	HandleUberStacks( iOwner );

	int iButtons = GetClientButtons( iOwner );
	if( iButtons & IN_ATTACK2 && !( g_iOldButtons[ iOwner ] & IN_ATTACK2 ) ) {
		if( Tracker_GetValue( iOwner, g_szHydropumpTrackerName ) >= 100.0 && !HasCustomCond( iOwner, TFCC_HYDROUBER ) ) {
			AddCustomCond( iOwner, TFCC_HYDROUBER, iOwner, iWeapon );
			DestroyPumpChargedMuzzle( iOwner );

			SpeakConceptIfAllowed( iOwner, MP_CONCEPT_MEDIC_CHARGEDEPLOYED );
		}
	}
	g_iOldButtons[ iOwner ] = iButtons;

	return MRES_Handled;
}

MRESReturn Hook_HydroPumpDeploy( int iWeapon, DHookReturn hReturn ) {
	//prevents the server from complaining about missing attachment points
	RequestFrame( Frame_HydroPumpDeploy, EntIndexToEntRef( iWeapon ) );
	return MRES_Handled;
}
void Frame_HydroPumpDeploy( int iWeapon ) {
	iWeapon = EntRefToEntIndex( iWeapon );
	if( iWeapon == -1 )
		return;

	int iOwner = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwnerEntity" );
	if( iOwner != -1 && GetEntPropEnt( iOwner, Prop_Send, "m_hActiveWeapon" ) == iWeapon && Tracker_GetValue( iOwner, g_szHydropumpTrackerName ) >= 100.0 )
		CreatePumpChargedMuzzle( iWeapon, iOwner );
}

MRESReturn Hook_HydroPumpHolster( int iWeapon, DHookReturn hReturn, DHookParam hParams ) {
	int iOwner = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwnerEntity" );
	if( iOwner != -1 ) {
		DestroyPumpChargedMuzzle( iOwner );
		EndHydropumpHitSound( iOwner );
	}

	return MRES_Handled;
}

MRESReturn Detour_SimulateFlamesPre( int iFlamethrower ) {
	int iOwner = GetEntPropEnt( iFlamethrower, Prop_Send, "m_hOwnerEntity" );
	if( !IsValidPlayer(iOwner) )
		return MRES_Ignored;

	SetForceLagCompensation(true);

	return MRES_Handled;
}
MRESReturn Detour_SimulateFlamesPost( int iFlamethrower ) {
	int iOwner = GetEntPropEnt( iFlamethrower, Prop_Send, "m_hOwnerEntity" );
	if( !IsValidPlayer(iOwner) )
		return MRES_Ignored;

	SetForceLagCompensation(false);

	return MRES_Handled;
}

//apparently tf2c flame particles aren't even derived from cbaseentity so they're passed by address instead
MRESReturn Detour_FireTouch( Address aFlame, DHookParam hParams ) {
	int iTarget = hParams.Get( 1 );
	int iOwner = LoadEntityHandleFromAddress( aFlame + view_as<Address>( g_iFlameOwnerOffset ) );
	if( !IsValidPlayer( iOwner ) )
		return MRES_Ignored;

	int iWeapon = GetEntityInSlot( iOwner, 1 );
	if( GetCustomMedigunType( iWeapon ) != CMEDI_FLAME )
		return MRES_Ignored;

	if( IsValidPlayer( iTarget ) && GetEntProp( iOwner, Prop_Send, "m_iTeamNum" ) == TeamSeenBy( iOwner, iTarget ) )
		FireTouchHeal( aFlame, iTarget, iOwner, iWeapon );

	return MRES_Supercede;
}

void FireTouchHeal( Address aFlame, int iCollide, int iOwner, int iWeapon ) {
	//float flRate = ( HYDRO_PUMP_HEAL_RATE * FLAMETHROWER_FIRING_INTERVAL );
	float flRate = 1.44; //precalculated
	
	flRate = AttribHookFloat( flRate, iOwner, "mult_medigun_healrate" );

	if( g_iMedigunCritBoostVal ) {
		if( g_iMedigunCritBoostVal == 2 && IsPlayerCritBoosted( iOwner ) )
			flRate *= 3.0;
		else if( IsPlayerMiniCritBoosted( iOwner ) )
			flRate *= 1.35;
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
		aFlame + view_as<Address>( g_iFlameBurnedVectorOffset ),
		LoadFromAddressOffset( aFlame, g_iFlameBurnedVectorOffset + g_iCUtlVectorSizeOffset ),
		LoadFromEntity( iCollide, g_iRefEHandleOffset ) );
}

#define UBER_REDUCTION_TIME 0.2
void HydroPumpBuildUber( int iOwner, int iTarget, int iWeapon ) {
	//float flChargeAmount = (FLAMETHROWER_FIRING_INTERVAL / HYDRO_PUMP_CHARGE_TIME) * 100.0;
	float flChargeAmount = 0.1; //precalculated version of above because the compiler does not precalculate float constants (not a constant expression?)
	//float flChargeAmount = 100.0; //for testing

	int iTargetMaxBuffedHealth = SDKCall( g_sdkGetBuffedMaxHealth, GetSharedFromPlayer( iTarget ) );
	if( GetClientHealth( iTarget ) >= RoundToFloor( iTargetMaxBuffedHealth * 0.95 ) )
		flChargeAmount *= 0.5;

	bool bIsInSetup;
	Address g_aCTFGameRules = LoadFromAddress( g_pCTFGameRules, NumberType_Int32 );
	if( g_aCTFGameRules != Address_Null ) {
		bIsInSetup = LoadFromAddressOffset( g_aCTFGameRules, g_iSetupOffset, NumberType_Int8 );
		if( bIsInSetup )
			flChargeAmount *= 3.0;
	}

	if( g_iMedigunCritBoostVal ) {
		if( g_iMedigunCritBoostVal == 2 && IsPlayerCritBoosted( iOwner ) )
			flChargeAmount *= 3.0;
		else if( IsPlayerMiniCritBoosted( iOwner ) )
			flChargeAmount *= 1.35;
	}

	HandleUberStacks( iOwner );
	flChargeAmount *= 1.0 + ( g_flUberBonusRate[iOwner] * 0.01 );

	flChargeAmount = AttribHookFloat( flChargeAmount, iWeapon, "mult_medigun_uberchargerate" );
	flChargeAmount = AttribHookFloat( flChargeAmount, iOwner, "mult_medigun_uberchargerate_wearer" );

	int iHealerCount = GetEntProp( iTarget, Prop_Send, "m_nNumHumanHealers" );
	if( !bIsInSetup && iHealerCount > 1 ) {
		flChargeAmount /= iHealerCount;
	}

	//reduce the rate of uber gained per player
	HydroPumpHealing healer;
	ArrayList alList = g_alHydroPumpHealing[iOwner];
	int iTargetIndex = -1;
	for( int i = 0; i < alList.Length; i++ ) {
		alList.GetArray( i, healer, sizeof( HydroPumpHealing ) );
		if( healer.iPlayer == iTarget ) {
			healer.flRemoveTime = GetGameTime() + UBER_REDUCTION_TIME;
			alList.SetArray( i, healer, sizeof( HydroPumpHealing ) );
			iTargetIndex = i;
			continue;
		}

		if( GetGameTime() > healer.flRemoveTime ) {
			alList.Erase( i );
			if( alList.Length < 1 ) {
				break;
			}
			else {
				i -= 1;
				continue;
			}
		}
	}

	if( iTargetIndex == -1 ) {
		healer.iPlayer = iTarget;
		healer.flRemoveTime = GetGameTime() + UBER_REDUCTION_TIME;
		alList.PushArray( healer, sizeof( HydroPumpHealing ) );
	}
	
	float flMult = alList.Length > 1 ? Pow( 0.9, float( alList.Length ) ) : 1.0;
	flChargeAmount *= flMult;

	//PrintToServer("%f %i", flChargeAmount, alList.Length);

	float flOldCharge = Tracker_GetValue( iOwner, g_szHydropumpTrackerName );
	float flNewCharge = flOldCharge + flChargeAmount;
	if( flOldCharge < 100.0 && flNewCharge >= 100.0 ) {
		CreatePumpChargedMuzzle( iWeapon, iOwner );
		SpeakConceptIfAllowed( iOwner, MP_CONCEPT_MEDIC_CHARGEREADY );
	}

	Tracker_SetValue( iOwner, g_szHydropumpTrackerName, flNewCharge );
}

/*MRESReturn Detour_UpdateChargeLevel( int iThis ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	if( iOwner == -1 || GetCustomMedigunType( iOwner ) != CMEDI_FLAME )
		return MRES_Ignored;

	PrintToServer( "%f", GetEntPropFloat( iThis, Prop_Send, "m_flChargeLevel" ) );
	SetEntPropFloat( iThis, Prop_Send, "m_flChargeLevel", Tracker_GetValue( iOwner, g_szHydropumpTrackerName ) * 0.01 );

	return MRES_Supercede;
}*/

void SetFlameHealSoundTime( int iOwner, int iWeapon ) {
	g_flHealSoundEndTime[ iOwner ] = GetGameTime() + 0.1;

	if( !g_pfIsPlayingSound.Get( iOwner ) && GetEntProp( iWeapon, Prop_Send, "m_iWeaponState" ) != 0 ) {
		g_pfIsPlayingSound.Set( iOwner, true );
		EmitSoundToAll( g_szHydropumpHealSound, iOwner );
	}
}
void EndHydropumpHitSound( int iOwner ) {
	g_flHealSoundEndTime[ iOwner ] = 0.0;
	g_pfIsPlayingSound.Set( iOwner, false );
	StopSound( iOwner, 0, g_szHydropumpHealSound );
}

void CreatePumpChargedMuzzle( int iWeapon, int iOwner ) {
	int iTeam = GetEntProp( iOwner, Prop_Send, "m_iTeamNum" ) - 2;
	DestroyPumpChargedMuzzle( iOwner );

	//first person
	int iParticle = CreateParticle( g_szHydropumpMuzzleParticles[ iTeam ] );
	ParentParticleToViewmodelEX( iParticle, iWeapon, "weapon_bone" ); //i have no idea why weapon bone works for this i hate this fucking engine so much
	SetEntPropEnt( iParticle, Prop_Send, "m_hOwnerEntity", iOwner );
	SDKHook( iParticle, SDKHook_SetTransmit, Hook_TransmitIfOwnerParticle );
	SetEdictFlags( iParticle, 0 );
	g_iHydroPumpBarrelChargedEmitters[iOwner][0] = EntIndexToEntRef( iParticle );

	//third person
	iParticle = CreateParticle( g_szHydropumpMuzzleParticles[ iTeam ] );
	ParentModel( iParticle, iWeapon, "weapon_bone" ); //i have no idea why weapon bone works for this i hate this fucking engine so much
	SetEntPropEnt( iParticle, Prop_Send, "m_hOwnerEntity", iOwner );
	SDKHook( iParticle, SDKHook_SetTransmit, Hook_TransmitIfNotOwnerParticle );
	SetEdictFlags( iParticle, 0 );
	g_iHydroPumpBarrelChargedEmitters[iOwner][1] = EntIndexToEntRef( iParticle );

	EmitSoundToAll( g_szHydropumpChargedSound, iOwner, .flags = SND_CHANGEVOL, .volume = 1.0 );
}
void DestroyPumpChargedMuzzle( int iOwner ) {
	for( int i = 0; i < 2; i++ ) {
		int iEntity = EntRefToEntIndex( g_iHydroPumpBarrelChargedEmitters[iOwner][i] );
		g_iHydroPumpBarrelChargedEmitters[iOwner][i] = INVALID_ENT_REFERENCE;
		if( iEntity == -1 )
			continue;

		RemoveEntity( iEntity );

	}
	StopSound( iOwner, SNDCHAN_AUTO, g_szHydropumpChargedSound );
}

Action Event_PlayerDeath( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iPlayer = GetClientOfUserId( hEvent.GetInt( "userid" ) );
	
	if( GetCustomMedigunType( iPlayer ) == CMEDI_FLAME && Tracker_GetValue( iPlayer, g_szHydropumpTrackerName ) >= 100.0 ) {
		float vecPos[3]; 
		GetEntPropVector( iPlayer, Prop_Data, "m_vecAbsOrigin", vecPos );
		vecPos[2] += 40.0;

		int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) - 2;
		TE_Particle( g_szHydropumpDropChargeParticles[ iTeam ], vecPos );

		EmitSoundToAll( g_szHydropumpDropChargeSound, iPlayer );
	}

	return Plugin_Continue;
}

//allow paintball rifle uber with m2 when scope is unavailable
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if( buttons & IN_ATTACK2 ) {
		int iWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if( iWeapon == -1 )
			return Plugin_Continue;

		static char szWeaponName[256];
		GetEntityClassname( iWeapon, szWeaponName, sizeof( szWeaponName ) );
		if( StrEqual( szWeaponName, "tf_weapon_paintballrifle" ) && AttribHookFloat( 0.0, client, "unimplemented_mod_sniper_no_charge" ) != 0.0 )
			buttons = ( buttons | IN_ATTACK3 ) & ~IN_ATTACK2;
	}

	return Plugin_Continue;
}

MRESReturn Detour_AddBurstHealer( Address aShared, DHookParam hParams ) {
	int iPlayer = GetPlayerFromShared( aShared );
	int iSource = hParams.Get( 1 );

	if( !( IsValidPlayer(iSource) && TF2_GetPlayerClass(iSource) == TFClass_Medic ) )
		return MRES_Ignored;

	float flRate = hParams.Get( 2 );
	float flNewRate = AttribHookFloat( flRate, iPlayer, "mult_healing_from_medics" );
	if( flRate != flNewRate ) {
		hParams.Set( 2, flNewRate );
		return MRES_ChangedHandled;
	}

	return MRES_Ignored;
}

MRESReturn Hook_PaintballPrimaryAttackPre( int iWeapon, DHookParam hParams ) {
	SetForceLagCompensation( true );
	return MRES_Handled;
}
MRESReturn Hook_PaintballPrimaryAttackPost( int iWeapon, DHookParam hParams ) {
	SetForceLagCompensation( false );
	return MRES_Handled;
}

MRESReturn Detour_PaintballRifleHitAlly( int iWeapon, DHookParam hParams ) {
	int iTarget = hParams.Get( 1 );
	int iOwner = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwnerEntity" );

	if( !IsValidPlayer( iOwner ) || !IsValidPlayer( iTarget ) )
		return MRES_Ignored;

	//creating the effect while still in lag compensation seems to cause issues at high ping where the particle detaches from the player
	DataPack pack = new DataPack();
	pack.WriteCell( EntIndexToEntRef( iOwner ) );
	pack.WriteCell( EntIndexToEntRef( iTarget ) );
	pack.Reset();
	RequestFrame( Frame_CreatePaintballFx, pack );

	//emit sound to owner from their pov
	EmitSoundToClient( iOwner, g_szPaintballHitSound, .volume=0.7 );

	//emit sound to everyone else from the receiver
	int iPlayers[MAXPLAYERS+1];
	int iSize = 0;
	for( int i = 1; i <= MaxClients; i++ ) {
		if( i == iOwner || !IsClientInGame(i) )
			continue;
		
		iPlayers[iSize] = i;
		iSize++;
	}
	EmitSound( iPlayers, iSize, g_szPaintballHitSound, iTarget );

	return MRES_Ignored;
}

void Frame_CreatePaintballFx( DataPack pack ) {
	int iOwner = EntRefToEntIndex( pack.ReadCell() );
	int iTarget = EntRefToEntIndex( pack.ReadCell() );
	delete pack;

	if( iOwner == -1 || iTarget == -1 )
		return;

	int iTeam = GetEntProp( iOwner, Prop_Send, "m_iTeamNum" ) - 2;

	int iEmitter = CreateEntityByName( "info_particle_system" );
	DispatchKeyValue( iEmitter, "effect_name", g_szPaintballHealEffect[ iTeam ] );

	float vecCoords[3];
	GetClientAbsOrigin( iTarget, vecCoords );

	TeleportEntity( iEmitter, vecCoords );
	ParentModel( iEmitter, iTarget );
	SetEntPropEnt( iEmitter, Prop_Send, "m_hOwnerEntity", iTarget );
	SetEntPropEnt( iEmitter, Prop_Send, "m_hControlPointEnts", iTarget );

	DispatchSpawn( iEmitter );
	ActivateEntity( iEmitter );
	AcceptEntityInput( iEmitter, "Start" );

	CreateTimer( 1.0, Timer_RemovePaintballHealFX, EntRefToEntIndex( iEmitter ), TIMER_FLAG_NO_MAPCHANGE );
}

Action Timer_RemovePaintballHealFX( Handle hTimer, int iParticle ) {
	iParticle = EntRefToEntIndex( iParticle );
	if( iParticle == -1 ) {
		return Plugin_Stop;
	}

	RemoveEntity( iParticle );
	return Plugin_Stop;
}

public void MidHook_PaintballRifleUber( MidHookRegisters hRegs ) {
	//probably don't need to null check the this pointer
	int iThis = GetEntityFromAddress( hRegs.Load( DHookRegister_EBP, 8, NumberType_Int32 ) );
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	if( !IsValidPlayer( iOwner ) )
		return;

	SetForceLagCompensation( true );
	StartLagCompensation( iOwner );
	SetForceLagCompensation( false );

	float vecEyeAngles[3];
	float vecShootPos[3];
	GetClientEyePosition( iOwner, vecShootPos );
	GetClientEyeAngles( iOwner, vecEyeAngles );

	Handle hTrace = TR_TraceRayFilterEx( vecShootPos, vecEyeAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer, iOwner );

	FinishLagCompensation( iOwner );

	int iTarget = TR_GetEntityIndex( hTrace );
	if( !IsValidPlayer( iTarget ) ) {
		StoreToAddress( hRegs.Get(DHookRegister_EBP)-32, 0, NumberType_Int32 );
		return;
	}
	StoreToAddress( hRegs.Get(DHookRegister_EBP)-32, GetEntityAddress(iTarget), NumberType_Int32 );
	CloseHandle( hTrace );
}

bool TraceEntityFilterPlayer( int iEntity, int iContentsMask, any data )
{
	if ( iEntity == data ) return false;
	if( IsValidPlayer( iEntity ) && TF2_GetClientTeam( data ) != TF2_GetClientTeam( iEntity ) )
		return false;

	static char sClassname[128];
	GetEdictClassname( iEntity, sClassname, sizeof(sClassname) );
	return strcmp( sClassname, "func_respawnroomvisualizer", false ) != 0;
}

//todo: move to kocwtools
void SpeakConceptIfAllowed( int iPlayer, int iConcept ) {
	SDKCall( g_sdkSpeakIfAllowed, iPlayer, iConcept, Address_Null, Address_Null, 0, 0, Address_Null );
}