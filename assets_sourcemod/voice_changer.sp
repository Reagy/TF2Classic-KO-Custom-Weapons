/**
 * ==============================================================================
 * Voice Changer!
 * Copyright (C) 2016 Benoist3012
 * ==============================================================================
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
 */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "0.2b"
#define CONFIG_VC		"configs/voicechanger_shit.cfg"

bool g_bLoaded;
bool g_bIsTF2;
KeyValues kvVC;

public Plugin myinfo = 
{
	name			= "[ANY] Voice Changer!",
	author			= "Benoist3012, Glubbable",
	description		= "Change players's voicelines with a cfg.",
	version			= PLUGIN_VERSION,
	url				= "http://steamcommunity.com/id/Benoist3012/"
};

public void OnPluginStart()
{
	CreateConVar("vc_version", PLUGIN_VERSION, "Voice Changer! Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	AddNormalSoundHook(view_as<NormalSHook>(NormalSoundHook));
}
public void OnMapStart()
{
	char g_sDir[64];
	GetGameFolderName(g_sDir, sizeof(g_sDir));
	if (strcmp(g_sDir, "tf") == 0 || strcmp(g_sDir, "tf_beta") == 0)
	{
		g_bIsTF2 = true;
	}
	else
		g_bIsTF2 = false;
	char g_sFile[256], buffer[255];
	BuildPath(Path_SM, g_sFile, sizeof(g_sFile), CONFIG_VC);
	kvVC = new KeyValues("");
	if(!kvVC.ImportFromFile(g_sFile)) 
	{
		SetFailState("Could not load file %s.", g_sFile);
		delete kvVC;
		g_bLoaded = false;
		return;
	}
	g_bLoaded = true;
	kvVC.GotoFirstSubKey();
	for(;;)
	{
		kvVC.GetSectionName(buffer, sizeof(buffer));
		if(!StrEqual(buffer,""))
		{
			kvVC.GotoFirstSubKey();
			for(;;)
			{
				kvVC.GetSectionName(buffer, sizeof(buffer));
				if(!StrEqual(buffer,""))
				{
					int i = 1;
					for (;;)
					{
						char s[64],s2[64];
						IntToString(i, s, sizeof(s));
						kvVC.GetString(s, s2, sizeof(s2));
						if (!s2[0])
							break;
						else
						{
							Format(s2, sizeof(s2),"sound/%s",s2);
							if(FileExists(s2))
							{
								AddFileToDownloadsTable(s2);
								PrintToServer("[VC]Precaching %s", s2);
								ReplaceString(s2, sizeof(s2), "sound/", "", false);
								PrecacheSound(s2, true);
							}
						}				
						i++;
					}
					if(!kvVC.GotoNextKey())
					{
						kvVC.GoBack();
						break;
					}
				}
				else
					break;
			}
			if(!kvVC.GotoNextKey())
				break;
		}
		else
			break;
	}
}
/*
*
* Somehow KvJumpToKey is broken so I found a replacement to fix it, don't blame me for that.
*
*
*/
public Action NormalSoundHook(int clients[64],int &numClients,char strSound[PLATFORM_MAX_PATH],int &entity,int &channel,float &volume,int &level,int &pitch,int &flags)
{
	if(!g_bLoaded)
		return Plugin_Continue;
	if(StrContains(strSound, "vo", false) == -1)
		return Plugin_Continue;
	bool bChange = false;
	if(g_bIsTF2 && StrContains(strSound, "scout_", false) != -1 
	&& StrContains(strSound, "soldier_", false) != -1
	&& StrContains(strSound, "sniper_", false) != -1
	&& StrContains(strSound, "spy_", false) != -1
	&& StrContains(strSound, "heavy_", false) != -1
	&& StrContains(strSound, "pyro_", false) != -1
	&& StrContains(strSound, "engineer_", false) != -1
	&& StrContains(strSound, "demoman_", false) != -1
	&& StrContains(strSound, "medic_", false) != -1
	&& StrContains(strSound, "civilian_", false) != -1	)
		return Plugin_Continue;
	if(entity<=MaxClients)
	{
		if(IsValidClient(entity))
		{
			char g_sModel[255];
			char buffer[PLATFORM_MAX_PATH];
			GetEntPropString(entity, Prop_Data, "m_ModelName", g_sModel, sizeof(g_sModel));
			TrimString(g_sModel);
			kvVC.Rewind();
			kvVC.GotoFirstSubKey();
			for(;;)
			{
				kvVC.GetSectionName(buffer, sizeof(buffer));
				if(StrEqual(g_sModel,buffer))
				{
					pitch = kvVC.GetNum("pitch", pitch);
					if (!kvVC.GotoFirstSubKey())
					{
						bChange = true;
					}
					do
					{
						kvVC.GetSectionName(buffer, sizeof(buffer));
						TrimString(buffer);
						if (StrContains(strSound, buffer, false) != -1 || StrContains(buffer, strSound, false) != -1)
						{
							int i = 1;
							for (;;)
							{
								char s[64],s2[64];
								IntToString(i, s, sizeof(s));
								kvVC.GetString(s, s2, sizeof(s2));
								if (!s2[0]) break;
								
								i++;
							}
							if (i > 1)
							{
								i = GetRandomInt(1, (i-1));
								char s[64];
								IntToString(i, s, sizeof(s));
								char newvoice[PLATFORM_MAX_PATH];
								kvVC.GetString(s, newvoice, PLATFORM_MAX_PATH);
								strcopy(strSound, PLATFORM_MAX_PATH, newvoice);
								//delete kvVC;
								bChange = true;
							}
						}
					} while (kvVC.GotoNextKey());
					break;
				}
				else
				{
					if(!kvVC.GotoNextKey())
						break;
				}
			}
			if(bChange)
				return Plugin_Changed;
			else
				return Plugin_Continue;
		}
	}
	return Plugin_Continue;
}
stock bool IsValidClient(int client)
{
	return view_as<bool>((client > 0 && client <= MaxClients && IsClientInGame(client)));
}