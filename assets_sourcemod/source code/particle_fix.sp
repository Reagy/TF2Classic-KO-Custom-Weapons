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

	// Hydro Pump
	PrecacheParticleEffect("mediflame_red");
	PrecacheParticleEffect("mediflame_blue");
	PrecacheParticleEffect("mediflame_green");
	PrecacheParticleEffect("mediflame_yellow");

	// db tracers
	PrecacheParticleEffect("db_tracer01_red");
	PrecacheParticleEffect("db_tracer01_blue");
	PrecacheParticleEffect("db_tracer01_green");
	PrecacheParticleEffect("db_tracer01_yellow");

	// Medibeams
	PrecacheParticleEffect("medicgun_beam_red_new");
	PrecacheParticleEffect("medicgun_invulnstatus_fullcharge_red_new");
	PrecacheParticleEffect("medicgun_beam_blue_new");
	PrecacheParticleEffect("medicgun_invulnstatus_fullcharge_blue_new");
	PrecacheParticleEffect("medicgun_beam_green_new");
	PrecacheParticleEffect("medicgun_invulnstatus_fullcharge_green_new");
	PrecacheParticleEffect("medicgun_beam_yellow_new");
	PrecacheParticleEffect("medicgun_invulnstatus_fullcharge_yellow_new");

	// PISS
	PrecacheParticleEffect("muzzle_piss_red");
	PrecacheParticleEffect("muzzle_piss_blue");
	PrecacheParticleEffect("muzzle_piss_green");
	PrecacheParticleEffect("muzzle_piss_yellow");

	FuckMe( "particles/db_tracers.pcf" );
	FuckMe( "particles/kocw_beams.pcf" );
	FuckMe( "particles/laser_tracers.pcf" );
	FuckMe( "particles/medicflames.pcf" );
	FuckMe( "particles/pisser.pcf" );
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