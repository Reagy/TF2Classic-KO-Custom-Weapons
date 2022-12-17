#include <sourcemod>
#include <sdktools> 

#define WEAPON_HAGIS 7047

public void OnEntityCreated(int entity, const char[] classname)
{
	if(!(strcmp(classname, "tf_weapon_grenade_mirv_bomb")))
		RequestFrame(MirvProjectile, entity);
}

void MirvProjectile(int entity)
{
	switch(GetWeaponIndex(GetEntPropEnt(entity, Prop_Send, "m_hOriginalLauncher")))
	{
		case WEAPON_HAGIS:
			AcceptEntityInput(entity, "Kill");
	}
}

stock int GetWeaponIndex(int weapon)
{
    return IsValidEnt(weapon) ? GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"):-1;
}

stock bool IsValidEnt(int ent)
{
    return ent > MaxClients && IsValidEntity(ent);
}
