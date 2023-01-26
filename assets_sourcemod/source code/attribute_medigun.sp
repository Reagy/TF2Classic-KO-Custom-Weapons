#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <kocwtools>
#include <condhandler>

#define MEDIGUN_THINK_INTERVAL 0.2

DynamicDetour	hCanTargetMedigun;
DynamicDetour	hMedigunThink;
DynamicHook	hMedigunSecondary;
DynamicHook	hMedigunPostframe;
DynamicHook	hMedigunHolster;

DynamicDetour hStartHeal;
DynamicDetour hStopHeal;
DynamicDetour hGetBuffedHealth;

Handle hGetHealerIndex;
Handle hGetMaxHealth;

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

bool bLateLoad;
public APLRes AskPluginLoad2( Handle myself, bool bLate, char[] error, int err_max ) {
	bLateLoad = bLate;

	return APLRes_Success;
}

public void OnPluginStart() {
	HookEvent( EVENT_POSTINVENTORY,	Event_PostInventory );
	HookEvent( EVENT_PLAYERDEATH,	Event_PlayerKilled );

	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	hCanTargetMedigun = DynamicDetour.FromConf( hGameConf, "CWeaponMedigun::AllowedToHealTarget" );
	if( !hCanTargetMedigun.Enable( Hook_Pre, Detour_AllowedToHealPre ) ) {
		SetFailState( "Detour setup for CWeaponMedigun::AllowedToHealTarget failed" );
	}
	hMedigunThink = DynamicDetour.FromConf( hGameConf, "CWeaponMedigun::HealTargetThink" );
	if( !hMedigunThink.Enable( Hook_Post, Detour_MedigunThinkPost ) ) {
		SetFailState( "Detour setup for CWeaponMedigun::HealTargetThink failed" );
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
	
	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayerShared::GetHealerByIndex" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	hGetHealerIndex = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFPlayer::GetMaxHealth" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	hGetMaxHealth = EndPrepSDKCall();

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

Action Event_PostInventory( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	int iMedigun = GetEntityInSlot( iPlayer, 1 );
	if( !IsValidEntity( iMedigun ) )
		return Plugin_Continue;

	static char szWeaponName[64];
	GetEntityClassname( iMedigun, szWeaponName, sizeof(szWeaponName) );
	if( StrEqual( szWeaponName, "tf_weapon_medigun" ) ) {
		CreateDummyGun( iPlayer, iMedigun );
		SetEntPropEnt( iMedigun, Prop_Send, "m_hHealingTarget", -1 );
		g_iOldTargets[iPlayer] = 69420;

		g_flMultTable[iPlayer] = AttribHookFloat( 0.5, iPlayer, "custom_maximum_overheal" );
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

public void OnClientDisconnect( int iClient ) {
	DeleteBeamEmitter( iClient, true );
	DeleteBeamEmitter( iClient, false );

	DeleteDummyGun( iClient );

	DeleteBeamTarget( iClient );
}

public void OnEntityCreated( int iThis, const char[] szClassname ) {
	if( !StrEqual( "tf_weapon_medigun", szClassname ) )
		return;
	
	HookMedigun( iThis );
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
	case 1: 
		return AngelGunUber( iThis );
	case 2:
		return BioGunUber( iThis );
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

static char szMedicParticles[][][] = {
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

static char szTeamStrings[][] = {
	"red",
	"blue",
	"green",
	"yellow"
};

//forces particle systems to respect settransmit
public void SetFlags(int iEdict) 
{ 
	SetEdictFlags(iEdict, 0);
} 

void CreateMedibeamString( char[] szBuffer, int iBufferSize, int iWeapon ) {
	int iBeam = RoundToFloor( AttribHookFloat( 0.0, iWeapon, "custom_medibeamtype" ) );
	int iMode = GetHealingMode( iWeapon );
	int iTeam = GetEntProp( iWeapon, Prop_Send, "m_iTeamNum" ) - 2;

	Format( szBuffer, iBufferSize, szMedicParticles[ iBeam ][ iMode ], szTeamStrings[ iTeam ] );
}
int GetHealingMode( int iWeapon ) {
	int iHealTarget = GetEntPropEnt( iWeapon, Prop_Send, "m_hHealingTarget" );
	int iOwner = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwnerEntity" );

	if( iHealTarget != -1 ) {
		int iType = RoundToFloor( AttribHookFloat( 0.0, iWeapon, "custom_medigun_type" ) );
		if( TF2_GetClientTeam( iHealTarget ) != TF2_GetClientTeam( iOwner ) && iType == 2 )
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
	We need 2 different info_particle_systems: one parented to the first person weapon only visible in first person,
	and one in third person, visible to everyone else
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

	if( GetEntPropFloat( iWeapon, Prop_Send, "m_flChargeLevel" ) >= 1.0 ) {
		AcceptEntityInput( g_iBeamEmitters[ iPlayer ][ 0 ], "Start" );
		AcceptEntityInput( g_iBeamEmitters[ iPlayer ][ 1 ], "Start" );
		return;
	}
}



MRESReturn Hook_ItemPostFrame( int iThis ) {
	int iTarget = GetEntPropEnt( iThis, Prop_Send, "m_hHealingTarget" );
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );

	bool bOldCharging = view_as<bool>( GetEntProp( iThis, Prop_Send, "m_bChargeRelease" ) );

	if( iTarget != g_iOldTargets[ iOwner ] ) {
		UpdateMedigunBeam( iOwner );
	}
	else if( g_bOldCharging[ iOwner ] != bOldCharging ) {
		UpdateMedigunBeam( iOwner );
	}


	g_iOldTargets[ iOwner ] = iTarget;
	g_bOldCharging[ iOwner ] = bOldCharging;

	return MRES_Handled;
}

/*
	BIO WASTE PUMP
*/

#define BWP_TOXIN_MULTIPLIER 2.0 //multiplier for the amount of time that toxin should be added while healing enemies

MRESReturn Detour_MedigunThinkPost( int iThis ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	int iTarget = GetEntPropEnt( iThis, Prop_Send, "m_hHealingTarget" );

	if( iOwner < 1 || iOwner > MaxClients || iTarget < 1 || iTarget > MaxClients )
		return MRES_Ignored;

	if( RoundToFloor( AttribHookFloat( 0.0, iThis, "custom_medigun_type" ) ) != 2 )
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
		
	if( !HasCustomCond( iTarget, TFCC_TOXIN ) ) {
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
	if( iIsPump != 2 ) return MRES_Ignored;

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

MRESReturn BioGunUber( int iThis ) {
	return MRES_Ignored;
}

/*
	GUARDIAN ANGEL
*/

MRESReturn AngelGunUber( int iThis ) {
	SetEntProp( iThis, Prop_Send, "m_bChargeRelease", false );

	float flChargeLevel = GetEntPropFloat( iThis, Prop_Send, "m_flChargeLevel" );
	if( flChargeLevel < 0.25 )
		return MRES_Ignored;

	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	
	bool bAppliedCharge = false;
	int iTarget = GetEntPropEnt( iThis, Prop_Send, "m_hHealingTarget" );
	if( iTarget > 0 && iTarget <= MaxClients && IsPlayerAlive( iTarget ) ) {
		if( !HasCustomCond( iTarget, TFCC_ANGELSHIELD ) ) {
			EmitSoundToAll( "weapons/angel_shield_on.wav", iTarget );
			AddCustomCond( iTarget, TFCC_ANGELSHIELD );
			SetCustomCondSourcePlayer( iTarget, TFCC_ANGELSHIELD, iOwner );
			SetCustomCondSourceWeapon( iTarget, TFCC_ANGELSHIELD, iThis );
			bAppliedCharge = true;
		}
	}

	if( !HasCustomCond( iOwner, TFCC_ANGELSHIELD ) ) {
		AddCustomCond( iOwner, TFCC_ANGELSHIELD );
		if( !bAppliedCharge ) EmitSoundToAll( "weapons/angel_shield_on.wav", iOwner );
		SetCustomCondSourcePlayer( iOwner, TFCC_ANGELSHIELD, iOwner );
		SetCustomCondSourceWeapon( iOwner, TFCC_ANGELSHIELD, iThis );
		bAppliedCharge = true;
	}

	if( bAppliedCharge ) {
		SetEntPropFloat( iThis, Prop_Send, "m_flChargeLevel", flChargeLevel - 0.25 );
		return MRES_Handled;
	}

	return MRES_Ignored;
}