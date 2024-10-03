#include <sourcemod>
#include <sdktools>
#include <morecolors>

public Plugin:myinfo = 
{
    name = "[TF2C] Roll To Die",
    author = "xDeRpYx",
    description = "Kills players who type rtd",
    version = "1.1",
}
public OnPluginStart()
{
    RegConsoleCmd("rtd", Command_YOUMUSTDIE); 
}

public Action:Command_YOUMUSTDIE(client, args)
{   
    if(!client)
    {
        ReplyToCommand(client, "[TF2C RTD] Why would you do this in console?");
        return Plugin_Handled;
    }
    if(!IsPlayerAlive(client))
    {
        ReplyToCommand(client, "[TF2C RTD] Target is already dead.");
        return Plugin_Handled;
    }
    
    ForcePlayerSuicide(client);
    PrintToChat(client, "{orange}[TF2C RTD]{default} You rolled, you died.");
    return Plugin_Handled;        
}