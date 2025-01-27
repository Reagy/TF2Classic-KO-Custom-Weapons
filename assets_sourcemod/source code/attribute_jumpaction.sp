#pragma newdecls required
#pragma semicolon 1

#include <tf2c>
#include <sourcemod>
#include <sdktools>
#include <kocwtools>
#include <dhooks>
#include <hudframework>

//todo: convert to string var
#define MAX_JUMPS 10.0
#define DAMAGE_TO_JUMP 40.0
#define JUMPS_PER_KILL 2.0

static char szJumpKeyName[] = "Jumps";

DynamicDetour hCheckJumpButton;

int g_iMovementTFPlayerOffset = -1;

float g_flDamageBuffer[ MAXPLAYERS + 1 ] = { 0.0, ... };
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

	hCheckJumpButton = DynamicDetourFromConfSafe( hGameConf, "CTFGameMovement::CheckJumpButton" );
	hCheckJumpButton.Enable( Hook_Post, Detour_CheckJumpButton );

	g_iMovementTFPlayerOffset = GameConfGetOffsetSafe( hGameConf, "CTFGameMovement::m_pTFPlayer" );

	delete hGameConf;

	HookEvent( "post_inventory_application", Event_Inventory, EventHookMode_Post );
	HookEvent( "player_death", Event_PlayerDeath, EventHookMode_Post );
}

public Action Event_Inventory( Event hEvent, const char[] sName, bool bDontBroadcast ) {
	int iPlayer = hEvent.GetInt( "userid" );
	iPlayer = GetClientOfUserId( iPlayer );

	if( IsValidPlayer( iPlayer ) ) {
		float flVal = AttribHookFloat( 0.0, iPlayer, "custom_jumpaction" );

		
		static char szBuffer[64];
		int wpn = GetEntPropEnt( iPlayer, Prop_Send, "m_hActiveWeapon" );
		GetEntityClassname( wpn, szBuffer, sizeof(szBuffer) );
		PrintToServer(szBuffer);
		

		char szTest[64] = "";
		//AttribHookString( szTest, sizeof(szTest), wpn, "custom_projectile_model" );
		AttribHookString( szTest, sizeof(szTest), wpn, "custom_projectile_model" );
		PrintToServer("output %s", szTest);

		if( flVal != 0.0 ) {
			Tracker_Create( iPlayer, szJumpKeyName, false );
			Tracker_SetFlags( iPlayer, szJumpKeyName, RTF_CLEARONSPAWN );
			Tracker_SetMax( iPlayer, szJumpKeyName, MAX_JUMPS );
			g_pfJumpaction.Set( iPlayer, true );
		}
		else {
			Tracker_Remove( iPlayer, szJumpKeyName );
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
		Tracker_SetValue( iPlayer, szJumpKeyName, FloatClamp( Tracker_GetValue( iPlayer, szJumpKeyName ) + JUMPS_PER_KILL, 0.0, MAX_JUMPS ) );

	return Plugin_Continue;
}	

MRESReturn Detour_CheckJumpButton( Address aThis, DHookReturn hReturn ) {
	int iPlayer = GetEntityFromAddress( DereferencePointer( aThis + view_as<Address>( g_iMovementTFPlayerOffset ) ) ); //todo: move to gamedata
	if( iPlayer == -1 )
		return MRES_Ignored;

	if( !g_pfJumpaction.Get( iPlayer ) )
		return MRES_Ignored;

	if( GetEntPropEnt( iPlayer, Prop_Send, "m_hGroundEntity" ) != -1 )
		return MRES_Ignored;

	bool bOldDash = view_as< bool >( GetEntProp( iPlayer, Prop_Send, "m_bAirDash" ) );
	int iJumps = RoundToFloor( Tracker_GetValue( iPlayer, szJumpKeyName ) );

	SetEntProp( iPlayer, Prop_Send, "m_bAirDash", iJumps == 0 );

	if( iJumps != 0 && bOldDash) {
		Tracker_SetValue( iPlayer, szJumpKeyName, float( iJumps - 1 ) );
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
		float flNewVal = FloatClamp( Tracker_GetValue( iAttacker, szJumpKeyName ) + flJumps, 0.0, MAX_JUMPS );
		Tracker_SetValue( iAttacker, szJumpKeyName, flNewVal );
		g_flDamageBuffer[ iAttacker ] -= ( flJumps * DAMAGE_TO_JUMP );
	}
}