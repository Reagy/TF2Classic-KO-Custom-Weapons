#pragma newdecls required
#pragma semicolon 1

#include <tf2c>
#include <sourcemod>
#include <sdktools>
#include <kocwtools>
#include <dhooks>
#include <hudframework>

#define JUMPKEYNAME "Jumps"
#define MAX_JUMPS 10.0
#define DAMAGE_TO_JUMP 40.0
#define JUMPS_PER_KILL 2.0

DynamicDetour hCheckJumpButton;

float g_flDamageBuffer[ MAXPLAYERS + 1 ] = { 0.0, ... };
//bool g_bPlayerJumpaction[ MAXPLAYERS + 1 ] = { false, ... };
PlayerFlags g_pfJumpaction;

public Plugin myinfo = {
	name = "Attribute: Jump Action",
	author = "Noclue",
	description = "Attributes for Jump Action Shotgun",
	version = "1.1",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	hCheckJumpButton = DynamicDetour.FromConf( hGameConf, "CTFGameMovement::CheckJumpButton" );
	hCheckJumpButton.Enable( Hook_Post, Detour_CheckJumpButton );

	delete hGameConf;

	HookEvent( "post_inventory_application", Event_Inventory, EventHookMode_Post );
	HookEvent( "player_death", Event_PlayerDeath, EventHookMode_Post );
}

public Action Event_Inventory( Event hEvent, const char[] sName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	if( IsValidPlayer( iPlayer ) ) {
		if( AttribHookFloat( 0.0, iPlayer, "custom_jumpaction" ) != 0.0 ) {
			Tracker_Create( iPlayer, JUMPKEYNAME, false );
			Tracker_SetFlags( iPlayer, JUMPKEYNAME, RTF_CLEARONSPAWN );
			Tracker_SetMax( iPlayer, JUMPKEYNAME, MAX_JUMPS );
			g_pfJumpaction.Set( iPlayer, true );
		}
		else {
			Tracker_Remove( iPlayer, JUMPKEYNAME );
			g_pfJumpaction.Set( iPlayer, false );
		}
	}
	
	return Plugin_Continue;
}
public Action Event_PlayerDeath( Event hEvent, const char[] sName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "attacker" );
	iPlayer = GetClientOfUserId( iPlayer );

	int iKilled = hEvent.GetInt( "userid" );
	iKilled = GetClientOfUserId( iKilled );

	if( iPlayer != iKilled && IsValidPlayer( iPlayer ) )
		Tracker_SetValue( iPlayer, JUMPKEYNAME, FloatClamp( Tracker_GetValue( iPlayer, JUMPKEYNAME ) + JUMPS_PER_KILL, 0.0, MAX_JUMPS ) );

	return Plugin_Continue;
}	

MRESReturn Detour_CheckJumpButton( Address aThis, DHookReturn hReturn ) {
	int iPlayer = GetEntityFromAddress( DereferencePointer( aThis + address( 3752 ) ) ); //todo: move to gamedata
	if( iPlayer == -1 )
		return MRES_Ignored;

	if( !g_pfJumpaction.Get( iPlayer ) )
		return MRES_Ignored;

	if( GetEntPropEnt( iPlayer, Prop_Send, "m_hGroundEntity" ) != -1 )
		return MRES_Ignored;

	bool bOldDash = view_as< bool >( GetEntProp( iPlayer, Prop_Send, "m_bAirDash" ) );
	float flJumps = Tracker_GetValue( iPlayer, JUMPKEYNAME );

	SetEntProp( iPlayer, Prop_Send, "m_bAirDash", flJumps == 0.0 );

	if( flJumps != 0.0 && bOldDash) {
		Tracker_SetValue( iPlayer, JUMPKEYNAME, flJumps - 1.0 );
	}
		

	return MRES_Handled;
}

public void OnTakeDamageTF( int iTarget, TFDamageInfo tfDamageInfo ) {
	int iAttacker = tfDamageInfo.iAttacker;

	if( !IsValidPlayer( iAttacker ) )
		return;

	if( !g_pfJumpaction.Get( iAttacker ) )
		return;

	g_flDamageBuffer[ iAttacker ] += tfDamageInfo.flDamage;

	float flJumps = float( RoundToFloor( g_flDamageBuffer[ iAttacker ] / DAMAGE_TO_JUMP ) );
	if( flJumps > 0.0 ) {
		Tracker_SetValue( iAttacker, JUMPKEYNAME,  FloatClamp( Tracker_GetValue( iAttacker, JUMPKEYNAME ) + flJumps, 0.0, MAX_JUMPS )  );
		g_flDamageBuffer[ iAttacker ] -= ( flJumps * DAMAGE_TO_JUMP );
	}
}