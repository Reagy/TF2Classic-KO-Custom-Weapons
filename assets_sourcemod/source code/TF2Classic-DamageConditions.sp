#include <tf2c>
#include <sdkhooks>
#include <sdktools>
#include <anymap>

#pragma newdecls required
#pragma semicolon 1;

bool isPlayerInvulnerable[MAXPLAYERS+1];

enum struct WeaponData
{
	TFCond Cond;
	int CritType;
	int Mode;
	int Gib;
	TFCond AddCond;
	float AddCondDuration;
	TFCond AddCondSelf;
	float AddCondDurationSelf;
}

#define DATAMAXSIZE sizeof(WeaponData)

#define DMG_AFTERBURN 2056 // ??????????
#define DMG_BLEEDING DMG_SLASH

AnyMap WeaponMap;

public Plugin myinfo = 
{
	name = "TF2Classic-DamageConditions",
	author = "azzy",
	description = "Expansion upon TF2Classic's condition related attributes",
	version = "2.1.4096",
	url = ""
}

public void OnPluginStart()
{
	WeaponMap = new AnyMap();
	
	ParseConfig();

	RegConsoleCmd("sm_damageconditions_reload", ReloadCommandHandler, "Reload configuration file");

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			OnClientPutInServer(i);
}

public void OnClientPutInServer(int client) 
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damageType, int& weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	/* 
		so for reasons beyond any mortal comprehension sometimes entity indexes come in at 4096 indices higher than they're supposed to
		i can't even begin to process why this would happen in the first place so we'll just do this instead
	*/
	if(weapon > 4096) weapon -= 4096;
	if(attacker > 4096) attacker -= 4096;
	if(inflictor > 4096) inflictor -= 4096;

	if(weapon == -1)
		return Plugin_Changed;

	int weaponIndex;

	char classname[16];
	GetEntityClassname(weapon, classname, 16);

	if(strcmp(classname, "obj_sentrygun") == 0)
		weaponIndex = GetWeaponIndex(GetPlayerWeaponSlot(attacker, TFWeaponSlot_Grenade));
	else
		weaponIndex = GetWeaponIndex(weapon);
	
	WeaponData Data;

	if(WeaponMap.GetArray(weaponIndex, Data, DATAMAXSIZE))
	{
		if(damageType & ~DMG_AFTERBURN && damageType & ~DMG_BLEEDING)
		{
			if(CondCheckType(victim, attacker, Data.Mode, Data.Cond))
			{
				switch(Data.CritType)
				{
					case 1:	// minicrit
						if (!TF2_IsPlayerInCondition(victim, TFCond_MarkedForDeath))
						{
							TF2_AddCondition(victim, TFCond_MarkedForDeath);
							SDKHook(victim, SDKHook_OnTakeDamagePost, Hook_RemoveMinicrits);
						}

					case 2: // crit
						damageType |= DMG_ACID;
				}
			}

			switch(Data.Gib)
			{
				case 1: 
					damageType |= DMG_ALWAYSGIB;
				case 2: 
					damageType |= DMG_NEVERGIB;
			}

			if(!isPlayerInvulnerable[victim])
			{
				if(Data.AddCondSelf)
					TF2_AddCondition(attacker, Data.AddCondSelf, Data.AddCondDurationSelf);

				if(Data.AddCond)
					TF2_AddCondition(victim, Data.AddCond, Data.AddCondDuration);
			}

			return Plugin_Changed;
		}
	}

	return Plugin_Changed;
}

Action Hook_RemoveMinicrits(int victim)
{
	SDKUnhook(victim, SDKHook_OnTakeDamagePost, Hook_RemoveMinicrits);
	TF2_RemoveCondition(victim, TFCond_MarkedForDeath);
}

public Action ReloadCommandHandler(int client, int args)
{
	PrintToServer("[TF2Classic-DamageConditions] Reloading...");
	ParseConfig();
}

stock bool IsValidEnt(int ent)
{
    return ent > MaxClients && IsValidEntity(ent);
}

stock bool CondCheckType(int victim, int attacker, int mode, TFCond cond)
{
	switch(mode)
	{
		case 0:
			return false;
		case 1:
			return TF2_IsPlayerInCondition(attacker, cond);
		case 2:
			return TF2_IsPlayerInCondition(victim, cond);
	}

	return false; // so it stops whining
}

stock int GetWeaponIndex(int weapon)
{
    return IsValidEnt(weapon) ? GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"):-1;
}

public void TF2_OnConditionAdded(int client, TFCond condition) {
	switch(condition)
	{
		case 5, 8, 51, 52, 57:
			isPlayerInvulnerable[client] = true;
	}
}

public void TF2_OnConditionRemoved(int client, TFCond condition) {
	switch(condition)
	{
		case 5, 8, 51, 52, 57:
			isPlayerInvulnerable[client] = false;
	}
}

// config parser

void ParseConfig()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/TF2Classic-DamageConditions.cfg");

	if(!FileExists(path)) 
		SetFailState("[TF2Classic-DamageConditions] Configuration file not found: %s", path);

	KeyValues kv = new KeyValues("Weapons");

	if(!kv.ImportFromFile(path))
		SetFailState("[TF2Classic-DamageConditions] Unable to parse configuration file");

	if(!kv.GotoFirstSubKey())
		SetFailState("[TF2Classic-DamageConditions] No weapons listed");
	
	do
	{
		WeaponData Data;
		
		char weapon[5];
		if(!kv.GetSectionName(weapon, sizeof(weapon)))
			SetFailState("Invalid Configuration File");
		
		int weaponid = StringToInt(weapon);

		char tempstring[32];

		kv.GetString("mode", tempstring, sizeof(tempstring), "none");
		if(strcmp(tempstring, "victim"))
			Data.Mode = 1;
		else if(strcmp(tempstring, "attacker"))
			Data.Mode = 2;
		else
			Data.Mode = 0;

		Data.Cond = view_as<TFCond>(kv.GetNum("cond", -1));

		kv.GetString("crittype", tempstring, sizeof(tempstring), "none");
		if(!strcmp(tempstring, "minicrit"))
			Data.CritType = 1;
		else if(!strcmp(tempstring, "crit"))
			Data.CritType = 2;
		else
			Data.CritType = 0;

		kv.GetString("gib", tempstring, sizeof(tempstring), "default");
		if(!strcmp(tempstring, "always"))
			Data.Gib = 1;
		else if(!strcmp(tempstring, "never"))
			Data.Gib = 2;
		else
			Data.Gib = 0;

		if(kv.JumpToKey("addcond"))
		{
			Data.AddCond = view_as<TFCond>(kv.GetNum("cond", -1));
			Data.AddCondDuration = kv.GetFloat("duration");
			kv.GoBack();
		}
		
		if(kv.JumpToKey("addcond_self"))
		{
			Data.AddCondSelf = view_as<TFCond>(kv.GetNum("cond", -1));
			Data.AddCondDurationSelf = kv.GetFloat("duration");
			kv.GoBack();
		}

		if(weaponid < 0)
			SetFailState("[TF2Classic-DamageConditions] WARNING: Invalid Weapon ID");

		if(Data.Cond < view_as<TFCond>(-1) || Data.Cond > view_as<TFCond>(127))
			SetFailState("[TF2Classic-DamageConditions] WARNING: Weapon ID %d has invalid Cond Value", weaponid);

		if(Data.CritType != 0 && Data.CritType != 1 && Data.CritType != 2)
			SetFailState("[TF2Classic-DamageConditions] WARNING: Weapon ID %d has invalid Crit Type", weaponid);

		if(Data.Mode != 0 && Data.Mode != 1 && Data.Mode != 2 && Data.Mode != 3)
			SetFailState("[TF2Classic-DamageConditions] WARNING: Weapon ID %d has invalid Crit Check Mode", weaponid);
		
		if(Data.AddCond < view_as<TFCond>(0) || Data.AddCond > view_as<TFCond>(127))
			SetFailState("[TF2Classic-DamageConditions] WARNING: Weapon ID %d has invalid Add Cond Value", weaponid);
		
		if(Data.AddCondDuration < 0)
			SetFailState("[TF2Classic-DamageConditions] WARNING: Weapon ID %d has invalid Add Cond Duration Value", weaponid);
	
		if(Data.AddCondSelf < view_as<TFCond>(0) || Data.AddCondSelf > view_as<TFCond>(127))
			SetFailState("[TF2Classic-DamageConditions] WARNING: Weapon ID %d has invalid Add Cond Value", weaponid);
		
		if(Data.AddCondDurationSelf < 0)
			SetFailState("[TF2Classic-DamageConditions] WARNING: Weapon ID %d has invalid Add Cond Duration Value", weaponid);
		
		WeaponMap.SetArray(weaponid, Data, DATAMAXSIZE);

		PrintToServer("[TF2Classic-DamageConditions] Weapon ID %d parsed", weaponid);
	}
	while(kv.GotoNextKey());
	
	delete kv;
}

