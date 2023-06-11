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
	version = "1.1",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

Handle hStickyCreate;
Handle hSetCollisionGroup;
Handle hDetonate;
Handle hAttackIsCritical;

DynamicHook hPrimaryFire;
DynamicHook hSecondaryFire;
DynamicHook hOnTakeDamage;
DynamicHook hShouldExplode;

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
ArrayList hLagCompensation;

int iBombUnlag = -1;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	hPrimaryFire = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::PrimaryAttack" );
	hSecondaryFire = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::SecondaryAttack" );

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
	hStickyCreate = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CBaseEntity::SetCollisionGroup" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	hSetCollisionGroup = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetVirtual( 232 ); //detonate
	hDetonate = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFWeaponBase::CalcAttackIsCritical" );
	hAttackIsCritical = EndPrepSDKCall();

	hShouldExplode = DynamicHook.FromConf( hGameConf, "CTFGrenadePipebombProjectile::ShouldExplodeOnEntity" );
	hOnTakeDamage = DynamicHook.FromConf( hGameConf, "CTFPlayer::OnTakeDamage" );

	hLagCompensation = new ArrayList( sizeof( BombLagComp ) );

	delete hGameConf;
}

public void OnMapStart() {
	PrecacheSound( "weapons/stickybomblauncher_shoot.wav" );
	PrecacheModel( "models/weapons/w_models/w_stickyrifle/c_stickybomb_rifle.mdl" );
	PrecacheModel( "models/props_gameplay/ball001.mdl" );

	hLagCompensation.Clear();
}

public void OnEntityCreated( int iEntity, const char[] szClassname ) {
	static char szName[64];
	GetEntityClassname( iEntity, szName, sizeof( szName ) );
	if( StrContains( szName, "tf_weapon" ) == -1 )
		return;

	RequestFrame( Frame_WeaponHook, iEntity );
}

void Frame_WeaponHook( int iEntity ) {
	if( AttribHookFloat( 0.0, iEntity, "custom_airdet" ) == 0.0 )
		return;

	hPrimaryFire.HookEntity( Hook_Pre, iEntity, Hook_PrimaryPre );
	hPrimaryFire.HookEntity( Hook_Post, iEntity, Hook_PrimaryPost );
	hSecondaryFire.HookEntity( Hook_Pre, iEntity, Hook_Secondary );
}

public void OnGameFrame() {
	BombLagComp comp;
	int iIndex = 0;
	while( iIndex < hLagCompensation.Length ) {
		hLagCompensation.GetArray( iIndex, comp );
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

		hLagCompensation.SetArray( iIndex, comp );

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

	StartBombUnlag( iOwner );

	return MRES_Handled;
}
MRESReturn Hook_PrimaryPost( int iEntity ) {
	int iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwner" );
	if( iOwner == -1 )
		return MRES_Ignored;


	if( iBombUnlag != -1 )
		EndBombUnlag( iOwner );

	return MRES_Handled;
}

MRESReturn Hook_Secondary( int iEntity ) {
	if( GetEntPropFloat( iEntity, Prop_Send, "m_flNextPrimaryAttack" ) > GetGameTime() || GetEntPropFloat( iEntity, Prop_Send, "m_flNextSecondaryAttack" ) > GetGameTime() ) {
		return MRES_Ignored;
	}

	int iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwner" );
	if( iOwner == -1 )
		return MRES_Ignored;

	int iAmmoType = 2;
	int iAmmo = GetEntProp( iOwner, Prop_Send, "m_iAmmo", 4, iAmmoType );
	if( iAmmo <= 0 )
		return MRES_Ignored;

	SetEntPropFloat( iEntity, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + 0.3 );
	SetEntPropFloat( iEntity, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() + 0.6 );

	int iViewmodel = GetEntPropEnt( iOwner, Prop_Send, "m_hViewModel" );
	SetEntProp( iViewmodel, Prop_Send, "m_nSequence", 2 );
	SetEntPropFloat( iEntity, Prop_Send, "m_flTimeWeaponIdle", GetGameTime() + 0.5 );

	SetEntProp( iOwner, Prop_Send, "m_iAmmo", iAmmo - 1, 4, iAmmoType );

	EmitSoundToAll( "weapons/stickybomblauncher_shoot.wav", iOwner, SNDCHAN_WEAPON );

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

	SDKCall( hAttackIsCritical, iEntity );

	int iGrenade = SDKCall( hStickyCreate, vecSrc, vecEyeAng, vecVel, vecImpulse, iOwner, iEntity, 0 );
	hShouldExplode.HookEntity( Hook_Pre, iGrenade, Hook_ShouldExplode );
	SetEntityModel( iGrenade, "models/weapons/w_models/w_stickyrifle/c_stickybomb_rifle.mdl" );

	SetEntProp( iGrenade, Prop_Send, "m_bCritical", LoadFromEntity( iEntity, 1566, NumberType_Int8 ) );

	SetEntPropFloat( iGrenade, Prop_Send, "m_flModelScale", 1.5 );

	StoreToEntity( iGrenade, 1212, 60.0 ); //damage
	StoreToEntity( iGrenade, 1216, 75.0 ); //radius

	int iCollider = CreateEntityByName( "prop_dynamic_override" );
	SetEntityModel( iCollider, "models/props_gameplay/ball001.mdl" );
	hOnTakeDamage.HookEntity( Hook_Pre, iCollider, Hook_DamageCollider );

	DispatchSpawn( iCollider );
 
	SetEntProp( iCollider, Prop_Data, "m_takedamage", 2 );
 	SetEntProp( iCollider, Prop_Send, "m_nSolidType", 6 );
	SetEntProp( iCollider, Prop_Send, "m_fEffects", 0x020 ); //nodraw

	SetEntPropEnt( iCollider, Prop_Send, "m_hOwnerEntity", iGrenade );

	SDKCall( hSetCollisionGroup, iCollider, 2 );

	AddNewBomb( EntIndexToEntRef( iGrenade ), EntIndexToEntRef( iCollider ) );

	return MRES_Supercede;
}

MRESReturn Hook_ShouldExplode( int iEntity, DHookReturn hReturn, DHookParam hParams ) {
	hReturn.Value = false;
	return MRES_Supercede;
}

MRESReturn Hook_DamageCollider( int iEntity, DHookReturn hReturn, DHookParam hParams ) {
	TFDamageInfo tfInfo = TFDamageInfo( hParams.GetAddress( 1 ) );
	hReturn.Value = 1;

	int iParent = GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" );
	if( iParent == -1 )
		return MRES_Supercede;

	int iLauncher = GetEntPropEnt( iParent, Prop_Send, "m_hOriginalLauncher" );
	int iWeapon = tfInfo.iWeapon;
	
	if( iLauncher != iWeapon )
		return MRES_Supercede;

	if( AttribHookFloat( 0.0, iWeapon, "custom_airdet" ) == 0.0 )
		return MRES_Supercede;
	
	if( !( tfInfo.iFlags & DMG_BULLET ) )
		return MRES_Supercede;

	RemoveBomb( iParent );
	RemoveEntity( iEntity );

	StoreToEntity( iParent, 1212, 240.0 ); //damage
	StoreToEntity( iParent, 1216, 150.0 ); //radius

	float vecColliderCoords[3];
	GetEntPropVector( iEntity, Prop_Send, "m_vecOrigin", vecColliderCoords );

	TeleportEntity( iParent, vecColliderCoords );

	SDKCall( hDetonate, iParent );
	
	return MRES_Ignored;
}

//lag compensation
int AddNewBomb( int iBomb, int iCollider ) {
	BombLagComp comp;
	comp.iBombRef = iBomb;
	comp.iColliderRef = iCollider;

	for( int i = 0; i < BOMBHISTORYSIZE; i++ )
		comp.flHistoryTime[i] = view_as< float >( 0xFFFFFFFE );

	return hLagCompensation.PushArray( comp );
}

int FindBomb( int iBomb ) {
	BombLagComp comp;
	for( int i = 0; i < hLagCompensation.Length; i++ ) {
		hLagCompensation.GetArray( i, comp );
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
	if( iIndex > -1 && iIndex < hLagCompensation.Length ) {
		hLagCompensation.GetArray( iIndex, comp );
		int iCollider = EntRefToEntIndex( comp.iColliderRef );
		if( iCollider != -1 )
			RemoveEntity( iCollider );

		hLagCompensation.Erase( iIndex );
	}
		
}
 
void StartBombUnlag( int iPlayer ) {
	float flLatency = GetClientLatency( iPlayer, NetFlow_Both );
	float flTargetTime = GetGameTime() - flLatency;

	iBombUnlag = iPlayer;

	BombLagComp comp;
	int iIndex = 0;
	while( iIndex < hLagCompensation.Length ) {
		hLagCompensation.GetArray( iIndex, comp );
		int iBombIndex = EntRefToEntIndex( comp.iBombRef );
		int iColliderIndex = EntRefToEntIndex( comp.iColliderRef );
		int iWeapon = GetEntPropEnt( iBombIndex, Prop_Send, "m_hOriginalLauncher" );
		int iOwner = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwner" );

		if( iOwner != iPlayer ) {
			iIndex++;
			continue;
		}

		if( iBombIndex == -1 || iColliderIndex == -1 ) {
			RemoveBombIndex( iIndex );
			continue;
		}

		int iBestIndex = 0;
		float flBestTime = 100.0; 

		float flNewCoords[ 3 ];
		if( flLatency < 0.016 ) {
			GetEntPropVector( iBombIndex, Prop_Send, "m_vecOrigin", flNewCoords );
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

			flNewCoords[ 0 ] = comp.flBombHistoryX[ iBestIndex ];
			flNewCoords[ 1 ] = comp.flBombHistoryY[ iBestIndex ];
			flNewCoords[ 2 ] = comp.flBombHistoryZ[ iBestIndex ];
		}

		TeleportEntity( iColliderIndex, flNewCoords );

		iIndex++;
	}
}
void EndBombUnlag( int iPlayer ) {
	BombLagComp comp;
	int iIndex = 0;
	while( iIndex < hLagCompensation.Length ) {
		hLagCompensation.GetArray( iIndex, comp );
		int iBombIndex = EntRefToEntIndex( comp.iBombRef );
		int iColliderIndex = EntRefToEntIndex( comp.iColliderRef );
		int iWeapon = GetEntPropEnt( iBombIndex, Prop_Send, "m_hOriginalLauncher" );
		int iOwner = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwner" );

		if( iOwner != iPlayer ) {
			iIndex++;
			continue;
		}

		if( iBombIndex == -1 || iColliderIndex == -1 ) {
			RemoveBombIndex( iIndex );
			continue;
		}

		TeleportEntity( iColliderIndex, { 0.0, 0.0, 0.0 } );

		iIndex++;
	}

	iBombUnlag = -1;
}