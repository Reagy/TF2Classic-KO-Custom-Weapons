/**
 * Create a new Resource Tracker
 * 
 * @param iPlayer            Player the resource belongs to
 * @param sName              Name of the resource
 * @param flStartAt          Default the state of the tracker's value
 * @param flRechargeTime     Time in seconds that the resource will take to regenerate. Default to never regenerate.
 */

enum {
	RTF_PERCENTAGE = 1 << 1,	//display value as a percentage
	RTF_DING = 1 << 2,		//play sound when fully charged
	RTF_RECHARGES = 1 << 3,
	RTF_NOOVERWRITE = 1 << 4,	//do not overwrite existing tracker
	RTF_CLEARONSPAWN = 1 << 5,	//reset on respawning
}

native void		Tracker_Create( int iPlayer, const char sName[32], float flStartAt = 100.0, float flRechargeRate = 0.0, int iFlags = 0 );
native void		Tracker_Remove( int iPlayer, const char sName[32] );
native float		Tracker_GetValue( int iPlayer, const char sName[32] );
native void		Tracker_SetValue( int iPlayer, const char sName[32], float flValue );
