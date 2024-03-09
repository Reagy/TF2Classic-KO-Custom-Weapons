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
DynamicHook g_dhReload;
DynamicHook g_dhItemPostFrame;

Handle g_sdkLookupSequence;
Handle g_sdkGetProjectileSetup;
Handle g_sdkIsDeflectable;
Handle g_sdkDeflected;
Handle g_sdkGetWeaponID;
Handle g_sdkAirblastPlayer;
Handle g_sdkAddDamagerToHistory;
Handle g_sdkWorldSpaceCenter;
Handle g_sdkSendWeaponAnim;

static char g_szAttribAirblastEnable[] = 	"custom_airblast";
static char g_szAttribAirblastParticle[] =	"custom_airblast_particle";
static char g_szAttribAirblastSound[] =		"custom_airblast_sound";
static char g_szAttribAirblastRefire[] = 	"mult_airblast_refire_time";
static char g_szAttribAirblastScale[] = 	"deflection_size_multiplier";
static char g_szAttribAirblastCost[] = 		"mult_airblast_cost";
static char g_szAttribAirblastSelfPush[] = 	"apply_self_knockback_airblast";
static char g_szAttribAirblastFlags[] = 	"airblast_functionality_flags";
static char g_szAttribAirblastNoPush[] = 	"disable_airblasting_players";
static char g_szAttribAirblastDestroy[] = 	"airblast_destroy_projectile";

static char g_szAirblastSound[] = 		"Weapon_FlameThrower.AirBurstAttack";
static char g_szDeleteAirblastSound[] = 	"Fire.Engulf";
static char g_szExtinguishSound[] = 		"TFPlayer.FlameOut";
static char g_szDeflectSound[] = 		"Weapon_FlameThrower.AirBurstAttackDeflect";
static char g_szAirblastPlayerSound[] = 	"TFPlayer.AirBlastImpact";

static char g_szAirblastParticle[] =		"pyro_blast";
static char g_szDeflectParticle[] = 		"deflect_fx";
static char g_szDeleteParticle[] = 		"explosioncore_sapperdestroyed";

ArrayList g_alAirblasted[MAXPLAYERS+1]; //list of players hit by airblast to prevent pushing multiple times
ArrayList g_alEntList; //temporary entity list for airblast enumeration
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

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CBaseCombatWeapon::SendWeaponAnim" );
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkSendWeaponAnim = EndPrepSDKCall();

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
}

public void OnEntityCreated( int iEntity ) {
	static char szBuffer[64];
	GetEntityClassname( iEntity, szBuffer, sizeof( szBuffer ) );
	if( StrContains( szBuffer, "tf_weapon_" ) == 0 )
		RequestFrame( Frame_CheckAttrib, EntIndexToEntRef( iEntity ) );
}

void Frame_CheckAttrib( int iWeapon ) {
	iWeapon = EntRefToEntIndex( iWeapon );
	if( iWeapon == -1 )
		return;

	if( AttribHookFloat( 0.0, iWeapon, g_szAttribAirblastEnable ) != 0.0 ) {
		g_dhSecondaryFire.HookEntity( Hook_Pre, iWeapon, Hook_SecondaryFire );
		g_dhItemPostFrame.HookEntity( Hook_Pre, iWeapon, Hook_ItemPostFrame );
	}	
}

MRESReturn Hook_SecondaryFire( int iWeapon ) {
	int iOwner = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwner" );
	if( iOwner == -1 )
		return MRES_Ignored;

	int iAmmoCost = RoundToNearest( AttribHookFloat( 20.0, iWeapon, g_szAttribAirblastCost ) );
	if( !HasAmmoToFire( iWeapon, iOwner, iAmmoCost, true ) )
		return MRES_Ignored;

	if( GetEntProp( iWeapon, Prop_Send, "m_iReloadMode" ) != 0 ) {
		SetEntPropFloat( iWeapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() );
		SetEntPropFloat( iWeapon, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() );
		SetEntProp( iWeapon, Prop_Send, "m_iReloadMode", 0 );
	}
	
	if( GetEntPropFloat( iWeapon, Prop_Send, "m_flNextPrimaryAttack" ) > GetGameTime() || GetEntPropFloat( iWeapon, Prop_Send, "m_flNextSecondaryAttack" ) > GetGameTime() )
		return MRES_Ignored;

	ConsumeAmmo( iWeapon, iOwner, iAmmoCost, true );

	float flAirblastInterval = AttribHookFloat( 0.75, iWeapon, g_szAttribAirblastRefire );
	SetEntPropFloat( iWeapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + flAirblastInterval );
	SetEntPropFloat( iWeapon, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() + flAirblastInterval );

	SDKCall( g_sdkSendWeaponAnim, iWeapon, 181 ); //ACT_VM_SECONDARYATTACK
	SetEntProp( iWeapon, Prop_Send, "m_iWeaponMode", 1 );
	SetEntPropFloat( iWeapon, Prop_Send, "m_flTimeWeaponIdle", GetGameTime() + flAirblastInterval - GetClientAvgLatency( iOwner, NetFlow_Both ) );

	EmitGameSoundToAll( g_szAirblastSound, iOwner, SNDCHAN_AUTO );

	DoAirblastParticles( iWeapon, iOwner );

	g_flAirblastEndTime[iOwner] = GetGameTime() + 0.06;

	//airblast_self_push

	return MRES_Supercede;
}

void DoAirblastParticles( int iWeapon, int iOwner ) {
	//first person
	int iParticle = CreateParticle( g_szAirblastParticle, .flDuration = 1.0 );
	ParentParticleToViewmodel( iParticle, iWeapon );
	SetEntProp( iParticle, Prop_Data, "m_iHealth", 1 ); //janky hack: store the behavior of the emitter in some dataprop that isn't used
	SetEntPropEnt( iParticle, Prop_Send, "m_hOwnerEntity", iOwner );
	SDKHook( iParticle, SDKHook_SetTransmit, Hook_EmitterTransmit );
	SetEdictFlags( iParticle, 0 );

	//third person

	//tricks the server into seeing what the client does, i think?
	static char szModelName[128];
	static char szModelNameOld[128];
	FindModelString( GetEntProp( iWeapon, Prop_Send, "m_iWorldModelIndex" ), szModelName, sizeof( szModelName ) );
	FindModelString( GetEntProp( iWeapon, Prop_Send, "m_nModelIndex" ), szModelNameOld, sizeof( szModelNameOld ) );
	SetEntityModel( iWeapon, szModelName );

	iParticle = CreateParticle( g_szAirblastParticle, .flDuration = 1.0 );
	ParentModel( iParticle, iWeapon, "muzzle" );
	SetEntProp( iParticle, Prop_Data, "m_iHealth", 0 );
	SetEntPropEnt( iParticle, Prop_Send, "m_hOwnerEntity", iOwner );
	SDKHook( iParticle, SDKHook_SetTransmit, Hook_EmitterTransmit );
	SetEdictFlags( iParticle, 0 );
	
	//untrick the server
	SetEntityModel( iWeapon, szModelNameOld );
}

//would love to not have to do this but tempent parenting just doesn't work i guess :))))))))
Action Hook_EmitterTransmit( int iEntity, int iClient ) {
	int iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" );
	SetEdictFlags( iEntity, 0 );

	//janky hack: store the behavior of the emitter in some dataprop that isn't used
	bool bIsFirstPersonEmitter = GetEntProp( iEntity, Prop_Data, "m_iHealth" ) == 1;
	if( iClient == iOwner ) {
		return bIsFirstPersonEmitter ? Plugin_Continue : Plugin_Handled;
	}
	return bIsFirstPersonEmitter ? Plugin_Handled : Plugin_Continue;
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

	float vecEntPos[3];
	GetEntPropVector( iProjectile, Prop_Data, "m_vecAbsOrigin", vecEntPos );

	if( AttribHookFloat( 0.0, iWeapon, g_szAttribAirblastDestroy ) != 0.0 ) {
		TE_Particle( g_szDeleteParticle, vecEntPos );

		EmitGameSoundToAll( g_szDeleteAirblastSound, iProjectile );
		RemoveEntity( iProjectile );
	}
	else {
		TE_Particle( g_szDeflectParticle, vecEntPos );

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