#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <tf2c>
#include <kocwtools>
#include <hudframework>

#define MDL_SAPPER              "models/weapons/c_models/c_remotesap/c_remotesap.mdl"

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

#define INTERMISSION_DURATION 7.5
#define INTERMISSION_RADIUS 350.0
#define INTERMISSION_DPS 10.0
#define INTERMISSION_THINK 0.2

/*
	todo:
	finish particles
	attribute sap damage to spy

	duration increased 50% (5>7.5)
	radius increased 16% (300>350)
	no longer saps your cloak
	recharges after 30s

	spy receives a 66% damage penalty against sentries he sapped
	sapper can be destroyed by anything that can remove sappers
	can no longer sap through walls
	
	fixed radial sap not working on jump pads (like you'd ever do that anyway)
*/

enum struct ThrownSapper {
	float flRemoveTime;
	ArrayList hSapping;
}

StringMap smSapperList; //contains a list of sappers
StringMap smSappedBuildings; //contains an arraylist of every sapper sapping this building

ArrayList hCheckList; //contains a list of buildings to check for

PlayerFlags fHasIntermission;

int g_hEffectSprite;                                                    // Handle for the lightning shockwave sprite.

public Plugin myinfo = {
	name = "Attribute: Intermission",
	description = "Throwable sapper plugin",
	author = "Noclue",
	version = "2.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
};

DynamicHook hOnTakeDamage;

Handle hSetObjectMode;
Handle hSetSubType;
Handle hGiveEcon;
Handle hSwapToBest;

public void OnPluginStart() {
	smSapperList = new StringMap();
	smSappedBuildings = new StringMap();

	hCheckList = new ArrayList();

	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	hOnTakeDamage = DynamicHook.FromConf( hGameConf, "CBaseEntity::OnTakeDamage" );

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetVirtual( 450 );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	hSetObjectMode = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetVirtual( 232 );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	hSetSubType = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetSignature( SDKLibrary_Server, "@_ZN9CTFPlayer12GiveEconItemEPKcii", 0 );
	PrepSDKCall_SetReturnInfo( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_String, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	hGiveEcon = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetSignature( SDKLibrary_Server, "@_ZN20CBaseCombatCharacter22SwitchToNextBestWeaponEP17CBaseCombatWeapon", 0 );
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL );
	hSwapToBest = EndPrepSDKCall();

	RegConsoleCmd( "sm_sapper_test", Command_Test, "test" );

	delete hGameConf;

	HookEvent( "post_inventory_application", Event_Inventory, EventHookMode_Post );
}

Action Command_Test( int iClient, int iArgs ) {
	GiveSpySapper( iClient );

	return Plugin_Handled;
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
	if( 
		StrEqual( szClassname, "obj_sentrygun" ) ||
		StrEqual( szClassname, "obj_dispenser" ) ||
		StrEqual( szClassname, "obj_teleporter" ) ||
		StrEqual( szClassname, "obj_jumppad" )
	) {
		hCheckList.Push( EntIndexToEntRef( iEntity ) );
		return;
	}
}

public Action Event_Inventory( Event hEvent, const char[] sName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

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
		Tracker_Create( iPlayer, SAPPERKEYNAME, 100.0, 100.0 / 30.0, RTF_PERCENTAGE | RTF_FORWARDONFULL | RTF_DING | RTF_RECHARGES );
		fHasIntermission.Set( iPlayer, true );
	}
	else {
		Tracker_Remove( iPlayer, SAPPERKEYNAME );
		fHasIntermission.Set( iPlayer, false );
	}
}

int iOldButtons[ MAXPLAYERS+1 ];
public Action OnPlayerRunCmd( int iPlayer, int &iButtons, int &iImpulse, float vecVel[3], float vecAngles[3], int &iWeapon, int &iSubtype, int &iCmdNum, int &iTickCount, int &iSeed, int iMouse[2] ) {
	CheckThrowIntermission( iPlayer, iButtons );

	iOldButtons[ iPlayer ] = iButtons;
	return Plugin_Continue;
}

void CheckThrowIntermission( int iPlayer, int iButtons ) {
	if( !fHasIntermission.Get( iPlayer ) )
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
	SetEntProp( iEntity, Prop_Data, "m_takedamage", DAMAGE_YES );
	SetEntProp( iEntity, Prop_Send, "m_iTeamNum", GetEntProp( iOwner, Prop_Send, "m_iTeamNum" ) );
	SetEntProp( iEntity, Prop_Data, "m_iHealth", AttribHookFloat( 100.0, iOwner, "mult_sapper_health" ) );

	SetEntityModel( iEntity, MDL_SAPPER );
	SetEntityMoveType( iEntity, MOVETYPE_VPHYSICS );
	SetCollisionGroup( iEntity, COLLISION_GROUP_PUSHAWAY );
	SetEntPropFloat( iEntity, Prop_Data, "m_flFriction", 10000.0 );
	SetEntPropFloat( iEntity, Prop_Data, "m_massScale", 100.0 );

	DispatchSpawn( iEntity );

	hOnTakeDamage.HookEntity( Hook_Pre, iEntity, Hook_IntermissionTakeDamage );

	int iRef = EntIndexToEntRef( iEntity );
	CreateTimer( INTERMISSION_THINK, Timer_IntermissionThink, iRef, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );

	EmitSoundToAll( SOUND_BOOT, iEntity, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 0.2, 30 );
	EmitSoundToAll( SOUND_SAPPER_THROW, iOwner );

	if ( TF2_IsPlayerInCondition( iOwner, TFCond_Disguised ) ) {
		TF2_RemoveCondition( iOwner, TFCond_Disguised );
	}

	Tracker_SetValue( iOwner, SAPPERKEYNAME, 0.0 );

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

	ThrownSapper hSapper;
	hSapper.flRemoveTime = GetGameTime() + INTERMISSION_DURATION;
	hSapper.hSapping = new ArrayList();

	smSapperList.SetArray( szRefString, hSapper, sizeof( ThrownSapper ) );
	return iRef;
}

void RemoveIntermission( int iRef, bool bSilent = false ) {
	PrintToServer("remove intermission");

	static char szRefString[32];
	IntToString( iRef, szRefString, sizeof( szRefString ) );

	int iSapper = EntRefToEntIndex( iRef );
	ThrownSapper hSapper;
	if( smSapperList.GetArray( szRefString, hSapper, sizeof( ThrownSapper ) ) ) {
		for( int i = 0; i < hSapper.hSapping.Length; i++ ) {
			int iObject = EntRefToEntIndex( hSapper.hSapping.Get( i ) );
			if( iObject == -1 )
				continue;

			UnsapBuilding( iRef, iObject );
		}
		delete hSapper.hSapping;
		smSapperList.Remove( szRefString );
	}

	if( iSapper != -1 ) {
		StopSound( iSapper, 0, SOUND_BOOT );

		float vecSapperPos[3];
		GetEntPropVector( iSapper, Prop_Data, "m_vecAbsOrigin", vecSapperPos );

		ShowParticle( EFFECT_CORE_FLASH, 1.0, vecSapperPos );
		ShowParticle( EFFECT_DEBRIS, 1.0, vecSapperPos );
		ShowParticle( EFFECT_FLASH, 1.0, vecSapperPos );
		ShowParticle( EFFECT_FLASHUP, 1.0, vecSapperPos );
		ShowParticle( EFFECT_FLYINGEMBERS, 1.0, vecSapperPos );
		ShowParticle( EFFECT_SMOKE, 1.0, vecSapperPos );

		if( !bSilent) EmitSoundToAll( SOUND_SAPPER_REMOVED, iSapper );

		PrintToServer("remove entity");
		RemoveEntity( iSapper );
	}
}

Action Timer_IntermissionThink( Handle hTimer, int iRef ) {
	int iEntity = EntRefToEntIndex( iRef );
	if( iEntity == -1 ) {
		RemoveIntermission( iRef );
		return Plugin_Stop;
	}

	AttachRings( iEntity );

	float vecSapperPos[3];
	GetEntPropVector( iEntity, Prop_Data, "m_vecAbsOrigin", vecSapperPos );

	int iSapperTeam = GetEntProp( iEntity, Prop_Send, "m_iTeamNum" );

	for( int i = 0; i < hCheckList.Length; i++ ) {
		int iObject = EntRefToEntIndex( hCheckList.Get( i ) );
		if( iObject == -1 ) {
			hCheckList.Erase( i );
			i--;
			continue;
		}

		if( iSapperTeam == GetEntProp( iObject, Prop_Send, "m_iTeamNum" ) )
			continue;

		float vecTargetPos[3];
		GetEntPropVector( iObject, Prop_Data, "m_vecAbsOrigin", vecTargetPos );
		if( GetVectorDistance( vecSapperPos, vecTargetPos ) > INTERMISSION_RADIUS )
			continue;

		SapBuilding( iRef, iObject );
	}

	static char szRefString[32];
	IntToString( iRef, szRefString, sizeof( szRefString ) );
	
	ThrownSapper hSapper;
	smSapperList.GetArray( szRefString, hSapper, sizeof( ThrownSapper ) );

	for( int i = 0; i < hSapper.hSapping.Length; i++ ) {
		int iObjectRef = EntRefToEntIndex( hSapper.hSapping.Get( i ) );

		if( iObjectRef == -1 ) {
			hSapper.hSapping.Erase( i );
			i--;
			continue;
		}

		SetVariantInt( RoundToNearest( INTERMISSION_DPS * INTERMISSION_THINK ) );
		AcceptEntityInput( iObjectRef, "RemoveHealth" );
	}

	if( GetGameTime() > hSapper.flRemoveTime )  {
		PrintToServer("intermission expired");
		RemoveIntermission( iRef );
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

void SapBuilding( int iSapperRef, int iObjectIndex ) {
	static char szRefString[32];

	int iObjectRef = EntIndexToEntRef( iObjectIndex );

	IntToString( iSapperRef, szRefString, sizeof( szRefString ) );

	ThrownSapper hSapper;
	smSapperList.GetArray( szRefString, hSapper, sizeof( hSapper ) );

	if( hSapper.hSapping.FindValue( iObjectRef ) == -1 ) {
		hSapper.hSapping.Push( iObjectRef );
	}

	IntToString( iObjectRef, szRefString, sizeof( szRefString ) );
	ArrayList hSappedBy;

	if( !smSappedBuildings.GetValue( szRefString, hSappedBy ) ) {
		hSappedBy = new ArrayList();
		smSappedBuildings.SetValue( szRefString, hSappedBy );
	}
	
	if( hSappedBy.FindValue( iSapperRef ) == -1 ) {
		hSappedBy.Push( iSapperRef );
	}

	SetVariantInt( 1 ); //throws a tantrum without some kind of parameter
	AcceptEntityInput( iObjectIndex, "Disable" );
}


void UnsapBuilding( int iSapperRef, int iObjectIndex ) {
	static char szRefString[32];

	int iObjectRef = EntIndexToEntRef( iObjectIndex );

	IntToString( iSapperRef, szRefString, sizeof( szRefString ) );

	ThrownSapper hSapper;
	smSapperList.GetArray( szRefString, hSapper, sizeof( hSapper ) );

	int iValue = hSapper.hSapping.FindValue( iObjectRef );
	if( iValue != -1 ) {
		hSapper.hSapping.Erase( iValue );
	}

	IntToString( iObjectRef, szRefString, sizeof( szRefString ) );
	ArrayList hSappedBy;
	if( smSappedBuildings.GetValue( szRefString, hSappedBy ) ) {
		iValue = hSappedBy.FindValue( iSapperRef );
		if( iValue != -1 ) {
			hSappedBy.Erase( iValue );

			if( hSappedBy.Length == 0 ) {
				SetVariantInt( 1 ); //throws a tantrum without some kind of parameter
				AcceptEntityInput( iObjectIndex, "Enable" );
				smSappedBuildings.Remove( szRefString );

				delete hSappedBy;
			}
		}
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
		RemoveIntermission( EntIndexToEntRef( iEntity ) );

	return MRES_Supercede;
}

public void OnTakeDamageBuilding( int iTarget, Address aDamageInfo ) {
	if( GetEntProp( iTarget, Prop_Send, "m_iObjectType" ) != 2 ) //sentry gun
		return;

	TFDamageInfo tfInfo = TFDamageInfo( aDamageInfo );
	
	static char szRefString[32];
	IntToString( EntIndexToEntRef( iTarget ), szRefString, sizeof( szRefString ) );

	ArrayList hSappers;
	if( !smSappedBuildings.GetValue( szRefString, hSappers ) )
		return;

	for( int i = 0; i < hSappers.Length; i++ ) {
		int iSapper = EntRefToEntIndex( hSappers.Get( i ) );
		if( iSapper == -1 )
			continue;

		int iSapperOwner = GetEntPropEnt( iSapper, Prop_Send, "m_hOwnerEntity" );
		if( tfInfo.iAttacker == iSapperOwner ) {
			tfInfo.flDamage *= 0.33;
			return;
		}
	}
}
static int iColors[6][4] = {
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
	MakeRings( vecSapperPos, iColors[ GetEntProp( iEntity, Prop_Send, "m_iTeamNum" ) ] );
}

void MakeRings( float vecSapperPos[3], int iColor[4] ) {
	for(int i = 0; i < 4; i++) {
		TE_SetupBeamRingPoint( vecSapperPos, 0.1, INTERMISSION_RADIUS, g_hEffectSprite, g_hEffectSprite, 1, 1, 0.6, 3.0, 10.0, iColor, 15, 0);
		TE_SendToAll();
	}
}

stock int AttachParticle( int iEntity, char szParticleName[64], float flTime, float vecAddPos[3] = NULL_VECTOR, float vecAddAngle[3] = NULL_VECTOR )
{
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

stock void ShowParticle(char szParticleName[64], float flTime, float vecPos[3], float vecAng[3]=NULL_VECTOR)
{
	int iParticle = CreateEntityByName("info_particle_system");

	TeleportEntity( iParticle, vecPos, vecAng, NULL_VECTOR );

	DispatchKeyValue( iParticle, "effect_name", szParticleName );
	DispatchSpawn( iParticle );
	ActivateEntity( iParticle );
	AcceptEntityInput( iParticle, "start" );
	CreateTimer( flTime, RemoveParticle, iParticle );
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
	SDKCall( hGiveEcon, iPlayer, "TF_WEAPON_BUILDER_SPY_TEST", 4, 0 ); //todo: find a way to make this not hardcoded
	int iSapper = GetEntityInSlot( iPlayer, 4 );

	//i can't fathom why it's like this but you can't reequip the sapper unless i do whatever the fuck this is
	SDKCall( hSetSubType, iSapper, 3 );
	SDKCall( hSetObjectMode, iSapper, 0 );
}
void TakeSpySapper( int iPlayer ) {
	int iWeapon = GetEntityInSlot( iPlayer, 4 );
	if( iWeapon > 0 ) {
		RemoveEntity( iWeapon );
		SDKCall( hSwapToBest, iPlayer, -1 );
	}
}

public void Tracker_OnRecharge( int iPlayer, const char szTrackerName[32], float flNewValue ) {
	if( !StrEqual( szTrackerName, SAPPERKEYNAME ) )
		return;

	if( !fHasIntermission.Get( iPlayer ) || !IsPlayerAlive( iPlayer ) )
		return;

	GiveSpySapper( iPlayer );
}