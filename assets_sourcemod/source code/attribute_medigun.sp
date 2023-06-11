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

DynamicDetour	hCanTargetMedigun;
DynamicDetour	hMedigunThink;
DynamicHook	hMedigunSecondary;

DynamicDetour	hFireCollide;
DynamicDetour	hFireCollideTeam;

DynamicHook	hPrimaryFire;
DynamicHook	hSecondaryFire;
DynamicHook	hWeaponPostframe;
DynamicHook	hWeaponHolster;

//DynamicHook	hGiveAmmo;
//DynamicDetour	hSetAmmo;

DynamicDetour 	hStartHeal;

DynamicDetour 	hCollideTeamReset;
DynamicDetour 	hRocketTouch;

Handle 		hGetHealerIndex;
Handle 		hGetMaxHealth;

Handle		hAddFlameTouchList;

enum {
	CMEDI_ANGEL = 1,
	CMEDI_BWP = 2,
	CMEDI_QFIX = 3,
	CMEDI_OATH = 4,
	CMEDI_BOW = 5,
	CMEDI_FLAME = 6,
}

public Plugin myinfo =
{
	name = "Attribute: Mediguns",
	author = "Noclue",
	description = "Atributes for Mediguns.",
	version = "1.3.1",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

int g_iDummyGuns[MAXPLAYERS+1] = { -1, ... };
int g_iBeamEmitters[MAXPLAYERS+1][2];
int g_iBeamTargetPoints[MAXPLAYERS+1] = { -1, ... };

int g_iOldTargets[MAXPLAYERS+1] = { 69420, ... };

//oath breaker
bool g_bRadiusHealer[MAXPLAYERS+1] = { false, ... };
float g_flLastHealed[MAXPLAYERS+1] = { 0.0, ... };

//flame healer
int g_iFlameHealEmitters[MAXPLAYERS+1][2];
bool g_bPlayerHydroPump[MAXPLAYERS+1] = { false, ... };

//int g_iRocketDamageOffset = -1; //1204
int g_iCollideWithTeamOffset = -1; //1168

bool bLateLoad;
public APLRes AskPluginLoad2( Handle myself, bool bLate, char[] error, int err_max ) {
	bLateLoad = bLate;

	return APLRes_Success;
}

public void OnPluginStart() {
	HookEvent( EVENT_POSTINVENTORY,	Event_PostInventory );
	HookEvent( EVENT_PLAYERDEATH,	Event_PlayerKilled );
	HookEvent( "player_healed",	Event_PlayerHealed );

	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "fuckme" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_ByRef );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	hAddFlameTouchList = EndPrepSDKCall();

	hCanTargetMedigun = DynamicDetour.FromConf( hGameConf, "CWeaponMedigun::AllowedToHealTarget" );
	if( !hCanTargetMedigun.Enable( Hook_Pre, Detour_AllowedToHealPre ) ) {
		SetFailState( "Detour setup for CWeaponMedigun::AllowedToHealTarget failed" );
	}
	hMedigunThink = DynamicDetour.FromConf( hGameConf, "CWeaponMedigun::HealTargetThink" );
	if( !hMedigunThink.Enable( Hook_Post, Detour_MedigunThinkPost ) ) {
		SetFailState( "Detour setup for CWeaponMedigun::HealTargetThink failed" );
	}
	hMedigunSecondary = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::SecondaryAttack" );
	

	hStartHeal = DynamicDetour.FromConf( hGameConf, "CTFPlayerShared::Heal" );
	if( !hStartHeal.Enable( Hook_Pre, Detour_HealStartPre ) ) {
		SetFailState( "Detour setup for CTFPlayerShared::Heal failed" );
	}

	hCollideTeamReset = DynamicDetour.FromConf( hGameConf, "CBaseProjectile::ResetCollideWithTeammates" );
	if( !hCollideTeamReset.Enable( Hook_Pre, Detour_CollideTeamReset ) ) {
		SetFailState( "Detour setup for CBaseProjectile::ResetCollideWithTeammates failed" );
	}

	hRocketTouch = DynamicDetour.FromConf( hGameConf, "CTFBaseRocket::RocketTouch" );
	if( !hRocketTouch.Enable( Hook_Pre, Detour_RocketTouch ) ) {
		SetFailState( "Detour setup for CTFBaseRocket::RocketTouch failed" );
	}

	hFireCollide = DynamicDetour.FromConf( hGameConf, "CTFFlameEntity::OnCollide" );
	if( !hFireCollide.Enable( Hook_Pre, Detour_FireTouch ) ) {
		SetFailState( "Detour setup for CTFFlameEntity::OnCollide failed" );
	}
	hFireCollideTeam = DynamicDetour.FromConf( hGameConf, "CTFFlameEntity::OnCollideWithTeammate" );
	if( !hFireCollideTeam.Enable( Hook_Pre, Detour_FireTouchTeam ) ) {
		SetFailState( "Detour setup for CTFFlameEntity::OnCollideWithTeammate failed" );
	}

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayerShared::GetHealerByIndex" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	hGetHealerIndex = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFPlayer::GetMaxHealth" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	hGetMaxHealth = EndPrepSDKCall();

	g_iCollideWithTeamOffset = GameConfGetOffset( hGameConf, "CBaseProjectile::m_bCollideWithTeammates" );

	hPrimaryFire = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::PrimaryAttack" );
	hSecondaryFire = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::SecondaryAttack" );
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

	for( int i = 0; i < sizeof( g_iBeamEmitters ); i++ ) {
		g_iBeamEmitters[i][0] = -1;
		g_iBeamEmitters[i][1] = -1;
	}

	for( int i = 0; i < sizeof( g_iFlameHealEmitters ); i++ ) {
		g_iFlameHealEmitters[i][0] = -1;
		g_iFlameHealEmitters[i][1] = -1;
	}
}

public void OnMapStart() {
	PrecacheSound( "weapons/angel_shield_on.wav" );
}

/*public void OnTakeDamageTF( int iTarget, Address aDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aDamageInfo );

	//OathbreakerDamageMult( iTarget, tfInfo );
}*/

/*public void OnClientConnected( int iClient ) {
	RequestFrame( Frame_Hook, iClient );
}

void Frame_Hook( int iClient ) {
	hGiveAmmo.HookEntity( Hook_Pre, iClient, Hook_GiveAmmo );
}*/

public void OnClientDisconnect( int iClient ) {
	DeleteBeamEmitter( iClient, true );
	DeleteBeamEmitter( iClient, false );

	DeleteDummyGun( iClient );

	DeleteBeamTarget( iClient );
}

public void OnEntityCreated( int iThis, const char[] szClassname ) {
	if( strcmp( szClassname, "tf_weapon_medigun", false ) == 0 )
		HookMedigun( iThis );

	if( strcmp( szClassname, "tf_weapon_flamethrower", false ) == 0 )
		RequestFrame( Frame_SetupFlamethrower, iThis ); //attributes don't seem to be setup yet

	if( strcmp( szClassname, "tf_weapon_pistol", false ) == 0 )
		RequestFrame( Frame_SetupUberdosis, iThis ); //attributes don't seem to be setup yet
}

void Frame_SetupUberdosis( int iThis ) {
	int iMode = RoundToNearest( AttribHookFloat( 0.0, iThis, "custom_medigun_type" ) );
	if( iMode == CMEDI_BOW ) {
		hSecondaryFire.HookEntity( Hook_Pre, iThis, Hook_Secondary );
	}
}

Action Event_PostInventory( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	if( IsValidPlayer( iPlayer ) ) {
		if( RoundToNearest( AttribHookFloat( 0.0, iPlayer, "custom_medigun_type" ) ) == CMEDI_FLAME ) {
			Tracker_Create( iPlayer, FLAMEKEYNAME, 0.0, 0.0, RTF_NOOVERWRITE | RTF_CLEARONSPAWN  );
			g_bPlayerHydroPump[ iPlayer ] = true;
		}
		else {
			Tracker_Remove( iPlayer, FLAMEKEYNAME );
			g_bPlayerHydroPump[ iPlayer ] = false;
		}
	}

	int iMedigun = GetEntityInSlot( iPlayer, 1 );
	if( !IsValidEntity( iMedigun ) )
		return Plugin_Continue;

	static char szWeaponName[64];
	GetEntityClassname( iMedigun, szWeaponName, sizeof(szWeaponName) );
	if( 
		StrEqual( szWeaponName, "tf_weapon_medigun" ) || 
		( StrEqual( szWeaponName, "tf_weapon_flamethrower" ) && RoundToNearest( AttribHookFloat( 0.0, iMedigun, "custom_medigun_type" ) ) == CMEDI_FLAME ) 
	) {
		CreateDummyGun( iPlayer, iMedigun );
		
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

MRESReturn Hook_MedigunHolster( int iThis ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );

	if( IsValidPlayer( iOwner ) ) {
		if( HasCustomCond( iOwner, TFCC_ANGELSHIELD ) && GetCustomCondSourcePlayer( iOwner, TFCC_ANGELSHIELD ) == iOwner ) {
			SetCustomCondLevel( iOwner, TFCC_ANGELSHIELD, 0 );
			RemoveCustomCond( iOwner, TFCC_ANGELSHIELD );
		}

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
	hWeaponPostframe.HookEntity( Hook_Post, iMedigun, Hook_ItemPostFrame );
	hWeaponHolster.HookEntity( Hook_Post, iMedigun, Hook_MedigunHolster );
}

bool ValidHealTarget( int iHealer, int iPatient ) {
	return TeamSeenBy( iHealer, iPatient ) == GetEntProp( iHealer, Prop_Send, "m_iTeamNum" );
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
		if( !ValidHealTarget( iOwner, iHealTarget ) && iType == CMEDI_BWP )
			return MODE_UBER;

		if( GetEntProp( iWeapon, Prop_Send, "m_bChargeRelease" ) && iType != CMEDI_BWP )
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
		SDKUnhook( iEmitter, SDKHook_SetTransmit, Hook_EmitterTransmit );
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
	int iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" );
	SetFlags( iEntity );

	//janky hack: store the behavior of the emitter in some dataprop that isn't used
	bool bIsFirstPersonEmitter = GetEntProp( iEntity, Prop_Data, "m_iHealth" ) == 1;
	if( iClient == iOwner ) {
		return bIsFirstPersonEmitter ? Plugin_Continue : Plugin_Handled;
		
	}
	return bIsFirstPersonEmitter ? Plugin_Handled : Plugin_Continue;
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
	Attaching the beam directly to a player directs to their feet
	so we need a new object to act as a target point.
*/

void CreateBeamTargetPoint( int iPlayer, int iTargetPlayer ) {
	DeleteBeamTarget( iPlayer );

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

	g_iBeamTargetPoints[ iPlayer ] = EntIndexToEntRef( iPoint );
}
void DeleteBeamTarget( int iPlayer ) {
	int iTarget = EntRefToEntIndex( g_iBeamTargetPoints[ iPlayer ] );
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
	g_iOldTargets[ iOwner ] = iTarget;

	if( !bIsCharging )
		return MRES_Handled;

	//uber handling

	int iMediType = RoundToFloor( AttribHookFloat( 0.0, iMedigun, "custom_medigun_type" ) );
	switch( iMediType ) {
		case CMEDI_QFIX: {
			PulseCustomUber( iMedigun, TFCC_QUICKUBER, iTarget, iOwner );
		}
		case CMEDI_BWP: {
			PulseCustomUber( iMedigun, TFCC_TOXINUBER, -1, iOwner );
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
	BIO WASTE PUMP
*/

#define BWP_TOXIN_MULTIPLIER 3.0 //multiplier for the amount of time that toxin should be added while healing enemies

MRESReturn Detour_MedigunThinkPost( int iThis ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	int iTarget = GetEntPropEnt( iThis, Prop_Send, "m_hHealingTarget" );

	if( !IsValidPlayer( iOwner ) || !IsValidPlayer( iTarget ) )
		return MRES_Ignored;

	if( RoundToFloor( AttribHookFloat( 0.0, iThis, "custom_medigun_type" ) ) != CMEDI_BWP )
		return MRES_Ignored;

	if( ValidHealTarget( iOwner, iTarget ) ) {
		/*if( !HasCustomCond( iTarget, TFCC_TOXINPATIENT ) ) {
			AddCustomCond( iTarget, TFCC_TOXINPATIENT );
			SetCustomCondSourcePlayer( iTarget, TFCC_TOXINPATIENT, iOwner );
			SetCustomCondSourceWeapon( iTarget, TFCC_TOXINPATIENT, iThis );
		}

		SetCustomCondDuration( iTarget, TFCC_TOXINPATIENT, 0.5, false );*/
		return MRES_Handled;
	}
	else {
		if( !HasCustomCond( iTarget, TFCC_TOXIN ) ) {
			AddCustomCond( iTarget, TFCC_TOXIN );
			SetCustomCondSourcePlayer( iTarget, TFCC_TOXIN, iOwner );
			SetCustomCondSourceWeapon( iTarget, TFCC_TOXIN, iThis );
			SetCustomCondDuration( iTarget, TFCC_TOXIN, 0.6, true );
		} else	SetCustomCondDuration( iTarget, TFCC_TOXIN, MEDIGUN_THINK_INTERVAL * BWP_TOXIN_MULTIPLIER, true );

		SDKHooks_TakeDamage( iTarget, iOwner, iOwner, 4.0, DMG_GENERIC | DMG_PHYSGUN, iThis, NULL_VECTOR, NULL_VECTOR, false );
		HealPlayer( iOwner, 2.0, iOwner, HF_NOOVERHEAL | HF_NOCRITHEAL );
	}

	return MRES_Handled;
}

MRESReturn Detour_AllowedToHealPre( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	int iIsPump = RoundToFloor( AttribHookFloat( 0.0, iThis, "custom_medigun_type" ) );
	if( iIsPump != CMEDI_BWP ) return MRES_Ignored;

	hReturn.Value = false;

	int iHealer = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	int iTarget = hParams.Get( 1 );

	if( ValidHealTarget( iHealer, iTarget ) )
		return MRES_Ignored;

	if( TF2_IsPlayerInCondition( iTarget, TFCond_Cloaked ) )
		return MRES_Ignored;

	hReturn.Value = true;
	return MRES_Supercede;
}

//just to bypass adding the medigun to the enemy's healer list
MRESReturn Detour_HealStartPre( Address aThis, DHookParam hParams ) {
	int iTarget = GetPlayerFromShared( aThis );
	if( hParams.IsNull( 1 ) )
		return MRES_Ignored;

	int iHealer = hParams.Get( 1 );

	if( ValidHealTarget( iHealer, iTarget ) )
		return MRES_Ignored;

	return MRES_Supercede;
}

/*
	GUARDIAN ANGEL
*/

#define ANGEL_UBER_COST 0.5

MRESReturn AngelGunUber( int iMedigun ) {
	float flChargeLevel = GetEntPropFloat( iMedigun, Prop_Send, "m_flChargeLevel" );
	if( flChargeLevel < ANGEL_UBER_COST )
		return MRES_Ignored;

	SetEntProp( iMedigun, Prop_Send, "m_bChargeRelease", false );
	
	int iOwner = GetEntPropEnt( iMedigun, Prop_Send, "m_hOwnerEntity" );
	int iTarget = GetEntPropEnt( iMedigun, Prop_Send, "m_hHealingTarget" );

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
		return MRES_Handled;
	}

	return MRES_Ignored;
}

/*
	OATHBREAKER
*/

/*static char g_szOathParticles[][] = {
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

	SetEntPropEnt( iEmitter, Prop_Send, "m_hOwnerEntity", iPlayer );

	SetFlags(iEmitter);
	SDKHook( iEmitter, SDKHook_SetTransmit, Hook_RadialParticle );

	DispatchSpawn( iEmitter );
	ActivateEntity( iEmitter );
	AcceptEntityInput( iEmitter, "Start" );

	g_iRadialHealerEmitters[ iPlayer ] = EntIndexToEntRef( iEmitter );
}
void RemoveRadialEmitter( int iPlayer ) {
	int iEmitter = EntRefToEntIndex( g_iRadialHealerEmitters[ iPlayer ] );
	if( iEmitter != -1 ) {
		SDKUnhook( iEmitter, SDKHook_SetTransmit, Hook_RadialParticle );
		RemoveEntity( iEmitter );
	}
		

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
		//StopRadialHeal( iPlayer );
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

		if( !ValidHealTarget( iPlayer, iTarget ) )
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

	int iDisguise = GetEntProp( iPlayer, Prop_Send, "m_nDisguiseTeam" );
	int iTeam;
	if( iDisguise != 0 )
		iTeam = iDisguise - 2;
	else
		iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) - 2;

	int iEmitter = CreateEntityByName( "info_particle_system" );

	DispatchKeyValue( iEmitter, "effect_name", g_szOathHealParticles[ iTeam ] );

	float vecPos[3]; GetClientAbsOrigin( iPlayer, vecPos );
	TeleportEntity( iEmitter, vecPos );

	ParentModel( iEmitter, iPlayer );

	SetEntPropEnt( iEmitter, Prop_Send, "m_hOwnerEntity", iPlayer );

	SetFlags(iEmitter);
	SDKHook( iEmitter, SDKHook_SetTransmit, Hook_RadialParticle );

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

Action Hook_RadialParticle( int iEntity, int iClient ) {
	SetFlags( iEntity );
	int iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" );

	if( iClient == iOwner ) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

void OathbreakerDamageMult( int iTarget, TFDamageInfo tfInfo ) {
	int iAttacker = tfInfo.iAttacker;
	if( !IsValidPlayer( iAttacker ) )
		return; 

	if( RoundToFloor( AttribHookFloat( 0.0, iAttacker, "custom_medigun_type" ) ) != CMEDI_OATH )
		return;

	float flMult = Tracker_GetValue( iAttacker, "Rage" );
	tfInfo.flDamage *= RemapValClamped(flMult, 0.0, 100.0, 1.0, 1.3 );
}*/

/*
	UBERDOSIS
*/

MRESReturn Detour_CollideTeamReset( int iThis ) {
	int iLauncher = GetEntPropEnt( iThis, Prop_Send, "m_hOriginalLauncher" );
	if( RoundToFloor( AttribHookFloat( 0.0, iLauncher, "custom_medigun_type" ) ) == CMEDI_BOW ) {
		StoreToEntity( iThis, g_iCollideWithTeamOffset, true, NumberType_Int8 );
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

//hooking the specific projectile could be slightly faster?
MRESReturn Detour_RocketTouch( int iThis, DHookParam hParams ) {
	if( hParams.IsNull( 1 ) )
		return MRES_Ignored;

	int iTouched = hParams.Get( 1 );
	if( !IsValidPlayer( iTouched ) )
		return MRES_Ignored;

	int iWeapon = GetEntPropEnt( iThis, Prop_Send, "m_hOriginalLauncher" );
	if( iWeapon == -1 )
		return MRES_Ignored;

	if( RoundToFloor( AttribHookFloat( 0.0, iWeapon, "custom_medigun_type" ) ) != CMEDI_BOW )
		return MRES_Ignored;

	int iOwner = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwner" );

	float flGive = 25.0;
	flGive = AttribHookFloat( flGive, iOwner, "mult_medigun_healrate" );

	int iGave = HealPlayer( iTouched, flGive, iOwner );

	Event eHealEvent = CreateEvent( "player_healed" );
	eHealEvent.SetInt( "patient", GetClientUserId( iTouched ) );
	eHealEvent.SetInt( "healer", GetClientUserId( iOwner ) );
	eHealEvent.SetInt( "amount", iGave );
	eHealEvent.Fire();

	return MRES_Handled;
}

MRESReturn Hook_Secondary( int iEntity ) {
	if( GetEntPropFloat( iEntity, Prop_Send, "m_flNextPrimaryAttack" ) > GetGameTime() ) {
		return MRES_Ignored;
	}

	int iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwner" );
	if( iOwner == -1 )
		return MRES_Ignored;

	/*int iAmmoType = 2;
	int iAmmo = GetEntProp( iOwner, Prop_Send, "m_iAmmo", 4, iAmmoType );
	if( iAmmo <= 0 )
		return MRES_Ignored;*/

	SetEntPropFloat( iEntity, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + 0.6 );

	int iViewmodel = GetEntPropEnt( iOwner, Prop_Send, "m_hViewModel" );
	SetEntProp( iViewmodel, Prop_Send, "m_nSequence", 9 );
	SetEntPropFloat( iEntity, Prop_Send, "m_flTimeWeaponIdle", GetGameTime() + 0.25 );

	//SetEntProp( iOwner, Prop_Send, "m_iAmmo", iAmmo - 1, 4, iAmmoType );

	float vecSrc[3], vecEyeAng[3], vecVel[3], vecImpulse[3];
	GetClientEyePosition( iOwner, vecSrc );

	float vecForward[3], vecRight[3], vecUp[3];
	GetClientEyeAngles( iOwner, vecEyeAng );
	GetAngleVectors( vecEyeAng, vecForward, vecRight, vecUp );

	ScaleVector( vecForward, 1200.0 );
	ScaleVector( vecUp, 200.0 );
	AddVectors( vecVel, vecForward, vecVel );
	AddVectors( vecVel, vecUp, vecVel );
	AddVectors( vecVel, vecRight, vecVel );

	vecImpulse[0] = 600.0;

	return MRES_Supercede;
}

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
		hWeaponHolster.HookEntity( Hook_Pre, iThis, Hook_HolsterFlame );
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
	int iOwner = LoadEntityHandleFromAddress( aThis + view_as<Address>( 112 ) );
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
	Address aVector = aThis + view_as<Address>( 120 );
	Address aSize = aThis + view_as<Address>( 132 );
	Address aEHandle = GetEntityAddress( iCollide ) + view_as< Address >( 836 );
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
		if( iWeaponState == 0 )
			RemoveFlameEmitter( iOwner );
		else if( iWeaponState == 1 || ( iWeaponState == 2 && g_iOldWeaponState[ iOwner ] != 1 ) )
			CreateFlameEmitter( iOwner, iThis );
		else if( iWeaponState == 3 ) {
			CreateFlameEmitter( iOwner, iThis, true );

			float flNewValue = FloatClamp( Tracker_GetValue( iOwner, FLAMEKEYNAME ) - 20.0, 0.0, 100.0 );
			Tracker_SetValue( iOwner, FLAMEKEYNAME, flNewValue );
		}
	}

	g_iOldWeaponState[ iOwner ] = iWeaponState;

	return MRES_Handled;
}

MRESReturn Hook_HolsterFlame( int iThis ) {
	int iPlayer = GetEntPropEnt( iThis, Prop_Send, "m_hOwner" );
	RemoveFlameEmitter( iPlayer );
	return MRES_Handled;
}

static char g_szFlameParticleName[][] = {
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
};

float g_flEmitterRemoveTime[ MAXPLAYERS+1 ];

void CreateFlameEmitter( int iPlayer, int iWeapon, bool bIsAirblast = false ) {
	RemoveFlameEmitter( iPlayer );

	for( int i = 0; i < 2; i++ ) {
		int iEmitter = CreateEntityByName( "info_particle_system" );
		int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) - 2;

		if( bIsAirblast ) {
			DispatchKeyValue( iEmitter, "effect_name", g_szAirblastParticleName[ iTeam ] );
			CreateTimer( 0.1, Timer_RemoveAirblast, EntIndexToEntRef( iEmitter ), TIMER_FLAG_NO_MAPCHANGE );
		}
		else {
			DispatchKeyValue( iEmitter, "effect_name", g_szFlameParticleName[ iTeam ] );
			g_iFlameHealEmitters[ iPlayer ][ i ] = EntIndexToEntRef( iEmitter );
		}

		DispatchSpawn( iEmitter );
		ActivateEntity( iEmitter );

		AcceptEntityInput( iEmitter, "Start" );

		SetEntPropEnt( iEmitter, Prop_Send, "m_hOwnerEntity", iPlayer );

		if( i == 0 ) { //first person
			bool bIsCModel = GetEntProp( iWeapon, Prop_Send, "m_iViewModelType" ) == 1;
			int iViewmodel = GetEntPropEnt( iPlayer, Prop_Send, "m_hViewModel" );
			ParentModel( iEmitter, iViewmodel, bIsCModel ? "weapon_bone_l" : "muzzle" );
			SetFlags( iEmitter );
		}
		else { //third person
			int iDummy = GetDummyGun( iPlayer );
			ParentModel( iEmitter, iDummy, "muzzle_alt" );
			SetFlags( iEmitter );
		}

		//janky hack: store the behavior of the emitter in some dataprop that isn't used
		SetEntProp( iEmitter, Prop_Data, "m_iHealth", view_as<int>(i == 0) );

		SDKHook( iEmitter, SDKHook_SetTransmit, Hook_EmitterTransmit );
		g_flEmitterRemoveTime[ iPlayer ] = GetGameTime() + 0.1;
	}
}

Action Timer_RemoveAirblast( Handle hTimer, int iEmitter ) {
	iEmitter = EntRefToEntIndex( iEmitter );

	if( iEmitter == -1 )
		return Plugin_Stop;

	RemoveEntity( iEmitter );
	return Plugin_Stop;
}

void RemoveFlameEmitter( int iPlayer ) {
	for( int i = 0; i < 2; i++ ) {
		int iEmitter = EntRefToEntIndex( g_iFlameHealEmitters[ iPlayer ][ i ] );

		if( iEmitter == -1 )
			continue;

		RemoveEntity( iEmitter );
		g_iFlameHealEmitters[ iPlayer ][ i ] = -1;
	}
}