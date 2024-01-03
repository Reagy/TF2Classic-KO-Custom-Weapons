/**
 * =============================================================================
 * SourceMod PsychoStats Plugin
 * Skill tracking in real-time in-game. Whenever player is skilled the skill
 * change is announced for both victim and killer. When player joins his skill
 * is announced publicly.
 *
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Version: $Id: ps_mapfix.sp 411 2008-04-23 18:07:12Z lifo $
 * Author: k1ller
 */

new Handle:hDatabase = INVALID_HANDLE;
new Handle:hSkills = INVALID_HANDLE;

public Plugin:myinfo =
{
        name = "PsychoStats - Skill Announce",
        author = "k1ller",
        description = "PsychoStats real-time skill change tracker in-game",
        version = "1.0"
};

public OnPluginStart()
{
 LoadTranslations("ps_skillannounce.phrases");
 HookEvent("player_connect", Event_PlayerConnect)
 HookEvent("player_death", Event_PlayerDeath)
 HookEvent("player_info", Event_PlayerInfo)
 StartSQL()
 hSkills = CreateKeyValues("Skills");
}

public StartSQL()
{
	SQL_TConnect(GotDatabase, "psychostats");
}
 
public GotDatabase(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		LogError("Database failure: %s", error);
	} else {
		hDatabase = hndl;
	}
}

public Action:Event_PlayerInfo(Handle:event, const String:name[], bool:dontBroadcast)
{
 new String:plrName[64]
 GetEventString(event, "name", plrName, sizeof(plrName))
 KvSetFloat(hSkills, plrName, 50.0)
 PrintToServer("Setting name skill for %s", plrName)
 return Plugin_Continue
}

public Action:Event_PlayerConnect(Handle:event, const String:name[], bool:dontBroadcast)
{
 new String:plrName[64]
 GetEventString(event, "name", plrName, sizeof(plrName))
 KvSetFloat(hSkills, plrName, 50.0)
 GetSkill(plrName)
 return Plugin_Continue
}

public GetSkill(const String:plrName[])
{
	decl String:query[255]
	Format(query, sizeof(query), "SELECT skill, '%s' AS plrName FROM ps_plr WHERE uniqueid LIKE '%s'", plrName, plrName);
	SQL_TQuery(hDatabase, T_GetSkill, query)
}
 
public T_GetSkill(Handle:owner, Handle:query, const String:error[], any:data)
{
	new Float:plrSkill = 50.0
	new String:plrName[64]

	if (query == INVALID_HANDLE)
	{
		LogError("Query failed! %s", error)
	} else if (SQL_GetRowCount(query)) {
		SQL_FetchRow(query)
		plrSkill = SQL_FetchFloat(query, 0)
		SQL_FetchString(query, 1, plrName, sizeof(plrName))
	}
	KvSetFloat(hSkills, plrName, plrSkill)
	if(strlen(plrName) != 0)
	{
		AnnounceJoin(plrName, plrSkill)
	}
}

public AnnounceJoin(const String:plrName[], const Float:skill)
{
 PrintHintTextToAll("%t", "Joined", plrName, skill) 
 PrintToServer("%t", "Joined", plrName, skill) 
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
 new victim_id = GetEventInt(event, "userid")
 new attacker_id = GetEventInt(event, "attacker")

 /* Return if suicide */
 if (victim_id == attacker_id) 
	return Plugin_Continue

 new victim = GetClientOfUserId(victim_id)
 new attacker = GetClientOfUserId(attacker_id)

 /* Return if team kill */
 if (GetClientTeam(victim) == GetClientTeam(attacker))
	return Plugin_Continue

 /* Get both players' name */
 new String:kname[64]
 new String:vname[64]
 GetClientName(attacker, kname, sizeof(kname))
 GetClientName(victim, vname, sizeof(vname))

 // Get current skills from KV table
 new Float:vskill = KvGetFloat(hSkills, vname, 50.0)
 new Float:kskill = KvGetFloat(hSkills, kname, 50.0)

 new Float:kbonus = 1.0
 new Float:vbonus = 1.0

 if (kskill > vskill) {
  // killer is better than the victim
  kbonus = Pow((kskill + vskill),2.0) / Pow(kskill,2.0);
  vbonus = kbonus * vskill / (vskill + kskill);
 } else {
  // the victim is better than the killer
  kbonus = Pow((vskill + kskill),2.0) / Pow(vskill,2.0) * vskill / kskill;
  vbonus = kbonus * (vskill + 50) / (vskill + kskill);
 }

 if (kbonus > 10.0) kbonus = 10.0 
 if (vbonus > 10.0) vbonus = 10.0

 if (kbonus > kskill) kbonus = kskill
 if (vbonus > vskill) vbonus = 1.0

 KvSetFloat(hSkills, kname, kskill+kbonus)
 KvSetFloat(hSkills, vname, vskill-vbonus)

 kskill = RoundToNearest(((kskill+kbonus) * 100)) / 100.0
 vskill = RoundToNearest(((vskill-vbonus) * 100)) / 100.0
 kbonus = RoundToNearest((kbonus * 100)) / 100.0
 vbonus = RoundToNearest((vbonus * 100)) / 100.0

 PrintToServer("%t", "Killer", kname, kbonus, kskill, vname, vbonus, vskill)
 PrintToConsole(victim, "%t", "Victim", kname, kbonus, kskill, vname, vbonus, vskill)
 PrintToConsole(attacker, "%t", "Killer", kname, kbonus, kskill, vname, vbonus, vskill)
 return Plugin_Continue
}
