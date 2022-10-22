#define WEAPON_DISPLACER 9033

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2c>

public void OnPluginStart()
{
	AddNormalSoundHook(Hook_EntitySound);
	
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			OnClientPutInServer(i);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(!(strcmp(classname, "tf_projectile_coil")))
		SetEntProp(entity, Prop_Send, "m_nForceBone", 0);
}

public Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damageType, int& weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	char classname[32];
	GetEntityClassname(inflictor, classname, 32);

	if(strcmp(classname, "tf_projectile_coil") == 0)
	{
		if(GetWeaponIndex(weapon) == WEAPON_DISPLACER)
			switch(GetEntProp(inflictor, Prop_Send, "m_nForceBone"))
			{
				case 1:
				{
					damage += 15;
					DealMiniCrit(victim);
					return Plugin_Changed;
				}
				case 2:
				{
					damage += 30;
					damageType |= DMG_ACID;
					damageType |= DMG_ALWAYSGIB;
					return Plugin_Changed;
				}
			}
	}

	return Plugin_Continue;
}

void DealMiniCrit(int victim)
{
	if (!TF2_IsPlayerInCondition(victim, TFCond_MarkedForDeath))
	{
		TF2_AddCondition(victim, TFCond_MarkedForDeath);
		SDKHook(victim, SDKHook_OnTakeDamagePost, Hook_RemoveMinicrits);
	}
}

public Action Hook_RemoveMinicrits(int victim)
{
	SDKUnhook(victim, SDKHook_OnTakeDamagePost, Hook_RemoveMinicrits);
	TF2_RemoveCondition(victim, TFCond_MarkedForDeath);
}

public Action Hook_EntitySound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if(StrContains(sample, "railgun_ric", false) >= 0)
	{
		int ricochets = GetEntProp(entity, Prop_Send, "m_nForceBone");
		SetEntProp(entity, Prop_Send, "m_nForceBone", ricochets + 1);
	}
	return Plugin_Continue;
}

stock int GetWeaponIndex(int weapon)
{
    return IsValidEnt(weapon) ? GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"):-1;
}

stock bool IsValidEnt(int ent)
{
    return ent > MaxClients && IsValidEntity(ent);
}