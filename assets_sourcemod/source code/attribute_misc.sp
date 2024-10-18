#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <kocwtools>
#include <hudframework>
#include <custom_entprops>

public Plugin myinfo =
{
	name = "Attribute: Misc",
	author = "Noclue",
	description = "Miscellaneous attributes.",
	version = "1.4",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

DynamicHook g_dhPrimaryFire;
DynamicHook g_dhSecondaryFire;
DynamicHook g_dhItemPostFrame;
DynamicHook g_dhWeaponHolster;

DynamicDetour g_dtGetMedigun;
DynamicDetour g_dtRestart;

DynamicDetour g_dtGrenadeCreate;
DynamicHook g_dhVPhysCollide;
//DynamicHook g_dhShouldExplode;
//DynamicHook g_dhOnTakeDamage;

//Handle g_sdkCBaseEntityVPhysCollide;
//Handle g_sdkPhysEnableMotion;

Handle g_sdkSendWeaponAnim;
Handle g_sdkAttackIsCritical;
Handle g_sdkPipebombCreate;

int g_iScrambleOffset = -1;
int g_iRestartTimeOffset = -1;
//int g_iPhysEventEntityOffset = -1;
int g_iSniperDotOffset = -1;

static char g_szUnderbarrelFireSound[] = "weapons/grenade_launcher_shoot.wav";

bool g_bLateLoad;
public APLRes AskPluginLoad2( Handle myself, bool bLate, char[] error, int err_max ) {
	g_bLateLoad = bLate;

	return APLRes_Success;
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	g_dhPrimaryFire = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::PrimaryAttack" );
	g_dhSecondaryFire = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::SecondaryAttack" );
	g_dhItemPostFrame = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::ItemPostFrame" );
	g_dhWeaponHolster = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::Holster" );

	g_dtGetMedigun = DynamicDetourFromConfSafe( hGameConf, "CTFPlayer::GetMedigun" );
	g_dtGetMedigun.Enable( Hook_Pre, Hook_GetMedigun );

	g_dtRestart = DynamicDetourFromConfSafe( hGameConf, "CTFGameRules::ResetMapTime" );
	g_dtRestart.Enable( Hook_Pre, Detour_ResetMapTimePre );
	g_dtRestart.Enable( Hook_Post, Detour_ResetMapTimePost );

	g_dtGrenadeCreate = DynamicDetourFromConfSafe( hGameConf, "CTFGrenadePipebombProjectile::Create" );
	g_dtGrenadeCreate.Enable( Hook_Post, Detour_CreatePipebomb );

	StartPrepSDKCall( SDKCall_Static );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFGrenadePipebombProjectile::Create" );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByRef );
	PrepSDKCall_AddParameter( SDKType_QAngle, SDKPass_ByRef );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByRef );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByRef );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
	g_sdkPipebombCreate = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CBaseCombatWeapon::SendWeaponAnim" );
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkSendWeaponAnim = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFWeaponBase::CalcAttackIsCritical" );
	g_sdkAttackIsCritical = EndPrepSDKCall();

	g_dhVPhysCollide = DynamicHookFromConfSafe( hGameConf, "CBaseEntity::VPhysicsCollision" );
	//g_dhShouldExplode = DynamicHook.FromConf( hGameConf, "CTFGrenadePipebombProjectile::ShouldExplodeOnEntity" );
	/*g_dhOnTakeDamage = DynamicHookFromConfSafe( hGameConf, "CBaseEntity::OnTakeDamage" );

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CBaseEntity::VPhysicsCollision" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Pointer ); //convert to plain?
	EndPrepSDKCallSafe( "CBaseEntity::VPhysicsCollision" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "IPhysicsObject::EnableMotion" );
	PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );
	EndPrepSDKCallSafe( "IPhysicsObject::EnableMotion" );*/

	g_iScrambleOffset = GameConfGetOffsetSafe( hGameConf, "CTFGameRules::m_bScrambleTeams" );
	g_iRestartTimeOffset = GameConfGetOffsetSafe( hGameConf, "CTFGameRules::m_flMapResetTime" );
	g_iSniperDotOffset = GameConfGetOffsetSafe( hGameConf, "CTFSniperRifle::m_hSniperDot" );
	//g_iPhysEventEntityOffset = GameConfGetOffset( hGameConf, "gamevcollisionevent_t.pEntities" );

	if( g_bLateLoad ) {
		int iIndex = MaxClients + 1;
		while( ( iIndex = FindEntityByClassname( iIndex, "tf_weapon_sniperrifle" ) ) != -1 ) {
			Frame_CheckSniper( EntIndexToEntRef( iIndex ) );
		}
	}

	delete hGameConf;
}

public void OnMapStart() {
	PrecacheSound( g_szUnderbarrelFireSound );
}

public void OnEntityCreated( int iEntity ) {
	static char szEntityName[ 32 ];
	GetEntityClassname( iEntity, szEntityName, sizeof( szEntityName ) );

	if( StrContains( szEntityName, "tf_weapon_" ) == 0 )
		RequestFrame( Frame_CheckWeapon, EntIndexToEntRef( iEntity ) );

	if( HasEntProp( iEntity, Prop_Send, "m_flChargedDamage" ) )
		RequestFrame( Frame_CheckSniper, EntIndexToEntRef( iEntity ) );
}

void Frame_CheckWeapon( int iWeaponRef ) {
	int iWeapon = EntRefToEntIndex( iWeaponRef );
	if( iWeapon == -1 )
		return;

	if( AttribHookFloat( 0.0, iWeapon, "custom_hurt_on_fire" ) != 0.0 )
		g_dhPrimaryFire.HookEntity( Hook_Pre, iWeapon, Hook_CursedPrimaryFire );

	if( AttribHookFloat( 0.0, iWeapon, "custom_unfortunate_son" ) != 0.0 )
		g_dhSecondaryFire.HookEntity( Hook_Pre, iWeapon, Hook_UnfortunateSonAltFire );
}
void Frame_CheckSniper( int iWeaponRef ) {
	int iWeapon = EntRefToEntIndex( iWeaponRef );
	if( iWeapon == -1 )
		return;
	
	if( AttribHookFloat( 0.0, iWeapon, "custom_sniper_laser" ) == 0.0 )
		return;

	g_dhItemPostFrame.HookEntity( Hook_Post, iWeapon, Hook_SniperPostFrame );
	g_dhWeaponHolster.HookEntity( Hook_Post, iWeapon, Hook_SniperHolster );
}

public void OnTakeDamageAlivePostTF( int iTarget, Address aDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aDamageInfo );
	CheckLifesteal( tfInfo );
	DoUberScale( tfInfo );
}
public void OnTakeDamageBuilding( int iTarget, Address aDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aDamageInfo );
	CheckLifesteal( tfInfo );
	DoUberScale( tfInfo );
}

/*
	Unfortunate Son
*/

MRESReturn Hook_UnfortunateSonAltFire( int iThis ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwner" );
	if( iOwner == -1 )
		return MRES_Ignored;

	int iCost = RoundToFloor( AttribHookFloat( 10.0, iThis, "custom_unfortunate_son_cost" ) );
	if( !HasAmmoToFire( iThis, iOwner, iCost, true ) )
		return MRES_Ignored;

	if( GetEntProp( iThis, Prop_Send, "m_iRoundsLeftInBurst" ) > 0 )
		return MRES_Ignored;

	if( GetEntProp( iThis, Prop_Send, "m_iReloadMode" ) != 0 ) {
		SetEntPropFloat( iThis, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() );
		SetEntPropFloat( iThis, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() );
		SetEntProp( iThis, Prop_Send, "m_iReloadMode", 0 );
	}

	if( GetEntPropFloat( iThis, Prop_Send, "m_flNextPrimaryAttack" ) > GetGameTime() || GetEntPropFloat( iThis, Prop_Send, "m_flNextSecondaryAttack" ) > GetGameTime() )
		return MRES_Ignored;

	ConsumeAmmo( iThis, iOwner, iCost, true );

	SetEntPropFloat( iThis, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + 0.7 );
	SetEntPropFloat( iThis, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() + 0.7 );

	SDKCall( g_sdkSendWeaponAnim, iThis, 181 ); //ACT_VM_SECONDARYATTACK
	SetEntProp( iThis, Prop_Send, "m_iWeaponMode", 1 );
	//adding latentcy prevents animation bugs
	SetEntPropFloat( iThis, Prop_Send, "m_flTimeWeaponIdle", GetGameTime() + 0.6 - GetClientAvgLatency( iOwner, NetFlow_Both ) );
	
	EmitSoundToAll( g_szUnderbarrelFireSound, iOwner, SNDCHAN_WEAPON );

	float vecSrc[3], vecEyeAng[3], vecVel[3], vecImpulse[3];
	GetClientEyePosition( iOwner, vecSrc );

	float vecForward[3], vecRight[3], vecUp[3];
	GetClientEyeAngles( iOwner, vecEyeAng );
	GetAngleVectors( vecEyeAng, vecForward, vecRight, vecUp );

	ScaleVector( vecForward, 960.0 );
	ScaleVector( vecUp, 200.0 );
	AddVectors( vecVel, vecForward, vecVel );
	AddVectors( vecVel, vecUp, vecVel );
	AddVectors( vecVel, vecRight, vecVel );

	vecImpulse[0] = 600.0;

	SDKCall( g_sdkAttackIsCritical, iThis );

	int iGrenade = SDKCall( g_sdkPipebombCreate, vecSrc, vecEyeAng, vecVel, vecImpulse, iOwner, iThis, 0 );

	//todo: move to gamedata
	SetEntProp( iGrenade, Prop_Send, "m_bCritical", LoadFromEntity( iThis, 1566, NumberType_Int8 ) );

	//todo: move to gamedata
	StoreToEntity( iGrenade, 1212, AttribHookFloat( 80.0, iThis, "custom_unfortunate_son_damage" ) ); //damage
	StoreToEntity( iGrenade, 1216, AttribHookFloat( 120.0, iThis, "custom_unfortunate_son_radius" ) ); //radius

	return MRES_Supercede;
}

/*
	BUGFIX:
	Prevent the game from resetting the map change timer when calling a vote scramble.
	I have no idea if this is intended behavior or not
*/

float g_flRestartTime = 0.0;
MRESReturn Detour_ResetMapTimePre( Address aThis ) {
	bool bScramble = LoadFromAddressOffset( aThis, g_iScrambleOffset, NumberType_Int8 );
	if( bScramble ) {
		g_flRestartTime = LoadFromAddressOffset( aThis, g_iRestartTimeOffset );
	}
	return MRES_Handled;
}

MRESReturn Detour_ResetMapTimePost( Address aThis ) {
	if( g_flRestartTime != -1.0 ) {
		StoreToAddressOffset( aThis, g_iRestartTimeOffset, g_flRestartTime );
		g_flRestartTime = -1.0;
	}
	return MRES_Handled;
}

/*
	BUGFIX:
	todo: check if 2.1.4 fixed this
	Fix segmentation fault when a player disconnects while healing someone with a paintball rifle.
*/

MRESReturn Hook_GetMedigun( int iPlayer, DHookReturn hReturn ) {
	if( iPlayer == -1 ) {
		hReturn.Value = INVALID_ENT_REFERENCE;
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

/*
	WEAPON: Broken Mann's Legacy
	Hurts the player, and then heals them for the damage dealt.
	Will not kill the player if self damage is counteracted by received healing.
*/

float g_flHurtMe[ MAXPLAYERS+1 ];

MRESReturn Hook_CursedPrimaryFire( int iEntity ) {
	if( GetEntPropFloat( iEntity, Prop_Send, "m_flNextPrimaryAttack" ) > GetGameTime() )
		return MRES_Ignored;

	int iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwner" );
	if( iOwner == -1 )
		return MRES_Ignored;

	//hack for lifesteal
	g_flHurtMe[ iOwner ] = AttribHookFloat( 0.0, iEntity, "custom_hurt_on_fire" );
	RequestFrame( Frame_HurtPlayer, iOwner );

	return MRES_Handled;
}

void CheckLifesteal( TFDamageInfo tfInfo ) {
	int iAttacker = tfInfo.iAttacker;

	if( !IsValidPlayer( iAttacker ) )
		return;

	g_flHurtMe[ iAttacker ] -= tfInfo.flDamage * AttribHookFloat( 0.0, tfInfo.iWeapon, "custom_lifesteal" );
}

void Frame_HurtPlayer( int iPlayer ) {
	if( !IsClientInGame( iPlayer ) || !IsPlayerAlive( iPlayer ) )
		return;

	float flAmount = g_flHurtMe[ iPlayer ];
	if( flAmount == 0.0 )
		return;

	int iDiff = 0;
	if( flAmount > 0.0 ) {
		SDKHooks_TakeDamage( iPlayer, iPlayer, iPlayer, flAmount );
		iDiff = -RoundToFloor( flAmount );
	} else {
		iDiff = HealPlayer( iPlayer, -flAmount, iPlayer, HF_NOCRITHEAL | HF_NOOVERHEAL );
	}

	Event eHealEvent = CreateEvent( "player_healonhit" );
	eHealEvent.SetInt( "entindex", iPlayer );
	eHealEvent.SetInt( "amount", iDiff );
	eHealEvent.FireToClient( iPlayer );
	CancelCreatedEvent( eHealEvent );

	g_flHurtMe[ iPlayer ] = 0.0;
}

/*
	Attribute: Uber Scales Damage
*/

void DoUberScale( TFDamageInfo tfInfo ) {
	int iWeapon = tfInfo.iWeapon;
	if( iWeapon == -1 )
		return;

	if( AttribHookFloat( 0.0, iWeapon, "custom_uber_scales_damage" ) == 0.0 ) 
		return;

	int iAttacker = tfInfo.iAttacker;
	if( iAttacker == -1 )
		return;

	float flUbercharge = 0.0;
	if( RoundToFloor( AttribHookFloat( 0.0, iAttacker, "custom_medigun_type" ) ) == 6 )
		flUbercharge = Tracker_GetValue( iAttacker, "Ubercharge" ) * 0.01;
	else
		flUbercharge = GetMedigunCharge( iAttacker );

	tfInfo.flDamage *= MaxFloat( flUbercharge, 0.1 );
}

/*
	Sniper laser
*/
int g_iSniperLaserEmitters[MAXPLAYERS+1] = { INVALID_ENT_REFERENCE, ... };
int g_iSniperLaserControlPoints[MAXPLAYERS+1] = { INVALID_ENT_REFERENCE, ... }; //position is used as a control point in the laser particle
MRESReturn Hook_SniperPostFrame( int iThis ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	if( iOwner == -1 )
		return MRES_Ignored;
	
	int iDot = LoadEntityHandleFromAddress( GetEntityAddress( iThis ) + view_as<Address>( g_iSniperDotOffset ) );
	int iEmitter = EntRefToEntIndex( g_iSniperLaserEmitters[iOwner] );
	if( iDot != -1 ) {
		if( iEmitter == -1 )
			CreateSniperLaser( iOwner, iDot );

		UpdateSniperControlPoint( iOwner, iThis );
	} else if( iEmitter != -1 && iDot == -1 ) {
		DeleteSniperLaser( iOwner );
	} 

	return MRES_Handled;
}
MRESReturn Hook_SniperHolster( int iThis ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	if( iOwner == -1 )
		return MRES_Ignored;

	DeleteSniperLaser( iOwner );

	return MRES_Handled;
}

void UpdateSniperControlPoint( int iOwner, int iWeapon ) {
	int iPoint = EntRefToEntIndex( g_iSniperLaserControlPoints[iOwner] );
	if( iPoint == -1 )
		return;

	float vecPos[3];
	vecPos[0] = RemapVal( GetEntPropFloat( iWeapon, Prop_Send, "m_flChargedDamage" ), 0.0, 150.0, 0.0, 1.0 );

	TeleportEntity( iPoint, vecPos );
}

static char g_szSniperLaserParticles[][] = {
	"sniper_laser_red",
	"sniper_laser_blue",
	"sniper_laser_green",
	"sniper_laser_yellow"
};

void CreateSniperLaser( int iOwner, int iDot ) {
	int iPoint = CreateEntityByName( "info_target" );
	DispatchSpawn( iPoint );
	ActivateEntity( iPoint );
	SetEdictFlags( iPoint, FL_EDICT_ALWAYS );
	g_iSniperLaserControlPoints[iOwner] = EntIndexToEntRef( iPoint );
	
	int iTeam = GetEntProp( iOwner, Prop_Send, "m_iTeamNum" ) - 2;
	int iEmitter = CreateParticle( g_szSniperLaserParticles[iTeam] );
	ParentModel( iEmitter, iOwner, "eyes" );
	g_iSniperLaserEmitters[iOwner] = EntIndexToEntRef( iEmitter );

	SetEntPropEnt( iEmitter, Prop_Send, "m_hOwnerEntity", iOwner );
	SetEntPropEnt( iEmitter, Prop_Send, "m_hControlPointEnts", iDot, 0 );
	SetEntPropEnt( iEmitter, Prop_Send, "m_hControlPointEnts", iPoint, 1 );

	//don't need this anymore because of "control point to disable rendering if it is the camera" on the particle
	//SDKHook( iEmitter, SDKHook_SetTransmit, Hook_TransmitIfNotOwner );
	//SetEdictFlags( iEmitter, 0 );
}
void DeleteSniperLaser( int iOwner ) {
	int iEmitter = EntRefToEntIndex( g_iSniperLaserEmitters[iOwner] );
	int iPoint = EntRefToEntIndex( g_iSniperLaserControlPoints[iOwner] );
	g_iSniperLaserEmitters[iOwner] = INVALID_ENT_REFERENCE;
	g_iSniperLaserControlPoints[iOwner] = INVALID_ENT_REFERENCE;
	
	if( iEmitter != -1 ) {
		AcceptEntityInput( iEmitter, "Stop" );
		CreateTimer( 1.0, Timer_RemoveParticle, EntIndexToEntRef( iEmitter ) );
	}
	if( iPoint != -1 )
		CreateTimer( 1.0, Timer_RemoveParticle, EntIndexToEntRef( iPoint ) );
}

/*
	Junkrat pipes
*/

MRESReturn Detour_CreatePipebomb( DHookReturn hReturn, DHookParam hParams ) {
	int iBomb = hReturn.Value;
	if( !IsValidEntity( iBomb ) )
		return MRES_Ignored;

	int iWeapon = GetEntPropEnt( iBomb, Prop_Send, "m_hLauncher" );
	if( iWeapon == -1 )
		return MRES_Ignored;

	float flAttrib = AttribHookFloat( 0.0, iWeapon, "custom_junkrat_pipes" );
	if( flAttrib == 0.0 )
		return MRES_Ignored;

	g_dhVPhysCollide.HookEntity( Hook_Post, iBomb, Hook_PipebombVPhysCollide );
	//g_dhShouldExplode.HookEntity( Hook_Pre, iBomb, Hook_PipebombShouldExplode );

	return MRES_Handled;
}

MRESReturn Hook_PipebombVPhysCollide( int iThis, DHookParam hParams ) {
	//load from gamedata
	bool bTouched = LoadFromEntity( iThis, 1260 );
	bool bOldTouched = GetCustomProp( iThis, "m_bTouched" );

	if( bTouched && !bOldTouched ) {
		float flDamage = LoadFromEntity( iThis, 1212 );
		StoreToEntity( iThis, 1212, flDamage * 0.7 );
		SetCustomProp( iThis, "m_bTouched", true );
	}
	//load from gamedata
	StoreToEntity( iThis, 1260, 0 );

	return MRES_Handled;
}

/*
	Sticky pipebombs
*/

/*
MRESReturn Detour_CreatePipebomb( int iThis, DHookParam hParams ) {
	int iWeapon = GetEntPropEnt( iThis, Prop_Send, "m_hLauncher" );
	if( iWeapon == -1 )
		return MRES_Ignored;

	float flAttrib = AttribHookFloat( 0.0, iWeapon, "custom_sticky_pipes" );
	if( flAttrib == 0.0 )
		return MRES_Ignored;

	g_dhGrenadeVPhysCollide.HookEntity( Hook_Pre, iThis, Hook_PipebombVPhysCollide );
	//g_dhOnTakeDamage.HookEntity( Hook_Pre, iThis, Hook_PipebombTakeDamage );

	return MRES_Handled;
}

MRESReturn Hook_PipebombVPhysCollide( int iThis, DHookParam hParams ) {
}


//obligatory move to gamedata
#define PHYSOBJ_OFFSET 520
#define USEIMPACTNORMAL 1220
#define VECIMPACTNORMAL 1224

//fuuuuuuuuuuck
MRESReturn Hook_PipebombVPhysCollide( int iThis, DHookParam hParams ) {
	int iGrenadeIndex = hParams.Get( 1 );
	int iIndex = hParams.Get( 2 );
	Address pCollisionEventPtr = hParams.Get( 3 );
	Address aCollisionEvent = LoadFromAddress( pCollisionEventPtr, NumberType_Int32 );

	SDKCall( g_sdkCBaseEntityVPhysCollide, iGrenadeIndex, iIndex, pCollisionEventPtr );

	int iOtherIndex = iThis == 0;
	Address pHitEntPtr = LoadFromAddressOffset( aCollisionEvent, g_iPhysEventEntityOffset + ( iOtherIndex * 4 ) );
	if( pHitEntPtr == Address_Null )
		return MRES_Supercede;

	//die if skybox goes here

	int iHitEnt = GetEntityFromAddress( LoadFromAddress( pHitEntPtr, NumberType_Int32 ) );
	static char szEntName[32];
	GetEntityClassname( iHitEnt, szEntName, sizeof( szEntName ) );
	if( iHitEnt == 0 || StrEqual( szEntName, "prop_dynamic", true ) ) {
		//m_bTouched = true;
		StoreToEntity( iThis, GRENADE_TOUCHED, true );

		//VPhysicsGetObject()->EnableMotion( false );
		Address pPhysicsObject = LoadFromEntity( iThis, PHYSOBJ_OFFSET );
		SDKCall( g_sdkPhysEnableMotion, pPhysicsObject, false );
		
		//m_bUseImpactNormal = true;
		StoreToEntity( iThis, USEIMPACTNORMAL, true );

	} else if( IsValidPlayer( iHitEnt ) || StrContains( szEntName, "obj_" ) == 0 ) {
		//stick to player/building
	}

	return MRES_Supercede;
}

MRESReturn Hook_PipebombTakeDamage( int iThis, DHookParam hParams ) {
	return MRES_Ignored;
}
*/