#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <kocwtools>
#include <hudframework>

public Plugin myinfo =
{
	name = "Attribute: Leap Ability",
	author = "Noclue",
	description = "Leaping attribute.",
	version = "1.1",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

bool bCanLeap[MAXPLAYERS+1];
#define LEAPKEYNAME "Leap"

public void OnPluginStart() {
	HookEvent( "post_inventory_application", Event_Inventory, EventHookMode_Post );
	HookEvent( "player_death", Event_PlayerDeath, EventHookMode_Post );
}

public void OnMapStart() {
	PrecacheSound( "player/demo_charge_windup1.wav" );
	PrecacheSound( "player/demo_charge_windup2.wav" );
	PrecacheSound( "player/demo_charge_windup3.wav" );
}

public Action Event_Inventory( Event hEvent, const char[] sName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	if( IsValidPlayer( iPlayer ) ) {
		float flValue = AttribHookFloat( 0.0, iPlayer, "custom_leap_ability" );
		bCanLeap[iPlayer] = flValue != 0.0 && TF2_GetPlayerClass( iPlayer ) != TFClass_Spy; //todo: find non-hack solution for this
		if( bCanLeap[iPlayer] )
			Tracker_Create( iPlayer, LEAPKEYNAME, 100.0, flValue );
		else
			Tracker_Remove( iPlayer, LEAPKEYNAME );
	}
	
	return Plugin_Continue;
}
public Action Event_PlayerDeath( Event hEvent, const char[] sName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "attacker" );
	iPlayer = GetClientOfUserId( iPlayer );

	if( IsValidPlayer( iPlayer ) && bCanLeap[ iPlayer ] )
		Tracker_SetValue( iPlayer, LEAPKEYNAME, 100.0 );

	return Plugin_Continue;
}


int iOldButtons[MAXPLAYERS+1];
public Action OnPlayerRunCmd( int iClient, int &iButtons, int &iImpulse, float flVel[3], float flAngles[3], int &iWeapon, int &iSubtype, int &iCmdnum, int &iTickcount, int &iSeed, int iMouse[2] ) {
	if( iButtons & IN_ATTACK2 && !( iOldButtons[iClient] & IN_ATTACK2 ) ) {
		if( bCanLeap[iClient] )
			PlayerLeap( iClient, flAngles );
	}
	iOldButtons[iClient] = iButtons;

	return Plugin_Continue;
}

void PlayerLeap( int iPlayer, float flAngles[3] ) {
	float flCharge = Tracker_GetValue( iPlayer, LEAPKEYNAME );
	if( flCharge != 100.0 ) {
		EmitGameSoundToClient( iPlayer, "Player.DenyWeaponSelection" );
		return;
	}

	float flPlayerVel[3];
	float flForwardVel[3];
	float flFinalVel[3];

	float flForce = 750.0;

	GetAngleVectors(flAngles, flForwardVel, NULL_VECTOR, NULL_VECTOR);
	
	flForwardVel[0] *= flForce;
	flForwardVel[1] *= flForce;
	flForwardVel[2] = FloatClamp( flForwardVel[2] * flForce, 260.0, 3000.0 );
		
	GetEntPropVector( iPlayer, Prop_Data, "m_vecVelocity", flPlayerVel );
	AddVectors( flPlayerVel, flForwardVel, flFinalVel );
	SetEntPropVector( iPlayer, Prop_Data, "m_vecAbsVelocity", flFinalVel );

	int iRandom = GetRandomInt( 1, 3 );

	static char szString[64];
	Format( szString, sizeof( szString ), "player/demo_charge_windup%i.wav", iRandom );
	EmitSoundToAll( szString, iPlayer );

	Tracker_SetValue( iPlayer, LEAPKEYNAME, 0.0 );
}