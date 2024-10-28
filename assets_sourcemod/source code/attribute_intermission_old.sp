#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <tf2c>
#include <kocwtools>
#include <hudframework>

//todo: replace these with static chars instead of defines
#define MDL_SAPPER              "models/weapons/c_models/c_remotesap/c_sapper.mdl"

#define SOUND_BOOT              "weapons/weapon_crit_charged_on.wav"
#define SOUND_SAPPER_REMOVED    "weapons/sapper_removed.wav"
#define SOUND_SAPPER_THROW      "weapons/knife_swing.wav"
#define SOUND_SAPPER_NOISE      "weapons/sapper_timer.wav"
#define SOUND_SAPPER_NOISE2     "player/invulnerable_off.wav"
#define SOUND_SAPPER_PLANT      "weapons/sapper_plant.wav"

#define EFFECT_SMOKE            "sapper_smoke"
#define EFFECT_SENTRY_FX        "sapper_sentry1_fx"
#define EFFECT_SENTRY_SPARKS1   "sapper_sentry1_sparks1"
#define EFFECT_SENTRY_SPARKS2   "sapper_sentry1_sparks2"

#define EFFECT_CORE_FLASH       "sapper_coreflash"
#define EFFECT_DEBRIS           "sapper_debris"
#define EFFECT_FLASH            "sapper_flash"
#define EFFECT_FLASHUP          "sapper_flashup"
#define EFFECT_FLYINGEMBERS     "sapper_flyingembers"
#define EFFECT_SMOKE            "sapper_smoke"

#define SPRITE_ELECTRIC_WAVE    "sprites/laser.vmt"

#define SAPPERKEYNAME "Sapper"

//time to recharge sapper in seconds
#define INTERMISSION_RECHARGE 20.0

//duration of radial sap in seconds
#define INTERMISSION_DURATION 7.5

//radius of radial sap in hammer units
#define INTERMISSION_RADIUS 350.0

//damage per second dealt by radial sap
#define INTERMISSION_DPS 10.0

//interval sapper checks for nearby buildings
#define INTERMISSION_THINK 0.2

#define INTERMISSION_SELF_DAMAGE_MULT 0.66

//uncomment this line to cause the spy to lose his sapper if he places it in addition to when he throws it
//#define SPY_LOSE_SAPPER

#define DEBUG

enum struct ThrownSapper {
	float flRemoveTime;
	ArrayList alSapping;
}

StringMap g_smSapperList; //contains a list of sappers

ArrayList g_alCheckList; //contains a list of buildings to check for

PlayerFlags g_pfHasIntermission;

int g_hEffectSprite;                                                    // Handle for the lightning shockwave sprite.

public Plugin myinfo = {
	name = "Attribute: Intermission",
	description = "Throwable sapper plugin",
	author = "Noclue",
	version = "3.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
};

DynamicHook g_dhOnTakeDamage;
DynamicHook g_dhObjectKilled;

#if defined SPY_LOSE_SAPPER
DynamicHook g_dhOnGoActive;
#endif

Handle g_hSetObjectMode;
Handle g_hSetSubType;
Handle g_hGiveEcon;
Handle g_hSwapToBest;

public void OnPluginStart() {
	g_smSapperList = new StringMap();

	g_alCheckList = new ArrayList();

	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	g_dhOnTakeDamage = DynamicHook.FromConf( hGameConf, "CBaseEntity::OnTakeDamage" );

	g_dhObjectKilled = DynamicHook.FromConf( hGameConf, "CBaseObject::Killed" );

#if defined SPY_LOSE_SAPPER
	g_dhOnGoActive = DynamicHook.FromConf( hGameConf, "CBaseObject::OnGoActive" );
#endif

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFWeaponBuilder::SetObjectMode" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_hSetObjectMode = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFWeaponBuilder::SetSubType" );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_hSetSubType = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayer::GiveEconItem" );
	PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_hGiveEcon = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CBaseCombatCharacter::SwitchToNextBestWeapon" );
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL );
	g_hSwapToBest = EndPrepSDKCall();

	delete hGameConf;

	HookEvent( "post_inventory_application", Event_Inventory, EventHookMode_Post );
}

public void OnMapStart() {
	PrecacheModel( MDL_SAPPER, true );
	PrecacheSound( SOUND_SAPPER_REMOVED, true );
	PrecacheSound( SOUND_SAPPER_NOISE2, true );
	PrecacheSound( SOUND_SAPPER_NOISE, true );
	PrecacheSound( SOUND_SAPPER_PLANT, true );
	PrecacheSound( SOUND_SAPPER_THROW, true);
	PrecacheSound( SOUND_BOOT, true );

	PrecacheGeneric( EFFECT_SMOKE, true );
	PrecacheGeneric( EFFECT_SENTRY_FX, true );
	PrecacheGeneric( EFFECT_SENTRY_SPARKS1, true );
	PrecacheGeneric( EFFECT_SENTRY_SPARKS2, true );

	g_hEffectSprite = PrecacheModel( SPRITE_ELECTRIC_WAVE, true );
}

public void OnEntityCreated( int iEntity, const char[] szClassname ) {
	if( StrContains( szClassname, "obj_" ) == 0 ) {
#if defined SPY_LOSE_SAPPER
		if( StrEqual( szClassname, "obj_attachment_sapper" ) ) {
			g_dhOnGoActive.HookEntity( Hook_Pre, iEntity, Hook_OnGoActive );
			return;
		}
#endif
		g_alCheckList.Push( EntIndexToEntRef( iEntity ) );
		g_dhObjectKilled.HookEntity( Hook_Pre, iEntity, Hook_ObjectKilled );
	}
}

#if defined SPY_LOSE_SAPPER
MRESReturn Hook_OnGoActive( int iThis ) {
	int iOwner = GetEntPropEnt( iThis, Prop_Send, "m_hBuilder" );
	if( iOwner > 0 && g_pfHasIntermission.Get( iOwner ) )
		TakeSpySapper( iOwner );

	return MRES_Handled;
}
#endif

public Action Event_Inventory( Event hEvent, const char[] sName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	//should this ever happen? no. will i check for it? hell yes
	if( !IsValidPlayer( iPlayer ) )
		return Plugin_Continue;

	RequestFrame( Frame_CheckSapper, EntIndexToEntRef( iPlayer ) );
	
	return Plugin_Continue;
}

void Frame_CheckSapper( int iRef ) {
	int iPlayer = EntRefToEntIndex( iRef );
	if( iPlayer == -1 )
		return;

	if( AttribHookFloat( 0.0, iPlayer, "custom_intermission" ) != 0.0 ) {
		//Tracker_Create( iPlayer, SAPPERKEYNAME, 100.0, 100.0 / INTERMISSION_RECHARGE, RTF_PERCENTAGE | RTF_FORWARDONFULL | RTF_DING | RTF_RECHARGES );
		Tracker_Create( iPlayer, SAPPERKEYNAME );
		Tracker_SetMax( iPlayer, SAPPERKEYNAME, 100.0 );
		Tracker_SetRechargeRate( iPlayer, SAPPERKEYNAME, 100.0 / INTERMISSION_RECHARGE );
		Tracker_SetFlags( iPlayer, SAPPERKEYNAME, RTF_PERCENTAGE | RTF_FORWARDONFULL | RTF_DING | RTF_RECHARGES );
		Tracker_SetValue( iPlayer, SAPPERKEYNAME, 100.0 );
		g_pfHasIntermission.Set( iPlayer, true );
	}
	else {
		Tracker_Remove( iPlayer, SAPPERKEYNAME );
		g_pfHasIntermission.Set( iPlayer, false );
	}
}

int iOldButtons[ MAXPLAYERS+1 ];
public Action OnPlayerRunCmd( int iPlayer, int &iButtons, int &iImpulse, float vecVel[3], float vecAngles[3], int &iWeapon, int &iSubtype, int &iCmdNum, int &iTickCount, int &iSeed, int iMouse[2] ) {
	CheckThrowIntermission( iPlayer, iButtons );

	iOldButtons[ iPlayer ] = iButtons;
	return Plugin_Continue;
}

void CheckThrowIntermission( int iPlayer, int iButtons ) {
	if( !g_pfHasIntermission.Get( iPlayer ) )
		return;

	if( !IsPlayerAlive( iPlayer ) )
		return;

	if( !( iButtons & IN_RELOAD && !( iOldButtons[ iPlayer ] & IN_RELOAD ) ) )
		return;

	if( TF2_IsPlayerInCondition( iPlayer, TFCond_Cloaked ) )
		return;

	int iActiveWeapon = GetEntPropEnt( iPlayer, Prop_Send, "m_hActiveWeapon" );
	if( iActiveWeapon == -1 || AttribHookFloat( 0.0, iActiveWeapon, "custom_intermission" ) == 0.0 )
		return;

	if( Tracker_GetValue( iPlayer, SAPPERKEYNAME ) != 100.0 ) {
		EmitGameSoundToClient( iPlayer, "Player.DenyWeaponSelection" );
		return;
	}

	CreateIntermission( iPlayer );
	TakeSpySapper( iPlayer );
}

int CreateIntermission( int iOwner ) {
	int iEntity = CreateEntityByName( "prop_physics_override" );
	SetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity", iOwner );
	SetEntProp( iEntity, Prop_Data, "m_takedamage", DAMAGE_EVENTS_ONLY );
	SetEntProp( iEntity, Prop_Send, "m_iTeamNum", GetEntProp( iOwner, Prop_Send, "m_iTeamNum" ) );
	SetEntProp( iEntity, Prop_Data, "m_iHealth", AttribHookFloat( 100.0, iOwner, "mult_sapper_health" ) );

	SetEntityModel( iEntity, MDL_SAPPER );
	SetEntityMoveType( iEntity, MOVETYPE_VPHYSICS );
	SetCollisionGroup( iEntity, COLLISION_GROUP_PUSHAWAY );
	SetEntPropFloat( iEntity, Prop_Data, "m_flFriction", 10000.0 );
	SetEntPropFloat( iEntity, Prop_Data, "m_massScale", 100.0 );

	DispatchSpawn( iEntity );

	g_dhOnTakeDamage.HookEntity( Hook_Pre, iEntity, Hook_IntermissionTakeDamage );

	int iRef = EntIndexToEntRef( iEntity );
	CreateTimer( INTERMISSION_THINK, Timer_IntermissionThink, iRef, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );

	EmitSoundToAll( SOUND_BOOT, iEntity, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 0.4, 30 );
	EmitSoundToAll( SOUND_SAPPER_THROW, iOwner );

	if ( TF2_IsPlayerInCondition( iOwner, TFCond_Disguised ) ) {
		TF2_RemoveCondition( iOwner, TFCond_Disguised );
	}

	float vecPlayerPos[3];
	float vecPlayerAngle[3];
	float vecPlayerSpeed[3];
	float vecThrowVel[3];

	GetClientEyePosition( iOwner, vecPlayerPos );
	GetClientEyeAngles( iOwner, vecPlayerAngle );
	GetEntPropVector( iOwner, Prop_Data, "m_vecAbsVelocity", vecPlayerSpeed );

	GetAngleVectors( vecPlayerAngle, vecThrowVel, NULL_VECTOR, NULL_VECTOR );

	ScaleVector( vecThrowVel, 500.0 );
	AddVectors( vecThrowVel, vecPlayerSpeed, vecThrowVel );

	TeleportEntity( iEntity, vecPlayerPos, vecPlayerAngle, vecThrowVel );

	static char szRefString[32];
	IntToString( iRef, szRefString, sizeof( szRefString ) );

	ThrownSapper tsSapper;
	tsSapper.flRemoveTime = GetGameTime() + INTERMISSION_DURATION;
	tsSapper.alSapping = new ArrayList();

	g_smSapperList.SetArray( szRefString, tsSapper, sizeof( ThrownSapper ) );
	return iRef;
}

enum {
	IR_SILENT = 0,
	IR_EXPIRE = 1,
	IR_DESTROY = 2
}

void RemoveIntermission( int iRef, int iRemoveType = 0 ) {
	static char szRefString[32];
	IntToString( iRef, szRefString, sizeof( szRefString ) );

	int iSapper = EntRefToEntIndex( iRef );
	ThrownSapper tsSapper;
	if( g_smSapperList.GetArray( szRefString, tsSapper, sizeof( ThrownSapper ) ) ) {
		for( int i = 0; i < tsSapper.alSapping.Length; i++ ) {
			int iObject = EntRefToEntIndex( tsSapper.alSapping.Get( i ) );
			if( iObject == -1 )
				continue;

			UnsapBuilding( iRef, iObject );
		}
		delete tsSapper.alSapping;
		g_smSapperList.Remove( szRefString );
	}

	if( iSapper == -1 )
		return;

	StopSound( iSapper, 0, SOUND_BOOT );

	float vecSapperPos[3];
	GetEntPropVector( iSapper, Prop_Data, "m_vecAbsOrigin", vecSapperPos );

	//todo: these effects could be better
	switch( iRemoveType ) {
	case ( IR_SILENT ): {

	}
	case ( IR_EXPIRE ): {
		ShowParticle( EFFECT_CORE_FLASH, 1.0, vecSapperPos );
		ShowParticle( EFFECT_DEBRIS, 1.0, vecSapperPos );
		ShowParticle( EFFECT_FLASH, 1.0, vecSapperPos );
		ShowParticle( EFFECT_FLASHUP, 1.0, vecSapperPos );
		ShowParticle( EFFECT_FLYINGEMBERS, 1.0, vecSapperPos );
		ShowParticle( EFFECT_SMOKE, 1.0, vecSapperPos );

		EmitSoundToAll( SOUND_SAPPER_REMOVED, iSapper );
	}
	case ( IR_DESTROY ): {
		ShowParticle( EFFECT_CORE_FLASH, 1.0, vecSapperPos );
		ShowParticle( EFFECT_DEBRIS, 1.0, vecSapperPos );
		ShowParticle( EFFECT_FLASH, 1.0, vecSapperPos );
		ShowParticle( EFFECT_FLASHUP, 1.0, vecSapperPos );
		ShowParticle( EFFECT_FLYINGEMBERS, 1.0, vecSapperPos );
		ShowParticle( EFFECT_SMOKE, 1.0, vecSapperPos );

		EmitGameSoundToAll( "Weapon_Grenade_Mirv.Disarm", iSapper );
	}
	}

	RemoveEntity( iSapper );
}

bool CheckLOS( int iThis, const float vecStart[3], const float vecEnd[3], int iTarget ) {
	Handle hTrace = TR_TraceRayFilterEx( vecStart, vecEnd, CONTENTS_SOLID | CONTENTS_MOVEABLE | CONTENTS_MIST, RayType_EndPoint, LOSFilter, iThis );

	if( TR_GetFraction( hTrace ) >= 1.0 ) return false;
	if( TR_GetEntityIndex( hTrace ) != iTarget ) return false;
	return true;
}

bool LOSFilter( int iEntity, int iMask, any data ) {
	return !( data == iEntity || iEntity <= MaxClients );
}

Action Timer_IntermissionThink( Handle hTimer, int iSapperRef ) {
	int iSapperIndex = EntRefToEntIndex( iSapperRef );
	if( iSapperIndex == -1 ) {
		RemoveIntermission( iSapperRef, IR_SILENT );
		return Plugin_Stop;
	}

	AttachRings( iSapperIndex );

	int iSapperOwner = GetEntPropEnt( iSapperIndex, Prop_Send, "m_hOwnerEntity" );
	if( iSapperOwner == -1 || !g_pfHasIntermission.Get( iSapperOwner ) ) {
		RemoveIntermission( iSapperRef, IR_SILENT );
		return Plugin_Stop;
	}
	int iSapperTeam = GetEntProp( iSapperIndex, Prop_Send, "m_iTeamNum" );
	if( iSapperTeam != GetEntProp( iSapperOwner, Prop_Send, "m_iTeamNum" ) ) {
		RemoveIntermission( iSapperRef, IR_SILENT );
		return Plugin_Stop;
	}

	float vecSapperPos[3];
	GetEntPropVector( iSapperIndex, Prop_Data, "m_vecAbsOrigin", vecSapperPos );

	for( int i = 0; i < g_alCheckList.Length; i++ ) {
		int iObjectIndex = EntRefToEntIndex( g_alCheckList.Get( i ) );
		if( iObjectIndex == -1 ) {
			g_alCheckList.Erase( i );
			i--;
			continue;
		}

		if( iSapperTeam == GetEntProp( iObjectIndex, Prop_Send, "m_iTeamNum" ) )
			continue;

		float vecTargetPos[3];
		GetEntPropVector( iObjectIndex, Prop_Data, "m_vecAbsOrigin", vecTargetPos );
		if( GetVectorDistance( vecSapperPos, vecTargetPos ) > INTERMISSION_RADIUS )
			continue;

		vecSapperPos[1] += 5.0;
		if( !CheckLOS( iSapperIndex, vecSapperPos, vecTargetPos, iObjectIndex ) ) {
			vecTargetPos[1] += 20.0; //check the top of the building
			if( !CheckLOS( iSapperIndex, vecSapperPos, vecTargetPos, iObjectIndex ) ) {
				continue;
			}
		}

		SapBuilding( iSapperRef, iObjectIndex );
	}

	static char szRefString[32];
	IntToString( iSapperRef, szRefString, sizeof( szRefString ) );
	
	ThrownSapper tsSapper;
	g_smSapperList.GetArray( szRefString, tsSapper, sizeof( ThrownSapper ) );

	for( int i = 0; i < tsSapper.alSapping.Length; i++ ) {
		int iObjectIndex = EntRefToEntIndex( tsSapper.alSapping.Get( i ) );

		if( iObjectIndex == -1 ) {
			tsSapper.alSapping.Erase( i );
			i--;
			continue;
		}

		SDKHooks_TakeDamage( iObjectIndex, iSapperIndex, iSapperIndex, INTERMISSION_DPS * INTERMISSION_THINK, 0 );
	}

	if( GetGameTime() > tsSapper.flRemoveTime )  {
		RemoveIntermission( iSapperRef, IR_EXPIRE );
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

void SapBuilding( int iSapperRef, int iObjectIndex ) {
	static char szRefString[32];

	int iObjectRef = EntIndexToEntRef( iObjectIndex );
	IntToString( iSapperRef, szRefString, sizeof( szRefString ) );

	ThrownSapper tsSapper;
	g_smSapperList.GetArray( szRefString, tsSapper, sizeof( tsSapper ) );

	if( tsSapper.alSapping.FindValue( iObjectRef ) == -1 ) {
		tsSapper.alSapping.Push( iObjectRef );
	}

	IntToString( iObjectRef, szRefString, sizeof( szRefString ) );
	ArrayList alSappedBy;

	if( !g_smSappedBuildings.GetValue( szRefString, alSappedBy ) ) {
		alSappedBy = new ArrayList();
		g_smSappedBuildings.SetValue( szRefString, alSappedBy );
	}
	
	float vecEffectPos[3];
	vecEffectPos[0] = GetRandomFloat( -25.0, 25.0 );
	vecEffectPos[1] = GetRandomFloat( -25.0, 25.0 );
	vecEffectPos[2] = GetRandomFloat( 10.0, ( GetEntProp( iObjectIndex, Prop_Send, "m_iObjectType" ) == 1 ) ? 25.0 : 65.0 );

	//todo: this is really stupid
	AttachParticle( iObjectIndex, EFFECT_SENTRY_FX, 0.5, vecEffectPos );
	AttachParticle( iObjectIndex, EFFECT_SENTRY_SPARKS1, 0.5, vecEffectPos );
	AttachParticle( iObjectIndex, EFFECT_SENTRY_SPARKS2, 0.5, vecEffectPos );

	if( alSappedBy.FindValue( iSapperRef ) != -1 )
		return;
		
	alSappedBy.Push( iSapperRef );

#if defined DEBUG
	PrintToServer( "building %i sapped list size %i", iObjectIndex, alSappedBy.Length );
#endif

	EmitSoundToAll( SOUND_SAPPER_NOISE, iObjectIndex, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 1.0, 150 );
	EmitSoundToAll( SOUND_SAPPER_NOISE2, iObjectIndex, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 1.0, 60 );
	EmitSoundToAll( SOUND_SAPPER_PLANT, iObjectIndex );

	SetVariantInt( 1 ); //throws a tantrum without some kind of parameter
	AcceptEntityInput( iObjectIndex, "Disable" );
}

void UnsapBuilding( int iSapperRef, int iObjectIndex ) {
	if( !IsValidEntity( iObjectIndex ) )
		return;

	static char szRefString[32];
	int iObjectRef = EntIndexToEntRef( iObjectIndex );
	IntToString( iSapperRef, szRefString, sizeof( szRefString ) );
	
	ThrownSapper tsSapper;
	if( !g_smSapperList.GetArray( szRefString, tsSapper, sizeof( tsSapper ) ) )
		return;
	
	int iValue = tsSapper.alSapping.FindValue( iObjectRef );
	if( iValue != -1 )
		tsSapper.alSapping.Erase( iValue );

	IntToString( iObjectRef, szRefString, sizeof( szRefString ) );
	ArrayList alSappedBy;
	if( !g_smSappedBuildings.GetValue( szRefString, alSappedBy ) )
		return;

	iValue = alSappedBy.FindValue( iSapperRef );
	if( iValue == -1 )
		return;

#if defined DEBUG
	PrintToServer( "building %i unsapped list size %i", iObjectIndex, alSappedBy.Length );
#endif

	alSappedBy.Erase( iValue );

	if( alSappedBy.Length == 0 ) {
#if defined DEBUG
		PrintToServer( "unsapping %i", iObjectIndex );
#endif

		SetVariantInt( 1 ); //throws a tantrum without some kind of parameter
		AcceptEntityInput( iObjectIndex, "Enable" );
		g_smSappedBuildings.Remove( szRefString );

		StopSound( iObjectIndex, 0, SOUND_SAPPER_NOISE );
		StopSound( iObjectIndex, 0, SOUND_SAPPER_NOISE2 );
		StopSound( iObjectIndex, 0, SOUND_SAPPER_PLANT );

		delete alSappedBy;
	}

}

MRESReturn Hook_IntermissionTakeDamage( int iEntity, DHookReturn hReturn, DHookParam hParams ) {
	TFDamageInfo tfInfo = TFDamageInfo( hParams.GetAddress( 1 ) );
	hReturn.Value = 0;
	
	if( tfInfo.iCustom != 4 ) //wrench fix
		return MRES_Supercede;

	int iAttacker = tfInfo.iAttacker;
	if( iAttacker == -1  )
		return MRES_Supercede;

	if( GetEntProp( iAttacker, Prop_Send, "m_iTeamNum" ) == GetEntProp( iEntity, Prop_Send, "m_iTeamNum" ) )
		return MRES_Supercede;

	SetEntProp( iEntity, Prop_Data, "m_iHealth", GetEntProp( iEntity, Prop_Data, "m_iHealth" ) - RoundToFloor( tfInfo.flDamage ) );
	if( GetEntProp( iEntity, Prop_Data, "m_iHealth" ) <= 0 )
		RemoveIntermission( EntIndexToEntRef( iEntity ), IR_DESTROY );

	return MRES_Supercede;
}

public void OnTakeDamageBuilding( int iTarget, Address aDamageInfo ) {
	if( GetEntProp( iTarget, Prop_Send, "m_iObjectType" ) != 2 ) //sentry gun
		return;

	TFDamageInfo tfInfo = TFDamageInfo( aDamageInfo );
	
	static char szRefString[32];
	IntToString( EntIndexToEntRef( iTarget ), szRefString, sizeof( szRefString ) );

	ArrayList alSappers;
	if( !g_smSappedBuildings.GetValue( szRefString, alSappers ) )
		return;

	for( int i = 0; i < alSappers.Length; i++ ) {
		int iSapper = EntRefToEntIndex( alSappers.Get( i ) );
		if( iSapper == -1 )
			continue;

		int iSapperOwner = GetEntPropEnt( iSapper, Prop_Send, "m_hOwnerEntity" );
		if( tfInfo.iAttacker == iSapperOwner ) {
			tfInfo.flDamage *= INTERMISSION_SELF_DAMAGE_MULT;
			return;
		}
	}
}
static int g_iColors[6][4] = {
	{ 0, 0, 0, 0 }, //spectator
	{ 0, 0, 0, 0 }, //unassigned
	{ 184, 56, 59, 255 }, //red
	{ 88, 133, 162, 255 }, //blue
	{ 66, 214, 84, 255 }, //green
	{ 255, 249, 77, 255 } //yellow
};
//Attaches team colored electrical rings to a sapper. Not tested with other entities.
stock void AttachRings( int iEntity ) {
	float vecSapperPos[3];
	GetEntPropVector( iEntity, Prop_Data, "m_vecAbsOrigin", vecSapperPos );
	MakeRings( vecSapperPos, g_iColors[ GetEntProp( iEntity, Prop_Send, "m_iTeamNum" ) ] );
}

void MakeRings( float vecSapperPos[3], int iColor[4] ) {
	for(int i = 0; i < 4; i++) {
		TE_SetupBeamRingPoint( vecSapperPos, 0.1, INTERMISSION_RADIUS, g_hEffectSprite, g_hEffectSprite, 1, 1, 0.6, 3.0, 10.0, iColor, 15, 0);
		TE_SendToAll();
	}
}

stock int AttachParticle( int iEntity, char szParticleName[64], float flTime, float vecAddPos[3] = NULL_VECTOR, float vecAddAngle[3] = NULL_VECTOR ) {
	int iParticle = CreateEntityByName( "info_particle_system" );

	float vecPos[3];
	float vecAng[3];

	GetEntPropVector( iEntity, Prop_Send, "m_vecOrigin", vecPos );
	AddVectors( vecPos, vecAddPos, vecPos );
	GetEntPropVector( iEntity, Prop_Send, "m_angRotation", vecAng );
	AddVectors( vecAng, vecAddAngle, vecAng );

	TeleportEntity( iParticle, vecPos, vecAng );
	DispatchKeyValue( iParticle, "effect_name", szParticleName );

	DispatchSpawn( iParticle );
	ParentModel( iParticle, iEntity );
	ActivateEntity( iParticle );

	AcceptEntityInput( iParticle, "start" );

	CreateTimer( flTime, RemoveParticle, EntIndexToEntRef( iParticle ), TIMER_FLAG_NO_MAPCHANGE );

	return iParticle;
}

stock void ShowParticle( char szParticleName[64], float flTime, float vecPos[3], float vecAng[3] = NULL_VECTOR ) {
	int iParticle = CreateEntityByName("info_particle_system");

	TeleportEntity( iParticle, vecPos, vecAng, NULL_VECTOR );

	DispatchKeyValue( iParticle, "effect_name", szParticleName );
	DispatchSpawn( iParticle );
	ActivateEntity( iParticle );
	AcceptEntityInput( iParticle, "start" );
	CreateTimer( flTime, RemoveParticle, EntIndexToEntRef( iParticle ) );
}

Action RemoveParticle( Handle hTimer, int iParticle ) {
	iParticle = EntRefToEntIndex( iParticle );
	if ( iParticle != -1 ) {
		AcceptEntityInput( iParticle, "stop" );
		AcceptEntityInput( iParticle, "Kill" );
	}
	return Plugin_Continue;
}

void GiveSpySapper( int iPlayer ) {
	SDKCall( g_hGiveEcon, iPlayer, "TF_WEAPON_BUILDER_SPY_TEST", 4, 0 ); //todo: find a way to make this not hardcoded
	int iSapper = GetEntityInSlot( iPlayer, 4 );

	//i can't fathom why it's like this but you can't reequip the sapper unless i do whatever the fuck this is
	SDKCall( g_hSetSubType, iSapper, 3 );
	SDKCall( g_hSetObjectMode, iSapper, 0 );
}
void TakeSpySapper( int iPlayer ) {
	int iWeapon = GetEntityInSlot( iPlayer, 4 );
	if( iWeapon > 0 ) {
		Tracker_SetValue( iPlayer, SAPPERKEYNAME, 0.0 );
		RemoveEntity( iWeapon );
		SDKCall( g_hSwapToBest, iPlayer, -1 );
	}
}

public void Tracker_OnRecharge( int iPlayer, const char szTrackerName[32], float flNewValue ) {
	if( !StrEqual( szTrackerName, SAPPERKEYNAME ) )
		return;

	if( !g_pfHasIntermission.Get( iPlayer ) || !IsPlayerAlive( iPlayer ) )
		return;

	GiveSpySapper( iPlayer );
}

MRESReturn Hook_ObjectKilled( int iThis, DHookParam hParams ) {
	static char szRefString[32];
	int iObjectRef = EntIndexToEntRef( iThis );
	IntToString( iObjectRef, szRefString, sizeof( szRefString ) );

	StopSound( iThis, 0, SOUND_SAPPER_NOISE );
	StopSound( iThis, 0, SOUND_SAPPER_NOISE2 );
	StopSound( iThis, 0, SOUND_SAPPER_PLANT );

	ArrayList alList;
	if( !g_smSappedBuildings.GetValue( szRefString, alList ) )
		return MRES_Ignored;

	delete alList;

	g_smSappedBuildings.Remove( szRefString );
	
	int iThisIndex = g_alCheckList.FindValue( iObjectRef );
	if( iThisIndex != -1 ) {
		g_alCheckList.Erase( iThisIndex );
	}

	return MRES_Handled;
}