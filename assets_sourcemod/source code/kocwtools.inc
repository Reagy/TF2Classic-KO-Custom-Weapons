native float 	AttribHookFloat( float fValue, int iEntity, const char[] sAttributeClass );
native void 	AttribHookString( char[] buffer, int iEntity, const char[] sAttributeClass );

native float	GetMedigunCharge( int iPlayer );
native int		GetEntityInSlot( int iPlayer, int iSlot );

native void 	SetNextThink( int iEntity, float flNextThink, const char[] sThinkContext );
native float 	GetNextThink( int iEntity, const char[] sThinkContext );

native int		GetPlayerFromShared( Address aShared );

/*
	MATH FUNCTIONS
*/

stock float ClampFloat(float flValue, float flMin, float flMax) {
	if (flValue > flMax) {
		return flMax;
	} else if (flValue < flMin) {
		return flMin;
	}
	return flValue;
}

// Remap a value in the range [A,B] to [C,D].
stock float RemapVal( float flVal, float flA, float flB, float flC, float flD )
{
	if ( flA == flB )
		return flVal >= flB ? flD : flC;
	return flC + (flD - flC) * (flVal - flA) / (flB - flA);
}
stock float RemapValClamped( float flVal, float flA, float flB, float flC, float flD )
{
	if ( flA == flB )
		return flVal >= flB ? flD : flC;
	float flCVal = (flVal - flA) / (flB - flA);
	flCVal = ClampFloat( flCVal, 0.0, 1.0 );

	return flC + (flD - flC) * flCVal;
}