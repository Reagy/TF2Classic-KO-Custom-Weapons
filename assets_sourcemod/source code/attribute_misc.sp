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
	name = "Attribute: Misc",
	author = "Noclue",
	description = "Miscellaneous attributes.",
	version = "1.3",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

DynamicHook g_dhPrimaryFire;
DynamicDetour g_dtGetMedigun;
DynamicDetour g_dtRestart;

//DynamicDetour g_dtGrenadeCreate;
//DynamicHook g_dhGrenadeVPhysCollide;
//DynamicHook g_dhOnTakeDamage;

//Handle g_sdkCBaseEntityVPhysCollide;
//Handle g_sdkPhysEnableMotion;

int g_iScrambleOffset = -1;
int g_iRestartTimeOffset = -1;
//int g_iPhysEventEntityOffset = -1;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	g_dhPrimaryFire = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::PrimaryAttack" );

	g_dtGetMedigun = DynamicDetourFromConfSafe( hGameConf, "CTFPlayer::GetMedigun" );
	g_dtGetMedigun.Enable( Hook_Pre, Hook_GetMedigun );

	g_dtRestart = DynamicDetourFromConfSafe( hGameConf, "CTFGameRules::ResetMapTime" );
	g_dtRestart.Enable( Hook_Pre, Detour_ResetMapTimePre );
	g_dtRestart.Enable( Hook_Post, Detour_ResetMapTimePost );

	/*g_dtGrenadeCreate = DynamicDetourFromConfSafe( hGameConf, "FILL THIS" );
	g_dtGrenadeCreate.Enable( Hook_Pre, Detour_CreatePipebomb );

	g_dhGrenadeVPhysCollide = DynamicHookFromConfSafe( hGameConf, "CTFGrenadePipebombProjectile::VPhysicsCollision" );
	g_dhOnTakeDamage = DynamicHookFromConfSafe( hGameConf, "CBaseEntity::OnTakeDamage" );

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CBaseEntity::VPhysicsCollision" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Pointer ); //convert to plain?
	EndPrepSDKCallSafe( "CBaseEntity::VPhysicsCollision" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "IPhysicsObject::EnableMotion" );
	PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );
	EndPrepSDKCallSafe( "IPhysicsObject::EnableMotion" );*/

	g_iScrambleOffset = GameConfGetOffset( hGameConf, "CTFGameRules::m_bScrambleTeams" );
	g_iRestartTimeOffset = GameConfGetOffset( hGameConf, "CTFGameRules::m_flMapResetTime" );
	//g_iPhysEventEntityOffset = GameConfGetOffset( hGameConf, "gamevcollisionevent_t.pEntities" );

	delete hGameConf;
}

public void OnEntityCreated( int iEntity ) {
	static char szEntityName[ 32 ];
	GetEntityClassname( iEntity, szEntityName, sizeof( szEntityName ) );
	if( StrContains( szEntityName, "tf_weapon_shotgun", false ) == 0 )
		g_dhPrimaryFire.HookEntity( Hook_Pre, iEntity, Hook_PrimaryFire );
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
	BUGFIX:
	Prevent the game from resetting the map change timer when calling a vote scramble.
	I have no idea if this is intended behavior or not
*/

float g_flRestartTime = 0.0;
MRESReturn Detour_ResetMapTimePre( Address aThis ) {
	bool bScramble = LoadFromAddressOffset( aThis, g_iScrambleOffset, NumberType_Int8 );
	if( bScramble ) {
		g_flRestartTime = LoadFromAddressOffset( aThis, g_iRestartTimeOffset, NumberType_Int32 );
	}
	return MRES_Handled;
}

MRESReturn Detour_ResetMapTimePost( Address aThis ) {
	if( g_flRestartTime != -1.0 ) {
		StoreToAddressOffset( aThis, g_iRestartTimeOffset, g_flRestartTime, NumberType_Int32 );
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

MRESReturn Hook_PrimaryFire( int iEntity ) {
	if( GetEntPropFloat( iEntity, Prop_Send, "m_flNextPrimaryAttack" ) > GetGameTime() ) {
		return MRES_Ignored;
	}

	int iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwner" );
	if( iOwner == -1 )
		return MRES_Ignored;

	float flValue = AttribHookFloat( 0.0, iEntity, "custom_hurt_on_fire" );
	if( flValue == 0.0 )
		return MRES_Ignored;

	//hack for lifesteal
	g_flHurtMe[ iOwner ] = flValue;
	RequestFrame( Frame_HurtPlayer, iOwner );

	return MRES_Handled;
}

void CheckLifesteal( TFDamageInfo tfInfo ) {
	int iAttacker = tfInfo.iAttacker;

	if( !IsValidPlayer( iAttacker ) )
		return;

	int iWeapon = tfInfo.iWeapon;
	float flMult = AttribHookFloat( 0.0, iWeapon, "custom_lifesteal" );
	if( flMult == 0.0 )
		return;

	float flAmount = tfInfo.flDamage * flMult;
	g_flHurtMe[ iAttacker ] -= flAmount;
}

void Frame_HurtPlayer( int iPlayer ) {
	if( !IsPlayerAlive( iPlayer ) )
		return;

	float flAmount = g_flHurtMe[ iPlayer ];
	int iDiff = 0;
	if( flAmount > 0.0 ) {
		SDKHooks_TakeDamage( iPlayer, iPlayer, iPlayer, flAmount );
		iDiff = -RoundToFloor( flAmount );
	} else if( flAmount < 0.0 ) {
		iDiff = HealPlayer( iPlayer, -flAmount, iPlayer, HF_NOCRITHEAL | HF_NOOVERHEAL );
	}

	Event eHealEvent = CreateEvent( "player_healonhit" );
	eHealEvent.SetInt( "entindex", iPlayer );
	eHealEvent.SetInt( "amount", iDiff );
	eHealEvent.FireToClient( iPlayer );
	eHealEvent.Cancel();

	g_flHurtMe[ iPlayer ] = 0.0;
}

/*
	Attribute: Uber Scales Damage
*/

void DoUberScale( TFDamageInfo tfInfo ) {
	int iWeapon = tfInfo.iWeapon;
	if( iWeapon == -1 )
		return;

	if( AttribHookFloat( 0.0, tfInfo.iWeapon, "custom_uber_scales_damage" ) == 0.0 ) 
		return;

	int iAttacker = tfInfo.iAttacker;
	if( iAttacker == -1 )
		return;

	float flUbercharge = 0.0;
	if( RoundToFloor( AttribHookFloat( 0.0, tfInfo.iAttacker, "custom_medigun_type" ) ) == 6 )
		flUbercharge = Tracker_GetValue( tfInfo.iAttacker, "Ubercharge" ) * 0.01;
	else
		flUbercharge = GetMedigunCharge( tfInfo.iAttacker );

	tfInfo.flDamage *= MaxFloat( flUbercharge, 0.1 );
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
	Address pHitEntPtr = LoadFromAddressOffset( aCollisionEvent, g_iPhysEventEntityOffset + ( iOtherIndex * 4 ), NumberType_Int32 );
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