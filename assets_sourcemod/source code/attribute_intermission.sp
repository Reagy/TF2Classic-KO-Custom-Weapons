#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <tf2c>
#include <kocwtools>
#include <hudframework>
#include <custom_entprops>

//todo: replace these with static chars instead of defines
static char g_szSapperModel[] = "models/weapons/c_models/c_remotesap/c_sapper.mdl";

static char g_szSoundSapperBoot[] =	"weapons/weapon_crit_charged_on.wav";
static char g_szSoundSapperRemoved[] = 	"weapons/sapper_removed.wav";
static char g_szSoundSapperThrow[] =	"weapons/knife_swing.wav";
static char g_szSoundSapperNoise[] =	"weapons/sapper_timer.wav";
static char g_szSoundSapperNoise2[] =	"player/invulnerable_off.wav";
static char g_szSoundSapperPlant[] =	"weapons/sapper_plant.wav";
static char g_szSndscrSapperDestroy[] =	"Weapon_Grenade_Mirv.Disarm";

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

//damage multiplier for attacking sentries the spy is sapping
#define INTERMISSION_SELF_DAMAGE_MULT 0.66

//uncomment this line to cause the spy to lose his sapper if he places it in addition to when he throws it
//#define SPY_LOSE_SAPPER

#define DEBUG

enum {
	IR_SILENT = 0,
	IR_EXPIRE = 1,
	IR_DESTROY = 2
}

enum struct ThrownSapper {
	int iReference;
	float flRemoveTime;
	ArrayList alSapping;
}

ThrownSapper g_esPlayerSappers[MAXPLAYERS+1];
ArrayList g_alBuildingList; //contains a list of building reference ids to iterate

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
	g_alBuildingList = new ArrayList();

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

	for( int i = 0; i < sizeof( g_esPlayerSappers ); i++ ) {
		g_esPlayerSappers[i].iReference = INVALID_ENT_REFERENCE;
		g_esPlayerSappers[i].alSapping = new ArrayList();
	}
}

public void OnMapStart() {
	PrecacheModel( g_szSapperModel, true );
	PrecacheSound( g_szSoundSapperRemoved, true );
	PrecacheSound( g_szSoundSapperNoise2, true );
	PrecacheSound( g_szSoundSapperNoise, true );
	PrecacheSound( g_szSoundSapperPlant, true );
	PrecacheSound( g_szSoundSapperThrow, true);
	PrecacheSound( g_szSoundSapperBoot, true );

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
		g_alBuildingList.Push( EntIndexToEntRef( iEntity ) );
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
		Tracker_Create( iPlayer, SAPPERKEYNAME );
		Tracker_SetMax( iPlayer, SAPPERKEYNAME, 100.0 );
		Tracker_SetRechargeRate( iPlayer, SAPPERKEYNAME, 100.0 / INTERMISSION_RECHARGE );
		Tracker_SetValue( iPlayer, SAPPERKEYNAME, 100.0 );
		Tracker_SetFlags( iPlayer, SAPPERKEYNAME, RTF_PERCENTAGE | RTF_FORWARDONFULL | RTF_DING | RTF_RECHARGES );
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
	if( EntRefToEntIndex( g_esPlayerSappers[iOwner].iReference ) != -1 ) {
		RemoveIntermission( iOwner );
	}

	int iSapper = CreateEntityByName( "prop_physics_override" );
	SetEntPropEnt( iSapper, Prop_Send, "m_hOwnerEntity", iOwner );
	SetEntProp( iSapper, Prop_Data, "m_takedamage", DAMAGE_EVENTS_ONLY );
	SetEntProp( iSapper, Prop_Send, "m_iTeamNum", GetEntProp( iOwner, Prop_Send, "m_iTeamNum" ) );
	SetEntProp( iSapper, Prop_Data, "m_iHealth", AttribHookFloat( 100.0, iOwner, "mult_sapper_health" ) );

	SetEntityModel( iSapper, g_szSapperModel );
	SetEntityMoveType( iSapper, MOVETYPE_VPHYSICS );
	SetCollisionGroup( iSapper, COLLISION_GROUP_PUSHAWAY );
	SetEntPropFloat( iSapper, Prop_Data, "m_flFriction", 10000.0 );
	SetEntPropFloat( iSapper, Prop_Data, "m_massScale", 100.0 );

	DispatchSpawn( iSapper );

	g_dhOnTakeDamage.HookEntity( Hook_Pre, iSapper, Hook_IntermissionTakeDamage );

	int iRef = EntIndexToEntRef( iSapper );
	CreateTimer( INTERMISSION_THINK, Timer_IntermissionThink, iOwner, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );

	EmitSoundToAll( g_szSoundSapperBoot, iSapper, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 0.4, 30 );
	EmitSoundToAll( g_szSoundSapperThrow, iOwner );

	if ( TF2_IsPlayerInCondition( iOwner, TFCond_Disguised ) )
		TF2_RemoveCondition( iOwner, TFCond_Disguised );

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

	TeleportEntity( iSapper, vecPlayerPos, vecPlayerAngle, vecThrowVel );

	g_esPlayerSappers[iOwner].iReference = iRef;
	g_esPlayerSappers[iOwner].flRemoveTime = GetGameTime() + INTERMISSION_DURATION;
	g_esPlayerSappers[iOwner].alSapping.Clear();

	return iRef;
}

void RemoveIntermission( int iOwner, int iRemoveType = 0 ) {
	int iSapper = EntRefToEntIndex( g_esPlayerSappers[iOwner].iReference );
	for( int i = 0; i < g_esPlayerSappers[iOwner].alSapping.Length; i++ ) {
		int iBuilding = EntRefToEntIndex( g_esPlayerSappers[iOwner].alSapping.Get( i ) );
		if( iBuilding == -1 )
			continue;

		UnsapBuilding( iOwner, iBuilding );
	}

	g_esPlayerSappers[iOwner].iReference = INVALID_ENT_REFERENCE;
	g_esPlayerSappers[iOwner].alSapping.Clear();

	if( iSapper == -1 )
		return;

	StopSound( iSapper, 0, g_szSoundSapperBoot );

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

		EmitSoundToAll( g_szSoundSapperRemoved, iSapper );
	}
	case ( IR_DESTROY ): {
		ShowParticle( EFFECT_CORE_FLASH, 1.0, vecSapperPos );
		ShowParticle( EFFECT_DEBRIS, 1.0, vecSapperPos );
		ShowParticle( EFFECT_FLASH, 1.0, vecSapperPos );
		ShowParticle( EFFECT_FLASHUP, 1.0, vecSapperPos );
		ShowParticle( EFFECT_FLYINGEMBERS, 1.0, vecSapperPos );
		ShowParticle( EFFECT_SMOKE, 1.0, vecSapperPos );

		EmitGameSoundToAll( g_szSndscrSapperDestroy, iSapper );
	}
	}

	RemoveEntity( iSapper );
}

bool CheckLOS( int iThis, const float vecStart[3], const float vecEnd[3], int iTarget ) {
	Handle hTrace = TR_TraceRayFilterEx( vecStart, vecEnd, CONTENTS_SOLID | CONTENTS_MOVEABLE | CONTENTS_MIST, RayType_EndPoint, LOSFilter, iThis );

	if( TR_GetFraction( hTrace ) >= 1.0 ) return false;
	//if( TR_GetEntityIndex( hTrace ) != iTarget ) return false;
	return true;
}

bool LOSFilter( int iEntity, int iMask, any data ) {
	return !( data == iEntity || iEntity <= MaxClients );
}

Action Timer_IntermissionThink( Handle hTimer, int iOwner ) {
	int iSapperRef = g_esPlayerSappers[iOwner].iReference;
	int iSapperIndex = EntRefToEntIndex( iSapperRef );
	if( iSapperIndex == -1 || !g_pfHasIntermission.Get( iOwner ) ) {
		RemoveIntermission( iOwner, IR_SILENT );
		return Plugin_Stop;
	}

	AttachRings( iSapperIndex );

	int iSapperTeam = GetEntProp( iSapperIndex, Prop_Send, "m_iTeamNum" );
	if( iSapperTeam != GetEntProp( iOwner, Prop_Send, "m_iTeamNum" ) ) {
		RemoveIntermission( iOwner, IR_SILENT );
		return Plugin_Stop;
	}

	float vecSapperPos[3];
	GetEntPropVector( iSapperIndex, Prop_Data, "m_vecAbsOrigin", vecSapperPos );

	for( int i = 0; i < g_alBuildingList.Length; i++ ) {
		int iObjectIndex = EntRefToEntIndex( g_alBuildingList.Get( i ) );
		if( iObjectIndex == -1 )
			continue;

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

		SapBuilding( iOwner, iObjectIndex );
	}

	for( int i = 0; i < g_esPlayerSappers[iOwner].alSapping.Length; i++ ) {
		int iObjectIndex = EntRefToEntIndex( g_esPlayerSappers[iOwner].alSapping.Get( i ) );
		if( iObjectIndex == -1 )
			continue;

		SDKHooks_TakeDamage( iObjectIndex, iSapperIndex, iSapperIndex, INTERMISSION_DPS * INTERMISSION_THINK, 0 );
	}

	if( GetGameTime() > g_esPlayerSappers[iOwner].flRemoveTime )  {
		RemoveIntermission( iOwner, IR_EXPIRE );
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

void SapBuilding( int iOwner, int iObjectIndex ) {
	if( !IsValidEntity( iObjectIndex ) )
		return;

	int iObjectRef = EntIndexToEntRef( iObjectIndex );
	if( g_esPlayerSappers[iOwner].alSapping.FindValue( iObjectRef ) != -1 ) {
		return;
	}
	
	g_esPlayerSappers[iOwner].alSapping.Push( iObjectRef );

	float vecEffectPos[3];
	vecEffectPos[0] = GetRandomFloat( -25.0, 25.0 );
	vecEffectPos[1] = GetRandomFloat( -25.0, 25.0 );
	vecEffectPos[2] = GetRandomFloat( 10.0, ( GetEntProp( iObjectIndex, Prop_Send, "m_iObjectType" ) == 1 ) ? 25.0 : 65.0 );

	//todo: this is really stupid
	AttachParticle( iObjectIndex, EFFECT_SENTRY_FX, 0.5, vecEffectPos );
	AttachParticle( iObjectIndex, EFFECT_SENTRY_SPARKS1, 0.5, vecEffectPos );
	AttachParticle( iObjectIndex, EFFECT_SENTRY_SPARKS2, 0.5, vecEffectPos );

	int iSapCount = 0; GetCustomProp( iObjectIndex, "m_iSapCount", iSapCount );

#if defined DEBUG
	PrintToServer( "building %i added sapper, count %i", iObjectIndex, iSapCount+1 );
#endif

	EmitSoundToAll( g_szSoundSapperNoise, iObjectIndex, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 1.0, 150 );
	EmitSoundToAll( g_szSoundSapperNoise2, iObjectIndex, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 1.0, 60 );
	EmitSoundToAll( g_szSoundSapperPlant, iObjectIndex, SNDCHAN_AUTO );

	SetVariantInt( 1 ); //throws a tantrum without some kind of parameter
	AcceptEntityInput( iObjectIndex, "Disable" );

	SetCustomProp( iObjectIndex, "m_iSapCount", iSapCount+1 );
}

void UnsapBuilding( int iOwner, int iObjectIndex ) {
	if( !IsValidEntity( iObjectIndex ) )
		return;

	int iSapCount = 0; GetCustomProp( iObjectIndex, "m_iSapCount", iSapCount );

#if defined DEBUG
	PrintToServer( "building %i removed sapper, count %i", iObjectIndex, iSapCount-1 );
#endif

	SetCustomProp( iObjectIndex, "m_iSapCount", iSapCount-1 );
	if( iSapCount-1 <= 0 ) {

		SetVariantInt( 1 ); //throws a tantrum without some kind of parameter
		AcceptEntityInput( iObjectIndex, "Enable" );

		StopSound( iObjectIndex, SNDCHAN_AUTO, g_szSoundSapperNoise );
		StopSound( iObjectIndex, SNDCHAN_AUTO, g_szSoundSapperNoise2 );
		StopSound( iObjectIndex, SNDCHAN_AUTO, g_szSoundSapperPlant );

#if defined DEBUG
		PrintToServer( "enabling %i", iObjectIndex );
#endif
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
	if( GetEntProp( iEntity, Prop_Data, "m_iHealth" ) <= 0 ) {
		int iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" );
		RemoveIntermission( iOwner, IR_DESTROY );
	}

	return MRES_Supercede;
}

public void OnTakeDamageBuilding( int iBuilding, TFDamageInfo tfDamageInfo ) {
	if( GetEntProp( iBuilding, Prop_Send, "m_iObjectType" ) != 2 ) //sentry gun
		return;
	
	int iAttacker = tfDamageInfo.iAttacker;
	if( !IsValidPlayer( iAttacker ) )
		return;

	int iSapCount = 0; GetCustomProp( iBuilding, "m_iSapCount", iSapCount );
	if( iSapCount <= 0 )
		return;

	//if building is in attacker's sap list return
	int iBuildingRef = EntIndexToEntRef( iBuilding );
	if( g_esPlayerSappers[iAttacker].alSapping.FindValue( iBuildingRef ) == -1 )
		return;

	tfDamageInfo.flDamage *= INTERMISSION_SELF_DAMAGE_MULT;
}
static int g_iRingColors[6][4] = {
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
	MakeRings( vecSapperPos, g_iRingColors[ GetEntProp( iEntity, Prop_Send, "m_iTeamNum" ) ] );
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

public void Tracker_OnRecharge( int iPlayer, const char[] szTrackerName, float flNewValue ) {
	if( !StrEqual( szTrackerName, SAPPERKEYNAME ) )
		return;

	if( iPlayer == -1 )
		return;

	if( !g_pfHasIntermission.Get( iPlayer ) || !IsPlayerAlive( iPlayer ) )
		return;

	GiveSpySapper( iPlayer );
}

MRESReturn Hook_ObjectKilled( int iThis, DHookParam hParams ) {
	int iObjectRef = EntIndexToEntRef( iThis );

	StopSound( iThis, 0, g_szSoundSapperNoise );
	StopSound( iThis, 0, g_szSoundSapperNoise2 );
	StopSound( iThis, 0, g_szSoundSapperPlant );
	
	int iThisIndex = g_alBuildingList.FindValue( iObjectRef );
	if( iThisIndex != -1 ) {
		g_alBuildingList.Erase( iThisIndex );
	}

	return MRES_Handled;
}