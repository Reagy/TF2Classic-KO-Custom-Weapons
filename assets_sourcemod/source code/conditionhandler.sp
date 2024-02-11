#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <kocwtools>
#include <hudframework>
#include <give_econ>

public Plugin myinfo =
{
	name = "Condition Handler",
	author = "Noclue",
	description = "Core plugin for custom conditions.",
	version = "1.1.3",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

//TODO: Shield parenting could be better

/*
	PROPERTIES
*/

const float	TOXIN_FREQUENCY		= 0.5;	//tick interval in seconds
const float	TOXIN_DAMAGE		= 2.0;	//damage per tick
const float	TOXIN_HEALING_MULT	= 0.25;	//multiplier for healing while under toxin

const int	ANGSHIELD_HEALTH	= 80;	//angel shield health
const float	ANGSHIELD_DURATION	= 8.0;	//angel shield duration
const float	ANGINVULN_DURATION	= 0.25;	//invulnerability period after a shield breaks

const float	FLAME_HEALRATE		= 30.0;	//health per second restored by the hydro pump

static char	g_szToxinLoopSound[]	= "items/powerup_pickup_plague_infected_loop.wav";

//#define DEBUG

enum {
	TFCC_TOXIN = 0,
	TFCC_TOXINUBER, //unused
	TFCC_UNUSED1, //unused

	TFCC_ANGELSHIELD,
	TFCC_ANGELINVULN,

	TFCC_QUICKUBER,

	TFCC_UNUSED2, //unused

	TFCC_FLAMEHEAL,

	TFCC_LAST
}
const int COND_BITFIELDS = (TFCC_LAST / 32) + 1;

enum struct EffectProps {
	int	iLevel;		//condition strength

	float	flExpireTime;	//time when effect expires
	float	flNextTick;	//time when effect should tick next

	int	iEffectSource; 	//player that caused effect
	int	iEffectWeapon; 	//weapon that caused effect
}

bool		g_bHasCond[MAXPLAYERS+1][TFCC_LAST];
EffectProps	g_ePlayerConds[MAXPLAYERS+1][TFCC_LAST];

//0 contains the index of the shield, 1 contains the material manager used for the damage effect
int 		g_iAngelShields[MAXPLAYERS+1][2];

DynamicHook g_dhTakeHealth;
DynamicDetour g_dtHealConds;
DynamicDetour g_dtApplyOnHit;

DynamicHook g_dhOnKill;

Handle g_hGetMaxHealth;
Handle g_hGetBuffedMaxHealth;

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

		if( HasCond( i, TFCC_FLAMEHEAL ) )
			TickFlameHeal( i );
	}
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	g_dhTakeHealth = DynamicHook.FromConf( hGameConf, "CTFPlayer::TakeHealth" );
	g_dtHealConds = DynamicDetour.FromConf( hGameConf, "CTFPlayerShared::HealNegativeConds" );
	g_dtHealConds.Enable( Hook_Post, Detour_HealNegativeConds );

	g_dtApplyOnHit = DynamicDetour.FromConf( hGameConf, "CTFWeaponBase::ApplyOnHitAttributes" );
	g_dtApplyOnHit.Enable( Hook_Post, Detour_OnHit );

	//todo: add to gamedata
	g_dhOnKill = new DynamicHook( 69, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity );
	g_dhOnKill.AddParam( HookParamType_CBaseEntity );
	g_dhOnKill.AddParam( HookParamType_ObjectPtr );

	StartPrepSDKCall( SDKCall_Player );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFPlayer::GetMaxHealth" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	g_hGetMaxHealth = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( hGameConf, SDKConf_Signature, "CTFPlayerShared::GetBuffedMaxHealth" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	g_hGetBuffedMaxHealth = EndPrepSDKCall();

	for( int i = 0; i < MAXPLAYERS+1; i++ ) {
		g_iAngelShields[i][0] = -1;
		g_iAngelShields[i][1] = -1;
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
	RegConsoleCmd( "sm_cond_test", Command_Test, "test");
#endif
}

public void OnClientConnected( int iClient ) {
	ClearConds( iClient );

	if( IsValidEdict( iClient ) )
		RequestFrame( DoPlayerHooks, iClient );
}
void DoPlayerHooks( int iPlayer ) {
	//g_dhTakeHealth.HookEntity( Hook_Pre, iPlayer, Hook_TakeHealth );
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
	return AddCond( iPlayer, iEffect );
}
bool AddCond( int iPlayer, int iCond ) {
	if( iCond < 0 || iCond >= TFCC_LAST || !IsValidPlayer( iPlayer ) )
		return false;

	if( HasCond( iPlayer, iCond ) ) 
		return false;
	if( IsNegativeCond( iCond ) && ( HasCond( iPlayer, TFCC_ANGELSHIELD ) || HasCond( iPlayer, TFCC_ANGELINVULN ) ) )
		return false;

	bool bGaveCond = false;
	switch( iCond ) {
	case TFCC_TOXIN: {
		AddToxin( iPlayer );
		bGaveCond = true;
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
	case TFCC_FLAMEHEAL: {
		bGaveCond = AddFlameHeal( iPlayer );
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

	g_ePlayerConds[iPlayer][iCond].iLevel =		0;
	g_ePlayerConds[iPlayer][iCond].flExpireTime =	0.0;
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
int GetCondLevel( int iPlayer, int iCond ) {
	return g_ePlayerConds[iPlayer][iCond].iLevel;
}
public any Native_SetCondLevel( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);
	int iLevel =  GetNativeCell(3);

	SetCondLevel( iPlayer, iEffect, iLevel);
	return 0;
}
void SetCondLevel( int iPlayer, int iCond, int iNewLevel ) {
	g_ePlayerConds[iPlayer][iCond].iLevel = iNewLevel;
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
void SetCondSourcePlayer( int iPlayer, int iCond, int iSource ) {
	g_ePlayerConds[iPlayer][iCond].iEffectSource = EntIndexToEntRef( iSource );
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
void SetCondSourceWeapon( int iPlayer, int iCond, int iWeapon ) {
	g_ePlayerConds[iPlayer][iCond].iEffectWeapon = EntIndexToEntRef( iWeapon );
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

MRESReturn Detour_OnHit( int iWeapon, DHookParam hParams ) {
	//int iOwner = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwnerEntity" );
	//int iSomething = hParams.Get( 1 );
	//PrintToServer("test");

	int iVictim = hParams.Get( 2 );

	if( hParams.IsNull( 1 ) )
		return MRES_Ignored;

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
	SDKHooks_TakeDamage( iPlayer, iDamagePlayer, iDamagePlayer, TOXIN_DAMAGE, DMG_GENERIC | DMG_PHYSGUN, iDamageWeapon, NULL_VECTOR, NULL_VECTOR, false );
	g_ePlayerConds[iPlayer][TFCC_TOXIN].flNextTick = GetGameTime() + TOXIN_FREQUENCY;
}

void RemoveToxin( int iPlayer ) {
	StopSound( iPlayer, 0, g_szToxinLoopSound );
	RemoveToxinEmitter( iPlayer );

	RemoveEconItem( iPlayer, 11000 );
}

//name is misleading, TakeHealth is used to RESTORE health because valve
MRESReturn Hook_TakeHealth( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	if( !IsValidPlayer( iThis ) )
		return MRES_Ignored;

	if( !HasCond( iThis, TFCC_TOXIN ) )
		return MRES_Ignored;

	float	flAddHealth = hParams.Get( 1 );
	//int	iDamageFlags = hParams.Get( 1 ); //don't need these for anything yet

	flAddHealth *= TOXIN_HEALING_MULT;

	//need to buffer values below 1 since otherwise they get rounded out
	flAddHealth += g_flHealthBuffer[ iThis ];
	int iRoundedHealth = RoundToFloor( flAddHealth );
	g_flHealthBuffer[ iThis ] = flAddHealth - float( iRoundedHealth );

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
	g_hShieldExpireTimers[ iPlayer ] = CreateTimer( ANGSHIELD_DURATION, ExpireAngelShield, iPlayer, TIMER_FLAG_NO_MAPCHANGE );
	g_ePlayerConds[iPlayer][TFCC_ANGELSHIELD].iLevel = ANGSHIELD_HEALTH;

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

	SDKHook( iNewShield, SDKHook_SetTransmit, Hook_ShieldTransmit );

	int iNewManager = CreateEntityByName( "material_modify_control" );

	ParentModel( iNewManager, iNewShield );

	DispatchKeyValue( iNewManager, "materialName", g_szShieldMats[iTeamNum] );
	DispatchKeyValue( iNewManager, "materialVar", "$shield_falloff" );

	DispatchSpawn( iNewManager );
	g_iAngelShields[iPlayer][1] = EntIndexToEntRef( iNewManager );

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
	g_ePlayerConds[iTarget][TFCC_ANGELSHIELD].iLevel -= RoundToFloor( flNewDamage );

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

	EmitGameSoundToAll( "Player.ResistanceHeavy", iTarget );

	if( g_ePlayerConds[iTarget][TFCC_ANGELSHIELD].iLevel <= 0 ) {
		RemoveCond( iTarget, TFCC_ANGELSHIELD );
	}
	g_flLastDamagedShield[ iTarget ] = GetGameTime();
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

Action Hook_ShieldTransmit( int iEntity, int iClient ) {
	if( GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" ) == iClient ) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

/*
	ANGEL SHIELD INVULN
*/

bool AddAngelInvuln( int iPlayer ) {
	CreateTimer( ANGINVULN_DURATION, ExpireAngelInvuln, iPlayer, TIMER_FLAG_NO_MAPCHANGE );
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

	TF2_AddCondition( iPlayer, TFCond_MegaHeal );
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

	//todo: unhardcode this
	//heal medic for 3x medigun heal rate, patient for 2x since they are already receiving the health from the medigun
	float flRate;
	if( iPlayer == GetCondSourcePlayer( iPlayer, TFCC_QUICKUBER ) ) flRate = 36.0 * 3.0 * GetGameFrameTime();
	else flRate = 36.0 * 2.0 * GetGameFrameTime();

	HealPlayer( iPlayer, flRate, GetCondSourcePlayer( iPlayer, TFCC_QUICKUBER ) );
}

void RemoveQuickUber( int iPlayer ) {
	RemoveQuickFixEmitter( iPlayer );

	if( IsClientInGame( iPlayer ) ) {
		//TF2_RemoveCondition( iPlayer, TFCond_MegaHeal );
		ClientCommand( iPlayer, "r_screenoverlay off");
	}
}

/*
	FLAME HEAL
*/

bool AddFlameHeal( int iPlayer ) {
	CreateTimer( 0.2, TickBatchHeal, iPlayer, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT );
	return true;
}

float g_flFlameHealDebt[ MAXPLAYERS+1 ];
int g_iFlameHealBatch[ MAXPLAYERS+1 ];
void TickFlameHeal( int iPlayer ) {
	float g_flFlameHealTick = GetGameFrameTime();

	int iSource = GetCondSourcePlayer( iPlayer, TFCC_FLAMEHEAL );

	if( !IsValidPlayer( iSource ) )
		return;

	float flRate = AttribHookFloat( FLAME_HEALRATE * g_flFlameHealTick, iSource, "mult_medigun_healrate" );
	int iLevel = MinInt( GetCondLevel( iPlayer, TFCC_FLAMEHEAL ), 275 );

	//turning off overheal decay is a pain so i'll just add more health to counteract it
	float flRateLoss = 0.0;
	int iMaxHealth = SDKCall( g_hGetMaxHealth, iPlayer );
	if( GetEntProp( iPlayer, Prop_Send, "m_iHealth" ) > iMaxHealth ) {
		Address aShared = GetSharedFromPlayer( iPlayer );
		flRateLoss = float( SDKCall( g_hGetBuffedMaxHealth, aShared ) - iMaxHealth ) / 15.0;
		flRateLoss *= g_flFlameHealTick;
	}

	float flAmount = MinFloat( flRate, float( iLevel ) * 0.1 ) + g_flFlameHealDebt[ iPlayer ];

	int iHealed = HealPlayer( iPlayer, flAmount + flRateLoss, iSource );
	int iNewLevel = iLevel - ( RoundToNearest( flAmount ) * 10 );

	g_iFlameHealBatch[ iPlayer ] += iHealed;

	Tracker_SetValue( iSource, "Pressure", Tracker_GetValue( iSource, "Pressure" ) + ( float( iHealed ) * 0.2 ) );

	g_flFlameHealDebt[ iPlayer ] = flAmount - RoundToFloor( flAmount );

	SetCondLevel( iPlayer, TFCC_FLAMEHEAL, iNewLevel );

	if( iNewLevel > 0 )
		return;
		
	RemoveCond( iPlayer, TFCC_FLAMEHEAL );
	g_flFlameHealDebt[ iPlayer ] = 0.0;
	g_iFlameHealBatch[ iPlayer ] = 0;

	return;
}

Action TickBatchHeal( Handle hTimer, int iPlayer ) {
	if( !HasCond( iPlayer, TFCC_FLAMEHEAL ) )
		return Plugin_Stop;

	int iSource = GetCondSourcePlayer( iPlayer, TFCC_FLAMEHEAL );

	Event eHealEvent = CreateEvent( "player_healed" );
	eHealEvent.SetInt( "patient", GetClientUserId( iPlayer ) );
	eHealEvent.SetInt( "healer", GetClientUserId( iSource ) );
	eHealEvent.SetInt( "amount", g_iFlameHealBatch[ iPlayer ] );
	eHealEvent.Fire();

	g_iFlameHealBatch[ iPlayer ] = 0;

	return Plugin_Continue;
}