#pragma semicolon 1
#include <sourcemod>
#include <sdktools>

/////////////////////////////////////////////////////////////
////////////////////////    SETUP    ////////////////////////
/////////////////////////////////////////////////////////////

#define PL_VERSION "1"

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

public void OnMapStart()
{
    CreateTimer(5.0, ChangeCvar);
}

public Action ChangeCvar(Handle Timer)
{
    // ServerCommand("sv_visiblemaxplayers 26"); // change 24 to whatever

    Handle cvar = FindConVar("sv_visiblemaxplayers");
    SetConVarInt(cvar, 26); // change 24 to whatever
    PrintToServer("[TF2C] Override Max Visible Slots: sv_visiblemaxplayers has been changed");
}  