#if defined _customcond_included
  #endinput
#endif
#define _customcond_included

enum {
	TFCC_TOXIN = 0,
	TFCC_TOXINUBER, //unused

	TFCC_HYDROPUMPHEAL,

	TFCC_ANGELSHIELD,
	TFCC_ANGELINVULN,

	TFCC_QUICKUBER,

	TFCC_HYDROUBER,
	TFCC_UNUSED3,

	TFCC_LAST
}

native bool AddCustomCond( int iPlayer, int iEffect, int iSourceIndex = -1, int iWeaponIndex = -1 );
native bool RemoveCustomCond( int iPlayer, int iEffect );

native bool HasCustomCond( int iPlayer, int iEffect );

native any GetCustomCondLevel( int iPlayer, int iEffect );
native void SetCustomCondLevel( int iPlayer, int iEffect, any level );

native float GetCustomCondDuration( int iPlayer, int iEffect );
native void SetCustomCondDuration( int iPlayer, int iEffect, float flDuration, bool bAdd );

native int GetCustomCondSourcePlayer( int iPlayer, int iEffect );
native void SetCustomCondSourcePlayer( int iPlayer, int iEffect, int iSource );

native int GetCustomCondSourceWeapon( int iPlayer, int iEffect );
native void SetCustomCondSourceWeapon( int iPlayer, int iEffect, int iSource );