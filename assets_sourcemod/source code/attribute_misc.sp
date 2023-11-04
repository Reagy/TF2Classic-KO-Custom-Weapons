#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <kocwtools>

public Plugin myinfo =
{
	name = "Attribute: Misc",
	author = "Noclue",
	description = "Miscellaneous attributes.",
	version = "1.2",
	url = "https://github.com/Reagy/TF2Classic-KO-Custom-Weapons"
}

DynamicHook hPrimaryFire;
DynamicDetour dtGetMedigun;
DynamicDetour dtRestart;

int g_iScrambleOffset = -1;
int g_iRestartTimeOffset = -1;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("kocw.gamedata");

	hPrimaryFire = DynamicHook.FromConf( hGameConf, "CTFWeaponBase::PrimaryAttack" );

	dtGetMedigun = DynamicDetour.FromConf( hGameConf, "CTFPlayer::GetMedigun" );
	dtGetMedigun.Enable( Hook_Pre, Hook_GetMedigun );

	dtRestart = DynamicDetour.FromConf( hGameConf, "CTFGameRules::ResetMapTime" );
	dtRestart.Enable( Hook_Pre, Detour_ResetMapTimePre );
	dtRestart.Enable( Hook_Post, Detour_ResetMapTimePost );

	g_iScrambleOffset = GameConfGetOffset( hGameConf, "CTFGameRules::m_bScrambleTeams" );
	g_iRestartTimeOffset = GameConfGetOffset( hGameConf, "CTFGameRules::m_flMapResetTime" );

	delete hGameConf;
}

/*
	BUGFIX:
	Prevent the game from resetting the map change timer when calling a vote scramble.
	I have no idea if this is intended behavior or not
*/

float g_flRestartTime = 0.0;
MRESReturn Detour_ResetMapTimePre( Address aThis ) {
	bool bScramble = LoadFromAddressOffset( aThis, g_iScrambleOffset, NumberType_Int8 );
	if( bScramble ) {
		g_flRestartTime = LoadFromAddressOffset( aThis, g_iRestartTimeOffset, NumberType_Int32 );
	}
	return MRES_Handled;
}

MRESReturn Detour_ResetMapTimePost( Address aThis ) {
	if( g_flRestartTime != -1.0 ) {
		StoreToAddressOffset( aThis, g_iRestartTimeOffset, g_flRestartTime, NumberType_Int32 );
		g_flRestartTime = -1.0;
	}
	return MRES_Handled;
}

/*
	BUGFIX:
	Fix segmentation fault when a player disconnects while healing someone with a paintball rifle.
*/

MRESReturn Hook_GetMedigun( int iPlayer, DHookReturn hReturn ) {
	if( iPlayer == -1 ) {
		hReturn.Value = INVALID_ENT_REFERENCE;
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

/*
	WEAPON: Broken Mann's Legacy
	Hurts the player, and then heals them for the damage dealt.
	Will not kill the player if self damage is counteracted by received healing.
*/

public void OnEntityCreated( int iEntity ) {
	static char szEntityName[ 32 ];
	GetEntityClassname( iEntity, szEntityName, sizeof( szEntityName ) );
	if( StrContains( szEntityName, "tf_weapon_shotgun", false ) == 0 )
		hPrimaryFire.HookEntity( Hook_Pre, iEntity, Hook_PrimaryFire );
}

public void OnTakeDamageAlivePostTF( int iTarget, Address aDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aDamageInfo );
	CheckLifesteal( iTarget, tfInfo );
}

public void OnTakeDamageBuilding( int iTarget, Address aDamageInfo ) {
	TFDamageInfo tfInfo = TFDamageInfo( aDamageInfo );
	CheckLifesteal( iTarget, tfInfo );
}


float g_flHurtMe[ MAXPLAYERS+1 ];

MRESReturn Hook_PrimaryFire( int iEntity ) {
	if( GetEntPropFloat( iEntity, Prop_Send, "m_flNextPrimaryAttack" ) > GetGameTime() ) {
		return MRES_Ignored;
	}

	int iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwner" );
	if( iOwner == -1 )
		return MRES_Ignored;

	float flValue = AttribHookFloat( 0.0, iEntity, "custom_hurt_on_fire" );
	if( flValue == 0.0 )
		return MRES_Ignored;

	//hack for lifesteal
	g_flHurtMe[ iOwner ] = flValue;
	RequestFrame( HurtPlayerDelay, iOwner );

	return MRES_Handled;
}

void CheckLifesteal( int iTarget, TFDamageInfo tfInfo ) {
	int iAttacker = tfInfo.iAttacker;

	if( !IsValidPlayer( iAttacker ) )
		return;

	int iWeapon = tfInfo.iWeapon;
	float flMult = AttribHookFloat( 0.0, iWeapon, "custom_lifesteal" );
	if( flMult == 0.0 )
		return;

	float flAmount = tfInfo.flDamage * flMult;
	g_flHurtMe[ iAttacker ] -= flAmount;
}

void HurtPlayerDelay( int iPlayer ) {
	if( !IsPlayerAlive( iPlayer ) )
		return;

	float flAmount = g_flHurtMe[ iPlayer ];
	int iDiff = 0;
	if( flAmount > 0.0 ) {
		SDKHooks_TakeDamage( iPlayer, iPlayer, iPlayer, flAmount );
		iDiff = -RoundToFloor( flAmount );
	} else if( flAmount < 0.0 ) {
		iDiff = HealPlayer( iPlayer, -flAmount, iPlayer, HF_NOCRITHEAL | HF_NOOVERHEAL );
	}

	Event eHealEvent = CreateEvent( "player_healonhit" );
	eHealEvent.SetInt( "entindex", iPlayer );
	eHealEvent.SetInt( "amount", iDiff );
	eHealEvent.FireToClient( iPlayer );
	delete eHealEvent;

	g_flHurtMe[ iPlayer ] = 0.0;
}