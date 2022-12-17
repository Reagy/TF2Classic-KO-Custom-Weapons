#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <tf2c>
#include <dhooks>
#include <kocwtools>

#include <stocksoup/memory>

DynamicDetour hPlayerBurn;

#define TF_BURNING_FLAME_LIFE_PYRO	0.25
#define TF_BURNING_FLAME_LIFE		10.0

public Plugin myinfo =
{
	name = "Bug Fix: Afterburn Source",
	author = "Noclue",
	description = "Fixes issue with afterburn source.",
	version = "1.0",
	url = "no"
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	hPlayerBurn = DynamicDetour.FromConf( hGameConf, "CTFPlayerShared::Burn" );
	hPlayerBurn.Enable( Hook_Post, Detour_Burn );
}

//void CTFPlayerShared::Burn( CTFPlayer *pAttacker, CTFWeaponBase *pWeapon /*= NULL*/, float flFlameDuration /*= -1.0f*/ )
MRESReturn Detour_Burn( Address pThis, DHookParam hParams ) {
	int iPlayer = GetPlayerFromShared( pThis );
	int iWeapon = view_as<int>( hParams.Get( 2 ) );

	bool bVictimIsPyro = TF2_GetPlayerClass( iPlayer ) == TFClass_Pyro;
	float flFlameLife = bVictimIsPyro ? TF_BURNING_FLAME_LIFE_PYRO : TF_BURNING_FLAME_LIFE;
	flFlameLife = AttribHookFloat( flFlameLife, iWeapon, "mult_wpn_burntime" );

	SetEntPropFloat( iPlayer, Prop_Send, "m_flFlameRemoveTime", GetGameTime() + flFlameLife );
	return MRES_Handled;
}