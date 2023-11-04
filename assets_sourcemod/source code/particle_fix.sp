#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dhooks>

public Plugin myinfo =
{
	name = "Bugfix: Particle Precaching",
	author = "Noclue",
	description = "Fixes janky particle precaching.",
	version = "1.1",
	url = "no"
}

public void OnMapStart() {
	PrecacheEffect("ParticleEffect");
	PrecacheParticleEffect("mediflame_red");
	PrecacheParticleEffect("mediflame_blue");
	PrecacheParticleEffect("mediflame_green");
	PrecacheParticleEffect("mediflame_yellow");

	FuckMe( "particles/kocw_beams.pcf" );
	FuckMe( "particles/db_tracers.pcf" );
	FuckMe( "particles/medicflames.pcf" );
	FuckMe( "particles/scattershock_fx.pcf" );
}

void FuckMe( const char[] szFuckMe ) {
	AddFileToDownloadsTable( szFuckMe );
	PrecacheGeneric( szFuckMe, true );
}

//thank you internet people
stock void PrecacheEffect(const char[] sEffectName) {
	static int table = INVALID_STRING_TABLE;

	if( table == INVALID_STRING_TABLE )
	{
		table = FindStringTable( "EffectDispatch" );
	}
	bool save = LockStringTables(false);
	AddToStringTable( table, sEffectName );
	LockStringTables( save );
}

stock void PrecacheParticleEffect(const char[] sEffectName) {
	static int table = INVALID_STRING_TABLE;

	if( table == INVALID_STRING_TABLE )
	{
		table=FindStringTable( "ParticleEffectNames" );
	}
	bool save = LockStringTables(false);
	AddToStringTable( table, sEffectName );
	LockStringTables( save );
}  