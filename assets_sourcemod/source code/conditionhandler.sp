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

//TODO: Shield parenting could be better

enum {
	TFCC_TOXIN = 0,
	TFCC_TOXINUBER,
	TFCC_TOXINPATIENT,
	TFCC_ANGELSHIELD,
	TFCC_ANGELINVULN,

	TFCC_LAST
}
const int COND_BITFIELDS = (TFCC_LAST / 32) + 1;

enum struct EffectProps {
	int	iLevel;		//condition strength

	Handle 	hTick;		//handle of the timer that ticks the effect
	float	flRemoveTime;	//time until effect expires

	int	iEffectSource; 	//player that caused effect
	int	iEffectWeapon; 	//weapon that caused effect
}

EffectProps	ePlayerConds[MAXPLAYERS+1][TFCC_LAST];
int		iPlayerCondFlags[MAXPLAYERS+1][COND_BITFIELDS];

DynamicHook hTakeHealth;
DynamicDetour hHealConds;

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
	hHealConds = DynamicDetour.FromConf( hGameConf, "CTFPlayerShared::HealNegativeConds" );
	hHealConds.Enable( Hook_Post, Detour_HealNegativeConds );

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
}

public void OnMapStart() {
	PrecacheSound( "items/powerup_pickup_plague_infected_loop.wav" );
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
		}
			
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
	int iIndex = iCond % 32 ;
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
	case TFCC_TOXINPATIENT: {
		AddToxinPatient( iPlayer );
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

	ePlayerConds[iPlayer][iCond].flRemoveTime = GetGameTime();

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
	/*case TFCC_TOXINPATIENT: {
	}*/
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
	ePlayerConds[iPlayer][iCond].flRemoveTime =	0.0;
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
	return ePlayerConds[iPlayer][iCond].flRemoveTime - GetGameTime();
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
	ePlayerConds[iPlayer][iCond].flRemoveTime = bAdd ? ePlayerConds[iPlayer][iCond].flRemoveTime + flDuration : GetGameTime() + flDuration;
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

/*
	TOXIN
*/

const float	TOXIN_FREQUENCY		= 0.5; //tick interval in seconds
const float	TOXIN_DAMAGE		= 2.0; //damage per tick
const float	TOXIN_HEALING_MULT	= 0.5; //multiplier for healing while under toxin

bool AddToxin( int iPlayer ) {
	ePlayerConds[iPlayer][TFCC_TOXIN].hTick = CreateTimer( 0.1, TickToxin, iPlayer, TIMER_FLAG_NO_MAPCHANGE );
	//start particle effect here

	EmitSoundToAll( "items/powerup_pickup_plague_infected_loop.wav",  iPlayer, SNDCHAN_STATIC );
	return true;
}

Action TickToxin( Handle hTimer, int iPlayer ) {
	if( !IsClientInGame( iPlayer ) || !IsPlayerAlive( iPlayer ) ) {
		RemoveCond( iPlayer, TFCC_TOXIN );
		return Plugin_Stop;
	}

	int iDamagePlayer = GetCondSourcePlayer( iPlayer, TFCC_TOXIN );
	int iDamageWeapon = GetCondSourceWeapon( iPlayer, TFCC_TOXIN );

	if( iDamagePlayer == -1 )
		iDamagePlayer = 0;
	if( iDamageWeapon == -1 )
		iDamageWeapon = 0;
	
	SDKHooks_TakeDamage( iPlayer, iDamagePlayer, iDamagePlayer, TOXIN_DAMAGE, DMG_SLASH, iDamageWeapon );

	if( ePlayerConds[iPlayer][TFCC_TOXIN].flRemoveTime <= GetGameTime() ) {
		RemoveCond( iPlayer, TFCC_TOXIN );
		return Plugin_Stop;
	}
	ePlayerConds[iPlayer][TFCC_TOXIN].hTick = CreateTimer( MinFloat( GetCondDuration( iPlayer, TFCC_TOXIN ), TOXIN_FREQUENCY ), TickToxin, iPlayer, TIMER_FLAG_NO_MAPCHANGE );
	
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

void ToxinTakeDamage( int iTarget, TFDamageInfo tfInfo ) {
	int iAttacker = tfInfo.iAttacker;
	if( !IsValidPlayer( iAttacker ) )
		return;
	
	if( HasCond( iAttacker, TFCC_TOXINPATIENT ) ) {
		tfInfo.iCritType = CT_MINI;
	}
}

/*
	TOXIN PATIENT
*/

bool AddToxinPatient( int iPlayer ) {
	ePlayerConds[iPlayer][TFCC_TOXINPATIENT].hTick = CreateTimer( TOXIN_FREQUENCY, TickToxinPatient, iPlayer, TIMER_FLAG_NO_MAPCHANGE );
	return true;
}
Action TickToxinPatient( Handle hTimer, int iPlayer ) {
	if( !IsClientInGame( iPlayer ) || !IsPlayerAlive( iPlayer ) ) {
		RemoveCond( iPlayer, TFCC_TOXINPATIENT );
		return Plugin_Stop;
	}

	if( ePlayerConds[iPlayer][TFCC_TOXINPATIENT].flRemoveTime <= GetGameTime() ) {
		RemoveCond( iPlayer, TFCC_TOXINPATIENT );
		return Plugin_Stop;
	}
	ePlayerConds[iPlayer][TFCC_TOXINPATIENT].hTick = CreateTimer( MinFloat( GetCondDuration( iPlayer, TFCC_TOXINPATIENT ), TOXIN_FREQUENCY ), TickToxinPatient, iPlayer, TIMER_FLAG_NO_MAPCHANGE );
	
	return Plugin_Continue;
}

/*
	ANGEL SHIELD
*/

const int ANGSHIELD_HEALTH = 120;
const float ANGSHIELD_DURATION = 2.5;

//0 contains the index of the shield, 1 contains the material manager used for the damage effect
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

	ParentModel( iNewManager, iNewShield );

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
		AddCond( iPlayer, TFCC_ANGELINVULN );
		CreateTimer( 0.5, RemoveAngelShield2, iPlayer, TIMER_FLAG_NO_MAPCHANGE );
		return;
	}

	EmitSoundToAll( "weapons/buffed_off.wav", iPlayer, SNDCHAN_AUTO, 100 );

	if( IsValidEntity( iAngelShields[iPlayer][0] ) ) {
		RemoveEntity( iAngelShields[iPlayer][0] );
	}
	if( IsValidEntity( iAngelShields[iPlayer][1] ) ) {
		RemoveEntity( iAngelShields[iPlayer][1] );
	}

	iAngelShields[iPlayer][0] = INVALID_ENT_REFERENCE;
	iAngelShields[iPlayer][1] = INVALID_ENT_REFERENCE;
}

static char szShieldKillParticle[][] = {
	"medic_hadcharge_red",
	"medic_hadcharge_blue",
	"medic_hadcharge_green",
	"medic_hadcharge_yellow"
};

Action RemoveAngelShield2( Handle hTimer, int iPlayer ) {
	EmitSoundToAll( "weapons/teleporter_explode.wav", iPlayer );

	int iTeam = GetEntProp( iPlayer, Prop_Send, "m_iTeamNum" ) - 2;
	int iEmitter = CreateEntityByName( "info_particle_system" );
	DispatchKeyValue( iEmitter, "effect_name", szShieldKillParticle[iTeam] );

	ParentModel( iEmitter, iPlayer );

	DispatchSpawn( iEmitter );
	ActivateEntity( iEmitter );

	AcceptEntityInput( iEmitter, "Start" );

	

	if( IsValidEntity( iAngelShields[iPlayer][0] ) ) {
		RemoveEntity( iAngelShields[iPlayer][0] );
	}
	if( IsValidEntity( iAngelShields[iPlayer][1] ) ) {
		RemoveEntity( iAngelShields[iPlayer][1] );
	}

	iAngelShields[iPlayer][0] = INVALID_ENT_REFERENCE;
	iAngelShields[iPlayer][1] = INVALID_ENT_REFERENCE;

	return Plugin_Continue;
}

void AngelShieldTakeDamage( int iTarget, TFDamageInfo tfInfo ) {
	ePlayerConds[iTarget][TFCC_ANGELSHIELD].iLevel -= RoundToFloor( tfInfo.flDamage );

	float vecTarget[3];
	GetEntPropVector( iTarget, Prop_Send, "m_vecOrigin", vecTarget );

	int iInflictor = tfInfo.iInflictor;
	if( IsValidEdict( iInflictor ) ) {
		float vecInflictor[3];
		GetEntPropVector( iInflictor, Prop_Send, "m_vecOrigin", vecInflictor );

		SubtractVectors( vecInflictor, vecTarget, vecTarget );
		NormalizeVector( vecTarget, vecTarget );

		ApplyPushFromDamage( iTarget, view_as<Address>(tfInfo), vecTarget );
	}

	tfInfo.flDamage = 0.0;

	EmitGameSoundToAll( "Player.ResistanceHeavy", iTarget );
	

	if( ePlayerConds[iTarget][TFCC_ANGELSHIELD].iLevel <= 0 ) {
		RemoveCond( iTarget, TFCC_ANGELSHIELD );
		flLastDamagedShield[ iTarget ] = GetGameTime() + 100;
	}
	else
		flLastDamagedShield[ iTarget ] = GetGameTime();

	return;
}

void ManageAngelShields() {
	for( int i = 1; i <= MaxClients; i++ ) {
		if( !IsClientInGame( i ) || !IsValidEntity( iAngelShields[ i ][ 0 ] ) )
			continue;

		float flVecPos[3];
		GetEntPropVector( i, Prop_Send, "m_vecOrigin", flVecPos );
		TeleportEntity( iAngelShields[ i ][ 0 ], flVecPos );

		float flLastDamaged = GetGameTime() - flLastDamagedShield[ i ];

		float flShieldFalloff = RemapValClamped( flLastDamaged, 0.0, 0.5, 5.0, -5.0 );

		static char szFalloff[8];
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

const float ANGINVULN_DURATION = 0.5;

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

void AngelInvulnTakeDamage( int iTarget, TFDamageInfo tfInfo ) {
	tfInfo.flDamage = 0.0;
}

public void OnTakeDamageTF( int iTarget, Address aTakeDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aTakeDamageInfo );

	if( HasCond( iTarget, TFCC_TOXIN ) )
		ToxinTakeDamage( iTarget, tfInfo );
	if( HasCond( iTarget, TFCC_ANGELSHIELD ) )
		AngelShieldTakeDamage( iTarget, tfInfo );
	if( HasCond( iTarget, TFCC_ANGELINVULN ) )
		AngelInvulnTakeDamage( iTarget, tfInfo );

	//AngelInvulnTakeDamage( iTarget, iAttacker, iInflictor, flDamage );
}
