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
	version = "1.1",
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

	//it should be safe to do attribute checks without verification since pWeapon MUST be a CTFWeaponBase
	flFlameLife = AttribHookFloat( flFlameLife, iWeapon, "mult_wpn_burntime" );

	SetEntPropFloat( iPlayer, Prop_Send, "m_flFlameRemoveTime", GetGameTime() + flFlameLife );
	return MRES_Handled;
}