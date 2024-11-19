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
	version = "1.5.1",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

DynamicHook g_dhPrimaryFire;
DynamicHook g_dhSecondaryFire;
DynamicHook g_dhItemPostFrame;
DynamicHook g_dhWeaponHolster;
DynamicHook g_dhFireProjectile;
DynamicHook g_dhGrenadeGetDamageType;

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
Handle g_sdkBrickCreate;
Handle g_sdkGetProjectileFireSetup;


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
	g_dhSecondaryFire = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::SecondaryAttack" );
	g_dhItemPostFrame = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::ItemPostFrame" );
	g_dhWeaponHolster = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::Holster" );
	g_dhFireProjectile = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBaseGun::FireProjectile" );

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

	g_dhGrenadeGetDamageType = DynamicHookFromConfSafe( hGameConf, "CTFBaseGrenade::GetDamageType" );

	StartPrepSDKCall( SDKCall_Static );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFBrickProjectile::Create" );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByRef );
	PrepSDKCall_AddParameter( SDKType_QAngle, SDKPass_ByRef );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByRef );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByRef );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
	g_sdkBrickCreate = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CBaseCombatWeapon::SendWeaponAnim" );
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkSendWeaponAnim = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFWeaponBase::CalcAttackIsCritical" );
	g_sdkAttackIsCritical = EndPrepSDKCall();

	//CTFPlayer*, Vector, Vector*, QAngle*, bool, bool
	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFWeaponBaseGun::GetProjectileFireSetup" );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByValue );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_Pointer, 0, VENCODE_FLAG_COPYBACK );
	PrepSDKCall_AddParameter( SDKType_QAngle, SDKPass_Pointer, 0, VENCODE_FLAG_COPYBACK );
	PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_ByValue );
	PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_ByValue );
	g_sdkGetProjectileFireSetup = EndPrepSDKCall();

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

	//todo: fix this
	/*if( g_bLateLoad ) {
		int iIndex = MaxClients + 1;
		while( ( iIndex = FindEntityByClassname( iIndex, "tf_weapon_sniperrifle" ) ) != -1 ) {
			Frame_CheckSniper( EntIndexToEntRef( iIndex ) );
		}
	}*/

	HookEvent( "post_inventory_application", Event_FixChargeCond, EventHookMode_Post );

	delete hGameConf;
}

public void Event_FixChargeCond( Event hEvent, const char[] sName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	if( iPlayer != -1 ) {
		TF2_RemoveCondition( iPlayer, TFCond_Charging );
	}
}

public void OnMapStart() {
	PrecacheSound( g_szUnderbarrelFireSound );
}

public void OnEntityCreated( int iEntity ) {
	static char szEntityName[ 32 ];
	GetEntityClassname( iEntity, szEntityName, sizeof( szEntityName ) );

	if( StrContains( szEntityName, "tf_weapon_" ) == 0 )
		RequestFrame( Frame_CheckWeapon, EntIndexToEntRef( iEntity ) );
}

void Frame_CheckWeapon( int iWeaponRef ) {
	int iWeapon = EntRefToEntIndex( iWeaponRef );
	if( iWeapon == -1 )
		return;

	//test this
	if( AttribHookFloat( 0.0, iWeapon, "custom_sniper_laser" ) != 0.0 ) {
		g_dhItemPostFrame.HookEntity( Hook_Post, iWeapon, Hook_SniperPostFrame );
		g_dhWeaponHolster.HookEntity( Hook_Post, iWeapon, Hook_SniperHolster );
	}

	if( AttribHookFloat( 0.0, iWeapon, "custom_hurt_on_fire" ) != 0.0 )
		g_dhPrimaryFire.HookEntity( Hook_Pre, iWeapon, Hook_CursedPrimaryFire );

	if( AttribHookFloat( 0.0, iWeapon, "custom_unfortunate_son" ) != 0.0 )
		g_dhSecondaryFire.HookEntity( Hook_Pre, iWeapon, Hook_UnfortunateSonAltFire );

	static char szBuffer[256];
	if( AttribHookString( szBuffer, sizeof(szBuffer), iWeapon, "custom_accuracy_scales_damage" ) )
		g_dhFireProjectile.HookEntity( Hook_Pre, iWeapon, Hook_FireProjectile );
}

public void OnTakeDamageAliveTF( int iTarget, Address aDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aDamageInfo );
	
	CheckAccuracyScalesDamage( tfInfo );
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
	CheckAccuracyScalesDamage( tfInfo );
}

/*
	Accuracy scales damage
*/

float g_flLastShot[MAXPLAYERS+1];
int g_iShotsHit[MAXPLAYERS+1] = { 0, ... };
int g_iShotsFired[MAXPLAYERS+1] = { 0, ... };

MRESReturn Hook_FireProjectile( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	int iOwner = hParams.Get(1);
	if( !IsValidPlayer(iOwner) )
		return MRES_Ignored;

	static char szBuffer[256];
	if( !AttribHookString( szBuffer, sizeof(szBuffer), iThis, "custom_accuracy_scales_damage" ) )
		return MRES_Ignored;

	static char szSplit[3][256];
	ExplodeString( szBuffer, " ", szSplit, 3, 256 );
	
	float flInterval = StringToFloat( szSplit[2] );
	if( GetGameTime() < g_flLastShot[iOwner] + flInterval )
		g_iShotsFired[iOwner]++;
	else {
		g_iShotsFired[iOwner] = 1;
		g_iShotsHit[iOwner] = 0;
	}
		
	g_flLastShot[iOwner] = GetGameTime();

	return MRES_Handled;
}

void CheckAccuracyScalesDamage( TFDamageInfo tfInfo ) {
	int iAttacker = tfInfo.iAttacker;
	if( !IsValidPlayer( iAttacker ) )
		return;

	int iWeapon = tfInfo.iWeapon;
	if( iWeapon == -1 )
		return;

	static char szBuffer[256];
	if( !AttribHookString( szBuffer, sizeof(szBuffer), iWeapon, "custom_accuracy_scales_damage" ) )
		return;

	static char szSplit[3][256];
	ExplodeString( szBuffer, " ", szSplit, 3, 256 );

	float flMin = StringToFloat( szSplit[0] );
	float flMax = StringToFloat( szSplit[1] );
	//int flTarget = 5;

	g_iShotsHit[iAttacker]++;

	float flRatio = float( g_iShotsHit[iAttacker] ) / float( g_iShotsFired[iAttacker] );
	float flBoost = RemapValClamped( flRatio, 0.0, 1.0, flMin, flMax );
	//PrintToServer("%f %i %i", flRatio,  g_iShotsHit[iAttacker],  g_iShotsFired[iAttacker]);
	tfInfo.flDamage = tfInfo.flDamage * flBoost;
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

	float flInterval = AttribHookFloat( 0.7, iThis, "custom_unfortunate_son_speed_mult" );

	SetEntPropFloat( iThis, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + flInterval );
	SetEntPropFloat( iThis, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() + flInterval );

	SDKCall( g_sdkSendWeaponAnim, iThis, 181 ); //ACT_VM_SECONDARYATTACK
	SetEntProp( iThis, Prop_Send, "m_iWeaponMode", 1 );
	//adding latentcy prevents animation bugs
	SetEntPropFloat( iThis, Prop_Send, "m_flTimeWeaponIdle", GetGameTime() + flInterval - GetClientAvgLatency( iOwner, NetFlow_Both ) );
	
	EmitSoundToAll( g_szUnderbarrelFireSound, iOwner, SNDCHAN_WEAPON );

	/*float vecSrc[3], vecEyeAng[3], vecVel[3], vecImpulse[3];
	GetClientEyePosition( iOwner, vecSrc );

	float vecForward[3], vecRight[3], vecUp[3];
	GetClientEyeAngles( iOwner, vecEyeAng );
	GetAngleVectors( vecEyeAng, vecForward, vecRight, vecUp );

	float flVelScaleHorz = AttribHookFloat( 1.0, iThis, "custom_unfortunate_son_vel_horz" );
	float flVelScaleVert = AttribHookFloat( 1.0, iThis, "custom_unfortunate_son_vel_vert" );

	ScaleVector( vecForward, 960.0 * flVelScaleHorz );
	ScaleVector( vecUp, 200.0 * flVelScaleVert );
	AddVectors( vecVel, vecForward, vecVel );
	AddVectors( vecVel, vecUp, vecVel );
	AddVectors( vecVel, vecRight, vecVel );

	vecImpulse[0] = 600.0;*/

	float vecEyeAng[3], vecVel[3], vecImpulse[3];
	vecImpulse[0] = 600.0;

	float vecForward[3], vecRight[3], vecUp[3];
	GetClientEyeAngles( iOwner, vecEyeAng );
	GetAngleVectors( vecEyeAng, vecForward, vecRight, vecUp );

	float flVelScaleHorz = AttribHookFloat( 1.0, iThis, "custom_unfortunate_son_vel_horz" );
	float flVelScaleVert = AttribHookFloat( 1.0, iThis, "custom_unfortunate_son_vel_vert" );

	ScaleVector( vecForward, 960.0 * flVelScaleHorz );
	ScaleVector( vecUp, 200.0 * flVelScaleVert );
	AddVectors( vecVel, vecForward, vecVel );
	AddVectors( vecVel, vecUp, vecVel );
	AddVectors( vecVel, vecRight, vecVel );

	float angForward[3], vecSrc[3];
	float vecOffset[3] = { 16.0, 8.0, -6.0 };
	SDKCall( g_sdkGetProjectileFireSetup, iThis, iOwner, vecOffset, vecSrc, angForward, false, true );

	SDKCall( g_sdkAttackIsCritical, iThis );

	//PrintToServer("%i %i %i", vecSrc[0], vecSrc[1], vecSrc[2]);

	int iProjectile = -1;
	switch( RoundToFloor( AttribHookFloat( 0.0, iThis, "custom_unfortunate_son" ) ) ) {
		case 1:
			iProjectile = SDKCall( g_sdkPipebombCreate, vecSrc, vecEyeAng, vecVel, vecImpulse, iOwner, iThis, 0 );
		case 2:
			iProjectile = SDKCall( g_sdkBrickCreate, vecSrc, vecEyeAng, vecVel, vecImpulse, iOwner, iThis, 0 );
		default: {
			PrintToServer("invalid projectile type for custom alt fire");
			return MRES_Ignored;
		}		
	}

	static char szModelString[256];
	if( AttribHookString( szModelString, sizeof(szModelString), iThis, "custom_unfortunate_son_model_override" ) ) {
		static int result = 0;
		if( result == 0 )
			result = PrecacheModel( szModelString );

		if( result != 0 ) {
			SetEntityModel( iProjectile, szModelString );
		}
		else
			PrintToServer( "invalid model string for alt fire projectile %s", szModelString );
	}

	//todo: move to gamedata
	SetEntProp( iProjectile, Prop_Send, "m_bCritical", LoadFromEntity( iThis, 1566, NumberType_Int8 ) );

	//todo: move to gamedata
	StoreToEntity( iProjectile, 1212, AttribHookFloat( 80.0, iThis, "custom_unfortunate_son_damage" ) ); //damage
	StoreToEntity( iProjectile, 1216, AttribHookFloat( 120.0, iThis, "custom_unfortunate_son_radius" ) ); //radius

	if( RoundToFloor( AttribHookFloat( 0.0, iThis, "custom_unfortunate_son_no_ramp" ) ) )
		g_dhGrenadeGetDamageType.HookEntity( Hook_Pre, iProjectile, Hook_GrenadeGetDamageType );

	return MRES_Supercede;
}

MRESReturn Hook_GrenadeGetDamageType( int iThis, DHookReturn hReturn ) {
	hReturn.Value = hReturn.Value & DMG_NOCLOSEDISTANCEMOD;
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
	todo: there seems to be a similar issue with CTFPaintballRifle::WeaponReset()
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
		//load from gamedata
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