#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <kocwtools>

#define DEBUG

public Plugin myinfo =
{
	name = "Condition Handler",
	author = "Noclue",
	description = "Core plugin for custom conditions.",
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

enum {
	TFCC_TOXIN = 0,
	TFCC_ANGELSHIELD,
	TFCC_ANGELINVULN,

	TFCC_LAST
}
const int COND_BITFIELDS = (TFCC_LAST / 32) + 1;

enum struct EffectProps {
	int	iLevel;		//condition strength

	Handle 	hTick;		//handle of the timer that ticks the effect
	float	flDuration;	//time until effect expires

	int	iEffectSource; 	//player that caused effect
	int	iEffectWeapon; 	//weapon that caused effect
}

EffectProps	ePlayerConds[MAXPLAYERS+1][TFCC_LAST];
int		iPlayerCondFlags[MAXPLAYERS+1][COND_BITFIELDS];

DynamicHook hTakeHealth;

bool bLateLoad;
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

	bLateLoad = bLate;

	return APLRes_Success;
}

public void OnGameFrame() {
	ManageAngelShields();
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	hTakeHealth = DynamicHook.FromConf( hGameConf, "CTFPlayer::TakeHealth" );

	if( !bLateLoad )
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
	if( IsValidEdict( iClient ) )
		RequestFrame( DoPlayerHooks, iClient );
}

void DoPlayerHooks( int iPlayer ) {
	hTakeHealth.HookEntity( Hook_Pre, iPlayer, Hook_TakeHealth );
	SDKHook( iPlayer, SDKHook_OnTakeDamage, Hook_OnTakeDamage );
}

public void OnMapStart() {
	PrecacheSound( "items/powerup_pickup_plague_infected_loop.wav" );
	PrecacheModel( "models/effects/resist_shield/resist_shield.mdl" );
}

#if defined DEBUG
Action Command_Test( int iClient, int iArgs ) {
	if(iArgs < 1) return Plugin_Handled;

	int iCondIndex = GetCmdArgInt( 1 );
	for( int i = 1; i <= MaxClients; i++ ) {
		if( IsClientInGame( i ) )
			AddCond( i, iCondIndex );
	}
	
	return Plugin_Handled;
}
#endif

int GetFlagArrayOffset( int iCond ) {
	if( iCond < 32 )
		return 0;

	return ( iCond / 32 ) - 1;
}
int GetFlagArrayBit( int iCond ) {
	int iIndex = iCond % 32;
	return ( 1 << iIndex );
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
	if( HasCond( iPlayer, iCond ) ) return false;

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
	}

	int iBit = GetFlagArrayBit( iCond );
	int iOffset = GetFlagArrayOffset( iCond );

	iPlayerCondFlags[ iPlayer ][ iOffset ] |= iBit;

	return bGaveCond;
}

public any Native_HasCond( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);
	return HasCond( iPlayer, iEffect );
}
bool HasCond( int iPlayer, int iCond ) {
	int iFlag = GetFlagArrayBit( iCond );
	int iOffset = GetFlagArrayOffset( iCond );

	return iPlayerCondFlags[iPlayer][iOffset] & iFlag != 0;
}

public any Native_RemoveCond( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);
	RemoveCond( iPlayer, iEffect );

	return 0;
}
void RemoveCond( int iPlayer, int iCond ) {
	switch(iCond) {
	case TFCC_TOXIN: {
		RemoveToxin( iPlayer );
	}
	case TFCC_ANGELSHIELD: {
		RemoveAngelShield( iPlayer );
	}
	case TFCC_ANGELINVULN: {
		RemoveAngelInvuln( iPlayer );
	}
	}

	if( IsValidHandle( ePlayerConds[iPlayer][iCond].hTick ) ) {
		KillTimer(ePlayerConds[iPlayer][iCond].hTick);
		ePlayerConds[iPlayer][iCond].hTick = null;
	}
	ePlayerConds[iPlayer][iCond].iLevel =		0;
	ePlayerConds[iPlayer][iCond].flDuration =	0.0;
	ePlayerConds[iPlayer][iCond].iEffectSource =	INVALID_ENT_REFERENCE;
	ePlayerConds[iPlayer][iCond].iEffectWeapon =	INVALID_ENT_REFERENCE;

	int iBit = GetFlagArrayBit( iCond );
	int iOffset = GetFlagArrayOffset( iCond );

	iPlayerCondFlags[ iPlayer ][ iOffset ] &= ~iBit;
}

//cond level
public any Native_GetCondLevel( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);

	return GetCondLevel( iPlayer, iEffect );
}
int GetCondLevel( int iPlayer, int iCond ) {
	return ePlayerConds[iPlayer][iCond].iLevel;
}
public any Native_SetCondLevel( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);
	int iLevel =  GetNativeCell(3);

	SetCondLevel( iPlayer, iEffect, iLevel);
	return 0;
}
void SetCondLevel( int iPlayer, int iCond, int iNewLevel ) {
	ePlayerConds[iPlayer][iCond].iLevel = iNewLevel;
}

//cond duration
public any Native_GetCondDuration( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);

	return GetCondDuration( iPlayer, iEffect );
}
float GetCondDuration( int iPlayer, int iCond ) {
	return ePlayerConds[iPlayer][iCond].flDuration;
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
	ePlayerConds[iPlayer][iCond].flDuration = bAdd ? ePlayerConds[iPlayer][iCond].flDuration + flDuration : flDuration;
}

//cond player source
public any Native_GetCondSourcePlayer( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);

	return GetCondSourcePlayer( iPlayer, iEffect );
}
int GetCondSourcePlayer( int iPlayer, int iCond ) {
	return ePlayerConds[iPlayer][iCond].iEffectSource;
}
public any Native_SetCondSourcePlayer( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);
	int iSource = GetNativeCell(3);

	SetCondSourcePlayer( iPlayer, iEffect, iSource );
	return 0;
}
void SetCondSourcePlayer( int iPlayer, int iCond, int iSource ) {
	ePlayerConds[iPlayer][iCond].iEffectSource = iSource;
}

//cond weapon source
public any Native_GetCondSourceWeapon( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);

	return GetCondSourceWeapon( iPlayer, iEffect );
}
int GetCondSourceWeapon( int iPlayer, int iCond ) {
	return ePlayerConds[iPlayer][iCond].iEffectWeapon;
}
public any Native_SetCondSourceWeapon( Handle hPlugin, int iNumParams ) {
	int iPlayer = GetNativeCell(1);
	int iEffect = GetNativeCell(2);
	int iWeapon = GetNativeCell(3);

	SetCondSourceWeapon( iPlayer, iEffect, iWeapon );
	return 0;
}
void SetCondSourceWeapon( int iPlayer, int iCond, int iWeapon ) {
	ePlayerConds[iPlayer][iCond].iEffectWeapon = iWeapon;
}

/*
	TOXIN
*/

const float	TOXIN_FREQUENCY		= 0.5; //tick interval in seconds
const float	TOXIN_DAMAGE		= 2.0; //damage per tick
const float	TOXIN_HEALING_MULT	= 0.5; //multiplier for healing while under toxin

bool AddToxin( int iPlayer ) {
	ePlayerConds[iPlayer][TFCC_TOXIN].hTick = CreateTimer( TOXIN_FREQUENCY, TickToxin, iPlayer, TIMER_FLAG_NO_MAPCHANGE );
	//start particle effect here

	EmitSoundToAll( "items/powerup_pickup_plague_infected_loop.wav",  iPlayer, SNDCHAN_STATIC, SNDLEVEL_HELICOPTER );
	return true;
}

Action TickToxin( Handle hTimer, int iPlayer ) {
	if( !IsClientConnected( iPlayer) ) {
		RemoveCond( iPlayer, TFCC_TOXIN );
		return Plugin_Stop;
	}

	int iDamagePlayer = ePlayerConds[iPlayer][TFCC_TOXIN].iEffectSource;
	int iDamageWeapon = ePlayerConds[iPlayer][TFCC_TOXIN].iEffectWeapon;

	SDKHooks_TakeDamage( iPlayer, iDamagePlayer, iDamagePlayer, TOXIN_DAMAGE, DMG_SLASH, iDamageWeapon );

	ePlayerConds[iPlayer][TFCC_TOXIN].flDuration -= TOXIN_FREQUENCY;
	if( ePlayerConds[iPlayer][TFCC_TOXIN].flDuration <= 0.0 ) {
		RemoveCond( iPlayer, TFCC_TOXIN );
		return Plugin_Stop;
	}
	ePlayerConds[iPlayer][TFCC_TOXIN].hTick = CreateTimer( MinFloat( ePlayerConds[iPlayer][TFCC_TOXIN].flDuration, TOXIN_FREQUENCY ), TickToxin, iPlayer, TIMER_FLAG_NO_MAPCHANGE );
	
	return Plugin_Continue;
}

void RemoveToxin( int iPlayer ) {
	StopSound( iPlayer, SNDCHAN_STATIC, "items/powerup_pickup_plague_infected_loop.wav" );
}

#if defined DEBUG
float flStart = 0.0;
int iHP = 0;
#endif

float flHealthBuffer[MAXPLAYERS+1] = { 0.0, ... }; //buffer for health cut off by rounding
//name is misleading, TakeHealth is used to RESTORE health because valve
MRESReturn Hook_TakeHealth( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	if( !( iThis > 0 && iThis <= MaxClients ) )
		return MRES_Ignored;

	if( !HasCond( iThis, TFCC_TOXIN ) )
		return MRES_Ignored;

	float	flAddHealth = hParams.Get( 1 );
	//int	iDamageFlags = hParams.Get( 1 ); //don't need these for anything yet

	flAddHealth *= TOXIN_HEALING_MULT;

	//need to buffer values below 1 since otherwise they get rounded out
	flAddHealth += flHealthBuffer[ iThis ];
	int iRoundedHealth = RoundToFloor( flAddHealth );
	flHealthBuffer[ iThis ] = flAddHealth - float( iRoundedHealth );

	hParams.Set( 1, flAddHealth );

#if defined DEBUG
	if( flStart == 0.0 ) {
		flStart = GetGameTime();
		iHP = GetClientHealth( iThis );
	}
	else if( GetGameTime() >= flStart + 1.0 ) {
		PrintToServer( "Health per second: %i", GetClientHealth( iThis ) - iHP );
		flStart = 0.0;
	}
#endif

	return MRES_ChangedHandled;
}

/*
	ANGEL SHIELD
*/

const int ANGSHIELD_HEALTH = 120;
const float ANGSHIELD_DURATION = 3.0;

//0 contains the index of the shield, 1 contains the material manager used for the damage effecct
int iAngelShields[MAXPLAYERS+1][2];
float flLastDamagedShield[MAXPLAYERS+1];

static char szShieldMats[][] = {
	"models/effects/resist_shield/resist_shield",
	"models/effects/resist_shield/resist_shield_blue",
	"models/effects/resist_shield/resist_shield_green",
	"models/effects/resist_shield/resist_shield_yellow"
};

bool AddAngelShield( int iPlayer ) {
	ePlayerConds[iPlayer][TFCC_ANGELSHIELD].hTick = CreateTimer( ANGSHIELD_DURATION, ExpireAngelShield, iPlayer, TIMER_FLAG_NO_MAPCHANGE );
	ePlayerConds[iPlayer][TFCC_ANGELSHIELD].iLevel = ANGSHIELD_HEALTH;

	flLastDamagedShield[iPlayer] = GetGameTime();

	int iNewShield = CreateEntityByName( "prop_dynamic" );
	SetEntityModel( iNewShield, "models/effects/resist_shield/resist_shield.mdl" );
	SetEntityCollisionGroup( iNewShield, 0 );
	DispatchKeyValue( iNewShield, "disableshadows", "1" );
	SetEntPropEnt( iNewShield, Prop_Send, "m_hOwnerEntity", iPlayer );

	int iTeamNum = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) - 2;
	SetEntProp( iNewShield, Prop_Send, "m_nSkin", iTeamNum );

	SDKHook( iNewShield, SDKHook_SetTransmit, Hook_NewShield );

	DispatchSpawn( iNewShield );
	iAngelShields[iPlayer][0] = iNewShield;

	int iNewManager = CreateEntityByName( "material_modify_control" );

	SetVariantString("!activator");
	AcceptEntityInput( iNewManager, "SetParent", iNewShield );

	DispatchKeyValue( iNewManager, "materialName", szShieldMats[iTeamNum] );
	DispatchKeyValue( iNewManager, "materialVar", "$shield_falloff" );

	DispatchSpawn( iNewManager );
	iAngelShields[iPlayer][1] = iNewManager;

	return true;
}
Action ExpireAngelShield( Handle hTimer, int iPlayer ) {
	RemoveCond( iPlayer, TFCC_ANGELSHIELD );

	return Plugin_Stop;
}
void RemoveAngelShield( int iPlayer ) {
	bool bBroken = ePlayerConds[iPlayer][TFCC_ANGELSHIELD].iLevel <= 0;

	if( bBroken ) {
		//AddCond( iPlayer, TFCC_ANGELINVULN );
		//SetCondDuration( iPlayer, TFCC_ANGELINVULN, ANGINVULN_DURATION );
	}

	if( IsValidEntity( iAngelShields[iPlayer][0] ) ) {
		RemoveEntity( iAngelShields[iPlayer][0] );
	}
	if( IsValidEntity( iAngelShields[iPlayer][1] ) ) {
		RemoveEntity( iAngelShields[iPlayer][1] );
	}

	iAngelShields[iPlayer][0] = INVALID_ENT_REFERENCE;
	iAngelShields[iPlayer][1] = INVALID_ENT_REFERENCE;
}

bool AngelShieldTakeDamage( int iVictim, int &iAttacker, int &iInflictor, float &flDamage ) {
	if( !HasCond( iVictim, TFCC_ANGELSHIELD ) )
		return false;

	ePlayerConds[iVictim][TFCC_ANGELSHIELD].iLevel -= RoundToFloor( flDamage );
	flDamage = 0.0;

	EmitGameSoundToAll( "Player.ResistanceMedium", iVictim );
	flLastDamagedShield[ iVictim ] = GetGameTime();

	if( ePlayerConds[iVictim][TFCC_ANGELSHIELD].iLevel <= 0 ) {
		RemoveCond( iVictim, TFCC_ANGELSHIELD );
	}

	return true;
}

void ManageAngelShields() {
	for( int i = 1; i <= MaxClients; i++ ) {
		if( !IsClientInGame( i ) || !IsValidEntity( iAngelShields[ i ][ 0 ] ) )
			continue;

		float flVecPos[3];
		GetEntPropVector( i, Prop_Send, "m_vecOrigin", flVecPos );
		TeleportEntity( iAngelShields[ i ][ 0 ], flVecPos );

		float flLastDamaged = GetGameTime() - flLastDamagedShield[ i ];
		if( flLastDamaged > 0.5 )
			continue;

		float flShieldFalloff = RemapValClamped( flLastDamaged, 0.0, 0.5, 5.0, -5.0 );

		static char szFalloff[8];// = "-4.0 -4.0 -4.0 1.0";
		FloatToString(flShieldFalloff, szFalloff, 8);

		SetVariantString( szFalloff );
		AcceptEntityInput( iAngelShields[ i ][ 1 ], "SetMaterialVar" );
	}
}

Action Hook_NewShield( int iEntity, int iClient ) {
	if( GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity") == iClient ) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

/*
	ANGEL SHIELD INVULN
*/

const float ANGINVULN_DURATION = 1.0;

bool AddAngelInvuln( int iPlayer ) {
	ePlayerConds[iPlayer][TFCC_ANGELINVULN].hTick = CreateTimer( ANGINVULN_DURATION, ExpireAngelInvuln, iPlayer, TIMER_FLAG_NO_MAPCHANGE );
	return true;
}
Action ExpireAngelInvuln( Handle hTimer, int iPlayer ) {
	RemoveCond( iPlayer, TFCC_ANGELINVULN );

	return Plugin_Stop;
}
void RemoveAngelInvuln( int iPlayer ) {

}

bool AngelInvulnTakeDamage( int iVictim, int &iAttacker, int &iInflictor, float &flDamage ) {
	if( !HasCond( iVictim, TFCC_ANGELINVULN ) )
		return false;

	flDamage = 0.0;

	return true;
}

Action Hook_OnTakeDamage( int iVictim, int &iAttacker, int &iInflictor, float &flDamage, int &damagetype, int &iWeapon, float damageForce[3], float damagePosition[3], int damagecustom ) {
	if(iWeapon >= 4096) iWeapon -= 4096;
	if(iAttacker >= 4096) iAttacker -= 4096;
	if(iInflictor >= 4096) iInflictor -= 4096;
	
	AngelShieldTakeDamage( iVictim, iAttacker, iInflictor, flDamage );
	AngelInvulnTakeDamage( iVictim, iAttacker, iInflictor, flDamage );

	return Plugin_Changed;
}