#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <kocwtools>

#include <stocksoup/memory>

DynamicDetour	dRocketSpawn;

public Plugin myinfo =
{
	name = "Bug Fix: Rocket Lifetime",
	author = "Noclue",
	description = "Fixes issue with rocket lifetime attribute.",
	version = "1.1",
	url = "no"
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	dRocketSpawn = DynamicDetour.FromConf( hGameConf, "CTFBaseRocket::Spawn" );
	if( !dRocketSpawn.Enable( Hook_Post, Detour_SpawnPost ) ) {
		SetFailState( "Detour for CTFRocketBase::Spawn failed." );
	}

	delete hGameConf;
}

MRESReturn Detour_SpawnPost( int iThis ) {
	int iLauncher = GetEntPropEnt( iThis, Prop_Send, "m_hLauncher" );
	if( !IsValidEntity( iLauncher ) ) return MRES_Ignored;

	static char sBuffer[64];
	float flRocketTime = 0.0;

	GetEntityClassname( iLauncher, sBuffer, 64 );
	if( strcmp(sBuffer, "obj_sentrygun") == 0 ) {
		flRocketTime = -1;
	}
	else {
		flRocketTime = AttribHookFloat( 0.0, iLauncher, "rocket_lifetime" );
		flRocketTime = flRocketTime == 0.0 ? -1 : GetGameTime() + flRocketTime;
	}
	SetNextThink( iThis, flRocketTime, "Detonate" );

	return MRES_Handled;
}