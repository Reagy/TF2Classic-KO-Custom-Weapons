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
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

DynamicDetour hSimpleTrace;
DynamicDetour hSentryTrace;
DynamicHook hShouldCollide;
DynamicHook hTouch;
DynamicHook hPostFrame;
DynamicHook hTakeDamage;

Handle hTouchCall;

PlayerFlags g_HasSphere;
int g_iSphereShields[ MAXPLAYERS+1 ] = { -1, ... };
int g_iMaterialManager[ MAXPLAYERS+1 ] = { -1, ... };
float g_flShieldCooler[ MAXPLAYERS+1 ];
float g_flLastDamagedShield[ MAXPLAYERS+1 ];

#define SHIELD_MODEL "models/props_mvm/mvm_player_shield.mdl"
#define SHIELDKEYNAME "Shield"

//max shield energy
#define SHIELD_MAX 1000.0
//multiplier for shield energy to be gained when dealing damage
#define SHIELD_DAMAGE_TO_CHARGE_SCALE 1.0
//multiplier for shield energy to be lost when it is damaged
#define SHIELD_DAMAGE_DRAIN_SCALE 1.0
//time to fully build a charge passively
#define SHIELD_REGEN_PASSIVE 120.0

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
	HookEvent( EVENT_POSTINVENTORY,	Event_PostInventory );

	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	hSimpleTrace = DynamicDetour.FromConf( hGameConf, "CTraceFilterSimple::ShouldHitEntity" );
	hSimpleTrace.Enable( Hook_Post, Detour_ShouldHitEntitySimple );

	hSentryTrace = DynamicDetour.FromConf( hGameConf, "CTraceFilterIgnoreTeammatesExceptEntity::ShouldHitEntity" );
	hSentryTrace.Enable( Hook_Post, Detour_ShouldHitEntitySentry );

	hShouldCollide = DynamicHook.FromConf( hGameConf, "CBaseEntity::ShouldCollide" );
	hTouch = DynamicHook.FromConf( hGameConf, "CBaseEntity::Touch" );

	hPostFrame = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::ItemPostFrame" );
	hTakeDamage = DynamicHook.FromConf( hGameConf, "CBaseEntity::OnTakeDamage" );

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CBaseEntity::Touch" );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	hTouchCall = EndPrepSDKCall();

	delete hGameConf;
}

public void OnMapStart() {
	PrecacheModel( SHIELD_MODEL );
	PrecacheSound( "weapons/medi_shield_deploy.wav" );
	PrecacheSound( "weapons/medi_shield_retract.wav" );

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

	hPostFrame.HookEntity( Hook_Post, iMinigun, Hook_PostFrame );
}

MRESReturn Hook_PostFrame( int iThis ) {
	int iWeaponOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	if( !IsValidPlayer( iWeaponOwner ) )
		return MRES_Ignored;

	int iWeaponState = GetEntProp( iThis, Prop_Send, "m_iWeaponState" );
	int iShield = EntRefToEntIndex( g_iSphereShields[ iWeaponOwner ] );
	float flTrackerValue = Tracker_GetValue( iWeaponOwner, SHIELDKEYNAME );

	if( !( iWeaponState == 3 ) || flTrackerValue < 0.0 ) { //spinning
		RemoveShield( iWeaponOwner );
		return MRES_Handled;
	}

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
			Tracker_Create( iPlayer, SHIELDKEYNAME, SHIELD_MAX, 0.0, RTF_NOOVERWRITE );

			if( !g_HasSphere.Get( iPlayer ) ) {
				Tracker_SetValue( iPlayer, SHIELDKEYNAME, 0.0 );
			}
			g_HasSphere.Set( iPlayer, true );
		}
		else {
			Tracker_Remove( iPlayer, SHIELDKEYNAME );
			g_HasSphere.Set( iPlayer, false );
		}
	}

	return Plugin_Continue;
}

//pls forgive me onplayercmd causes jittering
public void OnGameFrame() {
	for( int i = 1; i <= MaxClients; i++ ) {
		if( !IsClientInGame( i ) )
			return;

		float flValue = Tracker_GetValue( i, SHIELDKEYNAME );
		if( EntRefToEntIndex( g_iSphereShields[ i ] ) == -1 ) {
			flValue += ( SHIELD_MAX / ( SHIELD_REGEN_PASSIVE / GetGameFrameTime() ) );
			flValue = MinFloat( SHIELD_MAX, flValue );
			Tracker_SetValue( i, SHIELDKEYNAME, flValue );
		}

		if( !IsPlayerAlive( i ) || !g_HasSphere.Get( i ) || flValue <= 0.0 ) {
			RemoveShield( i );
			return;
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

	SetEntityModel( iShield, SHIELD_MODEL );
	SetEntPropEnt( iShield, Prop_Send, "m_hOwnerEntity", iOwner );

	int iOwnerTeam = GetEntProp( iOwner, Prop_Send, "m_iTeamNum" );
	SetEntProp( iShield, Prop_Send, "m_iTeamNum", iOwnerTeam );
	SetEntProp( iShield, Prop_Send, "m_nSkin", iOwnerTeam - 2 );
	
	SetEntProp( iShield, Prop_Data, "m_iEFlags", EFL_DONTBLOCKLOS );
	SetEntProp( iShield, Prop_Data, "m_fEffects", EF_NOSHADOW );
	
	DispatchSpawn( iShield );

	SetSolid( iShield, SOLID_VPHYSICS );
	SetCollisionGroup( iShield, TFCOLLISION_GROUP_COMBATOBJECT );

	//SetEntProp( iShield, Prop_Data, "m_takedamage", DAMAGE_EVENTS_ONLY );
	
	hShouldCollide.HookEntity( Hook_Post, iShield, Hook_ShieldShouldCollide );
	hTouch.HookEntity( Hook_Post, iShield, Hook_ShieldTouch );
	hTakeDamage.HookEntity( Hook_Pre, iShield, Hook_ShieldTakeDamage );

	EmitSoundToAll( "weapons/medi_shield_deploy.wav", iShield, SNDCHAN_AUTO, 95 );

	g_iSphereShields[ iOwner ] = EntIndexToEntRef( iShield );

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
		EmitSoundToAll( "weapons/medi_shield_retract.wav", iShield, SNDCHAN_AUTO, 95, 0, 0.8 );
		RemoveEntity( iShield );
		g_iSphereShields[ iOwner ] = -1;
		g_flShieldCooler[ iOwner ] = GetGameTime() + 2.0;
	}
	if( iManager != -1 ) {
		RemoveEntity( iManager );
		g_iMaterialManager[ iOwner ] = -1;
	}
}

void UpdateShield( int iClient ) {
	int iShield = EntRefToEntIndex( g_iSphereShields[ iClient ] );
	if( iShield == -1 ) {
		g_iSphereShields[ iClient ] = -1;
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
	ScaleVector( vecEndPos, 150.0 );
	AddVectors( vecOrigin, vecEndPos, vecEndPos );

	vecEyeAngles[0] = 0.0;
	TeleportEntity( iShield, vecEndPos, vecEyeAngles, { 0.0, 0.0, 0.0 } );
	ChangeEdictState( iShield );

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
		SDKCall( hTouchCall, iOther, GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" ) );
		EmitSoundToAll( szSoundNames[ GetRandomInt(0, 3) ], iThis, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 1.0, GetRandomInt( 90, 110 ) );
		//RemoveEntity( iOther );
		return MRES_Handled;
	}
	
	return MRES_Ignored;
}

MRESReturn Hook_ShieldTakeDamage( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	if( !IsValidPlayer( iOwner ) )
		return MRES_Ignored;

	TFDamageInfo tfInfo = TFDamageInfo( hParams.GetAddress( 1 ) );
	int iAttacker = tfInfo.iAttacker;

	int iOwnerTeam = GetEntProp( iOwner, Prop_Send, "m_iTeamNum" );
	int iAttackerTeam = GetEntProp( iAttacker, Prop_Send, "m_iTeamNum" );

	if( iOwnerTeam == iAttackerTeam )
		return MRES_Ignored;

	int iWeapon = tfInfo.iWeapon;
	if( iWeapon != -1 ) {
		static char szClassname[64];
		GetEntityClassname( iWeapon, szClassname, sizeof( szClassname ) );
		if( StrEqual( szClassname, "tf_weapon_minigun" ) )
			tfInfo.flDamage *= 0.25;
	}
	
	EmitSoundToAll( szSoundNames[ GetRandomInt(0, 3) ], iThis, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 1.0, GetRandomInt( 90, 110 ) );

	float flFalloff = TF2DamageFalloff( iThis, tfInfo );

	float flTrackerValue = Tracker_GetValue( iOwner, SHIELDKEYNAME );
	flTrackerValue = MaxFloat( 0.0, flTrackerValue - ( flFalloff * SHIELD_DAMAGE_DRAIN_SCALE ) );
	Tracker_SetValue( iOwner, SHIELDKEYNAME, flTrackerValue );
	
	PrintToServer("%f", flFalloff );

	g_flLastDamagedShield[ iOwner ] = GetGameTime();

	return MRES_Handled;
}

public void OnTakeDamagePostTF( int iTarget, Address aDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aDamageInfo );
	BuildShieldCharge( tfInfo );
}

public void OnTakeDamageBuilding( int iTarget, Address aDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aDamageInfo );
	BuildShieldCharge( tfInfo );
}

void BuildShieldCharge( TFDamageInfo tfInfo ) {
	int iOwner = tfInfo.iAttacker;
	if( !IsValidPlayer( iOwner ) )
		return;

	if( !g_HasSphere.Get( iOwner ) )
		return;

	float flNewValue = MinFloat( SHIELD_MAX, Tracker_GetValue( iOwner, SHIELDKEYNAME ) + ( tfInfo.flDamage * SHIELD_DAMAGE_TO_CHARGE_SCALE ) );
	Tracker_SetValue( iOwner, SHIELDKEYNAME, flNewValue );
}

//offset 4: pass entity
//offset 16: pass team
//offset 20: except entity


//todo: sentry and flame particle collision
MRESReturn Detour_ShouldHitEntitySimple( Address aTrace, DHookReturn hReturn, DHookParam hParams ) {
	//we only care about ignoring the shield so if we weren't going to hit it to begin with than ignore
	if( hReturn.Value == false )
		return MRES_Ignored;
	
	Address aLoad = LoadFromAddressOffset( aTrace, 4, NumberType_Int32 ); //offset of m_pPassEnt
	if( aLoad == Address_Null )
		return MRES_Ignored;

	int iPassEntity = GetEntityFromAddress( aLoad );
	if( !IsValidPlayer( iPassEntity ) )
		return MRES_Ignored;

	int iTouched = GetEntityFromAddress( hParams.GetAddress( 1 ) );
	int iOwner = GetEntPropEnt( iTouched, Prop_Send, "m_hOwnerEntity" );
	if( !IsValidPlayer( iOwner ) )
		return MRES_Ignored;

	if( iTouched == EntRefToEntIndex( g_iSphereShields[ iOwner ] ) && GetEntProp( iOwner, Prop_Send, "m_iTeamNum" ) == GetEntProp( iPassEntity, Prop_Send, "m_iTeamNum" ) ) {
		hReturn.Value = false;
		return MRES_ChangedOverride;
	}

	return MRES_Ignored;
}

//this is only ever called by sentry guns
MRESReturn Detour_ShouldHitEntitySentry( Address aTrace, DHookReturn hReturn, DHookParam hParams ) {
	//we only care about ignoring the shield so if we weren't going to hit it to begin with than ignore
	if( hReturn.Value == false )
		return MRES_Ignored;

	Address aLoad = LoadFromAddressOffset( aTrace, 20, NumberType_Int32 ); //offset of m_pExceptionEntity
	if( aLoad == Address_Null )
		return MRES_Ignored;

	int iExcept = GetEntityFromAddress( aLoad );
	if( !IsValidPlayer( iExcept ) )
		return MRES_Ignored;

	int iTouched = GetEntityFromAddress( hParams.Get( 1 ) );
	int iOwner = GetEntPropEnt( iTouched, Prop_Send, "m_hOwnerEntity" );
	if( !IsValidPlayer( iOwner ) )
		return MRES_Ignored;

	if( iTouched == EntRefToEntIndex( g_iSphereShields[ iOwner ] ) && GetEntProp( iTouched, Prop_Send, "m_iTeamNum" ) == GetEntProp( iExcept, Prop_Send, "m_iTeamNum" ) ) {
		hReturn.Value = false;
		return MRES_ChangedOverride;
	}

	return MRES_Ignored;
}