#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dhooks>

public Plugin myinfo =
{
	name = "Bugfix: Particle Precaching",
	author = "Noclue",
	description = "Fixes janky particle precaching.",
	version = "1.0",
	url = "no"
}

public void OnMapStart() {
	PrecacheEffect("ParticleEffect");
	PrecacheParticleEffect("laser_tracer_red");
	PrecacheParticleEffect("laser_tracer_blue");
	PrecacheParticleEffect("laser_tracer_green");
	PrecacheParticleEffect("laser_tracer_yellow");
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