#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <kocwtools>

DynamicHook hGetCaptureValue;

public Plugin myinfo =
{
	name = "Attribute: Capture Rate",
	author = "Noclue",
	description = "Capture Rate attribute.",
	version = "1.0",
	url = "no"
}

public void OnMapStart() {
	Handle hGameConf = LoadGameConfigFile( "kocw.gamedata" );

	hGetCaptureValue = DynamicHook.FromConf( hGameConf, "CTFGameRules::GetCaptureValueForPlayer" );
	if( !hGetCaptureValue.HookGamerules( Hook_Pre, Hook_GetCaptureValue ) ) {
		SetFailState( "Hook setup for CTFGameRules::GetCaptureValueForPlayer failed" );
	}

	delete hGameConf;
}

MRESReturn Hook_GetCaptureValue( Address aThis, DHookReturn hReturn, DHookParam hParam ) {
	int iEntity = hParam.Get( 1 );
	if( !(iEntity <= MaxClients) ) return MRES_Ignored;
	TFClassType class = TF2_GetPlayerClass( iEntity );

	int iReturn = 1;
	switch(class) {
		case( TFClass_Civilian ): {
			iReturn = 5;
		}
		case( TFClass_Scout ): {
			iReturn = 2;
		}
	}
	iReturn += RoundToFloor( AttribHookFloat( 0.0, iEntity, "custom_capture_rate" ) );
	hReturn.Value = iReturn;

	return MRES_ChangedOverride;
}

