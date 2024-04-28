#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <kocwtools>
#include <hudframework>
#include <give_econ>
#include <condhandler>
#include <custom_entprops>

public Plugin myinfo =
{
	name = "Condition Handler",
	author = "Noclue",
	description = "Core plugin for custom conditions.",
	version = "2.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

//TODO: Shield parenting could be better

/*
	PROPERTIES
*/

bool		g_bHasCond[MAXPLAYERS+1][TFCC_LAST];
EffectProps	g_ePlayerConds[MAXPLAYERS+1][TFCC_LAST];

const float	g_flToxinFrequency	= 0.5;	//tick interval in seconds
const float	g_flToxinDamage		= 2.0;	//damage per tick
const float	g_flToxinHealingMult	= 0.25;	//multiplier for healing while under toxin
static char	g_szToxinLoopSound[]	= "items/powerup_pickup_plague_infected_loop.wav";

const int	g_iAngShieldHealth	= 80;	//angel shield health
const float	g_iAngShieldDuration	= 8.0;	//angel shield duration
const float	g_iAngInvulnDuration	= 0.25;	//invulnerability period after a shield breaks
int 		g_iAngelShields[MAXPLAYERS+1][2]; //0 contains the index of the shield, 1 contains the material manager used for the damage effect


static char	g_szHydroPumpHealParticles[][] = {
	"mediflame_heal_red",
	"mediflame_heal_blue",
	"mediflame_heal_green",
	"mediflame_heal_yellow"
};
int		g_iHydroPumpEmitters[MAXPLAYERS+1] = { INVALID_ENT_REFERENCE, ... };

const float	g_flHydroUberHealRate	= 24.0;
const float	g_flHydroUberDuration	= 10.0;
const float	g_flHydroUberRange	= 500.0;
const float	g_flHydroUberFrequency	= 0.2;
static char	g_szHydroUberParticles[][] = {
	"mediflame_uber_red",
	"mediflame_uber_blue",
	"mediflame_uber_green",
	"mediflame_uber_yellow"
};
static char	g_szHydroUberParticlesFP[][] = {
	"mediflame_uber_red_fp",
	"mediflame_uber_blue_fp",
	"mediflame_uber_green_fp",
	"mediflame_uber_yellow_fp"
};
int		g_iHydroPumpUberEmitters[MAXPLAYERS+1][2];

#define DEBUG

#define SetCondNextTick(%1,%2,%3) g_ePlayerConds[%1][%2].flNextTick = %3

#define GetCondTime(%1,%2) g_ePlayerConds[%1][%2].flExpireTime
#define GetCondSrcPlr(%1,%2) EntRefToEntIndex( g_ePlayerConds[%1][%2].iEffectSource )
#define GetCondSrcWpn(%1,%2) EntRefToEntIndex( g_ePlayerConds[%1][%2].iEffectWeapon )

enum struct EffectProps {
	any	condLevel;	//condition strength

	float	flExpireTime;	//time when effect expires
	float	flNextTick;	//time when effect should tick next

	int	iEffectSource; 	//player that caused effect
	int	iEffectWeapon; 	//weapon that caused effect
}

DynamicHook g_dhTakeHealth;
DynamicDetour g_dtHealConds;
DynamicDetour g_dtApplyOnHit;
DynamicDetour g_dtApplyPushForce;
DynamicDetour g_dtAirblastPlayer;

DynamicHook g_dhOnKill;

Handle g_sdkGetMaxHealth;
Handle g_sdkGetBuffedMaxHealth;

bool g_bLateLoad;
public APLRes AskPluginLoad2( Handle myself, bool bLate, char[] error, int err_max ) {
	CreateNative( "AddCustomCond", Native_AddCond );
	CreateNative( "RemoveCustomCond", Native_RemoveCond );

	CreateNative( "HasCustomCond", Native_HasCond );

	CreateNative( "GetCustomCondLevel", Native_GetCondLevel );
	CreateNative( "SetCustomCondLevel", Native_SetCondLevel );

	CreateNative( "GetCustomCondDuration", Native_GetCondDuration );
	CreateNative( "SetCustomCondDuration", Native_SetCondDuration );

	CreateNative( "GetCustomCondSourcePlayer", Native_GetCondSourcePlayer );
	CreateNative( "SetCustomCondSourcePlayer", Native_SetCondSourcePlayer );

	CreateNative( "GetCustomCondSourceWeapon", Native_GetCondSourceWeapon );
	CreateNative( "SetCustomCondSourceWeapon", Native_SetCondSourceWeapon );

	g_bLateLoad = bLate;

	return APLRes_Success;
}

//can't use onplayerruncmd for this
public void OnGameFrame() {
	for( int i = 1; i <= MaxClients; i++ ) {
		if( !IsClientInGame( i ) || !IsPlayerAlive( i ) )
			continue;

		ManageAngelShield( i );

		if( HasCond( i, TFCC_TOXIN ) )
			TickToxin( i );

		if( HasCond( i, TFCC_QUICKUBER ) )
			TickQuickUber( i );

		if( HasCond( i, TFCC_HYDROPUMPHEAL ) )
			TickHydroPumpHeal( i );
	}
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	g_dhTakeHealth = DynamicHookFromConfSafe( hGameConf, "CTFPlayer::TakeHealth" );
	g_dtHealConds = DynamicDetourFromConfSafe( hGameConf, "CTFPlayerShared::HealNegativeConds" );
	g_dtHealConds.Enable( Hook_Post, Detour_HealNegativeConds );

	g_dtApplyOnHit = DynamicDetourFromConfSafe( hGameConf, "CTFWeaponBase::ApplyOnHitAttributes" );
	g_dtApplyOnHit.Enable( Hook_Post, Detour_ApplyOnHitAttributes );

	g_dhOnKill = DynamicHookFromConfSafe( hGameConf, "CTFPlayer::Event_KilledOther" );

	g_dtApplyPushForce = DynamicDetourFromConfSafe( hGameConf, "CTFPlayer::ApplyPushFromDamage" );
	g_dtApplyPushForce.Enable( Hook_Pre, Detour_ApplyPushFromDamage );
	g_dtAirblastPlayer = DynamicDetourFromConfSafe( hGameConf, "CTFPlayerShared::AirblastPlayer" );
	g_dtAirblastPlayer.Enable( Hook_Pre, Detour_AirblastPlayer );

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFPlayer::GetMaxHealth" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkGetMaxHealth = EndPrepSDKCallSafe( "CTFPlayer::GetMaxHealth" );

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayerShared::GetBuffedMaxHealth" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	g_sdkGetBuffedMaxHealth = EndPrepSDKCallSafe( "CTFPlayerShared::GetBuffedMaxHealth" );

	for( int i = 0; i < MAXPLAYERS+1; i++ ) {
		g_iAngelShields[i][0] = INVALID_ENT_REFERENCE;
		g_iAngelShields[i][1] = INVALID_ENT_REFERENCE;

		g_iHydroPumpUberEmitters[i][0] = INVALID_ENT_REFERENCE;
		g_iHydroPumpUberEmitters[i][1] = INVALID_ENT_REFERENCE;

		for( int j = 0; j < TFCC_LAST; j++ ) {
			SetCondLevel( i, j, 0 );
			SetCondDuration( i, j, 0.0, false );
			SetCondNextTick( i, j, 0.0 );
			g_ePlayerConds[i][j].iEffectSource = INVALID_ENT_REFERENCE;
			g_ePlayerConds[i][j].iEffectWeapon = INVALID_ENT_REFERENCE;
		}
	}

	HookEvent( "player_death", Event_PlayerDeath, EventHookMode_Post );

	if( !g_bLateLoad )
		return;

	//lateload
	for( int i = 1; i <= MaxClients; i++ ) {
		if( !IsValidEdict( i ) )
			continue;
		
		DoPlayerHooks( i );
	}

	delete hGameConf;

#if defined DEBUG
	RegConsoleCmd( "sm_cond_test", Command_Test );
#endif
}

public void OnClientConnected( int iClient ) {
	ClearConds( iClient );

	if( IsValidEdict( iClient ) )
		RequestFrame( DoPlayerHooks, iClient );
}
void DoPlayerHooks( int iPlayer ) {
	//g_dhTakeHealth.HookEntity( Hook_Pre, iPlayer, Hook_TakeHealth );
	//todo: migrate to a kill event
	g_dhOnKill.HookEntity( Hook_Post, iPlayer, Hook_OnPlayerKill );
}

public void OnClientDisconnect( int iClient ) {
	ClearConds( iClient );
}
public Action Event_PlayerDeath( Event hEvent, const char[] sName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	ClearConds( iPlayer );

	return Plugin_Continue;
}

MRESReturn Hook_OnPlayerKill( int iThis, DHookParam hParams ) {
	//int iVictim = hParams.Get( 1 );
	TFDamageInfo tfInfo = TFDamageInfo( hParams.GetAddress( 2 ) );

	int iAttacker = tfInfo.iAttacker;
	int iWeapon = tfInfo.iWeapon;

	if( !IsValidPlayer( iAttacker ) || !IsValidEdict( iWeapon ) )
		return MRES_Ignored;

	CheckOnKillCond( iAttacker, iWeapon );

	return MRES_Handled;
}

public void OnMapStart() {
	PrecacheSound( g_szToxinLoopSound );
	PrecacheSound( "weapons/buffed_off.wav" );
	PrecacheModel( "models/effects/resist_shield/resist_shield.mdl" );
}

#if defined DEBUG
Action Command_Test( int iClient, int iArgs ) {
	if(iArgs < 1) return Plugin_Handled;

	int iCondIndex = GetCmdArgInt( 1 );
	for( int i = 1; i <= MaxClients; i++ ) {
		if( IsClientInGame( i ) ) {
			AddCond( i, iCondIndex );
			SetCondDuration( i, iCondIndex, 10.0, false );
			SetCondSourcePlayer( i, iCondIndex, iClient );
		}
			
	}
	
	return Plugin_Handled;
}
#endif

bool IsNegativeCond( int iCond ) {
	return iCond == TFCC_TOXIN;
}

/*
	Copious amounts of boilerplate
*/

//native bool TFCC_AddCond( int player, int effect )
public any Native_AddCond( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);
	int iSource = GetNativeCell(3);
	int iWeapon = GetNativeCell(4);
	return AddCond( iPlayer, iEffect, iSource, iWeapon );
}
bool AddCond( int iPlayer, int iCond, int iSource = -1, int iWeapon = -1 ) {
	if( iCond < 0 || iCond >= TFCC_LAST || !IsValidPlayer( iPlayer ) )
		return false;

	if( HasCond( iPlayer, iCond ) ) 
		return false;
	if( IsNegativeCond( iCond ) && ( HasCond( iPlayer, TFCC_ANGELSHIELD ) || HasCond( iPlayer, TFCC_ANGELINVULN ) ) )
		return false;

	SetCondSourcePlayer( iPlayer, iCond, iSource );
	SetCondSourceWeapon( iPlayer, iCond, iWeapon );

	bool bGaveCond = false;
	switch( iCond ) {
	case TFCC_TOXIN: {
		AddToxin( iPlayer );
		bGaveCond = true;
	}
	case TFCC_HYDROPUMPHEAL: {
		bGaveCond = AddHydroPumpHeal( iPlayer, iSource );
	}
	case TFCC_HYDROUBER: {
		bGaveCond = AddHydroUber( iPlayer );
	}
	case TFCC_ANGELSHIELD: {
		AddAngelShield( iPlayer );
		bGaveCond = true;
	}
	case TFCC_ANGELINVULN: {
		AddAngelInvuln( iPlayer );
		bGaveCond = true;
	}
	case TFCC_QUICKUBER: {
		bGaveCond = AddQuickUber( iPlayer );
	}
	case TFCC_TOXINUBER: {
		bGaveCond = AddToxinUber( iPlayer );
	}
	}

	if( bGaveCond ) {
		g_bHasCond[iPlayer][iCond] = true;
		g_ePlayerConds[iPlayer][iCond].flExpireTime = GetGameTime();
	}

	return bGaveCond;
}

public any Native_HasCond( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);
	return HasCond( iPlayer, iEffect );
}
bool HasCond( int iPlayer, int iCond ) {
	return g_bHasCond[iPlayer][iCond];
}

public any Native_RemoveCond( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);

	return RemoveCond( iPlayer, iEffect );
}
bool RemoveCond( int iPlayer, int iCond ) {
	if( iCond < 0 || iCond >= TFCC_LAST )
		return false;

	if( !HasCond( iPlayer, iCond ) )
		return false;

	switch(iCond) {
	case TFCC_TOXIN: {
		RemoveToxin( iPlayer );
	}
	case TFCC_HYDROPUMPHEAL: {
		RemoveHydroPumpHeal( iPlayer );
	}
	case TFCC_HYDROUBER: {
		RemoveHydroUber( iPlayer );
	}
	case TFCC_ANGELSHIELD: {
		RemoveAngelShield( iPlayer );
	}
	case TFCC_QUICKUBER: {
		RemoveQuickUber( iPlayer );
	}
	case TFCC_TOXINUBER: {
		RemoveToxinUber( iPlayer );
	}
	}

	g_ePlayerConds[iPlayer][iCond].condLevel =		0;
	g_ePlayerConds[iPlayer][iCond].flExpireTime =		0.0;
	g_ePlayerConds[iPlayer][iCond].flNextTick	=	0.0;
	g_ePlayerConds[iPlayer][iCond].iEffectSource =	INVALID_ENT_REFERENCE;
	g_ePlayerConds[iPlayer][iCond].iEffectWeapon =	INVALID_ENT_REFERENCE;

	g_bHasCond[iPlayer][iCond] = false;

	return true;
}

void ClearConds( int iPlayer ) {
	for( int i = 0; i < TFCC_LAST; i++ ) {
		RemoveCond( iPlayer, i );
	}
}

//cond level
public any Native_GetCondLevel( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);

	return GetCondLevel( iPlayer, iEffect );
}
any GetCondLevel( int iPlayer, int iCond ) {
	return g_ePlayerConds[iPlayer][iCond].condLevel;
}
public any Native_SetCondLevel( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);
	any level =  GetNativeCell(3);

	SetCondLevel( iPlayer, iEffect, level );
	return 0;
}
void SetCondLevel( int iPlayer, int iCond, any newLevel ) {
	g_ePlayerConds[iPlayer][iCond].condLevel = newLevel;
}

//cond duration
public any Native_GetCondDuration( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);

	return GetCondDuration( iPlayer, iEffect );
}
float GetCondDuration( int iPlayer, int iCond ) {
	return g_ePlayerConds[iPlayer][iCond].flExpireTime - GetGameTime();
}
public any Native_SetCondDuration( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);
	float iDuration = GetNativeCell(3);
	bool bAdd = GetNativeCell(4);

	SetCondDuration( iPlayer, iEffect, iDuration, bAdd );
	return 0;
}
void SetCondDuration( int iPlayer, int iCond, float flDuration, bool bAdd = false ) {
	if( iCond == TFCC_TOXIN && bAdd ) {
		flDuration = MinFloat( g_ePlayerConds[iPlayer][iCond].flExpireTime + flDuration, GetGameTime() + 10.0 );
		g_ePlayerConds[iPlayer][iCond].flExpireTime = flDuration;
		return;
	}

	g_ePlayerConds[iPlayer][iCond].flExpireTime = bAdd ? g_ePlayerConds[iPlayer][iCond].flExpireTime + flDuration : GetGameTime() + flDuration;
}

//cond player source
public any Native_GetCondSourcePlayer( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);

	return GetCondSourcePlayer( iPlayer, iEffect );
}
int GetCondSourcePlayer( int iPlayer, int iCond ) {
	return EntRefToEntIndex( g_ePlayerConds[iPlayer][iCond].iEffectSource );
}
public any Native_SetCondSourcePlayer( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);
	int iSource = GetNativeCell(3);

	SetCondSourcePlayer( iPlayer, iEffect, iSource );
	return 0;
}
void SetCondSourcePlayer( int iPlayer, int iCond, int iSourceIndex ) {
	if( iSourceIndex == -1 )
		return;

	g_ePlayerConds[iPlayer][iCond].iEffectSource = EntIndexToEntRef( iSourceIndex );
}

//cond weapon source
public any Native_GetCondSourceWeapon( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);

	return GetCondSourceWeapon( iPlayer, iEffect );
}
int GetCondSourceWeapon( int iPlayer, int iCond ) {
	return EntRefToEntIndex( g_ePlayerConds[iPlayer][iCond].iEffectWeapon );
}
public any Native_SetCondSourceWeapon( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);
	int iWeapon = GetNativeCell(3);

	SetCondSourceWeapon( iPlayer, iEffect, iWeapon );
	return 0;
}
void SetCondSourceWeapon( int iPlayer, int iCond, int iWeaponIndex ) {
	if( iWeaponIndex == -1 )
		return;

	g_ePlayerConds[iPlayer][iCond].iEffectWeapon = EntIndexToEntRef( iWeaponIndex );
}

/*

*/

MRESReturn Detour_HealNegativeConds( Address aThis, DHookReturn hReturn ) {
	bool bRemovedCond = hReturn.Value;
	int iPlayer = GetPlayerFromShared( aThis );
	if( HasCond( iPlayer, TFCC_TOXIN ) ) {
		RemoveCond( iPlayer, TFCC_TOXIN );
		bRemovedCond = true;
	}
		
	hReturn.Value = bRemovedCond;
	return MRES_ChangedOverride;
}

MRESReturn Detour_ApplyOnHitAttributes( int iWeapon, DHookParam hParams ) {
	if( hParams.IsNull( 1 ) )
		return MRES_Ignored;

	int iAttacker = hParams.Get( 1 );
	int iVictim = hParams.Get( 2 );

	TFDamageInfo tfInfo =  TFDamageInfo( hParams.GetAddress( 3 ) );

	CheckOnHitCustomCond( iVictim, iWeapon, tfInfo );

	return MRES_Handled;
}

public void OnTakeDamageTF( int iTarget, Address aTakeDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aTakeDamageInfo );

	//CheckMultDamageAttrib( iTarget, tfInfo );
	CheckMultDamageAttribCustom( iTarget, tfInfo );

	if( HasCond( iTarget, TFCC_ANGELSHIELD ) )
		AngelShieldTakeDamage( iTarget, tfInfo );
}
public void OnTakeDamageAlivePostTF( int iTarget, Address aTakeDamageInfo ) {
	AngelShieldTakeDamagePost( iTarget );
}

void CheckMultDamageAttribCustom( int iTarget, TFDamageInfo tfInfo ) {
	int iAttacker = tfInfo.iAttacker;

	if( !HasEntProp( iTarget, Prop_Send, "m_hActiveWeapon" ) )
		return;

	int iWeapon = GetEntPropEnt( iTarget, Prop_Send, "m_hActiveWeapon" );
	if( iWeapon == -1 )
		return;

	static char szAttribute[64];
	if( AttribHookString( szAttribute, sizeof( szAttribute ), iWeapon, "custom_resist_customcond" ) == 0 ) {
		return;
	}
		
	static char szExplode[2][64];
	ExplodeString( szAttribute, " ", szExplode, 2, sizeof( szAttribute ) );

	int iCond = StringToInt( szExplode[0] );
	float flMult = StringToFloat( szExplode[1] );

	if( HasCond( iAttacker, iCond ) ) {
		tfInfo.flDamage *= flMult;
		EmitGameSoundToAll( "Player.ResistanceMedium", iTarget );
	}
}

/*void CheckMultDamageAttrib( int iTarget, TFDamageInfo tfInfo ) {
	int iAttacker = tfInfo.iAttacker;
	int iWeapon = tfInfo.iWeapon;

	static char szAttribute[64];
	if( AttribHookString( szAttribute, sizeof( szAttribute ), iWeapon, "custom_resist_cond" ) == 0 )
		return;

	static char szExplode[2][64];
	ExplodeString( szAttribute, " ", szExplode, 2, sizeof( szAttribute ) );

	int iCond = StringToInt( szExplode[0] );
	float flMult = StringToFloat( szExplode[1] );

	if( TF2_IsPlayerInCondition( iAttacker, view_as<TFCond>( iCond ) ) ) {
		tfInfo.flDamage *= flMult;
		EmitGameSoundToAll( "Player.ResistanceMedium", iTarget );
	}	
}*/

void CheckOnHitCustomCond( int iVictim, int iWeapon, TFDamageInfo tfInfo ) {
	if( !IsValidPlayer( iVictim ) )
		return;

	static char szAttribute[64];
	if( AttribHookString( szAttribute, sizeof( szAttribute ), iWeapon, "custom_inflictcustom_onhit" ) == 0 )
		return;

	static char szExplode[2][64];
	ExplodeString( szAttribute, " ", szExplode, 2, sizeof( szAttribute ) );

	int iCond = StringToInt( szExplode[0] );
	float flDuration = StringToFloat( szExplode[1] );

	//don't apply more toxin from toxin dot
	if( iCond == TFCC_TOXIN && ( tfInfo.iFlags & DMG_PHYSGUN || tfInfo.iFlags & DMG_BURN ) )
		return;

	AddCond( iVictim, iCond );
	SetCondSourcePlayer( iVictim, iCond, tfInfo.iAttacker );
	SetCondSourceWeapon( iVictim, iCond, iWeapon );
	SetCondDuration( iVictim, iCond, flDuration, true );
}

void CheckOnKillCond( int iAttacker, int iWeapon ) {
	static char szAttribute[64];
	if( AttribHookString( szAttribute, sizeof( szAttribute ), iWeapon, "custom_addcond_onkill" ) == 0 )
		return;

	static char szExplode[2][64];
	ExplodeString( szAttribute, " ", szExplode, 2, sizeof( szAttribute ) );

	int iCond = StringToInt( szExplode[0] );
	float flDuration = StringToFloat( szExplode[1] );

	TF2_AddCondition( iAttacker, view_as<TFCond>( iCond ), flDuration );
}


/*
	TOXIN
*/

static char g_szToxinParticle[] = "toxin_particles";
int g_iToxinEmitters[MAXPLAYERS+1] = { -1, ... };
float g_flHealthBuffer[MAXPLAYERS+1] = { 0.0, ... }; //buffer for health cut off by rounding

bool AddToxin( int iPlayer ) {
	EmitSoundToAll( g_szToxinLoopSound, iPlayer );
	g_flHealthBuffer[iPlayer] = 0.0;

	SetCondDuration( iPlayer, TFCC_TOXIN, 0.0, false );

	RemoveToxinEmitter( iPlayer );

	//int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) - 2;
	int iEmitter = CreateEntityByName( "info_particle_system" );
	DispatchKeyValue( iEmitter, "effect_name", g_szToxinParticle );

	float vecPos[3]; GetClientAbsOrigin( iPlayer, vecPos );
	TeleportEntity( iEmitter, vecPos );

	ParentModel( iEmitter, iPlayer );

	DispatchSpawn( iEmitter );
	ActivateEntity( iEmitter );
	AcceptEntityInput( iEmitter, "Start" );

	g_iToxinEmitters[iPlayer] = EntIndexToEntRef( iEmitter );

	GiveEconItem( iPlayer, 11000 );
	
	return true;
}

void RemoveToxinEmitter( int iPlayer ) {
	int iEmitter = EntRefToEntIndex( g_iToxinEmitters[iPlayer] );
	if( iEmitter != -1 ) {
		RemoveEntity( iEmitter );
	}
	g_iToxinEmitters[iPlayer] = -1;
	RemoveEconItem( iPlayer, 11000 );
}

void TickToxin( int iPlayer ) {
	if( g_ePlayerConds[iPlayer][TFCC_TOXIN].flExpireTime <= GetGameTime() ) {
		RemoveCond( iPlayer, TFCC_TOXIN );
		return;
	}

	if( GetGameTime() < g_ePlayerConds[iPlayer][TFCC_TOXIN].flNextTick )
		return;

	int iDamagePlayer = GetCondSourcePlayer( iPlayer, TFCC_TOXIN );
	int iDamageWeapon = GetCondSourceWeapon( iPlayer, TFCC_TOXIN );

	if( iDamagePlayer == -1 )
		iDamagePlayer = 0;
	if( iDamageWeapon == -1 )
		iDamageWeapon = 0;
	
	//todo: prevent this from applying more toxin
	SDKHooks_TakeDamage( iPlayer, iDamagePlayer, iDamagePlayer, g_flToxinDamage, DMG_GENERIC | DMG_PHYSGUN, iDamageWeapon, NULL_VECTOR, NULL_VECTOR, false );
	g_ePlayerConds[iPlayer][TFCC_TOXIN].flNextTick = GetGameTime() + g_flToxinFrequency;
}

void RemoveToxin( int iPlayer ) {
	StopSound( iPlayer, 0, g_szToxinLoopSound );
	RemoveToxinEmitter( iPlayer );

	RemoveEconItem( iPlayer, 11000 );
}

MRESReturn Detour_ApplyPushFromDamage( int iVictim, DHookParam hParams ) {
	if( !HasCond( iVictim, TFCC_QUICKUBER ) )
		return MRES_Ignored;

	TFDamageInfo tfInfo = TFDamageInfo( hParams.GetAddress( 1 ) );
	if( tfInfo.iAttacker == iVictim )
		return MRES_Ignored;

	return MRES_Supercede;
}

MRESReturn Detour_AirblastPlayer( Address aVictimShared, DHookParam hParams ) {
	int iVictim = GetPlayerFromShared( aVictimShared );
	if( !HasCond( iVictim, TFCC_QUICKUBER ) )
		return MRES_Ignored;

	return MRES_Supercede;
}

//name is misleading, TakeHealth is used to RESTORE health because valve
MRESReturn Hook_TakeHealth( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	if( !IsValidPlayer( iThis ) )
		return MRES_Ignored;

	if( !HasCond( iThis, TFCC_TOXIN ) )
		return MRES_Ignored;

	float	flAddHealth = hParams.Get( 1 );
	//int	iDamageFlags = hParams.Get( 1 ); //don't need these for anything yet

	flAddHealth *= g_flToxinHealingMult;

	//need to buffer values below 1 since otherwise they get rounded out
	flAddHealth += g_flHealthBuffer[ iThis ];
	int iRoundedHealth = RoundToFloor( flAddHealth );
	g_flHealthBuffer[ iThis ] = flAddHealth - iRoundedHealth;

	hParams.Set( 1, float( iRoundedHealth ) );

	return MRES_ChangedHandled;
}

/*
	TOXIN UBER
*/

#define TOXINUBER_PULSERATE 0.5
static char g_szToxinUberParticles[][] = {
	"biowastepump_uber_red",
	"biowastepump_uber_blue",
	"biowastepump_uber_green",
	"biowastepump_uber_yellow"
};

int g_iToxinUberEmitters[MAXPLAYERS+1] = { -1, ... };

bool AddToxinUber( int iPlayer ) {
	RemoveToxinUberEmitter( iPlayer );
	CreateTimer( TOXINUBER_PULSERATE, TickToxinUber, iPlayer, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT );

	int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) - 2;
	int iEmitter = CreateEntityByName( "info_particle_system" );
	DispatchKeyValue( iEmitter, "effect_name", g_szToxinUberParticles[ iTeam ] );

	float vecPos[3]; GetClientAbsOrigin( iPlayer, vecPos );
	TeleportEntity( iEmitter, vecPos );

	ParentModel( iEmitter, iPlayer );

	DispatchSpawn( iEmitter );
	ActivateEntity( iEmitter );
	AcceptEntityInput( iEmitter, "Start" );

	g_iToxinUberEmitters[iPlayer] = EntIndexToEntRef( iEmitter );

	return true;
}
Action TickToxinUber( Handle hTimer, int iPlayer ) {
	if( !( IsClientInGame( iPlayer ) && IsPlayerAlive( iPlayer ) ) ) {
		RemoveCond( iPlayer, TFCC_TOXINUBER );
		return Plugin_Stop;	
	}

	if( g_ePlayerConds[ iPlayer ][ TFCC_TOXINUBER ].flExpireTime < GetGameTime() ) {
		RemoveCond( iPlayer, TFCC_TOXINUBER );
		return Plugin_Stop;
	}

	float vecSource[3]; GetClientAbsOrigin( iPlayer, vecSource );

	int iTarget = -1;
	int iSource = GetCondSourcePlayer( iPlayer, TFCC_TOXINUBER );
	while ( ( iTarget = FindEntityInSphere( iTarget, vecSource, 300.0 ) ) != -1 ) {
		if( !IsValidPlayer( iTarget ) )
			continue;

		if( GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) == GetEntProp( iTarget, Prop_Send, "m_iTeamNum" ) ) {
			int iHealed = HealPlayer( iTarget, 10.0, iSource );

			Event eHealEvent = CreateEvent( "player_healed" );
			eHealEvent.SetInt( "patient", GetClientUserId( iTarget ) );
			eHealEvent.SetInt( "healer", GetClientUserId( iSource ) );
			eHealEvent.SetInt( "amount", iHealed );
			eHealEvent.Fire();
		}
		else {
			AddCond( iTarget, TFCC_TOXIN );
			SetCondDuration( iTarget, TFCC_TOXIN, 2.0, true );

			int iSourcePlayer = GetCondSourcePlayer( iPlayer, TFCC_TOXINUBER );
			if( iSourcePlayer != -1 )
				SetCondSourcePlayer( iTarget, TFCC_TOXIN, iSourcePlayer );

			int iSourceWeapon = GetCondSourceWeapon( iPlayer, TFCC_TOXINUBER );
			if( iSourceWeapon != -1 )
				SetCondSourceWeapon( iTarget, TFCC_TOXIN, iSourceWeapon );
		}
	}

	return Plugin_Continue;
}

void RemoveToxinUber( int iPlayer ) {
	RemoveToxinUberEmitter( iPlayer );
}

void RemoveToxinUberEmitter( int iPlayer ) {
	int iEmitter = EntRefToEntIndex( g_iToxinUberEmitters[ iPlayer ] );
	if( iEmitter != -1 )
		RemoveEntity( iEmitter );

	g_iToxinUberEmitters[ iPlayer ] = -1;
}

/*
	ANGEL SHIELD
*/

Handle g_hShieldExpireTimers[ MAXPLAYERS+1 ] = { INVALID_HANDLE, ... };

float g_flLastDamagedShield[ MAXPLAYERS+1 ];

static char g_szShieldMats[][] = {
	"models/effects/resist_shield/resist_shield",
	"models/effects/resist_shield/resist_shield_blue",
	"models/effects/resist_shield/resist_shield_green",
	"models/effects/resist_shield/resist_shield_yellow"
};

static char g_szShieldOverlays[][] = {
	"effects/invuln_overlay_red",
	"effects/invuln_overlay_blue",
	"effects/invuln_overlay_green",
	"effects/invuln_overlay_yellow"
};

int GetAngelShield( int iPlayer, int iType ) {
	return EntRefToEntIndex( g_iAngelShields[iPlayer][iType] );
}

bool AddAngelShield( int iPlayer ) {
	if( g_hShieldExpireTimers[ iPlayer ] != INVALID_HANDLE ) {
		KillTimer( g_hShieldExpireTimers[ iPlayer ] );
	}
	g_hShieldExpireTimers[ iPlayer ] = CreateTimer( g_iAngShieldDuration, ExpireAngelShield, iPlayer, TIMER_FLAG_NO_MAPCHANGE );
	g_ePlayerConds[iPlayer][TFCC_ANGELSHIELD].condLevel = g_iAngShieldHealth;

	g_flLastDamagedShield[iPlayer] = GetGameTime();

	if( IsValidEntity( GetAngelShield( iPlayer, 0 ) ) ) {
		RemoveEntity( GetAngelShield( iPlayer, 0 ) );
	}
	if( IsValidEntity( GetAngelShield( iPlayer, 1 ) ) ) {
		RemoveEntity( GetAngelShield( iPlayer, 1 ) );
	}

	int iNewShield = CreateEntityByName( "prop_dynamic" );
	SetEntityModel( iNewShield, "models/effects/resist_shield/resist_shield.mdl" );
	
	DispatchKeyValue( iNewShield, "disableshadows", "1" );

	int iTeamNum = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) - 2;
	SetEntProp( iNewShield, Prop_Send, "m_nSkin", iTeamNum );

	DispatchSpawn( iNewShield );
	ActivateEntity( iNewShield );
	g_iAngelShields[iPlayer][0] = EntIndexToEntRef( iNewShield );

	SetEntPropEnt( iNewShield, Prop_Send, "m_hOwnerEntity", iPlayer );
	SetEntityCollisionGroup( iNewShield, 0 );

	SDKHook( iNewShield, SDKHook_SetTransmit, Hook_TransmitIfNotOwner );
	SetEdictFlags( iNewShield, 0 );

	int iNewManager = CreateEntityByName( "material_modify_control" );

	ParentModel( iNewManager, iNewShield );

	DispatchKeyValue( iNewManager, "materialName", g_szShieldMats[iTeamNum] );
	DispatchKeyValue( iNewManager, "materialVar", "$shield_falloff" );

	DispatchSpawn( iNewManager );
	g_iAngelShields[iPlayer][1] = EntIndexToEntRef( iNewManager );

	//todo: replace with call to healnegativeconds
	TF2_RemoveCondition( iPlayer, TFCond_Bleeding );
	TF2_RemoveCondition( iPlayer, TFCond_OnFire );
	TF2_RemoveCondition( iPlayer, TFCond_KingRune ); //tranq
	RemoveCond( iPlayer, TFCC_TOXIN );

	static char szCommand[64];
	Format( szCommand, sizeof(szCommand), "r_screenoverlay %s", g_szShieldOverlays[iTeamNum] );

	if( IsClientInGame( iPlayer ) ) {
		ClientCommand( iPlayer, szCommand ); 
	}

	return true;
}

Action ExpireAngelShield( Handle hTimer, int iPlayer ) {
	g_hShieldExpireTimers[ iPlayer ] = INVALID_HANDLE;
	RemoveCond( iPlayer, TFCC_ANGELSHIELD );

	return Plugin_Stop;
}
void RemoveAngelShield( int iPlayer ) {
	/*bool bBroken = ePlayerConds[iPlayer][TFCC_ANGELSHIELD].iLevel <= 0;

	if( bBroken ) {
		AddCond( iPlayer, TFCC_ANGELINVULN );
		CreateTimer( ANGINVULN_DURATION, RemoveAngelShield2, iPlayer, TIMER_FLAG_NO_MAPCHANGE );
		return;
	}*/

	RemoveAngelShield2( iPlayer );

	if( IsClientInGame( iPlayer ) ) {
		ClientCommand( iPlayer, "r_screenoverlay off");
		EmitSoundToAll( "weapons/buffed_off.wav", iPlayer, SNDCHAN_AUTO, 100 );
	}

	if( IsValidEntity( GetAngelShield( iPlayer, 0 ) ) ) {
		RemoveEntity( GetAngelShield( iPlayer, 0 ) );
	}
	if( IsValidEntity( GetAngelShield( iPlayer, 1 ) ) ) {
		RemoveEntity( GetAngelShield( iPlayer, 1 ) );
	}

	if( g_hShieldExpireTimers[ iPlayer ] != INVALID_HANDLE ) {
		KillTimer( g_hShieldExpireTimers[ iPlayer ] );
		g_hShieldExpireTimers[ iPlayer ] = INVALID_HANDLE;
	}

	g_iAngelShields[iPlayer][0] = -1;
	g_iAngelShields[iPlayer][1] = -1;
}

static char g_szShieldKillParticle[][] = {
	"angel_shieldbreak_red",
	"angel_shieldbreak_blue",
	"angel_shieldbreak_green",
	"angel_shieldbreak_yellow"
}; 

//Action RemoveAngelShield2( Handle hTimer, int iPlayer ) {
void RemoveAngelShield2( int iPlayer ) {
	EmitSoundToAll( "weapons/teleporter_explode.wav", iPlayer );
	ClientCommand( iPlayer, "r_screenoverlay off"); 

	int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) - 2;
	int iEmitter = CreateEntityByName( "info_particle_system" );
	DispatchKeyValue( iEmitter, "effect_name", g_szShieldKillParticle[iTeam] );

	float vecPos[3]; GetClientAbsOrigin( iPlayer, vecPos );
	TeleportEntity( iEmitter, vecPos );

	ParentModel( iEmitter, iPlayer );

	DispatchSpawn( iEmitter );
	ActivateEntity( iEmitter );

	AcceptEntityInput( iEmitter, "Start" );

	CreateTimer( 1.0, RemoveEmitter, EntIndexToEntRef( iEmitter ), TIMER_FLAG_NO_MAPCHANGE );

	if( IsValidEntity( GetAngelShield( iPlayer, 0 ) ) ) {
		RemoveEntity( GetAngelShield( iPlayer, 0 ) );
	}
	if( IsValidEntity( GetAngelShield( iPlayer, 1 ) ) ) {
		RemoveEntity( GetAngelShield( iPlayer, 1 ) );
	}

	g_iAngelShields[iPlayer][0] = -1;
	g_iAngelShields[iPlayer][1] = -1;

	//return Plugin_Continue;
}
Action RemoveEmitter( Handle hTimer, int iEmitter ) {
	iEmitter = EntRefToEntIndex( iEmitter );
	if( iEmitter != -1 )
		RemoveEntity( iEmitter );

	return Plugin_Continue;
}

void AngelShieldTakeDamage( int iTarget, TFDamageInfo tfInfo ) {
	float flNewDamage = TF2DamageFalloff( iTarget, tfInfo );
	g_ePlayerConds[iTarget][TFCC_ANGELSHIELD].condLevel -= RoundToFloor( flNewDamage );

	float vecTarget[3];
	GetEntPropVector( iTarget, Prop_Send, "m_vecOrigin", vecTarget );

	TF2_AddCondition( iTarget, TFCond_UberchargedOnTakeDamage, 0.1 ); //todo: hook some sort of function to replace this

	Event eFakeDamage = CreateEvent( "player_hurt", true );
	eFakeDamage.SetInt( "userid", GetClientUserId( iTarget ) );
	eFakeDamage.SetInt( "health", 300 );
	eFakeDamage.SetInt( "attacker", GetClientUserId( tfInfo.iAttacker ) );
	eFakeDamage.SetInt( "damageamount", RoundToFloor( flNewDamage ) );
	eFakeDamage.SetInt( "bonuseffect", 2 );
	eFakeDamage.Fire();

	Event eBlockedDamage = CreateEvent( "damage_blocked", true );
	eBlockedDamage.SetInt( "provider", GetCondSourcePlayer( iTarget, TFCC_ANGELSHIELD ) );
	eBlockedDamage.SetInt( "victim", GetClientUserId( iTarget ) );
	eBlockedDamage.SetInt( "attacker", GetClientUserId( tfInfo.iAttacker ) );
	eBlockedDamage.SetInt( "amount", RoundToFloor( flNewDamage ) );
	eBlockedDamage.Fire();

	//todo: give damage score to attacker

	EmitGameSoundToAll( "Player.ResistanceHeavy", iTarget );

	if( g_ePlayerConds[iTarget][TFCC_ANGELSHIELD].condLevel <= 0 ) {
		RemoveCond( iTarget, TFCC_ANGELSHIELD );
	}
	g_flLastDamagedShield[ iTarget ] = GetGameTime(); //todo: use last damaged entprop for this
}
void AngelShieldTakeDamagePost( int iTarget ) {
	TF2_RemoveCondition( iTarget, TFCond_UberchargedOnTakeDamage );
}

//todo: parent to playermodel better
void ManageAngelShield( int iPlayer ) {
	int iAngelShield = GetAngelShield( iPlayer, 0 );
	if(  iAngelShield == -1 )
		return;

	float flVecPos[3];
	GetEntPropVector( iPlayer, Prop_Send, "m_vecOrigin", flVecPos );
	TeleportEntity( GetAngelShield( iPlayer, 0 ), flVecPos );

	int iAngelManager = GetAngelShield( iPlayer, 1 );
	if( iAngelManager == -1 )
		return;

	float flLastDamaged = GetGameTime() - g_flLastDamagedShield[ iPlayer ];

	float flShieldFalloff = RemapValClamped( flLastDamaged, 0.0, 0.5, 5.0, -5.0 );

	static char szFalloff[8];
	FloatToString(flShieldFalloff, szFalloff, 8);

	SetVariantString( szFalloff );
	AcceptEntityInput( iAngelManager, "SetMaterialVar" );
}


Action Hook_TransmitIfOwner( int iEntity, int iClient ) {
	SetEdictFlags( iEntity, 0 );
	return iClient == GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" ) ? Plugin_Continue : Plugin_Handled;
}
Action Hook_TransmitIfNotOwner( int iEntity, int iClient ) {
	SetEdictFlags( iEntity, 0 );
	return iClient != GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" ) ? Plugin_Continue : Plugin_Handled;
}

/*
	ANGEL SHIELD INVULN
*/

bool AddAngelInvuln( int iPlayer ) {
	CreateTimer( g_iAngInvulnDuration, ExpireAngelInvuln, iPlayer, TIMER_FLAG_NO_MAPCHANGE );
	return true;
}
Action ExpireAngelInvuln( Handle hTimer, int iPlayer ) {
	RemoveCond( iPlayer, TFCC_ANGELINVULN );

	return Plugin_Stop;
}
/*void RemoveAngelInvuln( int iPlayer ) {

}*/

/*
	QUICK FIX UBER
*/

int g_iQuickFixEmitters[MAXPLAYERS+1] = { -1, ... };
void RemoveQuickFixEmitter( int iPlayer ) {
	int iEmitter = EntRefToEntIndex( g_iQuickFixEmitters[iPlayer] );
	if( iEmitter != -1 ) {
		RemoveEntity( iEmitter );
	}
	g_iQuickFixEmitters[iPlayer] = -1;
}

static char g_szQFixParticle[][] = {
	"quickfix_pulse_red",
	"quickfix_pulse_blue",
	"quickfix_pulse_green",
	"quickfix_pulse_yellow"
};

bool AddQuickUber( int iPlayer ) {
	RemoveQuickFixEmitter( iPlayer );

	int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) - 2;
	int iEmitter = CreateEntityByName( "info_particle_system" );
	DispatchKeyValue( iEmitter, "effect_name", g_szQFixParticle[ iTeam ] );

	float vecPos[3]; GetClientAbsOrigin( iPlayer, vecPos );
	TeleportEntity( iEmitter, vecPos );

	ParentModel( iEmitter, iPlayer );

	DispatchSpawn( iEmitter );
	ActivateEntity( iEmitter );
	AcceptEntityInput( iEmitter, "Start" );

	g_iQuickFixEmitters[iPlayer] = EntIndexToEntRef( iEmitter );

	static char szCommand[64];
	Format( szCommand, sizeof(szCommand), "r_screenoverlay %s", g_szShieldOverlays[iTeam] );

	ClientCommand( iPlayer, szCommand ); 

	return true;
}

void TickQuickUber( int iPlayer ) {
	if( g_ePlayerConds[ iPlayer ][ TFCC_QUICKUBER ].flExpireTime < GetGameTime() ) {
		RemoveCond( iPlayer, TFCC_QUICKUBER );
		return;
	}

	//todo: unhardcode this/fix this
	//heal medic for 3x medigun heal rate, patient for 2x since they are already receiving the health from the medigun
	float flRate;
	if( iPlayer == GetCondSourcePlayer( iPlayer, TFCC_QUICKUBER ) ) flRate = 108.0 * GetGameFrameTime();
	else flRate = 72.0 * GetGameFrameTime();

	HealPlayer( iPlayer, flRate, GetCondSourcePlayer( iPlayer, TFCC_QUICKUBER ) );
}

void RemoveQuickUber( int iPlayer ) {
	RemoveQuickFixEmitter( iPlayer );
	if( IsClientInGame( iPlayer ) )
		ClientCommand( iPlayer, "r_screenoverlay off");
}

//hydro pump
bool AddHydroPumpHeal( int iPlayer, int iSource ) {
	int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) - 2;
	int iEmitter = CreateEntityByName( "info_particle_system" );
	DispatchKeyValue( iEmitter, "effect_name", g_szHydroPumpHealParticles[ iTeam ] );

	float vecPos[3]; GetClientAbsOrigin( iPlayer, vecPos );
	TeleportEntity( iEmitter, vecPos );

	ParentModel( iEmitter, iPlayer );
	SetEntPropEnt( iEmitter, Prop_Send, "m_hOwnerEntity", iPlayer );

	DispatchSpawn( iEmitter );
	ActivateEntity( iEmitter );
	AcceptEntityInput( iEmitter, "Start" );

	SetEntPropEnt( iEmitter, Prop_Send, "m_hControlPointEnts", iPlayer );

	g_iHydroPumpEmitters[iPlayer] = EntIndexToEntRef( iEmitter );

	//rate of 0.1 to block overheal decay
	AddPlayerHealer( iPlayer, iSource, 0.1, true );
	CreateTimer( 0.2, Timer_HydroPumpKillMe, EntRefToEntIndex( iPlayer ), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );

	//reusing shield transmit function because it already does what we need
	//SDKHook( iEmitter, SDKHook_SetTransmit, Hook_TransmitIfNotOwner );
	//SetEdictFlags( iEmitter, 0 );

	int iOldHydroHealer = 0;
	GetCustomProp( iSource, "m_iHydroHealing", iOldHydroHealer );
	SetCustomProp( iSource, "m_iHydroHealing", MaxInt( iOldHydroHealer + 1, 0 ) );

	return true;
}

void TickHydroPumpHeal( int iPlayer ) {
	//view as is necessary to trick the compiler into not fucking this up somehow
	//best guess is the "any" return of getcondlevel is being automatically treated as an int and using int multiplication
	float flFrameTime = GetGameFrameTime();
	float flLevel = view_as<float>( GetCondLevel( iPlayer, TFCC_HYDROPUMPHEAL ) ) * flFrameTime;
	HealPlayer( iPlayer, flLevel, GetCondSourcePlayer( iPlayer, TFCC_QUICKUBER ) );

	//extinguish burning players
	if( TF2_IsPlayerInCondition( iPlayer, TFCond_OnFire ) ) {
		float flRemoveTime = GetEntPropFloat( iPlayer, Prop_Send, "m_flFlameRemoveTime" );
		SetEntPropFloat( iPlayer, Prop_Send, "m_flFlameRemoveTime", MaxFloat( GetGameTime(), flRemoveTime - flFrameTime ) );
	}
}

Action Timer_HydroPumpKillMe( Handle hTimer, int iOwnerRef ) {
	int iOwner = EntRefToEntIndex( iOwnerRef );
	if( iOwner == -1 ) {
		RemoveCond( iOwner, TFCC_HYDROPUMPHEAL );
		return Plugin_Stop;
	}

	if( GetGameTime() > g_ePlayerConds[ iOwner ][ TFCC_HYDROPUMPHEAL ].flExpireTime ) {
		RemoveCond( iOwner, TFCC_HYDROPUMPHEAL );
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

void RemoveHydroPumpHeal( int iPlayer ) {
	int iSource = GetCondSourcePlayer( iPlayer, TFCC_HYDROPUMPHEAL );
	int iOldHydroHealer = 0;
	GetCustomProp( iSource, "m_iHydroHealing", iOldHydroHealer );
	SetCustomProp( iSource, "m_iHydroHealing", MaxInt( iOldHydroHealer - 1, 0 ) );

	RemovePlayerHealer( iPlayer, iSource );

	int iEmitter = EntRefToEntIndex( g_iHydroPumpEmitters[ iPlayer ] );
	g_iHydroPumpEmitters[ iPlayer ] = INVALID_ENT_REFERENCE;
	if( iEmitter == -1 )
		return;

	RemoveEntity( iEmitter );
}

//hydro uber
bool AddHydroUber( int iPlayer ) {
	CreateTimer( g_flHydroUberFrequency, Timer_HydroUberPulse, EntRefToEntIndex( iPlayer ), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );

	int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) - 2;
	float vecPos[3]; GetClientAbsOrigin( iPlayer, vecPos );

	//third person
	int iEmitter = CreateEntityByName( "info_particle_system" );
	DispatchKeyValue( iEmitter, "effect_name", g_szHydroUberParticles[ iTeam ] );
	
	TeleportEntity( iEmitter, vecPos );
	ParentModel( iEmitter, iPlayer );
	SetEntPropEnt( iEmitter, Prop_Send, "m_hOwnerEntity", iPlayer );

	DispatchSpawn( iEmitter );
	ActivateEntity( iEmitter );
	AcceptEntityInput( iEmitter, "Start" );

	SetEdictFlags( iEmitter, 0 );
	SDKHook( iEmitter, SDKHook_SetTransmit, Hook_TransmitIfNotOwner );

	g_iHydroPumpUberEmitters[iPlayer][0] = EntIndexToEntRef( iEmitter );

	//first person
	iEmitter = CreateEntityByName( "info_particle_system" );
	DispatchKeyValue( iEmitter, "effect_name", g_szHydroUberParticlesFP[ iTeam ] );
	
	TeleportEntity( iEmitter, vecPos );
	ParentModel( iEmitter, iPlayer );
	SetEntPropEnt( iEmitter, Prop_Send, "m_hOwnerEntity", iPlayer );

	DispatchSpawn( iEmitter );
	ActivateEntity( iEmitter );
	AcceptEntityInput( iEmitter, "Start" );

	SetEdictFlags( iEmitter, 0 );
	SDKHook( iEmitter, SDKHook_SetTransmit, Hook_TransmitIfOwner );

	g_iHydroPumpUberEmitters[iPlayer][1] = EntIndexToEntRef( iEmitter );

	return true;
}

Action Timer_HydroUberPulse( Handle hTimer, int iOwnerRef ) {
	int iOwner = EntRefToEntIndex( iOwnerRef );
	if( iOwner == -1 ) {
		RemoveCond( iOwner, TFCC_HYDROUBER );
		return Plugin_Stop;
	}

	float flOldValue = Tracker_GetValue( iOwner, "Ubercharge" );
	if( flOldValue <= 0.0 ) {
		RemoveCond( iOwner, TFCC_HYDROUBER );
		return Plugin_Stop;
	}

	//precalculated
	//float flDrainRate = 100.0 / ( g_flHydroUberDuration * ( 1.0 / g_flHydroUberFrequency ) );
	float flDrainRate = 2.0;
	int iWeapon = GetEntPropEnt( iOwner, Prop_Send, "m_hActiveWeapon" );
	if( iWeapon != -1 && RoundToFloor( AttribHookFloat( 0.0, iWeapon, "custom_medigun_type" ) ) != 6 ) {
		flDrainRate *= 1.5;
	}

	Tracker_SetValue( iOwner, "Ubercharge", flOldValue - flDrainRate );

	int iSourceWeapon = GetCondSourceWeapon( iOwner, TFCC_HYDROUBER );
	int iOwnerTeam = GetEntProp( iOwner, Prop_Send, "m_iTeamNum" );

	float vecOwnerPos[3];
	GetEntPropVector( iOwner, Prop_Data, "m_vecAbsOrigin", vecOwnerPos );
	for( int i = 1; i <= MaxClients; i++ ) {
		if( !PlayerInRadius( vecOwnerPos, g_flHydroUberRange, i ) )
			continue;

		if( TeamSeenBy( iOwner, i ) != iOwnerTeam )
			continue;

		//todo: do los check here

		AddCond( i, TFCC_HYDROPUMPHEAL, iOwner, iSourceWeapon );
		SetCondDuration( i, TFCC_HYDROPUMPHEAL, 0.5, false );
		SetCondLevel( i, TFCC_HYDROPUMPHEAL, g_flHydroUberHealRate );
	}

	return Plugin_Continue;
}

void RemoveHydroUber( int iPlayer ) {
	for( int i = 0; i <= 1; i++ ) {
		int iEmitter = EntRefToEntIndex( g_iHydroPumpUberEmitters[iPlayer][i] );
		g_iHydroPumpUberEmitters[iPlayer][i] = INVALID_ENT_REFERENCE;
		if( iEmitter == -1 )
			continue;

		RemoveEntity( iEmitter );
	}
}