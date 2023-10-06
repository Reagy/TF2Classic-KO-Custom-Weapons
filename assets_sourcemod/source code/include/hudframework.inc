#if defined _hudtracker_included
	#endinput
#endif
#define _hudtracker_included

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
	RTF_RECHARGES = 1 << 3,		//flag for future items that influence recharge
	RTF_NOOVERWRITE = 1 << 4,	//do not overwrite existing tracker (currently obsolete)
	RTF_CLEARONSPAWN = 1 << 5,	//reset on respawning
	RTF_FORWARDONFULL = 1 << 6,	//send a global forward when recharged
}

native void		Tracker_Create( int iPlayer, const char sName[32], bool bOverwrite = true );
native void		Tracker_SetMax( int iPlayer, const char szName[32], float flMax );
native void		Tracker_SetRechargeRate( int iPlayer, const char szName[32], float flRechargeRate );
native void		Tracker_SetFlags( int iPlayer, const char szName[32], int iFlags );
native void		Tracker_Remove( int iPlayer, const char sName[32] );
native float		Tracker_GetValue( int iPlayer, const char sName[32] );
native void		Tracker_SetValue( int iPlayer, const char sName[32], float flValue );

forward void 		Tracker_OnRecharge( int iPlayer, const char szTrackerName[32], float flValue );