// ///////////////////// DEMODASH /////////////////////////////////////////
// ////////////////////////////////////////////////////////////////////////
// ////////////////////////////////////////////////////////////////////////

// DASH SOUNDS
#define SOUND1 "player/demo_charge_windup1.wav"
#define SOUND2 "player/demo_charge_windup2.wav"
#define SOUND3 "player/demo_charge_windup3.wav"
#define READYSOUND "player/recharged.wav"

// VALUES
#define DEFAULTFORCE "700"
#define DEFAULTHEIGHT "300"
#define DEFAULTMODE "0"
#define DEFAULTCOOLDOWN "5.0"
#define DEFAULTREADYSOUNDMODE "1"

// ////////////////////////////////////////////////////////////////////////
// ////////////////////////////////////////////////////////////////////////
// ////////////////////////////////////////////////////////////////////////

#include <sourcemod>
#include <sdktools>
#include <tf2c>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "DemoDash",
	author = "azzy",
	description = "Dashing for All Demoman Secondary Slot Wearables",
	version = "1.0",
	url = ""
}


Handle TimerHandle[MAXPLAYERS+1];
Handle ForceConvar;
Handle HeightConvar;
Handle JumpModeConvar;
Handle CooldownConvar;
Handle ReadySoundConvar;

bool InShieldDash[MAXPLAYERS+1];

public void OnPluginStart()
{
	ForceConvar = CreateConVar("demodash_force", DEFAULTFORCE, "speed");
	HeightConvar = CreateConVar("demodash_height", DEFAULTHEIGHT, "jump height");
	JumpModeConvar = CreateConVar("demodash_mode", DEFAULTMODE, "0 = fixed jump height, 1 = dynamic jump height based on X viewangle and jump force");
	CooldownConvar = CreateConVar("demodash_cooldown", DEFAULTCOOLDOWN, "Cooldown between dashes");
	ReadySoundConvar = CreateConVar("demodash_readysound", DEFAULTREADYSOUNDMODE, "play sound when dash recharges");


	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_spawn", OnPlayerSpawn);
	PrecacheSound(SOUND1);
	PrecacheSound(SOUND2);
	PrecacheSound(SOUND3);
	PrecacheSound(READYSOUND);
}

public void OnClientDisconnect(int client)
{
	if(TimerHandle[client])
	{
		KillTimer(TimerHandle[client]);
	}
}

void OnPlayerDeath(Event event, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(TimerHandle[client])
	{
		KillTimer(TimerHandle[client]);
	}
}

void OnPlayerSpawn(Event event, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	InShieldDash[client] = false;
}

// main thing

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3])
{
	if(!InShieldDash[client] && IsPlayerAlive(client))
		if(buttons & IN_ATTACK2) 
		{
			TFClassType PlayerClass = TF2_GetPlayerClass(client);

		 	if(PlayerClass == TFClass_DemoMan)
			{
				if(GetWeaponIndex(GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary)) == -1)
					ShieldDash(client, angles);
			}
		}
}

void ShieldDash(int client, float angles[3])
{
	InShieldDash[client] = true;
			
	float playervel[3];
	float forwardvel[3];
	float finalvel[3];

	float force = GetConVarFloat(ForceConvar);
	float height = GetConVarFloat(HeightConvar);

	GetAngleVectors(angles, forwardvel, NULL_VECTOR, NULL_VECTOR);
	
	forwardvel[0] *= force;
	forwardvel[1] *= force;

	if(GetConVarBool(JumpModeConvar))
		forwardvel[2] *= force; // dynamic jump height based on X viewangle

	else
		forwardvel[2] = height; // static jump height
		
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", playervel);
	AddVectors(playervel, forwardvel, finalvel);
		
	SetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", finalvel);

	TimerHandle[client] = CreateTimer(GetConVarFloat(CooldownConvar), ShieldDashRemove, client);
	PlayDashSound(client);
}

public Action ShieldDashRemove(Handle timer, int client)
{
	if(GetConVarBool(ReadySoundConvar))
		EmitSoundToClient(client, READYSOUND);

	InShieldDash[client] = false;
}

void PlayDashSound(int client)
{
	int randomnum = GetRandomInt(0, 2);

	switch(randomnum)
	{
		case 0:
			EmitSoundToAll(SOUND1, client);
		case 1:
			EmitSoundToAll(SOUND2, client);
		case 2:
			EmitSoundToAll(SOUND3, client);
	}
}

stock bool IsValidEnt(int ent)
{
    return ent > MaxClients && IsValidEntity(ent);
}

stock int GetWeaponIndex(int weapon)
{
    return IsValidEnt(weapon) ? GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"):-1;
}

