/**
 * Create a new Resource Tracker
 * 
 * @param iPlayer            Player the resource belongs to
 * @param sName              Name of the resource
 * @param flStartAt          Default the state of the tracker's value
 * @param flRechargeTime     Time in seconds that the resource will take to regenerate. Default to never regenerate.
 */
native void		Tracker_Create( int iPlayer, const char sName[32], float flStartAt = 100.0, float flRechargeRate = 0.0 );
native void		Tracker_Remove( int iPlayer, const char sName[32] );
native float	Tracker_GetValue( int iPlayer, const char sName[32] );
native void		Tracker_SetValue( int iPlayer, const char sName[32] );
