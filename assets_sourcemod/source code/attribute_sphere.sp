#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <kocwtools>
#include <hudframework>
public Plugin myinfo =
{
	name = "Attribute: Sphere",
	author = "Noclue",
	description = "Attributes for The Sphere.",
	version = "1.2.1",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

DynamicHook g_dhShouldCollide;
DynamicHook g_dhTouch;
DynamicHook g_dhPostFrame;
DynamicHook g_dhTakeDamage;
DynamicDetour g_dtServerPassFilter;

Handle g_sdkTouchCall;

PlayerFlags g_HasSphere;
int g_iSphereShields[ MAXPLAYERS+1 ] = { INVALID_ENT_REFERENCE, ... };
int g_iMaterialManager[ MAXPLAYERS+1 ] = { INVALID_ENT_REFERENCE, ... };
float g_flShieldCooler[ MAXPLAYERS+1 ];
float g_flLastDamagedShield[ MAXPLAYERS+1 ];

//huge waste of memory but this needs to look up fast
bool g_bIsShield[2048] = { false, ... };

static char g_szShieldModel[] = "models/props_mvm/kocw_player_shield.mdl";
static char g_szShieldDeploySnd[] = "weapons/medi_shield_deploy.wav";
static char g_szShieldRetractSnd[] = "weapons/medi_shield_retract.wav";
static char g_szShieldKeyName[32] = "Shield";

//max shield energy
#define SHIELD_MAX 1000.0
//multiplier for shield energy to be gained when dealing damage
#define SHIELD_DAMAGE_TO_CHARGE_SCALE 2.0
//multiplier for shield energy to be lost when it is damaged
#define SHIELD_DAMAGE_DRAIN_SCALE 1.0

#define SHIELD_DISTANCE 180.0

static char szShieldMats[][] = {
	"models/effects/resist_shield/resist_shield",
	"models/effects/resist_shield/resist_shield_blue",
	"models/effects/resist_shield/resist_shield_green",
	"models/effects/resist_shield/resist_shield_yellow"
};

static int iCollisionMasks[4] = {
	0x800,	//red
	0x1000,	//blue
	0x400,	//green
	0x200,	//yellow
};

static char szSoundNames[][] = {
	"player/resistance_heavy1.wav",
	"player/resistance_heavy2.wav",
	"player/resistance_heavy3.wav",
	"player/resistance_heavy4.wav"
};

public void OnPluginStart() {
	HookEvent( "post_inventory_application", Event_PostInventory );

	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	g_dtServerPassFilter = DynamicDetourFromConfSafe( hGameConf, "PassServerEntityFilter" );
	g_dtServerPassFilter.Enable( Hook_Post, Detour_ServerPassFilter );

	g_dhShouldCollide = DynamicHookFromConfSafe( hGameConf, "CBaseEntity::ShouldCollide" );
	g_dhTouch = DynamicHookFromConfSafe( hGameConf, "CBaseEntity::Touch" );

	g_dhPostFrame = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::ItemPostFrame" );
	g_dhTakeDamage = DynamicHookFromConfSafe( hGameConf, "CBaseEntity::OnTakeDamage" );

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CBaseEntity::Touch" );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	g_sdkTouchCall = EndPrepSDKCallSafe( "CBaseEntity::Touch" );

	delete hGameConf;
}

public void OnMapStart() {
	PrecacheModel( g_szShieldModel );
	PrecacheSound( g_szShieldDeploySnd );
	PrecacheSound( g_szShieldRetractSnd );

	for( int i = 0; i < sizeof(szSoundNames); i++ ) {
		PrecacheSound( szSoundNames[i] );
	}
}

public void OnEntityCreated( int iEntity ) {
	static char szEntityName[ 128 ];
	GetEntityClassname( iEntity, szEntityName, sizeof( szEntityName ) );
	if( StrEqual( szEntityName, "tf_weapon_minigun", false ) ) {
		RequestFrame( SetupMinigun, EntIndexToEntRef( iEntity ) );
	}
}

void SetupMinigun( int iMinigun ) {
	iMinigun = EntRefToEntIndex( iMinigun );
	if( iMinigun == -1 || AttribHookFloat( 0.0, iMinigun, "custom_sphere" ) == 0.0 )
		return;

	g_dhPostFrame.HookEntity( Hook_Post, iMinigun, Hook_PostFrame );
}

MRESReturn Hook_PostFrame( int iThis ) {
	int iWeaponOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	if( !IsValidPlayer( iWeaponOwner ) )
		return MRES_Ignored;

	int iWeaponState = GetEntProp( iThis, Prop_Send, "m_iWeaponState" );
	float flTrackerValue = Tracker_GetValue( iWeaponOwner, g_szShieldKeyName );
	if( !( iWeaponState == 3 ) || flTrackerValue <= 0.0 ) { //spinning
		RemoveShield( iWeaponOwner );
		return MRES_Handled;
	}

	int iShield = EntRefToEntIndex( g_iSphereShields[ iWeaponOwner ] );
	if( iShield == -1 && flTrackerValue > 10.0 )
		SpawnShield( iWeaponOwner );
	//float flDrainRate = ( SHIELD_MAX / ( SHIELD_DURATION / GetGameFrameTime() ) );
	//Tracker_SetValue( iWeaponOwner, SHIELDKEYNAME, MaxFloat( 0.0, flTrackerValue - flDrainRate ) );

	return MRES_Handled;
}

Action Event_PostInventory( Event hEvent, const char[] szName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	if( IsValidPlayer( iPlayer ) ) {
		if( AttribHookFloat( 0.0, iPlayer, "custom_sphere" ) != 0.0 ) {
			g_flShieldCooler[iPlayer] = GetGameTime();

			Tracker_Create( iPlayer, g_szShieldKeyName, false );
			Tracker_SetMax( iPlayer, g_szShieldKeyName, SHIELD_MAX );
			Tracker_SetFlags( iPlayer, g_szShieldKeyName, RTF_RECHARGES | RTF_CLEARONSPAWN );

			if( !g_HasSphere.Get( iPlayer ) ) {
				Tracker_SetValue( iPlayer, g_szShieldKeyName, 0.0 );
			}
			g_HasSphere.Set( iPlayer, true );
		}
		else {
			Tracker_Remove( iPlayer, g_szShieldKeyName );
			g_HasSphere.Set( iPlayer, false );
		}
	}

	return Plugin_Continue;
}

//pls forgive me onplayercmd causes jittering
public void OnGameFrame() {
	for( int i = 1; i <= MaxClients; i++ ) {
		if( !IsClientInGame( i ) )
			continue;

		float flValue = Tracker_GetValue( i, g_szShieldKeyName );
		if( !IsPlayerAlive( i ) || !g_HasSphere.Get( i ) || flValue <= 0.0 ) {
			RemoveShield( i );
			continue;
		}

		UpdateShield( i );
	}
}

void SpawnShield( int iOwner ) {
	if( g_flShieldCooler[ iOwner ] > GetGameTime() )
		return;


	int iShield = CreateEntityByName( "prop_dynamic_override" );
	if( !IsValidEntity( iShield ) )
		return;

	SetEntityModel( iShield, g_szShieldModel );
	SetEntPropEnt( iShield, Prop_Send, "m_hOwnerEntity", iOwner );

	int iOwnerTeam = GetEntProp( iOwner, Prop_Send, "m_iTeamNum" );
	SetEntProp( iShield, Prop_Send, "m_iTeamNum", iOwnerTeam );
	SetEntProp( iShield, Prop_Send, "m_nSkin", iOwnerTeam - 2 );
	
	SetEntProp( iShield, Prop_Data, "m_iEFlags", EFL_DONTBLOCKLOS );
	SetEntProp( iShield, Prop_Data, "m_fEffects", EF_NOSHADOW );
	
	DispatchSpawn( iShield );

	SetSolid( iShield, SOLID_BBOX );
	SetCollisionGroup( iShield, TFCOLLISION_GROUP_COMBATOBJECT );

	//SetEntProp( iShield, Prop_Data, "m_takedamage", DAMAGE_EVENTS_ONLY );
	
	g_dhShouldCollide.HookEntity( Hook_Post, iShield, Hook_ShieldShouldCollide );
	g_dhTouch.HookEntity( Hook_Post, iShield, Hook_ShieldTouch );
	g_dhTakeDamage.HookEntity( Hook_Pre, iShield, Hook_ShieldTakeDamage );

	EmitSoundToAll( g_szShieldDeploySnd, iShield, SNDCHAN_AUTO, 95 );

	g_iSphereShields[ iOwner ] = EntIndexToEntRef( iShield );
	g_bIsShield[iShield] = true;

	int iManager = CreateEntityByName( "material_modify_control" );

	ParentModel( iManager, iShield );

	DispatchKeyValue( iManager, "materialName", szShieldMats[ iOwnerTeam - 2 ] );
	DispatchKeyValue( iManager, "materialVar", "$shield_falloff" );

	DispatchSpawn( iManager );
	g_iMaterialManager[ iOwner ] = EntIndexToEntRef( iManager );
}

void RemoveShield( int iOwner ) {
	int iShield = EntRefToEntIndex( g_iSphereShields[ iOwner ] );
	int iManager = EntRefToEntIndex( g_iMaterialManager[ iOwner ] );

	if( iShield != -1 ) {
		EmitSoundToAll( g_szShieldRetractSnd, iShield, SNDCHAN_AUTO, 95, 0, 0.8 );
		RemoveEntity( iShield );
		g_bIsShield[iShield] = false;
		g_iSphereShields[ iOwner ] = INVALID_ENT_REFERENCE;
		g_flShieldCooler[ iOwner ] = GetGameTime() + 2.0;
	}
	if( iManager != -1 ) {
		RemoveEntity( iManager );
		g_iMaterialManager[ iOwner ] = INVALID_ENT_REFERENCE;
	}
}

void UpdateShield( int iClient ) {
	int iShield = EntRefToEntIndex( g_iSphereShields[ iClient ] );
	if( iShield == -1 ) {
		g_iSphereShields[ iClient ] = INVALID_ENT_REFERENCE;
		return;
	}

	float vecOrigin[3];
	float vecEyePos[3];
	float vecEyeAngles[3];
	GetEntPropVector( iClient, Prop_Data, "m_vecAbsOrigin", vecOrigin );
	GetClientEyePosition( iClient, vecEyePos );
	GetClientEyeAngles( iClient, vecEyeAngles );

	float vecEndPos[3];
	GetAngleVectors( vecEyeAngles, vecEndPos, NULL_VECTOR, NULL_VECTOR );
	ScaleVector( vecEndPos, SHIELD_DISTANCE );
	AddVectors( vecOrigin, vecEndPos, vecEndPos );

	vecEyeAngles[0] = 0.0;
	TeleportEntity( iShield, vecEndPos, vecEyeAngles );

	float vecTest[3];
	GetEntPropVector( iShield, Prop_Data, "m_vecAbsOrigin", vecTest );

	int iManager = EntRefToEntIndex( g_iMaterialManager[ iClient ] );
	if( iManager == -1 )
		return;

	float flShieldFalloff = RemapValClamped( GetGameTime() - g_flLastDamagedShield[ iClient ], 0.0, 0.4, 0.6, 0.2 );

	static char szFalloff[8];
	FloatToString( flShieldFalloff, szFalloff, 8 );

	SetVariantString( szFalloff );
	AcceptEntityInput( iManager, "SetMaterialVar" );
}

MRESReturn Hook_ShieldShouldCollide( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	int iCollisionGroup = hParams.Get( 1 );
	if( !( iCollisionGroup == COLLISION_GROUP_PROJECTILE || iCollisionGroup == TFCOLLISION_GROUP_ROCKETS || iCollisionGroup == TFCOLLISION_GROUP_ROCKET_BUT_NOT_WITH_OTHER_ROCKETS ) )
		return MRES_Ignored;

	int iTeam = GetEntProp( iThis, Prop_Send, "m_iTeamNum" ) - 2;
	if( iTeam < 0 || iTeam > 3 )
		return MRES_Ignored;

	int iContentsMask = hParams.Get( 2 );
	hReturn.Value = ( iContentsMask & iCollisionMasks[ iTeam ] );
	return MRES_Override;
}

MRESReturn Hook_ShieldTouch( int iThis, DHookParam hParams ) {
	int iOther = hParams.Get( 1 );
	if( !HasEntProp( iOther, Prop_Send, "m_iDeflected" ) )
		return MRES_Handled;

	int iShieldTeam = GetEntProp( iThis, Prop_Send, "m_iTeamNum" );
	int iTouchTeam = GetEntProp( iOther, Prop_Send, "m_iTeamNum" );

	if( iShieldTeam != iTouchTeam ) {
		SDKCall( g_sdkTouchCall, iOther, GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" ) );
		EmitSoundToAll( szSoundNames[ GetRandomInt(0, 3) ], iThis, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 1.0, GetRandomInt( 90, 110 ) );
		//RemoveEntity( iOther );
		return MRES_Handled;
	}
	
	return MRES_Ignored;
}

MRESReturn Hook_ShieldTakeDamage( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	TFDamageInfo tfInfo = TFDamageInfo( hParams.GetAddress( 1 ) );
	int iAttacker = tfInfo.iAttacker;

	static char szBuffer[64];
	if( iAttacker != -1 ) {
		GetEntityClassname( iAttacker, szBuffer, sizeof( szBuffer ) );
		if( StrEqual( szBuffer, "func_tracktrain" ) || StrEqual( szBuffer, "trigger_hurt" ) ) {
			hReturn.Value = 0;
			return MRES_Supercede;
		}
	}

	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	if( !IsValidPlayer( iOwner ) )
		return MRES_Ignored;

	int iOwnerTeam = GetEntProp( iOwner, Prop_Send, "m_iTeamNum" );
	int iAttackerTeam = GetEntProp( iAttacker, Prop_Send, "m_iTeamNum" );

	if( iOwnerTeam == iAttackerTeam )
		return MRES_Ignored;

	int iWeapon = tfInfo.iWeapon;
	if( iWeapon != -1 ) {
		static char szClassname[64];
		GetEntityClassname( iWeapon, szClassname, sizeof( szClassname ) );
		if( StrEqual( szClassname, "tf_weapon_minigun" ) )
			tfInfo.flDamage *= 0.4;
	}
	
	EmitSoundToAll( szSoundNames[ GetRandomInt(0, 3) ], iThis, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 1.0, GetRandomInt( 90, 110 ) );

	float flFalloff = TF2DamageFalloff( iThis, tfInfo ) * SHIELD_DAMAGE_DRAIN_SCALE;

	float flTrackerValue = Tracker_GetValue( iOwner, g_szShieldKeyName );
	flTrackerValue = MaxFloat( 0.0, flTrackerValue - flFalloff );
	Tracker_SetValue( iOwner, g_szShieldKeyName, flTrackerValue );
	
	//todo: test this
	Event eResistEvent = CreateEvent( "damage_blocked", true );
	eResistEvent.SetInt( "provider", GetClientUserId( iOwner ) );
	eResistEvent.SetInt( "victim", GetClientUserId( iOwner ) );
	eResistEvent.SetInt( "attacker", GetClientUserId( iAttacker ) );
	eResistEvent.SetInt( "amount", RoundToFloor( flFalloff ) );
	eResistEvent.Fire();

	g_flLastDamagedShield[ iOwner ] = GetGameTime();

	return MRES_Handled;
}

public void OnTakeDamagePostTF( int iTarget, TFDamageInfo tfDamageInfo ) {
	BuildShieldCharge( tfDamageInfo );
}

public void OnTakeDamageBuilding( int iTarget, TFDamageInfo tfDamageInfo ) {
	BuildShieldCharge( tfDamageInfo );
}

void BuildShieldCharge( TFDamageInfo tfDamageInfo ) {
	int iOwner = tfDamageInfo.iAttacker;
	if( !IsValidPlayer( iOwner ) )
		return;

	if( !g_HasSphere.Get( iOwner ) )
		return;

	float flNewValue = MinFloat( SHIELD_MAX, Tracker_GetValue( iOwner, g_szShieldKeyName ) + ( tfDamageInfo.flDamage * SHIELD_DAMAGE_TO_CHARGE_SCALE ) );
	Tracker_SetValue( iOwner, g_szShieldKeyName, flNewValue );
}

MRESReturn Detour_ServerPassFilter( DHookReturn hReturn, DHookParam hParams ) {
	if( hReturn.Value == false )
		return MRES_Ignored;

	int iTouch = GetEntityFromAddress( hParams.Get(1) );
	int iPass = GetEntityFromAddress( hParams.Get(2) );

	if( !g_bIsShield[iTouch] )
		return MRES_Ignored;

	int iOwner = GetEntPropEnt( iTouch, Prop_Send, "m_hOwnerEntity" );
	if( iOwner == -1 )
		return MRES_Ignored;

	if( HasEntProp( iPass, Prop_Send, "m_iTeamNum" ) && GetEntProp( iPass, Prop_Send, "m_iTeamNum" ) == GetEntProp( iOwner, Prop_Send, "m_iTeamNum" ) ) {
		hReturn.Value = false;
		return MRES_Override;
	}

	//;
	return MRES_Ignored;
}