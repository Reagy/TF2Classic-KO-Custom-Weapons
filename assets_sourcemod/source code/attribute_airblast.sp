#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <kocwtools>

public Plugin myinfo = {
	name = "Attribute: Airblast",
	author = "Noclue",
	description = "Allow non-flamethrower weapons to airblast.",
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

DynamicHook g_dhSecondaryFire;
DynamicHook g_dhItemPostFrame;

Handle g_sdkLookupSequence;
Handle g_sdkGetProjectileSetup;
Handle g_sdkIsDeflectable;
Handle g_sdkDeflected;
Handle g_sdkGetWeaponID;
Handle g_sdkAirblastPlayer;
Handle g_sdkAddDamagerToHistory;
Handle g_sdkWorldSpaceCenter;

static char g_szAttribAirblastEnable[] = "custom_force_airblast";
static char g_szAttribAirblastRefire[] = "mult_airblast_refire_time";
static char g_szAttribAirblastScale[] = "deflection_size_multiplier";
static char g_szAttribAirblastCost[] = "mult_airblast_cost";
static char g_szAttribAirblastSelfPush[] = "apply_self_knockback_airblast";
static char g_szAttribAirblastFlags[] = "airblast_functionality_flags";
static char g_szAttribAirblastNoPush[] = "disable_airblasting_players";
static char g_szAttribAirblastDestroy[] = "airblast_destroy_projectile";

static char g_szAirblastSound[] = "";
static char g_szDeleteAirblastSound[] = "Fire.Engulf";
static char g_szExtinguishSound[] = "TFPlayer.FlameOut";
static char g_szDeflectSound[] = "Weapon_FlameThrower.AirBurstAttackDeflect";
static char g_szAirblastPlayerSound[] = "TFPlayer.AirBlastImpact";

static char g_szDeflectParticle[] = "deflect_fx";
static char g_szDeleteParticle[] = "explosioncore_sapperdestroyed";

ArrayList g_alAirblasted[MAXPLAYERS+1];
ArrayList g_alEntList; //ent list for airblast enumeration
float g_flAirblastEndTime[MAXPLAYERS+1];

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	g_dhSecondaryFire = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::SecondaryAttack" );
	g_dhItemPostFrame = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::ItemPostFrame" );

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CBaseAnimating::LookupSequence" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	g_sdkLookupSequence = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFWeaponBaseGun::GetProjectileReflectSetup" );
	PrepSDKCall_SetReturnInfo( SDKType_Vector, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_CBasePlayer, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkGetProjectileSetup = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CBaseEntity::IsDeflectable" );
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	g_sdkIsDeflectable = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CBaseEntity::Deflected" );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByRef );
	g_sdkDeflected = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFWeaponBase::GetWeaponID" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkGetWeaponID = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayerShared::AirblastPlayer" );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_Vector, SDKPass_ByRef );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	g_sdkAirblastPlayer = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayer::AddDamagerToHistory" );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	g_sdkAddDamagerToHistory = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CBaseEntity::WorldSpaceCenter" );
	PrepSDKCall_SetReturnInfo( SDKType_Vector, SDKPass_ByRef );
	g_sdkWorldSpaceCenter = EndPrepSDKCall();

	g_alEntList = new ArrayList();

	for( int i = 0; i < sizeof(g_alAirblasted); i++ ) {
		g_alAirblasted[i] = new ArrayList();
	}

	HookEvent( "post_inventory_application", Event_Inventory, EventHookMode_Post );

	delete hGameConf;
}

public Action Event_Inventory( Event hEvent, const char[] sName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );
	g_alAirblasted[iPlayer].Clear();
	g_flAirblastEndTime[iPlayer] = GetGameTime();
	return Plugin_Continue;
}

public void OnMapStart() {
	PrecacheScriptSound( g_szAirblastSound );
	PrecacheScriptSound( g_szDeleteAirblastSound );
	PrecacheScriptSound( g_szExtinguishSound );
	PrecacheScriptSound( g_szDeflectSound );
	PrecacheScriptSound( g_szAirblastPlayerSound );

	PrecacheModel( "models/weapons/w_models/w_stickyrifle/c_stickybomb_rifle.mdl" );
}

public void OnEntityCreated( int iEntity ) {
	static char szBuffer[64];
	GetEntityClassname( iEntity, szBuffer, sizeof( szBuffer ) );
	if( StrContains( szBuffer, "tf_weapon_" ) == 0 )
		RequestFrame( Frame_CheckAttrib, EntIndexToEntRef( iEntity ) );
}

void Frame_CheckAttrib( int iEntity ) {
	iEntity = EntRefToEntIndex( iEntity );
	if( iEntity == -1 )
		return;

	if( AttribHookFloat( 0.0, iEntity, g_szAttribAirblastEnable ) != 0.0 ) {
		g_dhSecondaryFire.HookEntity( Hook_Pre, iEntity, Hook_SecondaryFire );
		g_dhItemPostFrame.HookEntity( Hook_Pre, iEntity, Hook_ItemPostFrame );
	}
		
}

MRESReturn Hook_SecondaryFire( int iThis ) {
	if( GetEntPropFloat( iThis, Prop_Send, "m_flNextPrimaryAttack" ) > GetGameTime() || GetEntPropFloat( iThis, Prop_Send, "m_flNextSecondaryAttack" ) > GetGameTime() )
		return MRES_Ignored;

	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwner" );
	if( iOwner == -1 )
		return MRES_Ignored;

	int iAmmoType = GetEntProp( iThis, Prop_Send, "m_iPrimaryAmmoType" );
	int iAmmo = GetEntProp( iOwner, Prop_Send, "m_iAmmo", 4, iAmmoType );
	int iAmmoCost = RoundToNearest( AttribHookFloat( 20.0, iThis, g_szAttribAirblastCost ) );
	if( iAmmo < iAmmoCost )
		return MRES_Ignored;
	SetEntProp( iOwner, Prop_Send, "m_iAmmo", iAmmo - iAmmoCost, 4, iAmmoType );

	float flAirblastInterval = AttribHookFloat( 0.75, iThis, g_szAttribAirblastRefire );
	SetEntPropFloat( iThis, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + flAirblastInterval );
	SetEntPropFloat( iThis, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() + flAirblastInterval );

	int iViewmodel = GetEntPropEnt( iOwner, Prop_Send, "m_hViewModel" );
	int iSequence;
	if( GetEntProp( iThis, Prop_Send, "m_iViewModelType" ) == 1 )
		iSequence = SDKCall( g_sdkLookupSequence, iViewmodel, "ft_alt_fire" );
	else
		iSequence = SDKCall( g_sdkLookupSequence, iViewmodel, "alt_fire" );
	SetEntProp( iViewmodel, Prop_Send, "m_nSequence", iSequence );
	SetEntPropFloat( iThis, Prop_Send, "m_flTimeWeaponIdle", GetGameTime() + flAirblastInterval );

	//EmitSoundToAll( g_szAirblastSound, iOwner, SNDCHAN_WEAPON );

	g_flAirblastEndTime[iOwner] = GetGameTime() + 0.06;

	//airblast_self_push

	return MRES_Supercede;
}

MRESReturn Hook_ItemPostFrame( int iThis ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hOwner" );
	if( GetGameTime() <= g_flAirblastEndTime[iOwner] ) {
		StartLagCompensation( iOwner );
		DoAirblast( iThis, iOwner );
		FinishLagCompensation( iOwner );

		return MRES_Handled;
	} else if( g_alAirblasted[iOwner].Length > 0 ) {
		g_alAirblasted[iOwner].Clear();
	}

	return MRES_Ignored;
}

enum {
	AB_PUSH = 1,
	AB_EXTINGUISH = 2,
	AB_REFLECT = 4,
}

void DoAirblast( int iWeapon, int iOwner ) {
	PrintToServer("test1");
	int iFlags = RoundToFloor( AttribHookFloat( -1.0, iWeapon, g_szAttribAirblastFlags ) );
	if( iFlags == -1 ) iFlags = AB_PUSH | AB_EXTINGUISH | AB_REFLECT;

	if( AttribHookFloat( 0.0, iWeapon, g_szAttribAirblastNoPush ) != 0.0 ) iFlags = iFlags & ~AB_PUSH;

	float vecPlrOrigin[3];
	GetClientAbsOrigin( iOwner, vecPlrOrigin );
	vecPlrOrigin[0] += GetEntPropFloat( iOwner, Prop_Send, "m_vecViewOffset[0]" );
	vecPlrOrigin[1] += GetEntPropFloat( iOwner, Prop_Send, "m_vecViewOffset[1]" );
	vecPlrOrigin[2] += GetEntPropFloat( iOwner, Prop_Send, "m_vecViewOffset[2]" );
	float vecDir[3];
	float vecAngDir[3];
	GetClientEyeAngles( iOwner, vecAngDir );
	GetAngleVectors( vecAngDir, vecDir, NULL_VECTOR, NULL_VECTOR );

	float vecBlastSize[3] = { 128.0, 128.0, 64.0 };
	ScaleVector( vecBlastSize, AttribHookFloat( 1.0, iWeapon, g_szAttribAirblastScale ) );

	float flBlastDist = MaxFloat( MaxFloat( vecBlastSize[0], vecBlastSize[1] ), vecBlastSize[2] );

	//Vector vecOrigin = pOwner->Weapon_ShootPosition() + vecDir * flBlastDist;
	float vecBoxOrigin[3];
	ScaleVector( vecDir, flBlastDist );
	AddVectors( vecBoxOrigin, vecDir, vecBoxOrigin );
	AddVectors( vecBoxOrigin, vecPlrOrigin, vecBoxOrigin );
	
	float vecMins[3] = { 0.0, 0.0, 0.0 };
	float vecMaxs[3] = { 0.0, 0.0, 0.0 };

	SubtractVectors( vecBoxOrigin, vecBlastSize, vecMins );
	AddVectors( vecBoxOrigin, vecBlastSize, vecMaxs );

	g_alEntList.Clear();
	TR_EnumerateEntitiesBox( vecMins, vecMaxs, 0, Airblast_BoxFilter, iOwner );

	for( int i = 0; i < g_alEntList.Length; i++ ) {
		int iEntity = g_alEntList.Get(i);
		float vecEntPos[3];
		GetEntPropVector( iEntity, Prop_Data, "m_vecAbsOrigin", vecEntPos );

		TR_TraceRayFilter( vecAngDir, vecEntPos, 0, RayType_EndPoint, Airblast_RayFilter, iOwner );
		if ( TR_GetFraction() != 1.0 ) {
			continue;
		}

		if( IsValidPlayer( iEntity ) ) {
			bool bSameTeam = GetEntProp( iEntity, Prop_Send, "m_iTeamNum" ) == GetEntProp( iOwner, Prop_Send, "m_iTeamNum" );
			if( iFlags & AB_PUSH && !bSameTeam  ) {
				float angPushDir[3]; angPushDir[0] = vecAngDir[0]; angPushDir[1] = vecAngDir[1]; angPushDir[2] = vecAngDir[2];
				angPushDir[0] = MinFloat( -45.0, angPushDir[0] );

				float vecPushDir[3];
				GetAngleVectors( angPushDir, vecPushDir, NULL_VECTOR, NULL_VECTOR );

				AirblastPlayer( iEntity, iOwner, iWeapon, vecPushDir );
			}
			if( iFlags & AB_EXTINGUISH && bSameTeam ) {
				if( TF2_IsPlayerInCondition( iEntity, TFCond_OnFire ) ) {
					TF2_RemoveCondition( iEntity, TFCond_OnFire );
					EmitGameSoundToAll( g_szExtinguishSound, iEntity );
					
					Event eExtinguishEvent = CreateEvent( "player_extinguished", true );
					eExtinguishEvent.SetInt( "victim", iEntity );
					eExtinguishEvent.SetInt( "healer", iOwner );
					eExtinguishEvent.Fire();

					float flExtinguishHeal = AttribHookFloat( 0.0, iWeapon, "extinguish_restores_health" );
					if( flExtinguishHeal != 0.0 ) {
						HealPlayer( iOwner, flExtinguishHeal, -1, HF_NOCRITHEAL | HF_NOOVERHEAL );
					}

					//CTFGameStats::Event_PlayerBlockedDamage(CTFPlayer *,int)
					//CTF_GameStats.Event_PlayerAwardBonusPoints( pAttacker, pVictim, 1 );

				}
			}
		}
		else {
			if( !(iFlags & AB_REFLECT) )
				continue;

			float vecPos[3];
			GetEntPropVector( iEntity, Prop_Data, "m_vecAbsOrigin", vecPos );
			float vecDeflect[3];
			float vecReturn[3];
			SDKCall( g_sdkGetProjectileSetup, iWeapon, vecReturn, iOwner, vecPos, vecDeflect, false, false );

			AirblastEntity( iEntity, iOwner, iWeapon, vecReturn );
		}
	}
}

void AirblastPlayer( int iTarget, int iAttacker, int iWeapon, const float vecDir[3] ) {
	if( g_alAirblasted[iAttacker].FindValue( iTarget ) != -1 )
		return;

	float vecVictimDir[3];
	float vecTargetPos[3];
	float vecAttackerPos[3];

	SDKCall( g_sdkWorldSpaceCenter, iTarget, vecTargetPos );
	SDKCall( g_sdkWorldSpaceCenter, iAttacker, vecAttackerPos );

	SubtractVectors( vecTargetPos, vecAttackerPos, vecVictimDir );

	float vecVictimDir2D[3]; vecVictimDir2D[0] = vecVictimDir[0]; vecVictimDir2D[1] = vecVictimDir[1];
	NormalizeVector( vecVictimDir2D, vecVictimDir2D );

	float vecDir2D[3]; vecDir2D[0] = vecDir[0]; vecDir2D[1] = vecDir[1];
	NormalizeVector( vecDir2D, vecDir2D );

	float flDot = GetVectorDotProduct( vecDir2D, vecVictimDir2D );
	if( flDot >= 0.8 ) {
		EmitGameSoundToAll( g_szAirblastPlayerSound, iTarget );

		Event eDeflectedEvent = CreateEvent( "object_deflected", true );
		eDeflectedEvent.SetInt( "userid", GetClientUserId( iAttacker ) );
		eDeflectedEvent.SetInt( "ownerid", GetClientUserId( iTarget ) );
		eDeflectedEvent.SetInt( "weaponid", 0 );
		eDeflectedEvent.SetInt( "object_entindex", iTarget );
		eDeflectedEvent.Fire();

		SDKCall( g_sdkAddDamagerToHistory, iTarget, iAttacker, iWeapon );

		SDKCall( g_sdkAirblastPlayer, GetSharedFromPlayer( iTarget ), iAttacker, vecDir, 500.0 );
		g_alAirblasted[iAttacker].Push( iTarget );
	}
}

void AirblastEntity( int iProjectile, int iAttacker, int iWeapon, const float vecPushDir[3] ) {
	int iProjectileOwner = GetEntPropEnt( iProjectile, Prop_Send, "m_hOwnerEntity" );

	if( GetEntProp( iProjectile, Prop_Send, "m_iTeamNum" ) == GetEntProp( iAttacker, Prop_Send, "m_iTeamNum" ) )
		return;

	Event eDeflectedEvent = CreateEvent( "object_deflected", true );
	eDeflectedEvent.SetInt( "userid", GetClientUserId( iAttacker ) );
	eDeflectedEvent.SetInt( "ownerid", iProjectileOwner == -1 ? 0 : GetClientUserId( iProjectileOwner ) );
	eDeflectedEvent.SetInt( "weaponid", SDKCall( g_sdkGetWeaponID, iWeapon ) );
	eDeflectedEvent.SetInt( "object_entindex", iProjectile );
	eDeflectedEvent.Fire();

	if( AttribHookFloat( 0.0, iWeapon, g_szAttribAirblastDestroy ) != 0.0 ) {
		EmitGameSoundToAll( g_szDeleteAirblastSound, iProjectile );
		RemoveEntity( iProjectile );
		//do particles
	}
	else {
		EmitGameSoundToAll( g_szDeflectSound, iProjectile );
		SDKCall( g_sdkDeflected, iProjectile, iAttacker, vecPushDir );
	}
}

bool Airblast_RayFilter( int iEntity, int iContentsMask, int iOwner ) {
	if( iEntity == -1 )
		return false;
	
	if( iEntity == iOwner )
		return false;

	int iType = GetEntProp( iEntity, Prop_Send, "m_nSolidType" );
	int iMasked = GetEntProp( iEntity, Prop_Send, "m_usSolidFlags" ) & MASK_SOLID;

	return iMasked != 0 || iType == COLLISION_GROUP_DEBRIS;
}

bool Airblast_BoxFilter( int iEntity, int iOwner ) {
	if( !IsValidEntity( iEntity ) )
		return true;

	if( iEntity == iOwner )
		return true;

	if( !SDKCall( g_sdkIsDeflectable, iEntity ) )
		return true;

	g_alEntList.Push( iEntity );

	return true;
}