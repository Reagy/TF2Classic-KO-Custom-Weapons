#if defined _kocw_included
	#endinput
#endif
#define _kocw_included

#include <tf2c>
#include <stocksoup/memory>

//functional-style typecasting
#define address(%1) view_as<Address>(%1)

native float 	AttribHookFloat( float fValue, int iEntity, const char[] sAttributeClass );
native int	AttribHookString( char[] szOutput, int iMaxLen, int iEntity, const char[] szAttribute );

native float	GetMedigunCharge( int iPlayer );
native int	GetEntityInSlot( int iPlayer, int iSlot );

native void 	SetNextThink( int iEntity, float flNextThink, const char[] sThinkContext );
native float 	GetNextThink( int iEntity, const char[] sThinkContext );

native void	SetSolid( int iEntity, iSolid );
native void	SetSolidFlags( int iEntity, int iFlags );
native void	SetCollisionGroup( int iEntity, int iGroup );
native void	SetSize( int iEntity, const float vecSizeMin[3], const float vecSizeMax[3] );

//http://graphics.stanford.edu/~seander/bithacks.html#CountBitsSetParallel
stock int CountBits( int iBits ) {
	iBits = iBits - ( ( iBits >> 1 ) & 0x55555555 );			// reuse input as temporary
	iBits = ( iBits & 0x33333333 ) + ( ( iBits >> 2 ) & 0x33333333 );	// temp
	return ( ( iBits + ( iBits >> 4 ) & 0xF0F0F0F ) * 0x1010101 ) >> 24;	// count
}

enum struct PlayerFlags {
	int iFlags[ 2 ];

	void Set( int iPlayer, bool bValue ) {
		if( iPlayer < 1 || iPlayer > MaxClients )
			return;

		int iIndex = ( ( iPlayer + 31 ) / 32 ) - 1;
		int iOffset = ( iPlayer - 1 ) % 32;
		this.iFlags[ iIndex ] = bValue ? this.iFlags[ iIndex ] | ( 1 << iOffset ) : this.iFlags[ iIndex ] & ~( 1 << iOffset ) ;
	}
	void SetDirect( int iOffset, int iNewVal ) {
		this.iFlags[ iOffset ] = iNewVal;
	}

	bool Get( int iPlayer ) {
		if( iPlayer < 1 || iPlayer > MaxClients )
			return false;

		int iIndex = ( ( iPlayer + 31 ) / 32 ) - 1;
		int iOffset = ( iPlayer - 1 ) % 32;
		return view_as<bool>( this.iFlags[ iIndex ] & ( 1 << iOffset ) );
	}
	int GetDirect( int iOffset ) {
		return this.iFlags[ iOffset ];
	}

	int GetTotalBits() {
		return CountBits( this.iFlags[ 0 ] ) + CountBits( this.iFlags[ 1 ] );
	}
}

//solid types
enum
{
	SOLID_NONE	= 0,	// no solid model
	SOLID_BSP	= 1,	// a BSP tree
	SOLID_BBOX	= 2,	// an AABB
	SOLID_OBB	= 3,	// an OBB (not implemented yet)
	SOLID_OBB_YAW	= 4,	// an OBB, constrained so that it can only yaw
	SOLID_CUSTOM	= 5,	// Always call into the entity for tests
	SOLID_VPHYSICS	= 6,	// solid vphysics object, get vcollide from the model and collide with that
	SOLID_LAST,
};

//solid flags
enum
{
	FSOLID_CUSTOMRAYTEST		= 0x0001,	// Ignore solid type + always call into the entity for ray tests
	FSOLID_CUSTOMBOXTEST		= 0x0002,	// Ignore solid type + always call into the entity for swept box tests
	FSOLID_NOT_SOLID		= 0x0004,	// Are we currently not solid?
	FSOLID_TRIGGER			= 0x0008,	// This is something may be collideable but fires touch functions
							// even when it's not collideable (when the FSOLID_NOT_SOLID flag is set)
	FSOLID_NOT_STANDABLE		= 0x0010,	// You can't stand on this
	FSOLID_VOLUME_CONTENTS		= 0x0020,	// Contains volumetric contents (like water)
	FSOLID_FORCE_WORLD_ALIGNED	= 0x0040,	// Forces the collision rep to be world-aligned even if it's SOLID_BSP or SOLID_VPHYSICS
	FSOLID_USE_TRIGGER_BOUNDS	= 0x0080,	// Uses a special trigger bounds separate from the normal OBB
	FSOLID_ROOT_PARENT_ALIGNED	= 0x0100,	// Collisions are defined in root parent's local coordinate space
	FSOLID_TRIGGER_TOUCH_DEBRIS	= 0x0200,	// This trigger will touch debris objects

	FSOLID_MAX_BITS	= 10
};

//collision groups
enum
{
	COLLISION_GROUP_NONE					= 0,
	COLLISION_GROUP_DEBRIS					= 1,	// Collides with nothing but world and static stuff
	COLLISION_GROUP_DEBRIS_TRIGGER				= 2,	// Same as debris, but hits triggers
	COLLISION_GROUP_INTERACTIVE_DEBRIS			= 3,	// Collides with everything except other interactive debris or debris
	COLLISION_GROUP_INTERACTIVE				= 4,	// Collides with everything except interactive debris or debris
	COLLISION_GROUP_PLAYER					= 5,
	COLLISION_GROUP_BREAKABLE_GLASS				= 6,
	COLLISION_GROUP_VEHICLE					= 7,
	COLLISION_GROUP_PLAYER_MOVEMENT				= 8,	// For HL2, same as Collision_Group_Player, for
									// TF2, this filters out other players and CBaseObjects
	COLLISION_GROUP_NPC					= 9,	// Generic NPC group
	COLLISION_GROUP_IN_VEHICLE				= 10,	// for any entity inside a vehicle
	COLLISION_GROUP_WEAPON					= 11,	// for any weapons that need collision detection
	COLLISION_GROUP_VEHICLE_CLIP				= 12,	// vehicle clip brush to restrict vehicle movement
	COLLISION_GROUP_PROJECTILE				= 13,	// Projectiles!
	COLLISION_GROUP_DOOR_BLOCKER				= 14,	// Blocks entities not permitted to get near moving doors
	COLLISION_GROUP_PASSABLE_DOOR				= 15,	// Doors that the player shouldn't collide with
	COLLISION_GROUP_DISSOLVING				= 16,	// Things that are dissolving are in this group
	COLLISION_GROUP_PUSHAWAY				= 17,	// Nonsolid on client and server, pushaway in player code

	COLLISION_GROUP_NPC_ACTOR				= 18,	// Used so NPCs in scripts ignore the player.
	COLLISION_GROUP_NPC_SCRIPTED				= 19,	// USed for NPCs in scripts that should not collide with each other

	TF_COLLISIONGROUP_GRENADES				= 20,
	TFCOLLISION_GROUP_OBJECT				= 21,
	TFCOLLISION_GROUP_OBJECT_SOLIDTOPLAYERMOVEMENT		= 22,
	TFCOLLISION_GROUP_COMBATOBJECT				= 23,
	TFCOLLISION_GROUP_ROCKETS				= 24,	// Solid to players, but not player movement. ensures touch calls are originating from rocket
	TFCOLLISION_GROUP_RESPAWNROOMS				= 25,
	TFCOLLISION_GROUP_ROCKET_BUT_NOT_WITH_OTHER_ROCKETS	= 27,
};

//entity flags
enum
{
	EFL_KILLME	=			(1<<0),	// This entity is marked for death -- This allows the game to actually delete ents at a safe time
	EFL_DORMANT	=			(1<<1),	// Entity is dormant, no updates to client
	EFL_NOCLIP_ACTIVE =			(1<<2),	// Lets us know when the noclip command is active.
	EFL_SETTING_UP_BONES =			(1<<3),	// Set while a model is setting up its bones.
	EFL_KEEP_ON_RECREATE_ENTITIES = 	(1<<4), // This is a special entity that should not be deleted when we restart entities only

	EFL_HAS_PLAYER_CHILD=			(1<<4),	// One of the child entities is a player.

	EFL_DIRTY_SHADOWUPDATE =		(1<<5),	// Client only- need shadow manager to update the shadow...
	EFL_NOTIFY =				(1<<6),	// Another entity is watching events on this entity (used by teleport)

	// The default behavior in ShouldTransmit is to not send an entity if it doesn't
	// have a model. Certain entities want to be sent anyway because all the drawing logic
	// is in the client DLL. They can set this flag and the engine will transmit them even
	// if they don't have a model.
	EFL_FORCE_CHECK_TRANSMIT =		(1<<7),

	EFL_BOT_FROZEN =			(1<<8),	// This is set on bots that are frozen.
	EFL_SERVER_ONLY =			(1<<9),	// Non-networked entity.
	EFL_NO_AUTO_EDICT_ATTACH =		(1<<10), // Don't attach the edict; we're doing it explicitly
	
	// Some dirty bits with respect to abs computations
	EFL_DIRTY_ABSTRANSFORM =		(1<<11),
	EFL_DIRTY_ABSVELOCITY =			(1<<12),
	EFL_DIRTY_ABSANGVELOCITY =		(1<<13),
	EFL_DIRTY_SURROUNDING_COLLISION_BOUNDS= (1<<14),
	EFL_DIRTY_SPATIAL_PARTITION =		(1<<15),
//	UNUSED				=	(1<<16),

	EFL_IN_SKYBOX =				(1<<17),	// This is set if the entity detects that it's in the skybox.
											// This forces it to pass the "in PVS" for transmission.
	EFL_USE_PARTITION_WHEN_NOT_SOLID =	(1<<18),	// Entities with this flag set show up in the partition even when not solid
	EFL_TOUCHING_FLUID =			(1<<19),	// Used to determine if an entity is floating

	// FIXME: Not really sure where I should add this...
	EFL_IS_BEING_LIFTED_BY_BARNACLE = 	(1<<20),
	EFL_NO_ROTORWASH_PUSH =			(1<<21),		// I shouldn't be pushed by the rotorwash
	EFL_NO_THINK_FUNCTION =			(1<<22),
	EFL_NO_GAME_PHYSICS_SIMULATION = 	(1<<23),

	EFL_CHECK_UNTOUCH =			(1<<24),
	EFL_DONTBLOCKLOS =			(1<<25),		// I shouldn't block NPC line-of-sight
	EFL_DONTWALKON =			(1<<26),		// NPC;s should not walk on this entity
	EFL_NO_DISSOLVE =			(1<<27),		// These guys shouldn't dissolve
	EFL_NO_MEGAPHYSCANNON_RAGDOLL = 	(1<<28),	// Mega physcannon can't ragdoll these guys.
	EFL_NO_WATER_VELOCITY_CHANGE  =		(1<<29),	// Don't adjust this entity's velocity when transitioning into water
	EFL_NO_PHYSCANNON_INTERACTION =		(1<<30),	// Physcannon can't pick these up or punt them
	EFL_NO_DAMAGE_FORCES =			(1<<31),	// Doesn't accept forces from physics damage
};

//entity flags
enum {
	EF_BONEMERGE			= 0x001,	// Performs bone merge on client side
	EF_BRIGHTLIGHT 			= 0x002,	// DLIGHT centered at entity origin
	EF_DIMLIGHT 			= 0x004,	// player flashlight
	EF_NOINTERP			= 0x008,	// don't interpolate the next frame
	EF_NOSHADOW			= 0x010,	// Don't cast no shadow
	EF_NODRAW			= 0x020,	// don't draw entity
	EF_NORECEIVESHADOW		= 0x040,	// Don't receive no shadow
	EF_BONEMERGE_FASTCULL		= 0x080,	// For use with EF_BONEMERGE. If this is set, then it places this ent's origin at its
							// parent and uses the parent's bbox + the max extents of the aiment.
							// Otherwise, it sets up the parent's bones every frame to figure out where to place
							// the aiment, which is inefficient because it'll setup the parent's bones even if
							// the parent is not in the PVS.
	EF_ITEM_BLINK			= 0x100,	// blink an item so that the user notices it.
	EF_PARENT_ANIMATES		= 0x200,	// always assume that the parent entity is animating
	EF_MAX_BITS = 10
};

//m_takedamage
enum {
	DAMAGE_NO = 0,
	DAMAGE_EVENTS_ONLY,
	DAMAGE_YES,
	DAMAGE_AIM,
};

/**
 * Returns index of the player belonging to a CTFPlayerShared object
 * 
 * @param aShared	Location in memory of a CTFPlayerShared object
 * @return		Index of player
 */
native int GetPlayerFromShared( Address aShared );
/**
 * Returns the address of a CTFPlayerShared object from a player
 * @param iPlayer	Index of player to retrieve from
 * @return		Address of a CTFPlayerShared instance	
 */
native Address GetSharedFromPlayer( int iPlayer );

native void ApplyPushFromDamage( int iPlayer, Address tfInfo, float vecDir[3] );

native int FindEntityInSphere( int iStartEntity, float vecSearchPoint[3], float flRadius );

stock bool PlayerInRadius( float vecStart[3], float flRadius, int iPlayer ) {
	if( !IsClientInGame( iPlayer ) || !IsPlayerAlive( iPlayer ) )
		return false;

	float vecTargetPos[3];
	GetEntPropVector( iPlayer, Prop_Data, "m_vecAbsOrigin", vecTargetPos );
	return GetVectorDistance( vecStart, vecTargetPos, true ) < flRadius;
}
stock void PlayersInRadius( float vecStart[3], float flRadius, bool bOutput[ MAXPLAYERS+1 ] ) {
	for( int i = 0; i < MaxClients; i++ ) {
		bOutput[i] = PlayerInRadius( vecStart, flRadius, i );
	}
}

enum {
	HF_NOOVERHEAL = 1<<1, //prevent overheal
	HF_NOCRITHEAL = 1<<2, //prevent crit healing
}

native int HealPlayer( int iPlayer, float flAmount, int iSource = -1, int iFlags = 0 );

/*
	MATH FUNCTIONS
*/

stock float MinFloat( float v1, float v2 ) {
	return ( v1 < v2 ) ? v1 : v2;
}
stock float MaxFloat( float v1, float v2 ) {
	return ( v1 > v2 ) ? v1 : v2;
}
stock float FloatClamp( float flValue, float flMin, float flMax ) {
	return MinFloat( MaxFloat( flValue, flMin ), flMax );
}

stock int MinInt( int v1, int v2 ) {
	return ( v1 < v2 ) ? v1 : v2;
}
stock int MaxInt( int v1, int v2 ) {
	return ( v1 > v2 ) ? v1 : v2;
}
stock int IntClamp( int iValue, int iMin, int iMax ) {
	return MinInt( MaxInt( iValue, iMin ), iMax );
}
//mask out the most significant bit
stock int IntAbs( int iValue ) {
	return iValue & 0x7FFFFFFF;
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

// hermite basis function for smooth interpolation
// Similar to Gain() above, but very cheap to call
// value should be between 0 & 1 inclusive
stock float SimpleSpline( float flVal ) {
	float flValSquared = flVal * flVal;

	// Nice little ease-in, ease-out spline-like curve
	return ( 3.0 * flValSquared - 2.0 * flValSquared * flVal );
}

// remaps a value in [startInterval, startInterval+rangeInterval] from linear to
// spline using SimpleSpline
stock float SimpleSplineRemapValClamped( float flVal, float flA, float flB, float flC, float flD ) {
	if ( flA == flB )
		return flVal >= flB ? flD : flC;
	float flNewVal = ( flVal - flA ) / ( flB - flA );
	flNewVal = FloatClamp( flNewVal, 0.0, 1.0 );
	return flC + (flD - flC) * SimpleSpline( flNewVal );
}

/*
	MEMORY FUNCTIONS
*/

stock any LoadFromAddressOffset( Address aAddress, int iOffset, NumberType eNumberType ) {
	return LoadFromAddress( aAddress + address( iOffset ), eNumberType );
}
stock void StoreToAddressOffset( Address aAddress, int iOffset, any aValue, NumberType eNumberType ) {
	StoreToAddress( aAddress + address( iOffset ), aValue, eNumberType );
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
	DI_FORCEY = 1,
	DI_FORCEZ,

	DI_SOURCEX,
	DI_SOURCEY,
	DI_SOURCEZ,

	DI_REPORTX,
	DI_REPORTY,
	DI_REPORTZ,

	DI_INFLICTOR,
	DI_ATTACKER,
	DI_WEAPON,

	DI_DAMAGE,
	DI_BASEDAMAGE,

	DI_DAMAGEFLAGS,
	DI_DAMAGECUSTOM,

	DI_CRITTYPE, //updated

	DI_SIZE
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
forward void OnTakeDamageBuilding( int iBuilding, Address aTakeDamageInfo );

int iOffsetCache[DI_SIZE] = { -1, ... };
static char szOffsetNames[][] = {
	"CTakeDamageInfo::m_vecDamageForce.x",
	"CTakeDamageInfo::m_vecDamageForce.y",
	"CTakeDamageInfo::m_vecDamageForce.z",

	"CTakeDamageInfo::m_vecDamagePosition.x",
	"CTakeDamageInfo::m_vecDamagePosition.y",
	"CTakeDamageInfo::m_vecDamagePosition.z",

	"CTakeDamageInfo::m_vecReportedPosition.x",
	"CTakeDamageInfo::m_vecReportedPosition.y",
	"CTakeDamageInfo::m_vecReportedPosition.z",

	"CTakeDamageInfo::m_hInflictor",
	"CTakeDamageInfo::m_hAttacker",
	"CTakeDamageInfo::m_hWeapon",

	"CTakeDamageInfo::m_flDamage",
	"CTakeDamageInfo::m_flBaseDamage",

	"CTakeDamageInfo::m_bitsDamageType",
	"CTakeDamageInfo::m_iDamageCustom",

	"CTakeDamageInfo::m_iCritType",
}

int DMGInfoOffset( int iValue ) {
	if( iOffsetCache[iValue] == -1 ) {
		Handle hGameConf = LoadGameConfigFile("kocw.gamedata");
		iOffsetCache[iValue] = GameConfGetOffset( hGameConf, szOffsetNames[iValue] );
		delete hGameConf;
	}

	return iOffsetCache[iValue];
}

methodmap TFDamageInfo {
	public TFDamageInfo( Address aInfo ) {
		return view_as<TFDamageInfo>( aInfo );
	}

	property int iInflictor {
		public get() { return LoadEntityHandleFromAddress( address( this ) + address( DMGInfoOffset( DI_INFLICTOR ) ) ); }
		public set( int iEntity ) { StoreEntityHandleToAddress( address( this ) + address( DMGInfoOffset( DI_INFLICTOR ) ), iEntity ); }
	}
	property int iAttacker {
		public get() { return LoadEntityHandleFromAddress( address( this ) + address( DMGInfoOffset( DI_ATTACKER ) ) ); }
		public set( int iEntity ) { StoreEntityHandleToAddress( address( this ) + address( DMGInfoOffset( DI_ATTACKER ) ), iEntity ); }
	}
	property int iWeapon {
		public get() { return LoadEntityHandleFromAddress( address( this ) + address( DMGInfoOffset( DI_WEAPON ) ) ); }
		public set( int iEntity ) { StoreEntityHandleToAddress( address( this ) + address( DMGInfoOffset( DI_WEAPON ) ), iEntity ); }
	}

	property float flDamage {
		public get() { return LoadFromAddressOffset( address( this ), DMGInfoOffset( DI_DAMAGE ), NumberType_Int32 ); }
		public set( float iValue ) { StoreToAddressOffset( address( this ), DMGInfoOffset( DI_DAMAGE ), iValue, NumberType_Int32 ); }
	}
	property float flBaseDamage {
		public get() { return LoadFromAddressOffset( address( this ), DMGInfoOffset( DI_BASEDAMAGE ), NumberType_Int32 ); }
		public set( float iValue ) { StoreToAddressOffset( address( this ), DMGInfoOffset( DI_BASEDAMAGE ), iValue, NumberType_Int32 ); }
	}

	property int iFlags {
		public get() { return LoadFromAddressOffset( address( this ), DMGInfoOffset( DI_DAMAGEFLAGS ), NumberType_Int32 ); }
		public set( int iValue ) { StoreToAddressOffset( address( this ), DMGInfoOffset( DI_DAMAGEFLAGS ), iValue, NumberType_Int32 ); }
	}
	property int iCustom {
		public get() { return LoadFromAddressOffset( address( this ), DMGInfoOffset( DI_DAMAGECUSTOM ), NumberType_Int32 ); }
		public set( int iValue ) { StoreToAddressOffset( address( this ), DMGInfoOffset( DI_DAMAGECUSTOM ), iValue, NumberType_Int32 ); }
	}

	property int iCritType {
		public get() { return LoadFromAddressOffset( address( this ), DMGInfoOffset( DI_CRITTYPE ), NumberType_Int32 ); }
		public set( int iValue ) { StoreToAddressOffset( address( this ), DMGInfoOffset( DI_CRITTYPE ), iValue, NumberType_Int32 ); }
	}

	public void GetDamageForce( float flBuffer[3] ) {
		flBuffer[0] = LoadFromAddressOffset( address( this ), DMGInfoOffset( DI_FORCEX ), NumberType_Int32 );
		flBuffer[1] = LoadFromAddressOffset( address( this ), DMGInfoOffset( DI_FORCEY ), NumberType_Int32 );
		flBuffer[2] = LoadFromAddressOffset( address( this ), DMGInfoOffset( DI_FORCEZ ), NumberType_Int32 );
	}
	public void SetDamageForce( float flX, float flY, float flZ ) {
		StoreToAddressOffset( address( this ), DMGInfoOffset( DI_FORCEX ), flX, NumberType_Int32 );
		StoreToAddressOffset( address( this ), DMGInfoOffset( DI_FORCEY ), flY, NumberType_Int32 );
		StoreToAddressOffset( address( this ), DMGInfoOffset( DI_FORCEZ ), flZ, NumberType_Int32 );
	}
	public void GetDamageSource( float flBuffer[3] ) {
		flBuffer[0] = LoadFromAddressOffset( address( this ), DMGInfoOffset( DI_SOURCEX ), NumberType_Int32 );
		flBuffer[1] = LoadFromAddressOffset( address( this ), DMGInfoOffset( DI_SOURCEY ), NumberType_Int32 );
		flBuffer[2] = LoadFromAddressOffset( address( this ), DMGInfoOffset( DI_SOURCEZ ), NumberType_Int32 );
	}
	public void SetDamageSource( float flX, float flY, float flZ ) {
		StoreToAddressOffset( address( this ), DMGInfoOffset( DI_SOURCEX ), flX, NumberType_Int32 );
		StoreToAddressOffset( address( this ), DMGInfoOffset( DI_SOURCEY ), flY, NumberType_Int32 );
		StoreToAddressOffset( address( this ), DMGInfoOffset( DI_SOURCEZ ), flZ, NumberType_Int32 );
	}
	public void GetDamageReported( float flBuffer[3] ) {
		flBuffer[0] = LoadFromAddressOffset( address( this ), DMGInfoOffset( DI_REPORTX ), NumberType_Int32 );
		flBuffer[1] = LoadFromAddressOffset( address( this ), DMGInfoOffset( DI_REPORTY ), NumberType_Int32 );
		flBuffer[2] = LoadFromAddressOffset( address( this ), DMGInfoOffset( DI_REPORTZ ), NumberType_Int32 );
	}
	public void SetDamageReported( float flX, float flY, float flZ ) {
		StoreToAddressOffset( address( this ), DMGInfoOffset( DI_REPORTX ), flX, NumberType_Int32 );
		StoreToAddressOffset( address( this ), DMGInfoOffset( DI_REPORTY ), flY, NumberType_Int32 );
		StoreToAddressOffset( address( this ), DMGInfoOffset( DI_REPORTZ ), flZ, NumberType_Int32 );
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

//shitty copypaste of tf2's falloff algorithm
stock float TF2DamageFalloff( int iVictim, TFDamageInfo tfInfo ) {
	float flRandomDamage = tfInfo.flDamage * 0.5;
	float flCenter = 0.5;

	if ( tfInfo.iFlags & DMG_USEDISTANCEMOD ) {
		float vecOtherPos[3];
		float vecPos[3];

		GetEntPropVector( iVictim, Prop_Data, "m_vecAbsOrigin", vecPos );
		GetEntPropVector( tfInfo.iAttacker, Prop_Data, "m_vecAbsOrigin", vecOtherPos );

		SubtractVectors( vecPos, vecOtherPos, vecOtherPos );

		float flDistance = MaxFloat( 1.0,  SquareRoot( GetVectorLength( vecOtherPos, true ) ) );
		float flOptimalDistance = 512.0;

		flCenter = RemapValClamped( flDistance / flOptimalDistance, 0.0, 2.0, 1.0, 0.0 );
		if ( tfInfo.iFlags & DMG_NOCLOSEDISTANCEMOD ) {
			if ( flCenter > 0.5 )
				flCenter = RemapVal( flCenter, 0.5, 1.0, 0.5, 0.65 );
		}
	}

	float flOut = SimpleSplineRemapValClamped( flCenter, 0.0, 1.0, -flRandomDamage, flRandomDamage );
	return tfInfo.flDamage + flOut;
}