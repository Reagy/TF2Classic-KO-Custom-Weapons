#include <sourcemod>
#include <sdktools>
#define PLUGIN_VERSION "2.0"

int g_jumpPadModel;

public Plugin myinfo =
{
	name = "Jump Pad Replacer",
	author = "iamashaymin",
	description = "Replaces the Jump Pad with a custom model.",
	version = PLUGIN_VERSION,
	url = "http://www.google.com"
}

public OnPluginStart()
{
	HookEvent("player_builtobject", Event_player_builtobject);
}

public void OnMapStart()
{
	g_jumpPadModel = PrecacheModel("models/buildables/custom/jumppad.mdl");
	DownloadTable();
}

public DownloadTable()
{
	AddFileToDownloadsTable("materials/models/custom/buildables/jumppad/jumppad.vmt")
	AddFileToDownloadsTable("materials/models/custom/buildables/jumppad/jumppad.vtf")
	AddFileToDownloadsTable("materials/models/custom/buildables/jumppad/jumppad_blue.vmt")
	AddFileToDownloadsTable("materials/models/custom/buildables/jumppad/jumppad_blue.vtf")
	AddFileToDownloadsTable("materials/models/custom/buildables/jumppad/jumppad_green.vmt")
	AddFileToDownloadsTable("materials/models/custom/buildables/jumppad/jumppad_green.vtf")
	AddFileToDownloadsTable("materials/models/custom/buildables/jumppad/jumppad_yellow.vmt")
	AddFileToDownloadsTable("materials/models/custom/buildables/jumppad/jumppad_yellow.vtf")
}

public Action Event_player_builtobject(Handle:event, const String:name[], bool:dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int ent = GetEventInt(event, "index");

	char className[64];
	GetEntityClassname(ent, className, sizeof(className));
	if (strcmp(className, "obj_teleporter") == 0)
	{
		int pda = GetPlayerWeaponSlot(client, 3);
		if (pda > MaxClients && GetEntProp(pda, Prop_Send, "m_iItemDefinitionIndex") == 3352)
		{
			for (int i = 0; i < 4; i++)
			{
				SetEntProp(ent, Prop_Send, "m_nModelIndexOverrides", g_jumpPadModel, _, i);
			}
		}
	}
	return Plugin_Continue;
}