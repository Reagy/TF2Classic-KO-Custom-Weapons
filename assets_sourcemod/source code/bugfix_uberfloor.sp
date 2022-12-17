#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <tf2c>
#include <dhooks>
#include <kocwtools>

#include <stocksoup/memory>

DynamicDetour hApplyOnHit;

public Plugin myinfo =
{
	name = "Bug Fix: Uber Floor",
	author = "Noclue",
	description = "Fixes negative ubercharge values.",
	version = "1.0",
	url = "no"
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	hApplyOnHit = DynamicDetour.FromConf( hGameConf, "CTFWeaponBase::ApplyOnHitAttributes" );
	hApplyOnHit.Enable( Hook_Post, Detour_OnHit );
}

//void CTFPlayerShared::Burn( CTFPlayer *pAttacker, CTFWeaponBase *pWeapon /*= NULL*/, float flFlameDuration /*= -1.0f*/ )
MRESReturn Detour_OnHit( int iThis, DHookParam hParams ) {
	int iPlayer = GetEntPropEnt( iThis, Prop_Send, "m_hOwnerEntity" );
	int iMedigun = GetEntityInSlot( iPlayer, 1 );

	if( !IsValidEntity( iMedigun ) || !HasEntProp( iMedigun, Prop_Send, "m_flChargeLevel") )
		return MRES_Ignored;

	float flCharge = GetEntPropFloat( iMedigun, Prop_Send, "m_flChargeLevel" );
	if(flCharge < 0.0) SetEntPropFloat( iMedigun, Prop_Send, "m_flChargeLevel", 0.0 );

	return MRES_Handled;
}