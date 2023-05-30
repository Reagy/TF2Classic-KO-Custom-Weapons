#if defined _kocw_included
	#endinput
#endif
#define _kocw_included

#include <tf2c>
#include <stocksoup/memory>

native float 	AttribHookFloat( float fValue, int iEntity, const char[] sAttributeClass );
native int	AttribHookString( char[] szOutput, int iMaxLen, int iEntity, const char[] szAttribute );

native float	GetMedigunCharge( int iPlayer );
native int	GetEntityInSlot( int iPlayer, int iSlot );

native void 	SetNextThink( int iEntity, float flNextThink, const char[] sThinkContext );
native float 	GetNextThink( int iEntity, const char[] sThinkContext );

/**
 * Returns index of the player belonging to a CTFPlayerShared object
 * 
 * @param aShared     Location in memory of a CTFPlayerShared object
 * @return            Index of player
 */
native int		GetPlayerFromShared( Address aShared );
native Address		GetSharedFromPlayer( int iPlayer );

native void		ApplyPushFromDamage( int iPlayer, Address tfInfo, float vecDir[3] );

native int		FindEntityInSphere( int iStartEntity, float vecSearchPoint[3], float flRadius );

enum {
	HF_NOOVERHEAL = 1<<1, //prevent overheal
	HF_NOCRITHEAL = 1<<2, //prevent crit healing
}

native int		HealPlayer( int iPlayer, float flAmount, int iSource = -1, int iFlags = 0 );

/*
	MATH FUNCTIONS
*/

/**
 * I can't belive that SourcePawn doesn't have this
 * 
 * @param v1     Parameter 1
 * @param v2     Parameter 2
 * @return       Value of lowest parameter
 */
stock float MinFloat( float v1, float v2 ) {
	if( v1 < v2 ) return v1;
	return v2;
}

/**
 * I can't belive that SourcePawn doesn't have this
 * 
 * @param v1     Parameter 1
 * @param v2     Parameter 2
 * @return       Value of largest parameter
 */
stock float MaxFloat( float v1, float v2 ) {
	if( v1 > v2) return v1;
	return v2;
}

stock int MinInt( int v1, int v2 ) {
	if( v1 < v2) return v1;
	return v2;
}
stock int MaxInt( int v1, int v2 ) {
	if( v1 > v2) return v1;
	return v2;
}

stock float FloatClamp( float flValue, float flMin, float flMax ) {
	if( flValue >= flMax ) return flMax;
	if( flValue <= flMin) return flMin;
	return flValue;
}

stock int IntClamp( int iValue, int iMin, int iMax ) {
	if( iValue >= iMax ) return iMax;
	if( iValue <= iMin) return iMin;
	return iValue;
}

// Remap a value in the range [A,B] to [C,D].
stock float RemapVal( float flVal, float flA, float flB, float flC, float flD ) {
	if ( flA == flB )
		return flVal >= flB ? flD : flC;
	return flC + (flD - flC) * (flVal - flA) / (flB - flA);
}
stock float RemapValClamped( float flVal, float flA, float flB, float flC, float flD ) {
	if ( flA == flB )
		return flVal >= flB ? flD : flC;
	float flCVal = (flVal - flA) / (flB - flA);
	flCVal = FloatClamp( flCVal, 0.0, 1.0 );

	return flC + (flD - flC) * flCVal;
}

/*
	MEMORY FUNCTIONS
*/

stock any LoadFromAddressOffset( Address aAddress, int iOffset, NumberType eNumberType ) {
	return LoadFromAddress( aAddress + view_as< Address >( iOffset ), eNumberType );
}
stock void StoreToAddressOffset( Address aAddress, int iOffset, any aValue, NumberType eNumberType ) {
	StoreToAddress( aAddress + view_as< Address >( iOffset ), aValue, eNumberType );
}

stock any LoadFromEntity( int iEntity, int iOffset, NumberType iSize = NumberType_Int32 ) {
	return LoadFromAddressOffset( GetEntityAddress( iEntity ), iOffset, iSize );
}
stock void StoreToEntity( int iEntity, int iOffset, any anValue, NumberType iSize = NumberType_Int32 ) {
	StoreToAddressOffset( GetEntityAddress( iEntity ), iOffset, anValue, iSize );
}

/*
	GAME EVENT DEFINES
*/

#define EVENT_BUILTOBJECT		"player_builtobject"		//"userid", "object" (type), "index"
#define EVENT_UPGRADEOBJECT		"player_upgradedobject"		//"userid", "object" (type), "index", "isbuilder"
#define EVENT_CARRYOBJECT		"player_carryobject"		//"userid", "object" (type), "index"
#define EVENT_DROPOBJECT		"player_dropobject"			//"userid", "object" (type), "index"
#define EVENT_REMOVEOBJECT		"object_removed"			//"userid", "objecttype", "index"
#define EVENT_DESTROYOBJECT		"object_destroyed"			//"userid", "attacker", "assister", "weapon" (name), "weaponid", "objecttype", "index", "was_building"


#define EVENT_POSTINVENTORY		"post_inventory_application"
#define EVENT_PLAYERDEATH		"player_death"

/*
	CUSTOM ATTRIBUTE DEFINES
*/

#define ATR_MEDIGUN_TYPE	"custom_medigun_type"		//(ADDITIVE) 0: Default Behavior, 1: Guardian Angel, 2: Bio Waste Pump, 3: Totenwerfer
#define ATR_MEDIGUN_BEAM	"custom_medibeamtype"		//(ADDITIVE) 0: Stock Medigun, 1: Kritzkrieg, 2: Overhealer, 3: Bio Waste Pump
#define ATR_MEDIGUN_OVERHEAL	"custom_maximum_overheal"	//(MULTI) Scales maximum overheal from medigun
#define ATR_SELF_OVERHEAL	"custom_maximum_overheal_self"	//(MULTI) Scales maximum overheal on self

/*
	Custom Damage Handling
*/

enum {
	DI_FORCEX = 0,
	DI_FORCEY = 4,
	DI_FORCEZ = 8,

	DI_INFLICTOR = 36,
	DI_ATTACKER = 40,
	DI_WEAPON = 44,

	DI_DAMAGE = 48,
	DI_BASEDAMAGE = 52,

	DI_DAMAGEFLAGS = 60,
	DI_DAMAGECUSTOM = 64,

	DI_CRITTYPE = 108, //updated
}

enum {
	CT_NONE = 0,
	CT_MINI = 1,
	CT_FULL = 2
}

forward void OnTakeDamageTF( int iTarget, Address aTakeDamageInfo );
forward void OnTakeDamagePostTF( int iTarget, Address aTakeDamageInfo );
forward void OnTakeDamageAliveTF( int iTarget, Address aTakeDamageInfo );
forward void OnTakeDamageAlivePostTF( int iTarget, Address aTakeDamageInfo );

methodmap TFDamageInfo {
	public TFDamageInfo( Address aInfo ) {
		return view_as<TFDamageInfo>( aInfo );
	}

	property int iInflictor {
		public get() { return LoadEntityHandleFromAddress( view_as< Address >( this ) + view_as< Address >( DI_INFLICTOR ) ); }
		public set( int iEntity ) { StoreEntityHandleToAddress( view_as< Address >( this ) + view_as< Address >( DI_INFLICTOR ), iEntity ); }
	}
	property int iAttacker {
		public get() { return LoadEntityHandleFromAddress( view_as< Address >( this ) + view_as< Address >( DI_ATTACKER ) ); }
		public set( int iEntity ) { StoreEntityHandleToAddress( view_as< Address >( this ) + view_as< Address >( DI_ATTACKER ), iEntity ); }
	}
	property int iWeapon {
		public get() { return LoadEntityHandleFromAddress( view_as< Address >( this ) + view_as< Address >( DI_WEAPON ) ); }
		public set( int iEntity ) { StoreEntityHandleToAddress( view_as< Address >( this ) + view_as< Address >( DI_WEAPON ), iEntity ); }
	}

	property float flDamage {
		public get() { return LoadFromAddressOffset( view_as< Address >( this ), DI_DAMAGE, NumberType_Int32 ); }
		public set( float iValue ) { StoreToAddressOffset( view_as< Address >( this ), DI_DAMAGE, iValue, NumberType_Int32 ); }
	}
	property float flBaseDamage {
		public get() { return LoadFromAddressOffset( view_as< Address >( this ), DI_BASEDAMAGE, NumberType_Int32 ); }
		public set( float iValue ) { StoreToAddressOffset( view_as< Address >( this ), DI_BASEDAMAGE, iValue, NumberType_Int32 ); }
	}

	property int iFlags {
		public get() { return LoadFromAddressOffset( view_as< Address >( this ), DI_DAMAGEFLAGS, NumberType_Int32 ); }
		public set( int iValue ) { StoreToAddressOffset( view_as< Address >( this ), DI_DAMAGEFLAGS, iValue, NumberType_Int32 ); }
	}
	property int iCustom {
		public get() { return LoadFromAddressOffset( view_as< Address >( this ), DI_DAMAGECUSTOM, NumberType_Int32 ); }
		public set( int iValue ) { StoreToAddressOffset( view_as< Address >( this ), DI_DAMAGECUSTOM, iValue, NumberType_Int32 ); }
	}

	property int iCritType {
		public get() { return LoadFromAddressOffset( view_as< Address >( this ), DI_CRITTYPE, NumberType_Int32 ); }
		public set( int iValue ) { StoreToAddressOffset( view_as< Address >( this ), DI_CRITTYPE, iValue, NumberType_Int32 ); }
	}

	public void GetDamageForce( float flBuffer[3] ) {
		flBuffer[0] = LoadFromAddressOffset( view_as< Address >( this ), DI_FORCEX, NumberType_Int32 );
		flBuffer[1] = LoadFromAddressOffset( view_as< Address >( this ), DI_FORCEY, NumberType_Int32 );
		flBuffer[2] = LoadFromAddressOffset( view_as< Address >( this ), DI_FORCEZ, NumberType_Int32 );
	}
	public void SetDamageForce( float flX, float flY, float flZ ) {
		StoreToAddressOffset( view_as< Address >( this ), DI_FORCEX, flX, NumberType_Int32 );
		StoreToAddressOffset( view_as< Address >( this ), DI_FORCEY, flY, NumberType_Int32 );
		StoreToAddressOffset( view_as< Address >( this ), DI_FORCEZ, flZ, NumberType_Int32 );
	}
}

/*
	MISC FUNCTIONS
*/

//returns the team that iViewer sees iViewed as
stock int TeamSeenBy( int iViewer, int iViewed ) {
	int iViewerTeam = GetEntProp( iViewer, Prop_Send, "m_iTeamNum" );
	int iViewedRealTeam = GetEntProp( iViewed, Prop_Send, "m_iTeamNum" );
	int iViewedDisguiseTeam = GetEntProp( iViewer, Prop_Send, "m_nDisguiseTeam" );

	//if viewed is undisguised or really is the viewer's team, show the real team
	if( iViewedDisguiseTeam == 0 || iViewerTeam == iViewedRealTeam )
		return iViewedRealTeam;

	//grey disguises show the viewer's team
	if( iViewedDisguiseTeam == 7 )
		return iViewerTeam;

	//return the disguise
	return iViewedDisguiseTeam;	
}

stock bool IsValidPlayer( int iPlayer ) {
	return iPlayer > 0 && iPlayer <= MaxClients;
}

stock void ParentModel( int iChild, int iParent, const char[] szAttach = "" ) {
	SetVariantString( "!activator" );
	AcceptEntityInput( iChild, "SetParent", iParent, iChild, 0 );
	if( !StrEqual( "", szAttach ) ) {
		SetVariantString( szAttach );
		AcceptEntityInput( iChild, "SetParentAttachment", iChild, iChild, 0 );
	}
}

stock int FindModelString( int iModelIndex, char[] szModelString, int iStringSize ) {
	static int iStringTable = INVALID_STRING_TABLE;
	if ( iStringTable == INVALID_STRING_TABLE ) {
		iStringTable = FindStringTable( "modelprecache" );
	}
	return ReadStringTable( iStringTable, iModelIndex, szModelString, iStringSize );
}