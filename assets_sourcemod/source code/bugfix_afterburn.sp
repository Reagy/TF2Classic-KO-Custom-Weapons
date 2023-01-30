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
	version = "1.2",
	url = "no"
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	hPlayerBurn = DynamicDetour.FromConf( hGameConf, "CTFPlayerShared::Burn" );
	if( !hPlayerBurn.Enable( Hook_Post, Detour_Burn ) ) {
		SetFailState("Detour for CTFPlayerShared::Burn failed");
	}
}

//void CTFPlayerShared::Burn( CTFPlayer *pAttacker, CTFWeaponBase *pWeapon /*= NULL*/ )
MRESReturn Detour_Burn( Address pThis, DHookParam hParams ) {
	int iPlayer = GetPlayerFromShared( pThis );
	int iWeapon = view_as<int>( hParams.Get( 2 ) );

	float flFlameLife = TF_BURNING_FLAME_LIFE;
	if( TF2_GetPlayerClass( iPlayer ) == TFClass_Pyro && AttribHookFloat( 0.0, iWeapon, "custom_burn_pyro" ) == 0.0 )
		flFlameLife = TF_BURNING_FLAME_LIFE_PYRO;		

	flFlameLife = AttribHookFloat( flFlameLife, iWeapon, "mult_wpn_burntime" );

	float flNewRemoveTime = GetGameTime() + flFlameLife;
	if( flNewRemoveTime > GetEntPropFloat( iPlayer, Prop_Send, "m_flFlameRemoveTime" ) )
		SetEntPropFloat( iPlayer, Prop_Send, "m_flFlameRemoveTime", flNewRemoveTime );

	return MRES_Handled;
}