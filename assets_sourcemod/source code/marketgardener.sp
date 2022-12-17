#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2c>

/*  -----------------------
	ELIGIBLE ITEMS
----------------------- */
int WeaponList[] = {
	3445, // TF_WEAPON_MARKET_GARDENER
	3455, // TF_WEAPON_CABER
	7046 // TF_WEAPON_RAINMAKER
};

// /////////////////////   //////////////////////////////////////////////////// //
// ///////    ////////////////////////////////////////     //////////////////// //
// ///////////////////////////// stuff  /////////////////////////////////////// //
// ///////////////////////////////////////////////////////////////   ////////// //
// //////////////   /////////////////////////////////////////////////////////// //

int MGCrit[MAXPLAYERS+1];
int ActiveWeapon[MAXPLAYERS+1];
int ActiveWeaponEligible[MAXPLAYERS+1];
int WasOnGroundLastTime[MAXPLAYERS+1];
int WeaponListSize = sizeof(WeaponList);

public Plugin:myinfo = 
{
	name = "Market Gardener for TF2Classic",
	author = "azzy",
	description = "im terrible at sourcemod please don't hate me",
	version = "1.0",
	url = ""
}

public OnPluginStart()
{
	HookEvent("rocket_jump", Jumped);
	HookEvent("sticky_jump", Jumped);

	HookEvent("rocket_jump_landed", Landed);
	HookEvent("sticky_jump_landed", Landed);

	// fix keeping crit when spawning
	HookEvent("player_death", Landed);
	HookEvent("player_spawn", Landed);
}


/*  -----------------------
	stocks (not stolen)
----------------------- */
stock bool:IsValidEnt(iEnt)
{
    return iEnt > MaxClients && IsValidEntity(iEnt);
}

stock GetWeaponIndex(iWeapon)
{
    return IsValidEnt(iWeapon) ? GetEntProp(iWeapon, Prop_Send, "m_iItemDefinitionIndex"):-1;
}


/*  -----------------------
	add crit on rocket jump
----------------------- */
public Action:Jumped(Handle:event, const String:name[], bool:dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	MGCrit[client] = 1;
}

/*  -----------------------
	remove crit on landing
----------------------- */
public Action:Landed(Handle:event, const String:name[], bool:dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	TF2_RemoveCondition(client, TFCond:33);
	MGCrit[client] = 0;
}


/*  -----------------------
	ON GAME FRAME
----------------------- */

public OnGameFrame()
{
	for(int client = 1; client <= MaxClients; client++)
	{
		if( IsValidEntity(client) && IsClientInGame(client) && IsPlayerAlive(client) )
		{
			/*  --------------------
				get player weapon
			----------------------- */
			ActiveWeapon[client] = GetWeaponIndex(GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"));

			/*  --------------------
				weapon check
			----------------------- */
			if(MGCrit[client])
			{
				ActiveWeaponEligible[client] = 0;

				for(int i = 0; i < WeaponListSize; i++)
					if(ActiveWeapon[client] == WeaponList[i])
						ActiveWeaponEligible[client] = 1;

				if(ActiveWeaponEligible[client])
					TF2_AddCondition(client, TFCond:33, TFCondDuration_Infinite);

				else
					TF2_RemoveCondition(client, TFCond:33); // remove if switching weapons
			}

			/*  --------------------
				prevent bunnyhopping
			----------------------- */
			WasOnGroundLastTime[client] = (GetEntityFlags(client) & FL_ONGROUND);

			if(WasOnGroundLastTime[client])
			{
				MGCrit[client] = 0;
				TF2_RemoveCondition(client, TFCond:33);
			}
		}
	}
}
