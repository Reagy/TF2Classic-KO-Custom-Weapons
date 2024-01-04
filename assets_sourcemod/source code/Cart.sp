// Copyright (C) 2023 Katsute | Licensed under CC BY-NC-SA 4.0

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

int speed;

ConVar speedCV;

public Plugin myinfo = {
    name        = "Cart Speed",
    author      = "Katsute",
    description = "Set maximum cart speed",
    version     = "1.0",
    url         = "https://github.com/KatsuteTF/Cart-Speed"
}

public void OnPluginStart(){
    speedCV = CreateConVar("sm_cart_speed", "120", "Maximum cart speed");
    speedCV.AddChangeHook(OnConvarChanged);

    speed = speedCV.IntValue;

    HookEvent("teamplay_round_start", OnStart);
    HookEvent("teamplay_setup_finished", OnStart);
}

public void OnConvarChanged(const ConVar convar, const char[] oldValue, const char[] newValue){
	if(convar == speedCV){
        speed = StringToInt(newValue);
        SetSpeed();
    }
}

static void OnStart(const Event event, const char[] name, const bool dontBroadcast){
    SetSpeed();
}

static void SetSpeed(){
    int ent = -1;
    while((ent = FindEntityByClassname(ent, "func_tracktrain")) != -1)
        DispatchKeyValueInt(ent, "startspeed", speed);
}