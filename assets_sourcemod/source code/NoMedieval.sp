// Copyright (C) 2023 Katsute | Licensed under CC BY-NC-SA 4.0

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

public Plugin myinfo = {
    name        = "No Medieval",
    author      = "Katsute",
    description = "Force disable medieval mode",
    version     = "1.0",
    url         = "https://github.com/KatsuteTF/No-Medieval"
}

public void OnPluginStart(){
    HookEvent("teamplay_round_start", OnStart);
}

public void OnStart(const Event event, const char[] name, const bool dontBroadcast){
    GameRules_SetProp("m_bPlayingMedieval", 0);
}