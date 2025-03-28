#pragma newdecls required
#pragma semicolon 1

#include <kocwtools>
#include <dhooks>
#include <midhook>

public Plugin myinfo = {
	name = "Engineer Stacking Nerf",
	author = "Noclue",
	description = "Reduce the effectiveness of engineer stacking.",
	version = "1.0",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

ConVar g_cvConstructionPenalty;
float g_flConstructionPenaltyValue;
ConVar g_cvRepairPenalty;
float g_flRepairPenaltyValue;
ConVar g_cvUpgradePenalty;
float g_flUpgradePenaltyValue;

DynamicDetour g_dtGetConstructionValue;
DynamicDetour g_dtGetRepairValue;
DynamicDetour g_dtInputWrenchHit;

MidHook g_mhMetalPerHit;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	g_dtGetConstructionValue = DynamicDetourFromConfSafe( hGameConf, "CTFWrench::GetConstructionValue" );
	g_dtGetConstructionValue.Enable( Hook_Post, Detour_GetConstructionValue );

	g_dtGetRepairValue = DynamicDetourFromConfSafe( hGameConf, "CTFWrench::GetRepairValue" );
	g_dtGetRepairValue.Enable( Hook_Post, Detour_GetRepairValue );

	g_dtInputWrenchHit = DynamicDetourFromConfSafe( hGameConf, "CBaseObject::InputWrenchHit" );
	g_dtInputWrenchHit.Enable( Hook_Pre, Detour_InputWrenchHit );

	g_mhMetalPerHit = new MidHook( GameConfGetAddress( hGameConf, "CBaseObject::CheckUpgradeOnHit_MetalPerHit" ), Midhook_MetalPerHit, false );
	g_mhMetalPerHit.Enable();

	delete hGameConf;

	g_cvConstructionPenalty = CreateConVar( "engineer_stack_construction_penalty", "0.5", "Multiplier for construction boost when hitting friendly buildings.", FCVAR_NONE, true, 0.1 );
	g_cvConstructionPenalty.AddChangeHook( ConVarChanged_ConstructionPenalty );
	g_flConstructionPenaltyValue = g_cvConstructionPenalty.FloatValue;

	g_cvRepairPenalty = CreateConVar( "engineer_stack_repair_penalty", "0.5", "Multiplier for repairing friendly buildings.", FCVAR_NONE, true, 0.1 );
	g_cvRepairPenalty.AddChangeHook( ConVarChanged_RepairPenalty );
	g_flRepairPenaltyValue = g_cvRepairPenalty.FloatValue;

	g_cvUpgradePenalty = CreateConVar( "engineer_stack_upgrade_penalty", "0.5", "Multiplier for upgrading friendly buildings.", FCVAR_NONE, true, 0.1 );
	g_cvUpgradePenalty.AddChangeHook( ConVarChanged_UpgradePenalty );
	g_flUpgradePenaltyValue = g_cvUpgradePenalty.FloatValue;
}

void ConVarChanged_ConstructionPenalty( ConVar cvVar, const char[] szOldValue, const char[] szNewValue ) {
	g_flConstructionPenaltyValue = MaxFloat( StringToFloat( szNewValue ), 0.1 );
}
void ConVarChanged_RepairPenalty( ConVar cvVar, const char[] szOldValue, const char[] szNewValue ) {
	g_flRepairPenaltyValue = MaxFloat( StringToFloat( szNewValue ), 0.1 );
}
void ConVarChanged_UpgradePenalty( ConVar cvVar, const char[] szOldValue, const char[] szNewValue ) {
	g_flUpgradePenaltyValue = MaxFloat( StringToFloat( szNewValue ), 0.1 );
}

public void Midhook_MetalPerHit( MidHookRegisters hRegs ) {
	Address aPlayer = hRegs.Load( DHookRegister_EBP, 12, NumberType_Int32 );
	if( aPlayer == Address_Null )
		return;

	int iPlayer = GetEntityFromAddress( aPlayer );
	int iBuilding = GetEntityFromAddress( hRegs.Load( DHookRegister_EBP, 8, NumberType_Int32 ) );
	if( GetEntProp( iBuilding, Prop_Send, "m_iObjectType" ) == 2 && GetEntPropEnt( iBuilding, Prop_Send, "m_hBuilder" ) != iPlayer ) {
		float flAmountToAdd = hRegs.GetFloat( DHookRegister_ESI );
		hRegs.SetFloat( DHookRegister_ESI, flAmountToAdd * g_flUpgradePenaltyValue );
	}
}

int g_iBuilding = INVALID_ENT_REFERENCE;
MRESReturn Detour_InputWrenchHit( int iThis, DHookReturn hReturn, DHookParam hParams ) {
	g_iBuilding = GetEntProp( iThis, Prop_Send, "m_iObjectType" ) == 2 ? EntIndexToEntRef( iThis ) : INVALID_ENT_REFERENCE;
	return MRES_Handled;
}

MRESReturn Detour_GetConstructionValue( int iWrench, DHookReturn hReturn, DHookParam hParam ) {
	int iBuilding = EntRefToEntIndex( g_iBuilding );
	if( iBuilding == -1 )
		return MRES_Ignored;

	if( GetEntPropEnt( iWrench, Prop_Send, "m_hOwner" ) != GetEntPropEnt( iBuilding, Prop_Send, "m_hBuilder" ) ) {
		float flReturnVal = hReturn.Value;
		hReturn.Value = flReturnVal * g_flConstructionPenaltyValue;
		return MRES_Override;
	}

	return MRES_Ignored;
}
MRESReturn Detour_GetRepairValue( int iWrench, DHookReturn hReturn, DHookParam hParam ) {
	int iBuilding = EntRefToEntIndex( g_iBuilding );
	if( iBuilding == -1 )
		return MRES_Ignored;

	if( GetEntPropEnt( iWrench, Prop_Send, "m_hOwner" ) != GetEntPropEnt( iBuilding, Prop_Send, "m_hBuilder" ) ) {
		float flReturnVal = hReturn.Value;
		hReturn.Value = flReturnVal * g_flRepairPenaltyValue;
		return MRES_Override;
	}

	return MRES_Ignored;
}