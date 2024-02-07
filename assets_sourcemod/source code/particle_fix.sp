#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dhooks>

public Plugin myinfo =
{
	name = "Bugfix: Particle Precaching",
	author = "Noclue",
	description = "Maybe fixes janky particle precaching?",
	version = "1.2",
	url = "no"
}

/*public void OnMapStart() {
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
}*/

public void OnMapStart() {
	PrecacheGeneric("particles/db_tracers.pcf", true);
	PrecacheGeneric("particles/kocw_beams.pcf", true);
	PrecacheGeneric("particles/laser_tracers.pcf", true);
	PrecacheGeneric("particles/medicflames.pcf", true);
	PrecacheGeneric("particles/pisser.pcf", true);
	PrecacheGeneric("particles/scattershock_fx.pcf", true);

	// Hydro Pump
	PrecacheParticleSystem("mediflame_red");
	PrecacheParticleSystem("mediflame_blue");
	PrecacheParticleSystem("mediflame_green");
	PrecacheParticleSystem("mediflame_yellow");

	// db tracers
	PrecacheParticleSystem("db_tracer_explosion");
	PrecacheParticleSystem("db_tracer_impact01");
	PrecacheParticleSystem("db_tracer_impact_smoke");
	PrecacheParticleSystem("db_tracer01");
	PrecacheParticleSystem("db_tracer01_red");
	PrecacheParticleSystem("db_tracer01_red_crit");
	PrecacheParticleSystem("db_tracer01_blue");
	PrecacheParticleSystem("db_tracer01_blue_crit");
	PrecacheParticleSystem("db_tracer01_green");
	PrecacheParticleSystem("db_tracer01_green_crit");
	PrecacheParticleSystem("db_tracer01_yellow");
	
	// Scattershock tracers
	PrecacheParticleSystem("bullet_scattershock_tracer01_red");
	PrecacheParticleSystem("bullet_scattershock_tracer01_red_crit");
	PrecacheParticleSystem("bullet_scattershock_tracer01_blue");
	PrecacheParticleSystem("bullet_scattershock_tracer01_blue_crit");
	PrecacheParticleSystem("bullet_scattershock_tracer01_green");
	PrecacheParticleSystem("bullet_scattershock_tracer01_green_crit");
	PrecacheParticleSystem("bullet_scattershock_tracer01_yellow");
	PrecacheParticleSystem("bullet_scattershock_tracer01_yellow_crit");

	// Medibeams
	PrecacheParticleSystem("medicgun_beam_red_new");
	PrecacheParticleSystem("kritz_beam_red_new");
	PrecacheParticleSystem("overhealer_red_beam");
	PrecacheParticleSystem("medicgun_invulnstatus_fullcharge_red_new");
	PrecacheParticleSystem("medicgun_beam_red_invun_new");
	PrecacheParticleSystem("medicgun_beam_blue_new");
	PrecacheParticleSystem("kritz_beam_blue_new");
	PrecacheParticleSystem("overhealer_blue_beam");
	PrecacheParticleSystem("medicgun_invulnstatus_fullcharge_blue_new");
	PrecacheParticleSystem("medicgun_beam_blue_invun_new");
	PrecacheParticleSystem("medicgun_beam_green_new");
	PrecacheParticleSystem("kritz_beam_green_new");
	PrecacheParticleSystem("overhealer_rgreen_beam");
	PrecacheParticleSystem("medicgun_invulnstatus_fullcharge_green_new");
	PrecacheParticleSystem("medicgun_beam_green_invun_new");
	PrecacheParticleSystem("medicgun_beam_yellow_new");
	PrecacheParticleSystem("kritz_beam_yellow_new");
	PrecacheParticleSystem("overhealer_yellow_beam");
	PrecacheParticleSystem("medicgun_invulnstatus_fullcharge_yellow_new");
	PrecacheParticleSystem("medicgun_beam_yellow_invun_new");
	
	// Toxin
	PrecacheParticleSystem("toxin_particles");
	PrecacheParticleSystem("toxin_particles_particulate");
	PrecacheParticleSystem("toxin_particles_smoke");
	
	// Lasers
	PrecacheParticleSystem("laser_tracer_red");
	PrecacheParticleSystem("laser_tracer_red_crit");
	PrecacheParticleSystem("laser_tracer_blue");
	PrecacheParticleSystem("laser_tracer_blue_crit");
	PrecacheParticleSystem("laser_tracer_green");
	PrecacheParticleSystem("laser_tracer_green_crit");
	PrecacheParticleSystem("laser_tracer_yellow");
	PrecacheParticleSystem("laser_tracer_yellow_crit");

	// PISS
	PrecacheParticleSystem("muzzle_piss_red");
	PrecacheParticleSystem("muzzle_piss_blue");
	PrecacheParticleSystem("muzzle_piss_green");
	PrecacheParticleSystem("muzzle_piss_yellow");
}

stock int PrecacheParticleSystem(const char[] particleSystem)
{
    static int particleEffectNames = INVALID_STRING_TABLE;

    if (particleEffectNames == INVALID_STRING_TABLE) {
        if ((particleEffectNames = FindStringTable("ParticleEffectNames")) == INVALID_STRING_TABLE) {
            return INVALID_STRING_INDEX;
        }
    }

    int index = FindStringIndex2(particleEffectNames, particleSystem);
    if (index == INVALID_STRING_INDEX) {
        int numStrings = GetStringTableNumStrings(particleEffectNames);
        if (numStrings >= GetStringTableMaxStrings(particleEffectNames)) {
            return INVALID_STRING_INDEX;
        }
        
        AddToStringTable(particleEffectNames, particleSystem);
        index = numStrings;
    }
    
    return index;
}

stock int FindStringIndex2(int tableidx, const char[] str)
{
    char buf[1024];
    
    int numStrings = GetStringTableNumStrings(tableidx);
    for (int i=0; i < numStrings; i++) {
        ReadStringTable(tableidx, i, buf, sizeof(buf));
        
        if (StrEqual(buf, str)) {
            return i;
        }
    }
    
    return INVALID_STRING_INDEX;
}