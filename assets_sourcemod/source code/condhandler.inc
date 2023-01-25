#if defined _customcond_included
  #endinput
#endif
#define _customcond_included

enum {
	TFCC_TOXIN = 0,
	TFCC_TOXINUBER,
	TFCC_TOXINPATIENT,
	TFCC_ANGELSHIELD,
	TFCC_ANGELINVULN,

	TFCC_LAST
}

native bool AddCustomCond( int iPlayer, int iEffect );
native void RemoveCustomCond( int iPlayer, int iEffect );

native bool HasCustomCond( int iPlayer, int iEffect );

native void GetCustomCondLevel( int iPlayer, int iEffect );
native void SetCustomCondLevel( int iPlayer, int iEffect, int iLevel );

native void GetCustomCondDuration( int iPlayer, int iEffect );
native void SetCustomCondDuration( int iPlayer, int iEffect, float flDuration, bool bAdd );

native void GetCustomCondSourcePlayer( int iPlayer, int iEffect );
native void SetCustomCondSourcePlayer( int iPlayer, int iEffect, int iSource );

native void GetCustomCondSourceWeapon( int iPlayer, int iEffect );
native void SetCustomCondSourceWeapon( int iPlayer, int iEffect, int iSource );