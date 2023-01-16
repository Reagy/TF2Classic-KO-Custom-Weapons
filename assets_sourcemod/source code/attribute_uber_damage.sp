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
	version = "1.1",
	url = "no"
}

bool bLateLoad = false;
public APLRes AskPluginLoad2( Handle hMyself, bool bLate, char[] error, int err_max ) {
	bLateLoad = bLate;

	return APLRes_Success;
}

public void OnPluginStart() {
	if( bLateLoad ) {
		for(int i = 1; i < MaxClients; i++) {
			if( IsValidEntity( i ) ) {
				SDKHook( i, SDKHook_OnTakeDamage, Hook_TakeDamageUber );
			}
		}
	}
}

public void OnEntityCreated( int iEntity, const char[] sClassname ) {
	if( strcmp( sClassname, "player" ) == 0 ) {
		SDKHook( iEntity, SDKHook_OnTakeDamage, Hook_TakeDamageUber );
	}
}

public Action Hook_TakeDamageUber( int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom ) {
	/* 
		so for reasons beyond any mortal comprehension sometimes entity indexes come in at 4096 indices higher than they're supposed to
		i can't even begin to process why this would happen in the first place so we'll just do this instead
	*/
	if(weapon >= 4096) weapon -= 4096;
	if(attacker >= 4096) attacker -= 4096;
	if(inflictor >= 4096) inflictor -= 4096;

	if( !IsValidEntity( weapon ) ) return Plugin_Changed; //can't return plugin_continue because it will try to return the original broken indexes

	float flUberScale = AttribHookFloat( 0.0, weapon, "custom_uber_scales_damage" );
	if( flUberScale == 0.0 ) return Plugin_Changed;

	float flUbercharge = GetMedigunCharge( attacker );
	if( flUbercharge < 0.1) flUbercharge = 0.1; 

	damage *= flUbercharge;
	
	return Plugin_Changed;
}