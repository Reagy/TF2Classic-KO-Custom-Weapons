#pragma newdecls required
#pragma semicolon 1

#include <tf2c>
#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <kocwtools>
#include <dhooks>

public Plugin myinfo = {
	name = "Attribute: Airburst",
	author = "Noclue",
	description = "Attributes for demoman airburst gun",
	version = "1.2",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

Handle g_sdkPipebombCreate;
Handle g_sdkSetCollisionGroup;
Handle g_sdkDetonate;
Handle g_sdkAttackIsCritical;
Handle g_sdkSendWeaponAnim;

DynamicHook g_dhPrimaryFire;
DynamicHook g_dhSecondaryFire;
DynamicHook g_dhOnTakeDamage;
DynamicHook g_dhShouldExplode;

static char g_szStickybombModel[]	= "models/weapons/w_models/w_stickyrifle/c_stickybomb_rifle.mdl";
static char g_szFireSound[]		= "weapons/stickybomblauncher_shoot.wav";
static char g_szColliderModel[]		= "models/props_gameplay/ball001.mdl";

int g_iGrenadeDamageOffset = -1;
int g_iGrenadeRadiusOffset = -1;
int g_iAttackIsCritOffset = -1;

#define BOMBHISTORYSIZE 16
enum struct BombLagComp {
	int iBombRef;
	int iColliderRef;

	float flBombHistoryX[BOMBHISTORYSIZE];
	float flBombHistoryY[BOMBHISTORYSIZE];
	float flBombHistoryZ[BOMBHISTORYSIZE];
	float flHistoryTime[BOMBHISTORYSIZE]; //timestamp of snapshot

	int iLast;
}
ArrayList g_hLagCompensation;

int g_iBombUnlag = -1;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	g_dhPrimaryFire = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::PrimaryAttack" );
	g_dhSecondaryFire = DynamicHookFromConfSafe( hGameConf, "CTFWeaponBase::SecondaryAttack" );

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
	g_sdkPipebombCreate = EndPrepSDKCallSafe( "CTFGrenadePipebombProjectile::Create" );

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CBaseEntity::SetCollisionGroup" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkSetCollisionGroup = EndPrepSDKCallSafe( "CBaseEntity::SetCollisionGroup" );

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFBaseGrenade::Detonate" );
	g_sdkDetonate = EndPrepSDKCallSafe( "CTFBaseGrenade::Detonate" );

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFWeaponBase::CalcAttackIsCritical" );
	g_sdkAttackIsCritical = EndPrepSDKCallSafe( "CTFWeaponBase::CalcAttackIsCritical" );

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CBaseCombatWeapon::SendWeaponAnim" );
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkSendWeaponAnim = EndPrepSDKCallSafe( "CBaseCombatWeapon::SendWeaponAnim" );

	g_dhShouldExplode = DynamicHookFromConfSafe( hGameConf, "CTFGrenadePipebombProjectile::ShouldExplodeOnEntity" );
	g_dhOnTakeDamage = DynamicHookFromConfSafe( hGameConf, "CBaseEntity::OnTakeDamage" );

	g_iGrenadeDamageOffset = GameConfGetOffsetSafe( hGameConf, "CTFBaseGrenade::m_flDamage" );
	g_iGrenadeRadiusOffset = GameConfGetOffsetSafe( hGameConf, "CTFBaseGrenade::m_flRadius" );
	g_iAttackIsCritOffset = GameConfGetOffsetSafe( hGameConf, "CTFWeaponBase::m_bCurrentAttackIsCrit" );

	g_hLagCompensation = new ArrayList( sizeof( BombLagComp ) );

	delete hGameConf;
}

public void OnMapStart() {
	PrecacheSound( g_szFireSound );
	PrecacheModel( g_szStickybombModel );
	PrecacheModel( g_szColliderModel );

	g_hLagCompensation.Clear();
}

public void OnEntityCreated( int iEntity, const char[] szClassname ) {
	static char szName[64];
	GetEntityClassname( iEntity, szName, sizeof( szName ) );
	if( StrContains( szName, "tf_weapon" ) == -1 )
		return;

	RequestFrame( Frame_WeaponHook, EntIndexToEntRef( iEntity ) );
}

void Frame_WeaponHook( int iEntity ) {
	iEntity = EntRefToEntIndex( iEntity );
	if( AttribHookFloat( 0.0, iEntity, "custom_airdet" ) == 0.0 )
		return;

	g_dhPrimaryFire.HookEntity( Hook_Pre, iEntity, Hook_PrimaryPre );
	g_dhPrimaryFire.HookEntity( Hook_Post, iEntity, Hook_PrimaryPost );
	g_dhSecondaryFire.HookEntity( Hook_Pre, iEntity, Hook_Secondary );
}

public void OnGameFrame() {
	BombLagComp comp;
	int iIndex = 0;
	while( iIndex < g_hLagCompensation.Length ) {
		g_hLagCompensation.GetArray( iIndex, comp );
		int iBombIndex = EntRefToEntIndex( comp.iBombRef );
		if( iBombIndex == -1 ) {
			RemoveBombIndex( iIndex );
			continue;
		}

		float flNewCoords[3];
		GetEntPropVector( iBombIndex, Prop_Send, "m_vecOrigin", flNewCoords );

		int iNewIndex = ( comp.iLast + 1 ) % BOMBHISTORYSIZE;
		comp.flBombHistoryX[iNewIndex] = flNewCoords[ 0 ];
		comp.flBombHistoryY[iNewIndex] = flNewCoords[ 1 ];
		comp.flBombHistoryZ[iNewIndex] = flNewCoords[ 2 ];
		comp.flHistoryTime[iNewIndex] = GetGameTime();
		comp.iLast += 1;

		g_hLagCompensation.SetArray( iIndex, comp );

		iIndex++;
	}
}

MRESReturn Hook_PrimaryPre( int iEntity ) {
	if( GetEntPropFloat( iEntity, Prop_Send, "m_flNextPrimaryAttack" ) > GetGameTime() ) {
		return MRES_Ignored;
	}

	if( GetEntProp( iEntity, Prop_Send, "m_iClip1" ) <= 0 )
		return MRES_Ignored;

	int iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwner" );
	if( iOwner == -1 )
		return MRES_Ignored;

	//todo: sdkcall canattack
	if( !IsPlayerAlive( iOwner ) )
		return MRES_Ignored;

	StartBombUnlag( iOwner );

	return MRES_Handled;
}
MRESReturn Hook_PrimaryPost( int iEntity ) {
	int iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwner" );
	if( iOwner == -1 )
		return MRES_Ignored;


	if( g_iBombUnlag != -1 )
		EndBombUnlag( iOwner );

	return MRES_Handled;
}

MRESReturn Hook_Secondary( int iWeapon ) {
	int iOwner = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwner" );
	if( iOwner == -1 )
		return MRES_Ignored;

	if( !HasAmmoToFire( iWeapon, iOwner, 1, false ) )
		return MRES_Ignored;

	if( GetEntProp( iWeapon, Prop_Send, "m_iRoundsLeftInBurst" ) > 0 )
		return MRES_Ignored;

	if( GetEntProp( iWeapon, Prop_Send, "m_iReloadMode" ) != 0 ) {
		SetEntPropFloat( iWeapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() );
		SetEntPropFloat( iWeapon, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() );
		SetEntProp( iWeapon, Prop_Send, "m_iReloadMode", 0 );
	}

	if( GetEntPropFloat( iWeapon, Prop_Send, "m_flNextPrimaryAttack" ) > GetGameTime() || GetEntPropFloat( iWeapon, Prop_Send, "m_flNextSecondaryAttack" ) > GetGameTime() )
		return MRES_Ignored;

	ConsumeAmmo( iWeapon, iOwner, 1, false );

	SetEntPropFloat( iWeapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + 0.3 );
	SetEntPropFloat( iWeapon, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() + 0.6 );

	SDKCall( g_sdkSendWeaponAnim, iWeapon, 181 ); //ACT_VM_SECONDARYATTACK
	SetEntProp( iWeapon, Prop_Send, "m_iWeaponMode", 1 );
	//adding latentcy prevents animation bugs
	SetEntPropFloat( iWeapon, Prop_Send, "m_flTimeWeaponIdle", GetGameTime() + 0.6 - GetClientAvgLatency( iOwner, NetFlow_Both ) );
	
	EmitSoundToAll( g_szFireSound, iOwner, SNDCHAN_WEAPON );

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

	SDKCall( g_sdkAttackIsCritical, iWeapon );

	int iGrenade = SDKCall( g_sdkPipebombCreate, vecSrc, vecEyeAng, vecVel, vecImpulse, iOwner, iWeapon, 0 );
	g_dhShouldExplode.HookEntity( Hook_Pre, iGrenade, Hook_ShouldExplode );
	SetEntityModel( iGrenade, g_szStickybombModel );

	SetEntProp( iGrenade, Prop_Send, "m_bCritical", LoadFromEntity( iWeapon, g_iAttackIsCritOffset, NumberType_Int8 ) );

	SetEntPropFloat( iGrenade, Prop_Send, "m_flModelScale", 1.5 );

	StoreToEntity( iGrenade, g_iGrenadeDamageOffset, 60.0 ); //damage
	StoreToEntity( iGrenade, g_iGrenadeRadiusOffset, 75.0 ); //radius

	int iCollider = CreateEntityByName( "prop_dynamic_override" );
	SetEntityModel( iCollider, g_szColliderModel );

	//DispatchKeyValue( iCollider, "modelname", g_szColliderModel );

	g_dhOnTakeDamage.HookEntity( Hook_Pre, iCollider, Hook_DamageCollider );

	DispatchSpawn( iCollider );
 
	SetEntProp( iCollider, Prop_Data, "m_takedamage", 2 );
 	SetEntProp( iCollider, Prop_Send, "m_nSolidType", 6 );
	SetEntProp( iCollider, Prop_Send, "m_fEffects", 0x020 ); //nodraw

	SetEntPropEnt( iCollider, Prop_Send, "m_hOwnerEntity", iGrenade );

	SDKCall( g_sdkSetCollisionGroup, iCollider, 2 );

	AddNewBomb( EntIndexToEntRef( iGrenade ), EntIndexToEntRef( iCollider ) );

	return MRES_Supercede;
}

MRESReturn Hook_ShouldExplode( int iBomb, DHookReturn hReturn, DHookParam hParams ) {
	hReturn.Value = false;
	return MRES_Supercede;
}

MRESReturn Hook_DamageCollider( int iCollider, DHookReturn hReturn, DHookParam hParams ) {
	TFDamageInfo tfInfo = TFDamageInfo( hParams.GetAddress( 1 ) );
	hReturn.Value = 1;

	int iBomb = GetEntPropEnt( iCollider, Prop_Send, "m_hOwnerEntity" );
	if( iBomb == -1 )
		return MRES_Supercede;

	int iLauncher = GetEntPropEnt( iBomb, Prop_Send, "m_hOriginalLauncher" );
	int iWeapon = tfInfo.iWeapon;
	
	if( iLauncher != iWeapon )
		return MRES_Supercede;

	if( AttribHookFloat( 0.0, iWeapon, "custom_airdet" ) == 0.0 )
		return MRES_Supercede;
	
	if( !( tfInfo.iFlags & DMG_BULLET ) )
		return MRES_Supercede;

	int iOwner = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwnerEntity" );
	float vecOwnerPos[3];
	GetEntPropVector( iOwner, Prop_Data, "m_vecAbsOrigin", vecOwnerPos );
	float vecBombPos[3];
	GetEntPropVector( iBomb, Prop_Data, "m_vecAbsOrigin", vecBombPos );

	RemoveBomb( iBomb );
	RemoveEntity( iCollider );

	float flDamage = TF2DamageFalloff3( 215.0, vecOwnerPos, vecBombPos, iLauncher, DMG_USEDISTANCEMOD, true );
	//float flDamage = 240.0;

	//PrintToServer("fldamage %f", flDamage);

	StoreToEntity( iBomb, g_iGrenadeDamageOffset, flDamage, NumberType_Int32 ); //damage
	StoreToEntity( iBomb, g_iGrenadeRadiusOffset, 150.0 ); //radius

	float vecColliderCoords[3];
	GetEntPropVector( iCollider, Prop_Send, "m_vecOrigin", vecColliderCoords );

	TeleportEntity( iBomb, vecColliderCoords );

	SDKCall( g_sdkDetonate, iBomb );
	
	return MRES_Ignored;
}

//lag compensation
int AddNewBomb( int iBomb, int iCollider ) {
	BombLagComp comp;
	comp.iBombRef = iBomb;
	comp.iColliderRef = iCollider;

	for( int i = 0; i < BOMBHISTORYSIZE; i++ )
		comp.flHistoryTime[i] = view_as< float >( 0xFFFFFFFE );

	return g_hLagCompensation.PushArray( comp );
}

int FindBomb( int iBomb ) {
	BombLagComp comp;
	for( int i = 0; i < g_hLagCompensation.Length; i++ ) {
		g_hLagCompensation.GetArray( i, comp );
		int iIndex = EntRefToEntIndex( comp.iBombRef );
		if( iBomb == iIndex )
			return i;
	}

	return -1;
}

void RemoveBomb( int iBomb ) {
	int iIndex = FindBomb( iBomb );
	RemoveBombIndex( iIndex );
}
void RemoveBombIndex( int iIndex ) {
	BombLagComp comp;
	if( iIndex > -1 && iIndex < g_hLagCompensation.Length ) {
		g_hLagCompensation.GetArray( iIndex, comp );
		int iCollider = EntRefToEntIndex( comp.iColliderRef );
		if( iCollider != -1 )
			RemoveEntity( iCollider );

		g_hLagCompensation.Erase( iIndex );
	}
		
}
 
void StartBombUnlag( int iPlayer ) {
	float flLatency = GetClientLatency( iPlayer, NetFlow_Both );
	float flTargetTime = GetGameTime() - flLatency;

	g_iBombUnlag = iPlayer;

	BombLagComp comp;
	int iIndex = 0;
	while( iIndex < g_hLagCompensation.Length ) {
		g_hLagCompensation.GetArray( iIndex, comp );

		int iBombIndex = EntRefToEntIndex( comp.iBombRef );
		int iColliderIndex = EntRefToEntIndex( comp.iColliderRef );
		if( iBombIndex == -1 || iColliderIndex == -1 ) {
			RemoveBombIndex( iIndex );
			continue;
		}

		int iWeapon = GetEntPropEnt( iBombIndex, Prop_Send, "m_hOriginalLauncher" );
		int iOwner = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwner" );
		if( iOwner != iPlayer ) {
			iIndex++;
			continue;
		}

		int iBestIndex = 0;
		float flBestTime = 100.0; 

		float vecNewCoords[ 3 ];
		if( flLatency < 0.016 ) {
			GetEntPropVector( iBombIndex, Prop_Send, "m_vecOrigin", vecNewCoords );
		}
		else {
			for( int i = 0; i < BOMBHISTORYSIZE; i++ ) {
				float flNewTime = flTargetTime - comp.flHistoryTime[ i ];
				if( flNewTime < flBestTime && flNewTime > 0.0 ) {
					iBestIndex = i;
					flBestTime = flNewTime;
					continue;
				}
			}

			vecNewCoords[ 0 ] = comp.flBombHistoryX[ iBestIndex ];
			vecNewCoords[ 1 ] = comp.flBombHistoryY[ iBestIndex ];
			vecNewCoords[ 2 ] = comp.flBombHistoryZ[ iBestIndex ];
		}

		TeleportEntity( iColliderIndex, vecNewCoords );

		iIndex++;
	}
}
void EndBombUnlag( int iPlayer ) {
	BombLagComp comp;
	int iIndex = 0;
	while( iIndex < g_hLagCompensation.Length ) {
		g_hLagCompensation.GetArray( iIndex, comp );

		int iBombIndex = EntRefToEntIndex( comp.iBombRef );
		int iColliderIndex = EntRefToEntIndex( comp.iColliderRef );
		if( iBombIndex == -1 || iColliderIndex == -1 ) {
			RemoveBombIndex( iIndex );
			continue;
		}

		int iWeapon = GetEntPropEnt( iBombIndex, Prop_Send, "m_hOriginalLauncher" );
		int iOwner = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwner" );
		if( iOwner != iPlayer ) {
			iIndex++;
			continue;
		}

		TeleportEntity( iColliderIndex, { 0.0, 0.0, 0.0 } );

		iIndex++;
	}

	g_iBombUnlag = -1;
}