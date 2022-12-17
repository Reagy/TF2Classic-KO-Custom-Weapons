#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <kocwtools>

#include <stocksoup/memory>

DynamicDetour 	hRocketSpawn;

public Plugin myinfo =
{
	name = "Bug Fix: Rocket Lifetime",
	author = "Noclue",
	description = "Fixes issue with rocket lifetime attribute.",
	version = "1.0",
	url = "no"
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	hRocketSpawn = DynamicDetour.FromConf( hGameConf, "CTFBaseRocket::Spawn" );
	if( !hRocketSpawn.Enable( Hook_Post, Detour_SpawnPost ) ) {
		SetFailState( "Detour setup for CTFBaseRocket::Spawn failed" );
	}
}

MRESReturn Detour_SpawnPost( int iThis ) {
	int iLauncher = GetEntPropEnt( iThis, Prop_Send, "m_hLauncher");
	if( IsValidEntity( iLauncher ) ) {
		float flRocketTime = AttribHookFloat( 0.0, iLauncher, "rocket_lifetime" );
		float flNextTime = flRocketTime == 0.0 ? -1 : GetGameTime() + flRocketTime;
		SetNextThink( iThis, flNextTime, "Detonate" );
	}

	return MRES_Handled;
}