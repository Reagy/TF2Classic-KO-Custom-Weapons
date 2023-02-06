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

DynamicDetour	hCanTargetMedigun;
DynamicDetour	hMedigunThink;
DynamicDetour	hMedigunHealrate;
DynamicHook	hMedigunSecondary;
DynamicHook	hMedigunPostframe;
DynamicHook	hMedigunHolster;

DynamicDetour hStartHeal;
DynamicDetour hStopHeal;
DynamicDetour hGetBuffedHealth;
DynamicDetour hUpdateCharge;

DynamicDetour hCoilTouch;
DynamicDetour hCoilSpeed;
DynamicDetour hCollideTeamReset;

Handle hGetHealerIndex;
Handle hGetMaxHealth;
Handle hGetBuffedMaxHealth;
Handle hCallHealRate;
Handle hCallHeal;
Handle hCallStopHeal;
Handle hCallTakeHealth;

enum {
	CMEDI_ANGEL = 1,
	CMEDI_BWP = 2,
	CMEDI_QFIX = 3,
	CMEDI_OATH = 4,
	CMEDI_BEAM = 5,
}

public Plugin myinfo =
{
	name = "Attribute: Mediguns",
	author = "Noclue",
	description = "Atributes for Mediguns.",
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

int g_iDummyGuns[MAXPLAYERS+1] = { -1, ... };
int g_iBeamEmitters[MAXPLAYERS+1][2];
int g_iBeamTargetPoints[MAXPLAYERS+1] = { -1, ... };

int g_iOldTargets[MAXPLAYERS+1] = { 69420, ... };
bool g_bOldCharging[MAXPLAYERS+1] = { false, ... };

float g_flMultTable[MAXPLAYERS+1] = { 0.5, ... }; //cached maximum overheal for mediguns

//oath breaker
bool g_bRadiusHealer[MAXPLAYERS+1] = { false, ... };
float g_flLastHealed[MAXPLAYERS+1] = { 0.0, ... };

bool bLateLoad;
public APLRes AskPluginLoad2( Handle myself, bool bLate, char[] error, int err_max ) {
	bLateLoad = bLate;

	return APLRes_Success;
}

public void OnPluginStart() {
	HookEvent( EVENT_POSTINVENTORY,	Event_PostInventory );
	HookEvent( EVENT_PLAYERDEATH,	Event_PlayerKilled );
	HookEvent( "player_healed",	Event_PlayerHealed );
	HookEvent( "player_chargedeployed", Event_DeployUber );

	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	hCanTargetMedigun = DynamicDetour.FromConf( hGameConf, "CWeaponMedigun::AllowedToHealTarget" );
	if( !hCanTargetMedigun.Enable( Hook_Pre, Detour_AllowedToHealPre ) ) {
		SetFailState( "Detour setup for CWeaponMedigun::AllowedToHealTarget failed" );
	}
	hMedigunThink = DynamicDetour.FromConf( hGameConf, "CWeaponMedigun::HealTargetThink" );
	if( !hMedigunThink.Enable( Hook_Post, Detour_MedigunThinkPost ) ) {
		SetFailState( "Detour setup for CWeaponMedigun::HealTargetThink failed" );
	}
	hMedigunHealrate = DynamicDetour.FromConf( hGameConf, "CWeaponMedigun::GetHealRate" );
	if( !hMedigunHealrate.Enable( Hook_Post, Detour_MediHealRate ) ) {
		SetFailState( "Detour setup for CWeaponMedigun::GetHealRate failed" );
	}
	hMedigunSecondary = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::SecondaryAttack" );
	hMedigunPostframe = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::ItemPostFrame" );
	hMedigunHolster = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::Holster" );

	hStartHeal = DynamicDetour.FromConf( hGameConf, "CTFPlayerShared::Heal" );
	if( !hStartHeal.Enable( Hook_Pre, Detour_HealStartPre ) ) {
		SetFailState( "Detour setup for CTFPlayerShared::Heal failed" );
	}
	hStopHeal = DynamicDetour.FromConf( hGameConf, "CTFPlayerShared::StopHealing" );
	if( !hStopHeal.Enable( Hook_Pre, Detour_HealStopPre ) ) {
		SetFailState( "Detour setup for CTFPlayerShared::StopHealing failed" );
	}
	hGetBuffedHealth = DynamicDetour.FromConf( hGameConf, "CTFPlayerShared::GetBuffedMaxHealth" );
	if( !hGetBuffedHealth.Enable( Hook_Post, Detour_GetBuffedMaxHealth ) ) {
		SetFailState( "Detour setup for CTFPlayerShared::GetBuffedMaxHealth failed" );
	}
	hUpdateCharge = DynamicDetour.FromConf( hGameConf, "CTFPlayerShared::RecalculateChargeEffects" );
	if( !hUpdateCharge.Enable( Hook_Post, Detour_UpdateCharge ) ) {
		SetFailState( "Detour setup for CTFPlayerShared::RecalculateChargeEffects failed" );
	}

	hCoilTouch = DynamicDetour.FromConf( hGameConf, "CTFProjectile_Coil::RocketTouch" );
	if( !hCoilTouch.Enable( Hook_Pre, Detour_CoilTouch ) ) {
		SetFailState( "Detour setup for CTFProjectile_Coil::RocketTouch failed" );
	}
	hCoilSpeed = DynamicDetour.FromConf( hGameConf, "CTFCoilGun::GetProjectileSpeed" );
	if( !hCoilSpeed.Enable( Hook_Post, Detour_CoilProjectileSpeed ) ) {
		SetFailState( "Detour setup for CTFCoilGun::GetProjectileSpeed failed" );
	}
	hCollideTeamReset = DynamicDetour.FromConf( hGameConf, "CBaseProjectile::ResetCollideWithTeammates" );
	if( !hCollideTeamReset.Enable( Hook_Pre, Detour_CollideTeamReset ) ) {
		SetFailState( "Detour setup for CBaseProjectile::ResetCollideWithTeammates failed" );
	}

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayerShared::Heal" );
	PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_ByValue, VDECODE_FLAG_ALLOWNULL );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	hCallHeal = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayerShared::StopHealing" );
	PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer );
	hCallStopHeal = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayerShared::GetHealerByIndex" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	hGetHealerIndex = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFPlayer::GetMaxHealth" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	hGetMaxHealth = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayerShared::GetBuffedMaxHealth" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	hGetBuffedMaxHealth = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CWeaponMedigun::GetHealRate" );
	PrepSDKCall_SetReturnInfo( SDKType_Float, SDKPass_Plain );
	hCallHealRate = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFPlayer::TakeHealth" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	hCallTakeHealth = EndPrepSDKCall();

	delete hGameConf;

	if( bLateLoad ) {
		int iIndex = MaxClients + 1;
		while( ( iIndex = FindEntityByClassname( iIndex, "tf_weapon_medigun" ) ) != -1 ) {
			HookMedigun( iIndex );
		}
	}

	for( int i = 0; i < sizeof(g_iBeamEmitters); i++ ) {
		g_iBeamEmitters[i][0] = -1;
		g_iBeamEmitters[i][1] = -1;
	}
}

public void OnMapStart() {
	PrecacheSound( "weapons/angel_shield_on.wav" );
}

public void OnTakeDamageTF( int iTarget, Address aDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aDamageInfo );

	OathbreakerDamageMult( iTarget, tfInfo );
}

public void OnClientDisconnect( int iClient ) {
	DeleteBeamEmitter( iClient, true );
	DeleteBeamEmitter( iClient, false );

	DeleteDummyGun( iClient );

	DeleteBeamTarget( iClient );

	StopRadialHeal( iClient );
}

public void OnEntityCreated( int iThis, const char[] szClassname ) {
	if( strcmp( szClassname, "tf_weapon_medigun", false ) != 0 )
		return;

	HookMedigun( iThis );
}

Action Event_PostInventory( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	//SetEntPropFloat( iPlayer, Prop_Data, "m_flGravity", 0.9 );

	g_flMultTable[iPlayer] = AttribHookFloat( 0.5, iPlayer, "custom_maximum_overheal" );
	if( RoundToFloor( AttribHookFloat( 0.0, iPlayer, "custom_medigun_type" ) ) == CMEDI_OATH ) {
		StartRadialHeal( iPlayer );
		return Plugin_Continue;
	}
	else 
	{
		g_bRadiusHealer[ iPlayer ] = false;
		Tracker_Remove( iPlayer, "Rage" );
	}

	static char szFuck[128];
	AttribHookString( "test", iPlayer, "custom_projectile_model", szFuck, sizeof( szFuck ) );
	PrintToServer( "here's the thing: %s", szFuck );

	//do oathbreaker projectile setup here

	int iMedigun = GetEntityInSlot( iPlayer, 1 );
	if( !IsValidEntity( iMedigun ) )
		return Plugin_Continue;

	static char szWeaponName[64];
	GetEntityClassname( iMedigun, szWeaponName, sizeof(szWeaponName) );
	if( StrEqual( szWeaponName, "tf_weapon_medigun" ) ) {
		CreateDummyGun( iPlayer, iMedigun );
		SetEntPropEnt( iMedigun, Prop_Send, "m_hHealingTarget", -1 );
		g_iOldTargets[iPlayer] = 69420;
	}
	return Plugin_Continue;
}

Action Event_PlayerKilled( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );
	
	DeleteBeamEmitter( iPlayer, false );
	DeleteBeamEmitter( iPlayer, true );
	DeleteBeamTarget( iPlayer );
	DeleteDummyGun( iPlayer );
	
	return Plugin_Continue;
}

Action Event_PlayerHealed( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iHealer = hEvent.GetInt( "healer" );
	iHealer = GetClientOfUserId( iHealer );
	int iPatient = hEvent.GetInt( "patient" );
	iPatient = GetClientOfUserId( iPatient );
	int iHealed = hEvent.GetInt( "amount" );

	if( !IsValidPlayer( iHealer ) || !IsValidPlayer( iPatient ) )
		return Plugin_Continue;

	if( !g_bRadiusHealer[ iHealer ] ) 
		return Plugin_Continue;

	float flTrackerVal = Tracker_GetValue( iHealer, "Rage" );
	float flTrackerAdd = flTrackerVal + ( float( iHealed ) * 0.1 );
	Tracker_SetValue( iHealer, "Rage", MinFloat( 100.0, flTrackerAdd ) );

	g_flLastHealed[ iHealer ] = GetGameTime();

	return Plugin_Continue;
}

MRESReturn Detour_GetBuffedMaxHealth( Address aThis, DHookReturn hReturn ) {
	int iPlayer = GetPlayerFromShared( aThis );
	int iMaxBase = SDKCall( hGetMaxHealth, iPlayer );

	float flLargestMult = 0.0;
	int iHealers = GetEntProp( iPlayer, Prop_Send, "m_nNumHealers" );

	if( iHealers == 0 )
		flLargestMult = 0.5;
	else for( int i = 0; i < iHealers; i++ ) {
		Address aHealer = SDKCall( hGetHealerIndex, aThis, i );
		int iIndex = GetEntityFromAddress( aHealer );
		if( !IsValidPlayer( iIndex ) )
			continue;

		float flNewMult = g_flMultTable[iIndex];
		flLargestMult = MaxFloat( flLargestMult, flNewMult );
	}

	flLargestMult *= AttribHookFloat( 1.0, iPlayer, "custom_maximum_overheal_self" );

	int iDiff = RoundToCeil( float( iMaxBase ) * flLargestMult );

	iDiff /= 5;
	iDiff *= 5;

	hReturn.Value = MaxInt( iMaxBase + iDiff, iMaxBase );
	return MRES_ChangedOverride;
}

float g_flLastSound[MAXPLAYERS+1];
MRESReturn Detour_UpdateCharge( Address aThis, DHookParam hParams ) {
	bool bBioUbered = false;
	bool bQuickFixed = false;

	int iPlayer = GetPlayerFromShared( aThis );
	int iMyMedigun = GetEntityInSlot( iPlayer, 1 );

	bool bSelfUber = false;

	int iSourcePlayer = -1;
	int iSourceWeapon = -1;

	if( IsValidEdict( iMyMedigun ) ) {
		if( HasEntProp( iMyMedigun, Prop_Send, "m_bChargeRelease" ) && GetEntProp( iMyMedigun, Prop_Send, "m_bChargeRelease" ) && !GetEntProp( iMyMedigun, Prop_Send, "m_bHolstered" ) )
		{
			int iMyMediType = RoundToNearest( AttribHookFloat( 0.0, iMyMedigun, "custom_medigun_type" ) );
			if( iMyMediType == CMEDI_QFIX ) {
				bQuickFixed = true;
				bSelfUber = true;
			}
				
			if( iMyMediType == CMEDI_BWP )
				bBioUbered = true;

			iSourcePlayer = iPlayer;
			iSourceWeapon = iMyMedigun;
		}
	}

	int iHealers = GetEntProp( iPlayer, Prop_Send, "m_nNumHealers" );
	for( int i = 0; i < iHealers; i++ ) {
		Address aHealer = SDKCall( hGetHealerIndex, aThis, i );
		if( aHealer == Address_Null )
			continue;
		int iHealer = GetEntityFromAddress( aHealer );
		if( !IsValidPlayer( iHealer ) )
			continue;

		int iMedigun = GetEntityInSlot( iHealer, 1 );
		if( !HasEntProp( iMedigun, Prop_Send, "m_bChargeRelease" ) )
			continue;
		if( !GetEntProp( iMedigun, Prop_Send, "m_bChargeRelease" ) )
			continue;

		int iMediType = RoundToNearest( AttribHookFloat( 0.0, iMedigun, "custom_medigun_type" ) );
		if( iMediType == CMEDI_QFIX ) {
			bQuickFixed = true;
		}
			
		if( iMediType == CMEDI_BWP ) {
			bBioUbered = true;
		}
			
		iSourcePlayer = iHealer;
		iSourceWeapon = iMedigun;
	}

	if( bBioUbered ) {
		AddCustomCond( iPlayer, TFCC_TOXINUBER );
		SetCustomCondSourcePlayer( iPlayer, TFCC_TOXINUBER, iSourcePlayer );
		SetCustomCondSourceWeapon( iPlayer, TFCC_TOXINUBER, iSourceWeapon );
	}
	else
		RemoveCustomCond( iPlayer, TFCC_TOXINUBER );

	if( bQuickFixed ) {
		if( AddCustomCond( iPlayer, TFCC_QUICKUBER ) && GetGameTime() > g_flLastSound[iPlayer] + 0.1 ) {
			EmitGameSoundToAll( "TFPlayer.InvulnerableOn", iPlayer );
			g_flLastSound[iPlayer] = GetGameTime();
		}

		SetCustomCondLevel( iPlayer, TFCC_QUICKUBER, view_as<int>( bSelfUber ) );
	}		
	else if( RemoveCustomCond( iPlayer, TFCC_QUICKUBER ) && GetGameTime() > g_flLastSound[iPlayer] + 0.1 ) {
		EmitGameSoundToAll( "TFPlayer.InvulnerableOff", iPlayer );
		g_flLastSound[iPlayer] = GetGameTime();
	} 
		

	return MRES_Ignored;
}

MRESReturn Hook_MedigunHolster( int iThis ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );

	if( IsValidPlayer( iOwner ) ) {
		DeleteBeamEmitter( iOwner, true );
		DeleteBeamEmitter( iOwner, false );

		DeleteBeamTarget( iOwner );

		SetEntPropEnt( iThis, Prop_Send, "m_hHealingTarget", -1 );
		g_iOldTargets[iOwner] = 69420;
	}
	return MRES_Handled;
}

MRESReturn Hook_MedigunSecondaryPost( int iThis ) {
	switch( RoundToNearest( AttribHookFloat( 0.0, iThis, "custom_medigun_type" ) ) ) {
	case CMEDI_ANGEL: {
		return AngelGunUber( iThis );
	}	
	}

	return MRES_Ignored;
}

void HookMedigun( int iMedigun ) {
	hMedigunSecondary.HookEntity( Hook_Post, iMedigun, Hook_MedigunSecondaryPost );
	hMedigunPostframe.HookEntity( Hook_Post, iMedigun, Hook_ItemPostFrame );
	hMedigunHolster.HookEntity( Hook_Post, iMedigun, Hook_MedigunHolster );
}

/*
	CUSTOM MEDI BEAM
*/

#define EF_BONEMERGE                (1 << 0)
#define EF_NOSHADOW                 (1 << 4)
#define EF_NORECEIVESHADOW          (1 << 6)
#define EF_PARENT_ANIMATES          (1 << 9)

static char g_szMedicParticles[][][] = {
	// Stock
	{
		"medicgun_invulnstatus_fullcharge_%s_new",
		"medicgun_beam_%s_new",
		"medicgun_beam_%s_invun_new"
	},
	// Kritzkrieg
	{
		"medicgun_invulnstatus_fullcharge_%s_new",
		"kritz_beam_%s_new",
		"kritz_beam_%s_invun_new"
	},
	// Guardian Angel
	{
		"medicgun_invulnstatus_fullcharge_%s_new",
		"overhealer_%s_beam",
		"overhealer_%s_beam"
	},
	// Bio Waste Pump
	{
		"biowastepump_invulnstatus_fullcharge_%s",
		"biowastepump_beam_%s",
		"biowastepump_beam_enemy"
	}
};

enum {
	MODE_CHARGED = 0,
	MODE_HEALING,
	MODE_UBER
}

static char g_szTeamStrings[][] = {
	"red",
	"blue",
	"green",
	"yellow"
};

//forces particle systems to respect settransmit
public void SetFlags(int iEdict) { 
	SetEdictFlags(iEdict, 0);
} 

void CreateMedibeamString( char[] szBuffer, int iBufferSize, int iWeapon ) {
	int iBeam = RoundToFloor( AttribHookFloat( 0.0, iWeapon, "custom_medibeamtype" ) );
	int iMode = GetHealingMode( iWeapon );
	int iTeam = GetEntProp( iWeapon, Prop_Send, "m_iTeamNum" ) - 2;

	Format( szBuffer, iBufferSize, g_szMedicParticles[ iBeam ][ iMode ], g_szTeamStrings[ iTeam ] );
}
int GetHealingMode( int iWeapon ) {
	int iHealTarget = GetEntPropEnt( iWeapon, Prop_Send, "m_hHealingTarget" );
	int iOwner = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwnerEntity" );

	if( iHealTarget != -1 ) {
		int iType = RoundToFloor( AttribHookFloat( 0.0, iWeapon, "custom_medigun_type" ) );
		if( TF2_GetClientTeam( iHealTarget ) != TF2_GetClientTeam( iOwner ) && iType == CMEDI_BWP )
			return MODE_UBER;

		if( GetEntProp( iWeapon, Prop_Send, "m_bChargeRelease" ) && iType != 2 )
			return MODE_UBER;

		return MODE_HEALING;
	}

	return MODE_CHARGED;
}

/* 
	Parenting of the player's weapons only appears to happen locally, so what we're doing here is creating a dummy prop to parent the beam to
*/

int GetDummyGun( int iPlayer ) {
	return g_iDummyGuns[ iPlayer ];
}
int CreateDummyGun( int iPlayer, int iMedigun ) {
	if( GetDummyGun( iPlayer ) != -1 )
		DeleteDummyGun( iPlayer );

	int iDummyGun = CreateEntityByName( "prop_dynamic_override" );
	static char szModelName[64];

	FindModelString( GetEntProp( iMedigun, Prop_Send, "m_iWorldModelIndex" ), szModelName, sizeof( szModelName ) );
	SetEntityModel( iDummyGun, szModelName );
	
	DispatchSpawn( iDummyGun );
	ActivateEntity( iDummyGun );

	SetEntProp( iDummyGun, Prop_Send, "m_fEffects", 32|EF_BONEMERGE|EF_NOSHADOW|EF_NORECEIVESHADOW|EF_PARENT_ANIMATES);
	ParentModel( iDummyGun, iMedigun, "weapon_bone_l" );

	SetFlags(iDummyGun);

	g_iDummyGuns[ iPlayer ] = iDummyGun;
	return iDummyGun;
}
void DeleteDummyGun( int iPlayer ) {
	int iDummyGun = g_iDummyGuns[ iPlayer ];
	if( IsValidEntity( iDummyGun ) ) {
		RemoveEntity( iDummyGun );
	}

	g_iDummyGuns[ iPlayer ] = -1;
}

/*
	We need 2 different info_particle_systems: one parented to the viewmodel in first person,
	and one parented to the world model in third person, visible to everyone else
*/

int GetBeamEmitter( int iPlayer, bool bClient ) { 
	return g_iBeamEmitters[ iPlayer ][ view_as<int>(bClient) ];
}
int CreateBeamEmitter( int iPlayer, bool bClient ) {
	if( GetBeamEmitter( iPlayer, bClient ) != -1 )
		DeleteBeamEmitter( iPlayer, bClient );

	int iEmitter = CreateEntityByName( "info_particle_system" );
	
	g_iBeamEmitters[ iPlayer ][ view_as<int>(bClient) ] = iEmitter;
	SetBeamParticle( iPlayer, bClient );

	SetFlags(iEmitter);
	SDKHook( iEmitter, SDKHook_SetTransmit, Hook_EmitterTransmit );

	DispatchSpawn( iEmitter );
	ActivateEntity( iEmitter );
	
	SetEntPropEnt( iEmitter, Prop_Send, "m_hOwnerEntity", iPlayer );
	//janky hack: store the behavior of the emitter in some dataprop that isn't used
	SetEntProp( iEmitter, Prop_Data, "m_iHealth", view_as<int>(bClient) );
	return iEmitter;
}
void DeleteBeamEmitter( int iPlayer, bool bClient ) {
	int iEmitter = g_iBeamEmitters[ iPlayer ][ view_as<int>(bClient) ];
	if( IsValidEntity( iEmitter ) ) {
		AcceptEntityInput( iEmitter, "Stop" );
		RemoveEntity( iEmitter );
	}
	g_iBeamEmitters[ iPlayer ][ view_as<int>(bClient) ] = -1;
}
void SetBeamParticle( int iPlayer, bool bClient ) {
	static char szBeamName[64];
	int iWeapon = GetEntityInSlot( iPlayer, 1 );
	if( iWeapon == -1 )
		return;

	GetEntityClassname( iWeapon, szBeamName, sizeof( szBeamName ) );
	if( !StrEqual( szBeamName, "tf_weapon_medigun" ) )
		return;

	CreateMedibeamString( szBeamName, sizeof( szBeamName ), iWeapon );
	DispatchKeyValue( GetBeamEmitter( iPlayer, bClient ), "effect_name", szBeamName );
}

Action Hook_EmitterTransmit( int iEntity, int iClient ) {
	SetFlags( iEntity );
	int iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" );
	//janky hack: store the behavior of the emitter in some dataprop that isn't used
	bool bIsClientEmitter = GetEntProp( iEntity, Prop_Data, "m_iHealth" ) == 1;

	
	if( iClient == iOwner ) {
		return bIsClientEmitter ? Plugin_Continue : Plugin_Handled;
		
	}
	return bIsClientEmitter ? Plugin_Handled : Plugin_Continue;
}

void AttachBeam_FPS( int iPlayer, int iWeapon ) {
	int iEmitter = GetBeamEmitter( iPlayer, true );
	bool bIsCModel = GetEntProp( iWeapon, Prop_Send, "m_iViewModelType" ) == 1;

	int iViewmodel = GetEntPropEnt( iPlayer, Prop_Send, "m_hViewModel" );
	ParentModel( iEmitter, iViewmodel, bIsCModel ? "weapon_bone_l" : "muzzle" );
	SetFlags( iEmitter );
}
void AttachBeam_TPS( int iPlayer ) {
	int iEmitter = GetBeamEmitter( iPlayer, false );
	int iDummy = GetDummyGun( iPlayer );
	ParentModel( iEmitter, iDummy, "muzzle" );
	SetFlags( iEmitter );
}

/*
	Attaching the beam directly to a player directs to their feet, so we
	need a new object to act as a target point.
*/

void CreateBeamTargetPoint( int iPlayer, int iTargetPlayer ) {
	if( g_iBeamTargetPoints[ iPlayer ] != -1 ) {
		RemoveEntity( g_iBeamTargetPoints[ iPlayer ] );
		g_iBeamTargetPoints[ iPlayer ] = -1;
	}

	int iPoint = CreateEntityByName( "prop_dynamic_override" );
	DispatchKeyValue( iPoint, "model", "models/error.mdl");
	DispatchKeyValue( iPoint, "solid", "0" );

	float flVec[3];
	GetEntPropVector( iTargetPlayer, Prop_Send, "m_vecOrigin", flVec );
	flVec[2] += 50.0;

	TeleportEntity( iPoint, flVec );
	ParentModel( iPoint, iTargetPlayer );
	
	SetEntPropEnt( GetBeamEmitter( iPlayer, true ), Prop_Send, "m_hControlPointEnts", iPoint );
	SetEntPropEnt( GetBeamEmitter( iPlayer, false ), Prop_Send, "m_hControlPointEnts", iPoint );

	DispatchSpawn( iPoint );
	SetEntProp( iPoint, Prop_Send, "m_fEffects", 32|EF_NOSHADOW|EF_NORECEIVESHADOW );

	g_iBeamTargetPoints[ iPlayer ] = iPoint;
}
void DeleteBeamTarget( int iPlayer ) {
	int iTarget = g_iBeamTargetPoints[ iPlayer ];
	if( IsValidEntity( iTarget ) )
		RemoveEntity( iTarget );

	g_iBeamTargetPoints[ iPlayer ] = -1;
}

void UpdateMedigunBeam( int iPlayer ) {
	int iWeapon = GetEntPropEnt( iPlayer, Prop_Send, "m_hActiveWeapon" );

	static char szWeaponName[64];
	GetEntityClassname( iWeapon, szWeaponName, sizeof(szWeaponName) );
	if( !StrEqual( szWeaponName, "tf_weapon_medigun" ) ) {
		DeleteBeamEmitter( iPlayer, false );
		DeleteBeamEmitter( iPlayer, true );
		return;
	}
		
	int iHealTarget = GetEntPropEnt( iWeapon, Prop_Send, "m_hHealingTarget" );

	CreateBeamEmitter( iPlayer, false );
	CreateBeamEmitter( iPlayer, true );
	AttachBeam_FPS( iPlayer, iWeapon );
	AttachBeam_TPS( iPlayer );

	if( iHealTarget != -1 ) {
		CreateBeamTargetPoint( iPlayer, iHealTarget );
		AcceptEntityInput( g_iBeamEmitters[ iPlayer ][ 0 ], "Start" );
		AcceptEntityInput( g_iBeamEmitters[ iPlayer ][ 1 ], "Start" );
		return;
	}

	float flThreshold = RoundToFloor( AttribHookFloat( 0.0, iWeapon, "custom_medigun_type" ) ) == CMEDI_ANGEL ? 0.25 : 1.0;
	if( GetEntPropFloat( iWeapon, Prop_Send, "m_flChargeLevel" ) >= flThreshold ) {
		AcceptEntityInput( g_iBeamEmitters[ iPlayer ][ 0 ], "Start" );
		AcceptEntityInput( g_iBeamEmitters[ iPlayer ][ 1 ], "Start" );
		return;
	}
}

MRESReturn Hook_ItemPostFrame( int iMedigun ) {
	int iTarget = GetEntPropEnt( iMedigun, Prop_Send, "m_hHealingTarget" );
	int iOwner = GetEntPropEnt( iMedigun, Prop_Send, "m_hOwnerEntity" );

	bool bIsCharging = view_as<bool>( GetEntProp( iMedigun, Prop_Send, "m_bChargeRelease" ) );

	if( iTarget != g_iOldTargets[ iOwner ] ) {
		UpdateMedigunBeam( iOwner );
	}
	else if( g_bOldCharging[ iOwner ] != bIsCharging ) {
		//readd self into target's healing list to update quickfix uber heal rate
		if( iTarget != -1 && RoundToFloor( AttribHookFloat( 0.0, iMedigun, "custom_medigun_type" ) ) == CMEDI_QFIX && g_bOldCharging[ iOwner ] && !bIsCharging ) {
			Address aShared = GetSharedFromPlayer( iTarget );

			float flHealRate = SDKCall( hCallHealRate, iMedigun );
			SDKCall( hCallHeal, aShared, iOwner, flHealRate, -1, false );
		}
		UpdateMedigunBeam( iOwner );
	}

	g_iOldTargets[ iOwner ] = iTarget;
	g_bOldCharging[ iOwner ] = bIsCharging;

	return MRES_Handled;
}

/*
	BIO WASTE PUMP
*/

#define BWP_TOXIN_MULTIPLIER 2.0 //multiplier for the amount of time that toxin should be added while healing enemies

MRESReturn Detour_MedigunThinkPost( int iThis ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	int iTarget = GetEntPropEnt( iThis, Prop_Send, "m_hHealingTarget" );

	if( !IsValidPlayer( iOwner ) || !IsValidPlayer( iTarget ) )
		return MRES_Ignored;

	if( RoundToFloor( AttribHookFloat( 0.0, iThis, "custom_medigun_type" ) ) != CMEDI_BWP )
		return MRES_Ignored;

	if( TF2_GetClientTeam( iTarget ) == TF2_GetClientTeam( iOwner ) ) {
		if( !HasCustomCond( iTarget, TFCC_TOXINPATIENT ) ) {
			AddCustomCond( iTarget, TFCC_TOXINPATIENT );
			SetCustomCondSourcePlayer( iTarget, TFCC_TOXINPATIENT, iOwner );
			SetCustomCondSourceWeapon( iTarget, TFCC_TOXINPATIENT, iThis );
		}

		SetCustomCondDuration( iTarget, TFCC_TOXINPATIENT, 0.5, false );
		return MRES_Handled;
	}
	else if( !HasCustomCond( iTarget, TFCC_TOXIN ) ) {
		AddCustomCond( iTarget, TFCC_TOXIN );
		SetCustomCondSourcePlayer( iTarget, TFCC_TOXIN, iOwner );
		SetCustomCondSourceWeapon( iTarget, TFCC_TOXIN, iThis );
		SetCustomCondDuration( iTarget, TFCC_TOXIN, 0.6, true );
	} else	
		SetCustomCondDuration( iTarget, TFCC_TOXIN, MEDIGUN_THINK_INTERVAL * BWP_TOXIN_MULTIPLIER, true );

	return MRES_Handled;
}

MRESReturn Detour_AllowedToHealPre( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	int iIsPump = RoundToFloor( AttribHookFloat( 0.0, iThis, "custom_medigun_type" ) );
	if( iIsPump != CMEDI_BWP ) return MRES_Ignored;

	hReturn.Value = false;

	int iHealer = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	int iTarget = hParams.Get( 1 );

	if( TF2_GetClientTeam( iTarget ) == TF2_GetClientTeam( iHealer ) )
		return MRES_Ignored;

	hReturn.Value = true;
	return MRES_Supercede;
}

//just to bypass adding the medigun to the enemy's healer list
MRESReturn Detour_HealStartPre( Address aThis, DHookParam hParams ) {
	int iTarget = GetPlayerFromShared( aThis );
	int iHealer = hParams.Get( 1 );

	if( TF2_GetClientTeam( iTarget ) == TF2_GetClientTeam( iHealer ) )
		return MRES_Ignored;

	return MRES_Supercede;
}
MRESReturn Detour_HealStopPre( Address aThis, DHookParam hParams ) {
	int iTarget = GetPlayerFromShared( aThis );
	int iHealer = hParams.Get( 1 );

	if( TF2_GetClientTeam( iTarget ) == TF2_GetClientTeam( iHealer ) ) 
		return MRES_Ignored;

	return MRES_Supercede;
}

/*
	GUARDIAN ANGEL
*/

MRESReturn AngelGunUber( int iMedigun ) {
	SetEntProp( iMedigun, Prop_Send, "m_bChargeRelease", false );

	float flChargeLevel = GetEntPropFloat( iMedigun, Prop_Send, "m_flChargeLevel" );
	if( flChargeLevel < 0.25 )
		return MRES_Ignored;

	int iOwner = GetEntPropEnt( iMedigun, Prop_Send, "m_hOwnerEntity" );

	bool bAppliedCharge = false;
	int iTarget = GetEntPropEnt( iMedigun, Prop_Send, "m_hHealingTarget" );
	if( IsValidPlayer( iTarget ) && IsPlayerAlive( iTarget ) ) {
		if( !HasCustomCond( iTarget, TFCC_ANGELSHIELD ) && !HasCustomCond( iTarget, TFCC_ANGELINVULN ) ) {
			EmitSoundToAll( "weapons/angel_shield_on.wav", iTarget, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEVOL, 0.75 );
			AddCustomCond( iTarget, TFCC_ANGELSHIELD );
			SetCustomCondSourcePlayer( iTarget, TFCC_ANGELSHIELD, iOwner );
			SetCustomCondSourceWeapon( iTarget, TFCC_ANGELSHIELD, iMedigun );
			bAppliedCharge = true;
		}
	}

	if( !HasCustomCond( iOwner, TFCC_ANGELSHIELD ) && !HasCustomCond( iOwner, TFCC_ANGELINVULN ) ) {
		AddCustomCond( iOwner, TFCC_ANGELSHIELD );
		EmitSoundToAll( "weapons/angel_shield_on.wav", iOwner, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEVOL, 0.75 );
		SetCustomCondSourcePlayer( iOwner, TFCC_ANGELSHIELD, iOwner );
		SetCustomCondSourceWeapon( iOwner, TFCC_ANGELSHIELD, iMedigun );
		bAppliedCharge = true;
	}

	if( bAppliedCharge ) {
		SetEntPropFloat( iMedigun, Prop_Send, "m_flChargeLevel", flChargeLevel - 0.25 );
		return MRES_Handled;
	}
		
	return MRES_Ignored;
}

/*
	QUICK FIX
*/

MRESReturn Detour_MediHealRate( int iMedigun, DHookReturn hReturn ) {
	if( GetEntProp( iMedigun, Prop_Send, "m_bChargeRelease" ) && RoundToNearest( AttribHookFloat( 0.0, iMedigun, "custom_medigun_type" ) ) == CMEDI_QFIX ) {
		float flRes = hReturn.Value;
		hReturn.Value = flRes * 3.0;
		return MRES_ChangedOverride;
	}
	return MRES_Ignored;
}



//need to reapply the quick-fix to the target's healer list to update the heal rate when ubering
Action Event_DeployUber( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iHealer = hEvent.GetInt( "userid" );
	iHealer = GetClientOfUserId( iHealer );
	
	int iMedigun = GetEntityInSlot( iHealer, 1 );
	if( !HasEntProp( iMedigun, Prop_Send, "m_bChargeRelease" ) )
		return Plugin_Continue;

	int iTarget = GetEntPropEnt( iMedigun, Prop_Send, "m_hHealingTarget" );
	if( !IsValidPlayer( iTarget ) )
		return Plugin_Continue;

	if( RoundToNearest( AttribHookFloat( 0.0, iMedigun, "custom_medigun_type" ) ) != CMEDI_QFIX )
		return Plugin_Continue;

	Address aShared = GetSharedFromPlayer( iTarget );

	float flHealRate = SDKCall( hCallHealRate, iMedigun );
	SDKCall( hCallHeal, aShared, iHealer, flHealRate, -1, false );

	return Plugin_Continue;
}

/*
	OATHBREAKER
*/

static char g_szOathParticles[][] = {
	"oathbreaker_emitter_red",
	"oathbreaker_emitter_blue",
	"oathbreaker_emitter_green",
	"oathbreaker_emitter_yellow"
};

static char g_szOathHealParticles[][] = {
	"oathbreaker_heal_red",
	"oathbreaker_heal_blue",
	"oathbreaker_heal_green",
	"oathbreaker_heal_yellow"
};

const float RADIUSHEAL_INTERVAL = 0.5;

int g_iRadialHealerEmitters[MAXPLAYERS+1] = { -1, ... };
int g_iRadialPatientEmitters[MAXPLAYERS+1] = { -1, ... };

int g_iRadialPatientBits[MAXPLAYERS+1][2]; //bitfields for each player to track who's giving a radial heal
bool g_bRadialPatientHealed[MAXPLAYERS+1] = { false, ... };

void StartRadialHeal( int iPlayer ) {
	Tracker_Create( iPlayer, "Rage", 0.0 );
	CreateRadialEmitter( iPlayer );
	CreateTimer( RADIUSHEAL_INTERVAL, Timer_RadialHeal, iPlayer, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT );
	g_bRadiusHealer[ iPlayer ] = true;
}

void CreateRadialEmitter( int iPlayer ) {
	RemoveRadialEmitter( iPlayer );

	int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) - 2;
	int iEmitter = CreateEntityByName( "info_particle_system" );

	DispatchKeyValue( iEmitter, "effect_name", g_szOathParticles[ iTeam ] );

	float vecPos[3]; GetClientAbsOrigin( iPlayer, vecPos );
	TeleportEntity( iEmitter, vecPos );

	ParentModel( iEmitter, iPlayer );

	DispatchSpawn( iEmitter );
	ActivateEntity( iEmitter );
	AcceptEntityInput( iEmitter, "Start" );

	g_iRadialHealerEmitters[ iPlayer ] = EntIndexToEntRef( iEmitter );
}
void RemoveRadialEmitter( int iPlayer ) {
	int iEmitter = EntRefToEntIndex( g_iRadialHealerEmitters[ iPlayer ] );
	if( iEmitter != -1 )
		RemoveEntity( iEmitter );

	g_iRadialHealerEmitters[ iPlayer ] = -1;
}

void StopRadialHeal( int iPlayer ) {
	for( int i = 1; i <= MaxClients; i++ ) {
		if( i == iPlayer || !IsClientInGame( i ) )
			continue;

		Address aShared = GetSharedFromPlayer( i );
		SDKCall( hCallStopHeal, aShared, iPlayer );
		
		int iField = iPlayer != 0 ? iPlayer / 32 : 0;
		int iBit = 1 << ( iPlayer % 32);
		g_iRadialPatientBits[ i ][ iField ] &= ~iBit;

		UpdatePatientRadialParticles( i );
	}
	RemoveRadialEmitter( iPlayer );
}

//TODO: optimize this
Action Timer_RadialHeal( Handle hTimer, int iPlayer ) {
	if( !IsClientConnected( iPlayer ) || !IsClientInGame( iPlayer ) || !IsPlayerAlive( iPlayer ) || RoundToFloor( AttribHookFloat( 0.0, iPlayer, "custom_medigun_type" ) ) != CMEDI_OATH ) {
		StopRadialHeal( iPlayer );
		return Plugin_Stop;
	}	

	float vecSource[3]; GetClientAbsOrigin( iPlayer, vecSource );
	bool bIsInRadius[MAXPLAYERS+1] = { false, ... };

	int iTarget = -1;
	while ( ( iTarget = FindEntityInSphere( iTarget, vecSource, 300.0 ) ) != -1 ) {
		if( !IsValidPlayer( iTarget ) )
			continue;

		if( iTarget == iPlayer )
			continue;

		if( TF2_GetClientTeam( iTarget ) != TF2_GetClientTeam( iPlayer ) )
			continue;

		bIsInRadius[ iTarget ] = true;
	}

	for( int i = 1; i <= MaxClients; i++ ) {
		if( i == iPlayer || !IsClientInGame( i ) )
			continue;

		Address aShared = GetSharedFromPlayer( i );

		if( bIsInRadius[i] ) {
			SDKCall( hCallHeal, aShared, iPlayer, 10.0, -1, false );

			int iField = iPlayer != 0 ? iPlayer / 32 : 0;
			int iBit = 1 << ( iPlayer % 32);
			
			g_iRadialPatientBits[ i ][ iField ] |= iBit;

			UpdatePatientRadialParticles( i );

			g_flLastHealed[ iPlayer ] = GetGameTime();
		}
		else {
			SDKCall( hCallStopHeal, aShared, iPlayer );

			int iField = iPlayer != 0 ? iPlayer / 32 : 0;
			int iBit = 1 << ( iPlayer % 32);
			g_iRadialPatientBits[ i ][ iField ] &= ~iBit;

			UpdatePatientRadialParticles( i );
		}
	}

	if( GetGameTime() > g_flLastHealed[ iPlayer ] + 8.0 ) {
		float flTrackerVal = Tracker_GetValue( iPlayer, "Rage" ) * 0.95;
		Tracker_SetValue( iPlayer, "Rage", MaxFloat( 0.0, flTrackerVal ) );
	}
	else if( GetGameTime() > g_flLastHealed[ iPlayer ] + 6.0 ) {
		float flTrackerVal = Tracker_GetValue( iPlayer, "Rage" ) * 0.98;
		Tracker_SetValue( iPlayer, "Rage", MaxFloat( 0.0, flTrackerVal ) );
	}

	return Plugin_Continue;
}

void CreatePatientRadialParticles( int iPlayer ) {
	RemovePatientRadialParticles( iPlayer );

	PrintToServer("test");

	int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) - 2;
	int iEmitter = CreateEntityByName( "info_particle_system" );

	DispatchKeyValue( iEmitter, "effect_name", g_szOathHealParticles[ iTeam ] );

	float vecPos[3]; GetClientAbsOrigin( iPlayer, vecPos );
	TeleportEntity( iEmitter, vecPos );

	ParentModel( iEmitter, iPlayer );

	DispatchSpawn( iEmitter );
	ActivateEntity( iEmitter );
	AcceptEntityInput( iEmitter, "Start" );

	g_iRadialPatientEmitters[ iPlayer ] = EntIndexToEntRef( iEmitter );
}
void UpdatePatientRadialParticles( int iPlayer ) {
	bool bHasHealer = ( g_iRadialPatientBits[ iPlayer ][0] != 0 || g_iRadialPatientBits[ iPlayer ][1] != 0 );
	if( bHasHealer != g_bRadialPatientHealed[ iPlayer ] ) {
		if( bHasHealer )
			CreatePatientRadialParticles( iPlayer );
		else
			RemovePatientRadialParticles( iPlayer );
	}
	g_bRadialPatientHealed[ iPlayer ] = bHasHealer;
}
void RemovePatientRadialParticles( int iPlayer ) {
	int iEmitter = EntRefToEntIndex( g_iRadialPatientEmitters[ iPlayer ] );
	if( iEmitter != -1 )
		RemoveEntity( iEmitter );

	g_iRadialPatientEmitters[ iPlayer ] = -1;
}

MRESReturn Hook_ProjectileSpeed( int iThis, DHookReturn hReturn ) {
	//vtable 442
}

void OathbreakerDamageMult( int iTarget, TFDamageInfo tfInfo ) {
	int iAttacker = tfInfo.iAttacker;
	if( !IsValidPlayer( iAttacker ) )
		return; 

	if( RoundToFloor( AttribHookFloat( 0.0, iAttacker, "custom_medigun_type" ) ) != CMEDI_OATH )
		return;

	float flMult = Tracker_GetValue( iAttacker, "Rage" );
	tfInfo.flDamage *= RemapValClamped(flMult, 0.0, 100.0, 1.0, 1.3 );
}

/*
	BEAM THING
*/

MRESReturn Detour_CoilTouch( int iThis, DHookParam hParams ) {
	int iOther = hParams.Get( 1 );

	//StoreToEntity( iThis, 1204, 69.0, NumberType_Int32 );

	if( !IsValidPlayer( iOther ) )
		return MRES_Ignored;

	int iOriginalLauncher =  GetEntPropEnt( iThis, Prop_Send, "m_hOriginalLauncher" );
	if( RoundToFloor( AttribHookFloat( 0.0, iOriginalLauncher, "custom_medigun_type" ) ) != CMEDI_BEAM )
		return MRES_Ignored;

	float flDamage = LoadFromEntity( iThis, 1204 );

	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	bool bSpyGetsHealed = false;
	if( TF2_GetClientTeam( iOwner ) != TF2_GetClientTeam( iOther ) && !bSpyGetsHealed ) {
		StoreToEntity( iThis, 1204, flDamage * 0.25, NumberType_Int32 );
		return MRES_Ignored;
	}

	float flTimeSinceDamage = GetGameTime() - GetEntPropFloat( iOther, Prop_Send, "m_flLastDamageTime" );
	float flScale = RemapValClamped( flTimeSinceDamage, 10.0, 15.0, 1.0, 3.0 );
	flDamage *= flScale;

	Address aShared = GetSharedFromPlayer( iOther );
	int iMaxHealth = SDKCall( hGetBuffedMaxHealth, aShared );
	int iHealth = GetClientHealth( iOther );

	int iDiff = iMaxHealth - iHealth;

	float flGive = MinFloat( float( iDiff ), flDamage );
	int iGave = SDKCall( hCallTakeHealth, iOther, flGive, 1 << 1 );
	
	Event eHealEvent = CreateEvent( "player_healed", true );
	eHealEvent.SetInt( "patient", GetClientUserId( iOther ) );
	eHealEvent.SetInt( "healer", GetClientUserId( iOwner ) );
	eHealEvent.SetInt( "amount", iGave );
	eHealEvent.Fire();

	//EmitGameSoundToAll( "HealthKit.Touch", iOther );

	return MRES_Handled;
}

MRESReturn Detour_CollideTeamReset( int iThis ) {
	int iLauncher = GetEntPropEnt( iThis, Prop_Send, "m_hOriginalLauncher" );
	if( RoundToFloor( AttribHookFloat( 0.0, iLauncher, "custom_medigun_type" ) ) == CMEDI_BEAM ) {
		StoreToEntity( iThis, 1168, true, NumberType_Int8 );
		
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

MRESReturn Detour_CoilProjectileSpeed( int iThis, DHookReturn hReturn ) {
	if( RoundToFloor( AttribHookFloat( 0.0, iThis, "custom_medigun_type" ) ) != CMEDI_BEAM )
		return MRES_Ignored;

	float flCharge = 0.0;
	if( GetEntPropFloat( iThis, Prop_Send, "m_flChargeBeginTime" ) != 0.0 )
		flCharge = GetGameTime() - GetEntPropFloat( iThis, Prop_Send, "m_flChargeBeginTime" );

	hReturn.Value = RemapValClamped( flCharge, 0.0, 2.0, 2400.0, 3000.0 );
	return MRES_ChangedOverride;
}