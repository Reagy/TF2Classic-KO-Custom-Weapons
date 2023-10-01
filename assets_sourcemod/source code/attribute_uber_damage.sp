#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <dhooks>
#include <kocwtools>

public Plugin myinfo =
{
	name = "Attribute: Uber Damage Scale",
	author = "Noclue",
	description = "Ubercharge Damage attribute.",
	version = "2.0",
	url = "no"
}

public void OnTakeDamageTF( int iTarget, Address aTakeDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aTakeDamageInfo );
	if( AttribHookFloat( 0.0, tfInfo.iWeapon, "custom_uber_scales_damage" ) == 0.0 ) 
		return;

	float flUbercharge = MaxFloat( 0.1, GetMedigunCharge( tfInfo.iAttacker ) );
	tfInfo.flDamage *= flUbercharge;
}