#pragma semicolon 1
#include <sourcemod>
#include <sdktools>

/////////////////////////////////////////////////////////////
////////////////////////    SETUP    ////////////////////////
/////////////////////////////////////////////////////////////

#define PL_VERSION "1.3"

public Plugin:myinfo = 
{
    name = "[TF2C] Override Max Visible Slots",
    author = "Reagy",
    description = "Changes max visible slots because fuck you I guess???",
    version = PL_VERSION,
    url = "https://tf2c.knockout.chat/"
}

/////////////////////////////////////////////////////////////
//////////////////////    CODE LOL    ///////////////////////
/////////////////////////////////////////////////////////////

// Brute force this shit seriously...

public OnPluginStart()
{
    HookEvent("teamplay_round_start", RoundStart);
    HookEvent("player_disconnect", PlayerDisconnect_Event); 
}

public RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
    CreateTimer(10.0, ChangeCvar);
}

// Brute force this shit seriously...

public void OnMapStart()
{
    CreateTimer(10.0, ChangeCvar);
}

// FUCK GSCRAMBLE

public Action:PlayerDisconnect_Event(Handle:event, const String:name[], bool:dontBroadcast) 
{
    CreateTimer(1.0, ChangeCvar);
} 

// FUCK GSCRAMBLE

public Action ChangeCvar(Handle Timer)
{
    // ServerCommand("sv_visiblemaxplayers 26"); // change 24 to whatever
    Handle cvar = FindConVar("sv_visiblemaxplayers");
    SetConVarInt(cvar, 26); // change 24 to whatever
    PrintToServer("[TF2C] Override Max Visible Slots: sv_visiblemaxplayers has been changed");
}