#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <tf2c>

#define PLUGIN_VERSION					"2409"
#define HOMING_ROCKETS_LIMIT			2048
#define ALLOWED_LAUNCHERS_LIMIT			8

#define ROCKETTYPE_REGULAR				1
#define ROCKETTYPE_SENTRY				2

#if !defined VDECODE_FLAG_ALLOWWORLD
	#define VDECODE_FLAG_ALLOWWORLD		(1<<2)
#endif

//////////////////////////////////////////////////
public Plugin:myinfo = 
{
	name = "[TF2] Homing Rocket",
	author = "Leonardo",
	description = "Aim your rockets to where you're looking at.",
	version = PLUGIN_VERSION,
	url = "http://xpenia.org/"
}

//////////////////////////////////////////////////
// SDK calls
new Handle:g_hRocketTouch = INVALID_HANDLE;
new Handle:g_hSRocketTouch = INVALID_HANDLE;
// storing data
new bool:g_bActiveHoming[MAXPLAYERS+1] = false;
new g_iRocketOwners[HOMING_ROCKETS_LIMIT];
new Handle:g_hRocketAimingTimers[HOMING_ROCKETS_LIMIT];
new g_iRocketLifeTimeMeters[HOMING_ROCKETS_LIMIT];
new Handle:g_hRocketLifeTimers[HOMING_ROCKETS_LIMIT];
new g_iRocketType[HOMING_ROCKETS_LIMIT];
// console variables
new Handle:g_hIsPluginOn = INVALID_HANDLE;
new Handle:g_hIsDebugOn = INVALID_HANDLE;
new Handle:g_hHomingMode = INVALID_HANDLE;
new Handle:g_hAccuracy = INVALID_HANDLE;
new Handle:g_hSAccuracy = INVALID_HANDLE;
new Handle:g_hForceHoming = INVALID_HANDLE;
new Handle:g_hSForceHoming = INVALID_HANDLE;
new Handle:g_hShowAim = INVALID_HANDLE;
new Handle:g_hSShowAim = INVALID_HANDLE;
new Handle:g_hMvMDisabler = INVALID_HANDLE;
new Handle:g_hLifeTime = INVALID_HANDLE;
new Handle:g_hLTMode = INVALID_HANDLE;
// convar values (don't check too often)
new g_bPluginOn = true;
new g_bShowAim = true;
new g_bSShowAim = true;
new g_bMvMDisabler = true;
new g_nForceHoming = 1;
new g_nSForceHoming = 0;
new g_nHomingMode = 1;
new g_nAdminFlags = 0;
new g_nAllowedLaunchers[ALLOWED_LAUNCHERS_LIMIT] = { -1, ... };
new bool:g_bAllowAllLaunchers = true;
// glow model ID's
new g_iBlueGlowModelID = -1;
new g_iRedGlowModelID = -1;

//////////////////////////////////////////////////
public OnPluginStart()
{
	decl String:strFilePath[PLATFORM_MAX_PATH];
	BuildPath( Path_SM, strFilePath, sizeof(strFilePath), "gamedata/homingrocket.gamedata.txt" );
	if( FileExists( strFilePath ) )
	{
		new Handle:hGameData = LoadGameConfigFile("homingrocket.gamedata");
		if(hGameData != INVALID_HANDLE)
		{
			StartPrepSDKCall(SDKCall_Entity);
			PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "RocketTouch");
			PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWWORLD);
			g_hRocketTouch = EndPrepSDKCall();
			
			StartPrepSDKCall(SDKCall_Entity);
			PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "SRocketTouch");
			PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWWORLD);
			g_hSRocketTouch = EndPrepSDKCall();
		}
		CloseHandle(hGameData);
	}
	
	g_hIsDebugOn = CreateConVar("sm_hr_debug","0","Enable/Disable Debug Mode (0 - disabled)", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hLifeTime = CreateConVar("sm_hr_lifetime", "10", "Homing rocket's life time.\nValue in integer seconds.", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0);
	g_hLTMode = CreateConVar("sm_hr_lifetimemode", "1", "Life time for homing rockets (1) or for all rockets (0).", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0);
	g_hAccuracy = CreateConVar("sm_hr_accuracy", "1", "Homing accuracy (0-10)", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 10.0);
	g_hSAccuracy = CreateConVar("sm_hr_saccuracy", "3", "(Sentry) Homing accuracy (0-10)", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 10.0);
	
	g_hIsPluginOn = CreateConVar("sm_hr_enable","1","Enable/Disable Plugin (0 = disabled | 1 = enabled)", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	HookConVarChange(g_hIsPluginOn, OnConVarChanged_PluginOn);
	g_bPluginOn = (GetConVarInt(g_hIsPluginOn)!=0?true:false);
	
	g_hForceHoming = CreateConVar("sm_hr_forcehoming", "1", "Force homing on (2), or force off (0), or make players able to (de)activate (1).", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 2.0);
	HookConVarChange(g_hForceHoming, OnConVarChanged_ForceHoming);
	g_nForceHoming = GetConVarInt(g_hForceHoming);
	
	g_hSForceHoming = CreateConVar("sm_hr_sforcehoming", "0", "(Sentry) Force homing on (1), or make players able to (de)activate (0).", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	HookConVarChange(g_hSForceHoming, OnConVarChanged_SForceHoming);
	g_nSForceHoming = GetConVarInt(g_hSForceHoming);
	
	g_hShowAim = CreateConVar("sm_hr_showaim", "1", "Show (1) dot on aim or not (0).", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	HookConVarChange(g_hShowAim, OnConVarChanged_ShowAim);
	g_bShowAim = (GetConVarInt(g_hShowAim)!=0?true:false);
	
	g_hSShowAim = CreateConVar("sm_hr_sshowaim", "1", "(Sentry) Show (1) dot on aim or not (0).", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	HookConVarChange(g_hSShowAim, OnConVarChanged_SShowAim);
	g_bSShowAim = (GetConVarInt(g_hSShowAim)!=0?true:false);
	
	g_hHomingMode = CreateConVar("sm_hr_mode","3","Enable homing for soldier's rockets (1), or for sentry's rockets (2), or for both of them (3), or disable it (0).", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 3.0);
	HookConVarChange(g_hHomingMode, OnConVarChanged_HomingMode);
	g_nHomingMode = GetConVarInt(g_hHomingMode);
	
	g_hMvMDisabler = CreateConVar("sm_hr_mvm_disabler", "1", "Disable plugin for BLU team (MvM mode).", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	HookConVarChange(g_hMvMDisabler, OnConVarChanged_MvM);
	g_bMvMDisabler = (GetConVarInt(g_hMvMDisabler)!=0?true:false);
	
	new Handle:hConVar = INVALID_HANDLE;
	new iBufferSize = 65 * ALLOWED_LAUNCHERS_LIMIT - 1; 
	if ( iBufferSize < 90 ) iBufferSize = 90; // LOL
	
	new String:sBuffer[iBufferSize--];
	Format(sBuffer, iBufferSize, "Item defenition ID's of allowed rocket launchers.\nSeparate with semicolon. %i is a limit.", ALLOWED_LAUNCHERS_LIMIT);
	
	hConVar = CreateConVar("sm_hr_adminflag", "", "Admins Flag for access; make it empty to turn off.", FCVAR_PLUGIN|FCVAR_NOTIFY);
	HookConVarChange(hConVar, OnConVarChanged_AdminAccess);
	GetConVarString(hConVar, sBuffer, iBufferSize);
	OnConVarChanged_AdminAccess(hConVar, "", sBuffer);
	
	hConVar = CreateConVar("sm_hr_launchers", "", sBuffer, FCVAR_PLUGIN|FCVAR_NOTIFY);
	HookConVarChange(hConVar, OnConVarChanged_AllowedLaunchers);
	GetConVarString(hConVar, sBuffer, iBufferSize);
	OnConVarChanged_AllowedLaunchers(hConVar, "", sBuffer);
	
	hConVar = CreateConVar("sm_homingrocket", PLUGIN_VERSION, "Version of Homing Rockets", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	SetConVarString(hConVar, PLUGIN_VERSION, true, true);
	HookConVarChange(hConVar, OnConVarChanged_VersionNumber);
	
	CloseHandle(hConVar);
	
	RegConsoleCmd("sm_togglehoming", Command_ToggleHoming, "Toggle rocket homing.");
}

//////////////////////////////////////////////////
public OnGameFrame()
{
	static bool:bPressed[65] = { false , ... };
	new String:sWeaponName[32];
	new bool:bRocketLauncher = false;
	new bool:bLaserPointer = false;
	new iWeaponDefID = -1;
	new Float:flTargetPos[3];
	
	for( new iClient = 1; iClient <= MaxClients; iClient++ )
	{
		if( IsClientInGame(iClient) && IsPlayerAlive(iClient) && (g_nAdminFlags!=0 && (GetUserFlagBits(iClient) & g_nAdminFlags)!=0 || g_nAdminFlags==0) )
		{
			if( g_bMvMDisabler && IsMvM() && GetClientTeam(iClient) == _:TFTeam_Blue )
				continue;
			GetClientWeapon(iClient, sWeaponName, sizeof(sWeaponName));
			bRocketLauncher = (StrContains(sWeaponName, "tf_weapon_rocketlauncher", false) != -1);
			bLaserPointer = (StrContains(sWeaponName, "tf_weapon_laser_pointer", false) != -1);
			if( bRocketLauncher && (g_nHomingMode==1 || g_nHomingMode==3) || bLaserPointer && (g_nHomingMode==2 || g_nHomingMode==3) )
			{
				// toggle homing
				if( g_nForceHoming == 1 && bRocketLauncher || g_nSForceHoming == 0 && bLaserPointer )
					if( bRocketLauncher && (GetClientButtons(iClient) & IN_ATTACK2) || bLaserPointer && (GetClientButtons(iClient) & IN_RELOAD) )
					{
						if(!bPressed[iClient])
						{
							g_bActiveHoming[iClient] = !g_bActiveHoming[iClient];
							if( GetConVarInt(g_hIsDebugOn)>0 )
								PrintToServer("Changing status for %N: %s", iClient, ( g_bActiveHoming[iClient] ? "true" : "false" ) );
							PrintToChat(iClient, "\x03Homing %sactivated!", ( g_bActiveHoming[iClient] ? "" : "de" ));
							PrintToChat(iClient, "\x01Click %s to %sactivate.", ( bLaserPointer ? "the reload key" : "the right mouse button" ), ( g_bActiveHoming[iClient] ? "de" : "" ));
						}
						bPressed[iClient] = true;
					}
					else
						bPressed[iClient] = false;
				
				if( g_bShowAim && bRocketLauncher && ( g_bActiveHoming[iClient] && g_nForceHoming==1 || g_nForceHoming==2 ) || g_bSShowAim && bLaserPointer && ( g_bActiveHoming[iClient] && g_nSForceHoming==0 || g_nSForceHoming==1 ) )
				{
					iWeaponDefID = GetEntProp(GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon"), Prop_Send, "m_iItemDefinitionIndex");
					for( new i = 0; i < ALLOWED_LAUNCHERS_LIMIT; i++ )
						if( g_nAllowedLaunchers[i] == iWeaponDefID || g_bAllowAllLaunchers )
						{
							if( !TF2_HasCond(iClient, int:TFCond_Taunting) && !TF2_HasCond(iClient, int:TFCond_Dazed) )
							{
								GetPlayerEye(iClient, flTargetPos);
								if(GetClientTeam(iClient)==2)
									TE_SetupGlowSprite( flTargetPos, g_iRedGlowModelID, 0.1, 0.17, 75 );
								else
									TE_SetupGlowSprite( flTargetPos, g_iBlueGlowModelID, 0.1, 0.17, 25 );
								TE_SendToAll();
							}
							break; // draw once
						}
				}
			}
		}
	}
}

//////////////////////////////////////////////////
public OnMapStart()
{
	g_bPluginOn = GetConVarBool(g_hIsPluginOn);
	g_nForceHoming = GetConVarInt(g_hForceHoming);
	g_nSForceHoming = GetConVarInt(g_hSForceHoming);
	g_bShowAim = GetConVarBool(g_hShowAim);
	g_bSShowAim = GetConVarBool(g_hSShowAim);
	g_nHomingMode = GetConVarInt(g_hHomingMode);
	
	if( GuessSDKVersion() == SOURCE_SDK_EPISODE2VALVE )
		SetConVarString(FindConVar("sm_homingrocket"), PLUGIN_VERSION, true, true);
	
	g_iBlueGlowModelID = PrecacheModel("sprites/blueglow1.vmt");
	g_iRedGlowModelID = PrecacheModel("sprites/redglow1.vmt");
	
	for(new i = 1; i <= MAXPLAYERS; i++)
		g_bActiveHoming[i] = false;
	
	for(new i = 0; i < HOMING_ROCKETS_LIMIT; i++)
	{
		g_iRocketOwners[i] = 0;
		g_iRocketLifeTimeMeters[i] = 0;
		g_hRocketAimingTimers[i] = INVALID_HANDLE;
		g_hRocketLifeTimers[i] = INVALID_HANDLE;
		g_iRocketType[i] = 0;
	}
	
	IsMvM( true );
}

//////////////////////////////////////////////////
public OnClientPutInServer(iClient)
	DoKillClientData(iClient);

//////////////////////////////////////////////////
public OnClientDisconnect(iClient)
	DoKillClientData(iClient);

//////////////////////////////////////////////////
public OnEntityCreated(entity, const String:sClassName[])
{
	if( g_bPluginOn )
		if(StrEqual(sClassName,"tf_projectile_rocket") && (g_nHomingMode==1 || g_nHomingMode==3))
			SDKHook(entity, SDKHook_Spawn, Hook_OnRocketSpawn);
		else if(StrEqual(sClassName, "tf_projectile_sentryrocket") && (g_nHomingMode==2 || g_nHomingMode==3))
			SDKHook(entity, SDKHook_Spawn, Hook_OnSentryRocketSpawn);
}

//////////////////////////////////////////////////
public Hook_OnRocketSpawn(entity)
	if( g_bPluginOn )
		if( g_iRocketOwners[entity] <= 0 )
		{
			new iOwner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
			if( iOwner > 0 && iOwner <= MaxClients )
			{
				g_iRocketOwners[entity] = iOwner;
				
				g_iRocketLifeTimeMeters[entity] = 0;
				g_hRocketAimingTimers[entity] = CreateTimer(0.0005, Timer_RocketCheck, EntIndexToEntRef(entity), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
				if( GetConVarInt(g_hLifeTime)>0 )
					g_hRocketLifeTimers[entity] = CreateTimer(1.0, Timer_LifeCheck, EntIndexToEntRef(entity), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
				
				g_iRocketType[entity] = ROCKETTYPE_REGULAR;
				
				if( GetConVarInt(g_hIsDebugOn)>0 )
					PrintToServer("Rocket's ID: %d; owner: %N (hooked)",entity,iOwner);
			}
		}

//////////////////////////////////////////////////
public Hook_OnSentryRocketSpawn(entity)
	if( g_bPluginOn )
		if( g_iRocketOwners[entity] <= 0 )
		{
			new iOwner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
			if( IsValidEntity(iOwner) )
			{
				iOwner = GetEntDataEnt2(iOwner, FindSendPropOffs("CObjectSentrygun","m_hBuilder"));
				if( iOwner > 0 && iOwner <= MaxClients )
				{
					g_iRocketOwners[entity] = iOwner;
					
					g_iRocketLifeTimeMeters[entity] = 0;
					g_hRocketAimingTimers[entity] = CreateTimer(0.0005, Timer_RocketCheck, EntIndexToEntRef(entity), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
					if( GetConVarInt(g_hLifeTime)>0 )
						g_hRocketLifeTimers[entity] = CreateTimer(1.0, Timer_LifeCheck, EntIndexToEntRef(entity), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
					
					g_iRocketType[entity] = ROCKETTYPE_SENTRY;
					
					if( GetConVarInt(g_hIsDebugOn)>0 )
						PrintToServer("SentryRocket's ID: %d; owner: %N (hooked)",entity,iOwner);
				}
			}
		}

//////////////////////////////////////////////////
public OnEntityDestroyed(entity)
{
	if( entity > 0 && IsValidEntity(entity) /* WUT */ && IsValidEdict(entity) )
	{
		new String:sClassName[32];
		GetEdictClassname(entity, sClassName, sizeof(sClassName));
		if(StrEqual(sClassName, "tf_projectile_rocket") || StrEqual(sClassName, "tf_projectile_sentryrocket"))
			DoKillData(entity);
	}
}

//////////////////////////////////////////////////
public Action:Timer_RocketCheck(Handle:timer, any:entref)
{
	new entity = EntRefToEntIndex(entref);
	if(!IsValidEntity(entref))
	{
		DoKillData(entity);
		return Plugin_Stop;
	}
	
	if( g_hRocketAimingTimers[entity] == INVALID_HANDLE )
	{
		DoKillData(entity);
		return Plugin_Stop;
	}
	
	if( g_bPluginOn )
	{
		if( IsValidEntity(entity) )
		{
			if( g_iRocketOwners[entity] > 0 )
			{
				if(g_iRocketType[entity] == ROCKETTYPE_REGULAR && (g_nHomingMode==0 || g_nHomingMode==2) || g_iRocketType[entity] == ROCKETTYPE_SENTRY && (g_nHomingMode==0 || g_nHomingMode==1))
				{
					DoKillData(entity);
					return Plugin_Stop;
				}
				
				new iOwner = -1;
				if( g_iRocketType[entity] == ROCKETTYPE_SENTRY )
				{
					iOwner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
					if( IsValidEntity(iOwner) )
						iOwner = GetEntDataEnt2(iOwner, FindSendPropOffs("CObjectSentrygun","m_hBuilder"));
				}
				else
					iOwner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
				if( iOwner <= 0 || iOwner > MaxClients || !IsClientInGame(iOwner) || !IsPlayerAlive(iOwner) )
				{
					DoKillData(entity);
					return Plugin_Stop;
				}
				
				if ( g_iRocketOwners[entity] != iOwner ) // Noooo, Pyros shouldn't use homing
				{
					DoKillData(entity);
					return Plugin_Stop;
				}
				
				if ( g_nAdminFlags!=0 && (GetUserFlagBits(iOwner) & g_nAdminFlags)==0 )
					return Plugin_Continue;
				
				if( g_bMvMDisabler && IsMvM() && GetClientTeam(iOwner) == _:TFTeam_Blue )
				{
					DoKillData(entity); // Keeping it enabled will be a big mistake
					return Plugin_Continue;
				}
				
				if( g_iRocketType[entity] == ROCKETTYPE_SENTRY )
				{
					if( g_nSForceHoming != 1 )
						if( !g_bActiveHoming[iOwner] )
							return Plugin_Continue;
				}
				else
				{
					if( g_nForceHoming != 2 )
						if( g_nForceHoming == 1 && !g_bActiveHoming[iOwner] || g_nForceHoming == 0 )
							return Plugin_Continue;
				}
				
				new String:sWeaponName[32];
				GetClientWeapon(iOwner, sWeaponName, sizeof(sWeaponName));
				if ( StrContains(sWeaponName, "tf_weapon_rocketlauncher", false) == -1 && StrContains(sWeaponName, "tf_weapon_laser_pointer", false) == -1 )
					return Plugin_Continue;
				
				if( !g_bAllowAllLaunchers && StrContains(sWeaponName, "tf_weapon_rocketlauncher", false) != -1 )
				{
					new iWeaponDefID = GetEntProp(GetEntPropEnt(iOwner, Prop_Send, "m_hActiveWeapon"), Prop_Send, "m_iItemDefinitionIndex");
					decl bool:bAllowed;
					bAllowed = false;
					for( new i = 0; i < ALLOWED_LAUNCHERS_LIMIT; i++ )
						if( g_nAllowedLaunchers[i] == iWeaponDefID )
							bAllowed = true;
					if(!bAllowed)
						return Plugin_Continue;
				}
				
				if( GetConVarInt(g_hIsDebugOn)>1 )
					PrintToServer("Rocket's ID: %d; owner: %N (updating)", entity, iOwner);
				
				new Float:RocketPos[3];
				new Float:RocketAng[3];
				new Float:RocketVec[3];
				new Float:TargetPos[3];
				new Float:TargetVec[3];
				new Float:MiddleVec[3];
				
				GetPlayerEye(iOwner, TargetPos);
				
				GetEntPropVector( entity, Prop_Data, "m_vecAbsOrigin", RocketPos );
				GetEntPropVector( entity, Prop_Data, "m_angRotation", RocketAng );
				GetEntPropVector( entity, Prop_Data, "m_vecAbsVelocity", RocketVec );

				new Float:RocketSpeed = GetVectorLength( RocketVec );
				SubtractVectors( TargetPos, RocketPos, TargetVec );
				
				new iAccuracy = 0;
				if( g_iRocketType[entity] == ROCKETTYPE_SENTRY )
					iAccuracy = GetConVarInt(g_hSAccuracy);
				else
					iAccuracy = GetConVarInt(g_hAccuracy);
				
				if ( iAccuracy<=0 ) // negative values
					NormalizeVector( TargetVec, RocketVec );
				else
				{
					if ( iAccuracy==1 )
						AddVectors( RocketVec, TargetVec, RocketVec );
					else if ( iAccuracy==2 )
					{
						AddVectors( RocketVec, TargetVec, MiddleVec );
						AddVectors( RocketVec, MiddleVec, RocketVec );
					}
					else //if ( iAccuracy>=3 )
					{
						AddVectors( RocketVec, TargetVec, MiddleVec );
						for( new j=0; j < iAccuracy-2; j++ )
							AddVectors( RocketVec, MiddleVec, MiddleVec );
						AddVectors( RocketVec, MiddleVec, RocketVec );
					}
					NormalizeVector( RocketVec, RocketVec );
				}
				
				GetVectorAngles( RocketVec, RocketAng );
				SetEntPropVector( entity, Prop_Data, "m_angRotation", RocketAng );

				ScaleVector( RocketVec, RocketSpeed );
				SetEntPropVector( entity, Prop_Data, "m_vecAbsVelocity", RocketVec );
				
				//ChangeEdictState( entity );
				
				return Plugin_Continue;
			}
		}
	}
	
	DoKillData(entity);
	return Plugin_Stop;
}

//////////////////////////////////////////////////
public Action:Timer_LifeCheck(Handle:timer, any:entref)
{
	new entity = EntRefToEntIndex(entity);
	if( !IsValidEntity(entity) )
	{
		DoKillData(entity);
		return Plugin_Stop;
	}
	
	if( g_hRocketLifeTimers[entity] == INVALID_HANDLE )
	{
		DoKillData(entity);
		return Plugin_Stop;
	}
	
	if( g_bPluginOn )
		if(IsValidEntity(entity))
			if( GetConVarInt(g_hLifeTime)>0 )
			{
				new iOwner = -1;
				if( g_iRocketType[entity] == ROCKETTYPE_SENTRY )
					iOwner = GetEntDataEnt2(GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity"), FindSendPropOffs("CObjectSentrygun","m_hBuilder"));
				else
					iOwner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
				if( iOwner > 0 && iOwner <= MaxClients && IsClientInGame(iOwner) && IsPlayerAlive(iOwner) )
					if( g_bActiveHoming[iOwner] && GetConVarInt(g_hForceHoming)==1 || GetConVarInt(g_hForceHoming)==2 || GetConVarInt(g_hLTMode)<=0 )
					{
						if( ++g_iRocketLifeTimeMeters[entity] >= GetConVarInt(g_hLifeTime) )
						{
							if( GetConVarInt(g_hIsDebugOn)>0 )
								PrintToServer("Rocket's ID: %d; owner: %N (killing rocket)", entity, iOwner);
							DoExplodeRocket(entity);
						}
						else
							return Plugin_Continue;
					}
					else
						return Plugin_Continue;
			}
	
	DoKillData(entity);
	return Plugin_Stop;
}

//////////////////////////////////////////////////
public Action:Command_ToggleHoming(iClient, iArgs)
{
	if( iClient > 0 && iClient <= MaxClients && IsClientInGame(iClient) )
	{
		if( g_bMvMDisabler && IsMvM() && GetClientTeam(iClient) == _:TFTeam_Blue )
			return Plugin_Handled;
		new String:sWeaponName[32], bool:bLaserPointer, bool:bRocketLauncher;
		GetClientWeapon(iClient, sWeaponName, sizeof(sWeaponName));
		bRocketLauncher = (StrContains(sWeaponName, "tf_weapon_rocketlauncher", false) != -1);
		bLaserPointer = (StrContains(sWeaponName, "tf_weapon_laser_pointer", false) != -1);
		if( bRocketLauncher && (g_nHomingMode==1 || g_nHomingMode==3) && g_nForceHoming == 1 || bLaserPointer && (g_nHomingMode==2 || g_nHomingMode==3) && g_nSForceHoming == 1 )
			if( g_nAdminFlags!=0 && (GetUserFlagBits(iClient) & g_nAdminFlags)!=0 || g_nAdminFlags==0 )
			{
				g_bActiveHoming[iClient] = !g_bActiveHoming[iClient];
				PrintToChat(iClient, "\x03Homing %sactivated!", ( g_bActiveHoming[iClient] ? "" : "de" ));
				PrintToChat(iClient, "\x01Type !togglehoming to %sactivate.", ( g_bActiveHoming[iClient] ? "de" : "" ));
			}
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

//////////////////////////////////////////////////
DoKillData( id )
{
	if( id < 0 || id >= HOMING_ROCKETS_LIMIT )
		return;
	
	g_iRocketOwners[id] = 0;
	g_iRocketLifeTimeMeters[id] = 0;
	
	if( g_hRocketAimingTimers[id] != INVALID_HANDLE )
		KillTimer( g_hRocketAimingTimers[id] );
	g_hRocketAimingTimers[id] = INVALID_HANDLE;
	
	if( g_hRocketLifeTimers[id] != INVALID_HANDLE )
		KillTimer( g_hRocketLifeTimers[id] );
	g_hRocketLifeTimers[id] = INVALID_HANDLE;
}

//////////////////////////////////////////////////
DoKillClientData( client )
{
	if( client < 0 || client > MaxClients )
		return;
	
	new id = -1;
	for( new i=0; i<HOMING_ROCKETS_LIMIT; i++ )
		if( g_iRocketOwners[i] == client )
		{
			id = i;
			break;
		}
	if ( id == -1 ) return;
	
	g_iRocketOwners[id] = 0;
	g_iRocketLifeTimeMeters[id] = 0;
	
	if( g_hRocketAimingTimers[id] != INVALID_HANDLE )
		KillTimer( g_hRocketAimingTimers[id] );
	g_hRocketAimingTimers[id] = INVALID_HANDLE;
	
	if( g_hRocketLifeTimers[id] != INVALID_HANDLE )
		KillTimer( g_hRocketLifeTimers[id] );
	g_hRocketLifeTimers[id] = INVALID_HANDLE;
}

//////////////////////////////////////////////////
DoExplodeRocket( entity )
{
	if( entity <= 0 || !IsValidEntity(entity) )
		return;
	
	if( g_iRocketType[entity] == ROCKETTYPE_REGULAR && g_hRocketTouch != INVALID_HANDLE )
	{
		SDKCall(g_hRocketTouch, entity, 0);
		CreateTimer( 0.1, Timer_DoExplodeRocket, EntIndexToEntRef(entity) );
	}
	else if( g_iRocketType[entity] == ROCKETTYPE_SENTRY && g_hSRocketTouch != INVALID_HANDLE )
	{
		SDKCall(g_hSRocketTouch, entity, 0);
		CreateTimer( 0.1, Timer_DoExplodeRocket, EntIndexToEntRef(entity) );
	}
	else
		AcceptEntityInput(entity, "Kill");
}

//////////////////////////////////////////////////
// kill rocket on sdkcall failed
public Action:Timer_DoExplodeRocket(Handle:hTimer, any:entref)
{
	new entity = EntRefToEntIndex(entref);
	if( !IsValidEntity(entity) )
		return Plugin_Stop;
	
	AcceptEntityInput(entity, "Kill");
	return Plugin_Stop;
}

//////////////////////////////////////////////////
public OnConVarChanged_VersionNumber(Handle:hConVar, const String:sOldValue[], const String:sNewValue[])
	if(!StrEqual(sNewValue, PLUGIN_VERSION, false))
		SetConVarString(hConVar, PLUGIN_VERSION, true, true);

//////////////////////////////////////////////////
public OnConVarChanged_PluginOn(Handle:hConVar, const String:sOldValue[], const String:sNewValue[])
	g_bPluginOn = ( StringToInt(sNewValue)!=0 ? true : false );

//////////////////////////////////////////////////
public OnConVarChanged_ForceHoming(Handle:hConVar, const String:sOldValue[], const String:sNewValue[])
	g_nForceHoming = StringToInt(sNewValue);

//////////////////////////////////////////////////
public OnConVarChanged_SForceHoming(Handle:hConVar, const String:sOldValue[], const String:sNewValue[])
	g_nSForceHoming = StringToInt(sNewValue);

//////////////////////////////////////////////////
public OnConVarChanged_HomingMode(Handle:hConVar, const String:sOldValue[], const String:sNewValue[])
	g_nHomingMode = StringToInt(sNewValue);

//////////////////////////////////////////////////
public OnConVarChanged_AdminAccess(Handle:hConVar, const String:sOldValue[], const String:sNewValue[])
	g_nAdminFlags = ReadFlagString(sNewValue);

//////////////////////////////////////////////////
public OnConVarChanged_ShowAim(Handle:hConVar, const String:sOldValue[], const String:sNewValue[])
	g_bShowAim = ( StringToInt(sNewValue)!=0 ? true : false );

//////////////////////////////////////////////////
public OnConVarChanged_SShowAim(Handle:hConVar, const String:sOldValue[], const String:sNewValue[])
	g_bSShowAim = ( StringToInt(sNewValue)!=0 ? true : false );

//////////////////////////////////////////////////
public OnConVarChanged_MvM(Handle:hConVar, const String:sOldValue[], const String:sNewValue[])
	g_bMvMDisabler = ( StringToInt(sNewValue)!=0 ? true : false );

//////////////////////////////////////////////////
public OnConVarChanged_AllowedLaunchers(Handle:hConVar, const String:sOldValue[], const String:sNewValue[])
{
	if(strlen(sNewValue)>0)
	{
		decl String:sBuffer[ALLOWED_LAUNCHERS_LIMIT][64]; 
		ExplodeString(sNewValue, ";", sBuffer, sizeof(sBuffer), sizeof(sBuffer[])); 
		for(new i=0; i<ALLOWED_LAUNCHERS_LIMIT; i++)
			if(strlen(sBuffer[i])>0)
				g_nAllowedLaunchers[i] = StringToInt(sBuffer[i]);
			else
				g_nAllowedLaunchers[i] = -1;
		g_bAllowAllLaunchers = false;
	}
	else
	{
		for(new i=0; i<ALLOWED_LAUNCHERS_LIMIT; i++)
			g_nAllowedLaunchers[i] = -1;
		g_bAllowAllLaunchers = true;
	}
}

//////////////////////////////////////////////////
bool:GetPlayerEye(client, Float:pos[3])
{
	new Float:vAngles[3], Float:vOrigin[3];
	GetClientEyePosition(client, vOrigin);
	GetClientEyeAngles(client, vAngles);
	
	new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer, client);
	
	if(TR_DidHit(trace))
	{
		TR_GetEndPosition(pos, trace);
		CloseHandle(trace);
		return true;
	}
	CloseHandle(trace);
	return false;
}
public bool:TraceEntityFilterPlayer(entity, contentsMask, any:data)
{
	if ( entity <= 0 ) return true;
	if ( entity == data ) return false;
	
	decl String:sClassname[128];
	GetEdictClassname(entity, sClassname, sizeof(sClassname));
	if(StrEqual(sClassname, "func_respawnroomvisualizer", false))
		return false;
	else
		return true;
}

//////////////////////////////////////////////////
stock bool:TF2_HasCond(iClient, iCondBit=0)
{
	if( iClient>0 && iClient<=MaxClients && IsValidEdict(iClient) )
	{
		new iCondBits = GetEntProp(iClient, Prop_Send, "m_nPlayerCond");
		return (iCondBits>=0 && iCondBit>=0 ? ((iCondBits & (1 << iCondBit)) != 0) : false);
	}
	return false;
}

//////////////////////////////////////////////////
stock IsMvM( bool:bRecalc = false )
{
	static bool:bChecked = false;
	static bool:bMannVsMachines = false;
	
	if( bRecalc || !bChecked )
	{
		new iEnt = FindEntityByClassname( -1, "tf_logic_mann_vs_machine" );
		bMannVsMachines = ( iEnt > MaxClients && IsValidEntity( iEnt ) );
		bChecked = true;
	}
	
	return bMannVsMachines;
}