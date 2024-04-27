#if defined _kocw_included
	#endinput
#endif
#define _kocw_included

#include <tf2c>
#include <dhooks>
#include <stocksoup/memory>
#include <sdkhooks>

//functional-style typecasting
#define address(%1) view_as<Address>(%1)

native float 	AttribHookFloat( float fValue, int iEntity, const char[] sAttributeClass );
native int	AttribHookString( char[] szOutput, int iMaxLen, int iEntity, const char[] szAttribute );
native int	AttribHookInt( int iValue, int iEntity, const char[] szAttributeClass )

native float	GetMedigunCharge( int iPlayer );
native int	GetEntityInSlot( int iPlayer, int iSlot );

native void 	SetNextThink( int iEntity, float flNextThink, const char[] sThinkContext );
native float 	GetNextThink( int iEntity, const char[] sThinkContext );

native void	SetSolid( int iEntity, iSolid );
native void	SetSolidFlags( int iEntity, int iFlags );
native void	SetCollisionGroup( int iEntity, int iGroup );
native void	SetSize( int iEntity, const float vecSizeMin[3], const float vecSizeMax[3] );

native void	StartLagCompensation( int iPlayer );
native void	FinishLagCompensation( int iPlayer );

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
	return GetVectorDistance( vecStart, vecTargetPos ) < flRadius;
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
native void AddPlayerHealer( int iReciever, int iSource, float flRate, bool bAllowCritHeals = true );
native void AddPlayerHealerTimed( int iReciever, int iSource, float flRate, float flDuration, bool bReset, bool bOverheal );
native void RemovePlayerHealer( int iReceiver, int iSource, int iHealerType = 0 );

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

stock float FRoundToFloor( float flVal ) {
	return flVal - FloatFraction( flVal );
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
//mask out the most significant bit (test if this works)
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

stock any LoadFromAddressOffset( Address aAddress, int iOffset, NumberType eNumberType = NumberType_Int32 ) {
	return LoadFromAddress( aAddress + address( iOffset ), eNumberType );
}
stock void StoreToAddressOffset( Address aAddress, int iOffset, any aValue, NumberType eNumberType = NumberType_Int32 ) {
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
static char g_szDmgOffsetNames[][] = {
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
		iOffsetCache[iValue] = GameConfGetOffset( hGameConf, g_szDmgOffsetNames[iValue] );
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
	int iViewedDisguiseTeam = GetEntProp( iViewed, Prop_Send, "m_nDisguiseTeam" );

	//if viewed is undisguised or really is the viewer's team, show the real team
	if( iViewedDisguiseTeam == 0 || iViewerTeam == iViewedRealTeam )
		return iViewedRealTeam;

	//grey disguises show the viewer's team
	if( iViewedDisguiseTeam == 7 )
		return iViewerTeam;

	//return the disguise
	return iViewedDisguiseTeam;	
}
stock bool IsPlayerMiniCritBoosted( int iPlayer ) {
	return TF2_IsPlayerInCondition( iPlayer, view_as<TFCond>( 133 ) ); //TF_COND_DAMAGE_BOOST
}
//thank you grand and wise IDA pro
//pro tip: tf2c.fgd has a list of all the conds with more up to date names than tf2ctools
stock bool IsPlayerCritBoosted( int iPlayer ) {
	return (
		TF2_IsPlayerInCondition( iPlayer, view_as<TFCond>( 11 ) ) ||	//TF_COND_CRITBOOSTED
		TF2_IsPlayerInCondition( iPlayer, view_as<TFCond>( 33 ) ) ||	//TF_COND_CRITBOOSTED_PUMPKIN
		TF2_IsPlayerInCondition( iPlayer, view_as<TFCond>( 34 ) ) ||	//TF_COND_CRITBOOSTED_USER_BUFF
		TF2_IsPlayerInCondition( iPlayer, view_as<TFCond>( 35 ) ) ||	//TF_COND_CRITBOOSTED_DEMO_CHARGE
		TF2_IsPlayerInCondition( iPlayer, view_as<TFCond>( 37 ) ) ||	//TF_COND_CRITBOOSTED_FIRST_BLOOD
		TF2_IsPlayerInCondition( iPlayer, view_as<TFCond>( 38 ) ) ||	//TF_COND_CRITBOOSTED_BONUS_TIME
		TF2_IsPlayerInCondition( iPlayer, view_as<TFCond>( 39 ) ) ||	//TF_COND_CRITBOOSTED_CTF_CAPTURE
		TF2_IsPlayerInCondition( iPlayer, view_as<TFCond>( 40 ) ) ||	//TF_COND_CRITBOOSTED_ON_KILL
		TF2_IsPlayerInCondition( iPlayer, view_as<TFCond>( 56 ) ) ||	//TF_COND_CRITBOOSTED_CARD_EFFECT
		TF2_IsPlayerInCondition( iPlayer, view_as<TFCond>( 105 ) )	//TF_COND_CRITBOOSTED_RUNE_TEMP
	);  
}

stock bool IsValidPlayer( int iPlayer ) {
	return iPlayer > 0 && iPlayer <= MaxClients;
}

stock void ParentModel( int iChild, int iParent, const char[] szAttach = "" ) {
	SetVariantString( "!activator" );
	AcceptEntityInput( iChild, "SetParent", iParent, iParent, 0 );
	if( !StrEqual( "", szAttach ) ) {
		SetVariantString( szAttach );
		AcceptEntityInput( iChild, "SetParentAttachment", iParent, iParent, 0 );
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
//todo: respect falloff modifying attributes
/*stock float TF2DamageFalloff( int iVictim, TFDamageInfo tfInfo ) {
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

	if( flCenter > 0.5 && IsValidEntity( tfInfo.iWeapon ) ) {
		static char szClassname[48];
		GetEntityClassname( tfInfo.iWeapon, szClassname, sizeof( szClassname ) );

		if( StrEqual( szClassname, "tf_weapon_scattergun" ) )
			flRandomDamage *= 1.5;
		else if(StrEqual( szClassname, "tf_weapon_rocketlauncher" ) ||
			StrEqual( szClassname, "tf_weapon_pipebomblauncher" ) )
			flRandomDamage *= 0.5;
	}

	float flOut = SimpleSplineRemapValClamped( flCenter, 0.0, 1.0, -flRandomDamage, flRandomDamage );
	return tfInfo.flDamage + flOut;
}*/

stock float TF2DamageFalloff( int iVictim, TFDamageInfo tfInfo ) {
	return TF2DamageFalloff2( iVictim, tfInfo.flDamage, tfInfo.iAttacker, tfInfo.iWeapon, tfInfo.iFlags );
}
stock float TF2DamageFalloff2( int iVictim, float flDamage, int iAttacker, int iWeapon, int iFlags, bool bWeakRampup = false ) {
	float flRandomDamage = flDamage * 0.5;
	float flCenter = 0.5;

	if ( iFlags & DMG_USEDISTANCEMOD ) {
		float vecOtherPos[3];
		float vecPos[3];

		GetEntPropVector( iVictim, Prop_Data, "m_vecAbsOrigin", vecPos );
		GetEntPropVector( iAttacker, Prop_Data, "m_vecAbsOrigin", vecOtherPos );

		SubtractVectors( vecPos, vecOtherPos, vecOtherPos );

		float flDistance = MaxFloat( 1.0,  SquareRoot( GetVectorLength( vecOtherPos, true ) ) );
		float flOptimalDistance = 512.0;

		flCenter = RemapValClamped( flDistance / flOptimalDistance, 0.0, 2.0, 1.0, 0.0 );
		if ( iFlags & DMG_NOCLOSEDISTANCEMOD ) {
			if ( flCenter > 0.5 )
				flCenter = RemapVal( flCenter, 0.5, 1.0, 0.5, 0.65 );
		}
	}

	if( flCenter > 0.5 && IsValidEntity( iWeapon ) ) {
		static char szClassname[96];
		GetEntityClassname( iWeapon, szClassname, sizeof( szClassname ) );

		if( StrEqual( szClassname, "tf_weapon_scattergun" ) )
			flRandomDamage *= 1.5;
		else if(StrEqual( szClassname, "tf_weapon_rocketlauncher" ) ||
			StrEqual( szClassname, "tf_weapon_pipebomblauncher" ) || bWeakRampup )
			flRandomDamage *= 0.5;
	}

	float flOut = SimpleSplineRemapValClamped( flCenter, 0.0, 1.0, -flRandomDamage, flRandomDamage );
	return flDamage + flOut;
}
stock float TF2DamageFalloff3( float flDamage, const float vecAttackerPos[3], const float vecVictimPos[3], int iWeapon, int iFlags, bool bWeakRampup = false ) {
	float flRandomDamage = flDamage * 0.5;
	float flCenter = 0.5;

	if ( iFlags & DMG_USEDISTANCEMOD ) {
		float vecOtherPos[3];
		SubtractVectors( vecAttackerPos, vecVictimPos, vecOtherPos );

		float flDistance = MaxFloat( 1.0, SquareRoot( GetVectorLength( vecOtherPos, true ) ) );
		float flOptimalDistance = 512.0;

		flCenter = RemapValClamped( flDistance / flOptimalDistance, 0.0, 2.0, 1.0, 0.0 );
		if ( iFlags & DMG_NOCLOSEDISTANCEMOD ) {
			if ( flCenter > 0.5 )
				flCenter = RemapVal( flCenter, 0.5, 1.0, 0.5, 0.65 );
		}
	}

	if( flCenter > 0.5 ) {
		if( bWeakRampup )
			flRandomDamage *= 0.25;
		else if( IsValidEntity( iWeapon ) ) {
			static char szClassname[96];
			GetEntityClassname( iWeapon, szClassname, sizeof( szClassname ) );

			if( StrEqual( szClassname, "tf_weapon_scattergun" ) )
				flRandomDamage *= 1.5;
			else if( StrEqual( szClassname, "tf_weapon_rocketlauncher" ) ||
				StrEqual( szClassname, "tf_weapon_pipebomblauncher" ) )
				flRandomDamage *= 0.5;
		}

		
	}

	float flOut = SimpleSplineRemapValClamped( flCenter, 0.0, 1.0, -flRandomDamage, flRandomDamage );
	return flDamage + flOut;
}

stock bool HasAmmoToFire( int iWeapon, int iOwner, int iAmmoCost, bool bUsesClip ) {
	if( bUsesClip ) {
		int iClip = GetEntProp( iWeapon, Prop_Send, "m_iClip1" );
		if( iClip < iAmmoCost )
			return false;
	}
	else {
		int iAmmoType = GetEntProp( iWeapon, Prop_Send, "m_iPrimaryAmmoType" );
		int iAmmo = GetEntProp( iOwner, Prop_Send, "m_iAmmo", 4, iAmmoType );
		if( iAmmo < iAmmoCost )
			return false;
	}
	return true;
}
stock void ConsumeAmmo( int iWeapon, int iOwner, int iAmmoCost, bool bUsesClip ) {
	if( bUsesClip ) {
		int iClip = GetEntProp( iWeapon, Prop_Send, "m_iClip1" );
		SetEntProp( iWeapon, Prop_Send, "m_iClip1", iClip - iAmmoCost );
	}
	else {
		int iAmmoType = GetEntProp( iWeapon, Prop_Send, "m_iPrimaryAmmoType" );
		int iAmmo = GetEntProp( iOwner, Prop_Send, "m_iAmmo", 4, iAmmoType );
		SetEntProp( iOwner, Prop_Send, "m_iAmmo", iAmmo - iAmmoCost, 4, iAmmoType );
	}
}

enum
{
	PATTACH_ABSORIGIN = 0,			// Create at absorigin, but don't follow
	PATTACH_ABSORIGIN_FOLLOW,		// Create at absorigin, and update to follow the entity
	PATTACH_CUSTOMORIGIN,			// Create at a custom origin, but don't follow
	PATTACH_POINT,					// Create on attachment point, but don't follow
	PATTACH_POINT_FOLLOW,			// Create on attachment point, and update to follow the entity

	PATTACH_WORLDORIGIN,			// Used for control points that don't attach to an entity

	PATTACH_ROOTBONE_FOLLOW,		// Create at the root bone of the entity, and update to follow

	MAX_PATTACH_TYPES,
};

stock int CreateParticle( const char[] szParticleName, float vecPos[3] = NULL_VECTOR, float vecAng[3] = NULL_VECTOR, float flDuration = -1.0 ) {
	int iParticle = CreateEntityByName( "info_particle_system" );

	DispatchKeyValue( iParticle, "effect_name", szParticleName );
	DispatchKeyValueInt( iParticle, "start_active", 1 );

	DispatchSpawn( iParticle );
	TeleportEntity( iParticle, vecPos, vecAng );
	ActivateEntity( iParticle );

	if( flDuration != -1.0 )
		CreateTimer( flDuration, Timer_RemoveParticle, EntIndexToEntRef( iParticle ) );

	return iParticle;
}

stock void ParentParticleToViewmodel( int iParticle, int iWeapon ) {
	bool bIsCModel = GetEntProp( iWeapon, Prop_Send, "m_iViewModelType" ) == 1;

	int iPlayer = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwnerEntity" );
	int iViewmodel = GetEntPropEnt( iPlayer, Prop_Send, "m_hViewModel" );
	ParentModel( iParticle, iViewmodel, bIsCModel ? "weapon_bone_l" : "muzzle" );
	SetEdictFlags( iParticle, 0 );
}
//idk how the bone works just try random bones on the weapon until it works
stock void ParentParticleToViewmodelEX( int iParticle, int iWeapon, const char[] szBoneName ) {
	bool bIsCModel = GetEntProp( iWeapon, Prop_Send, "m_iViewModelType" ) == 1;

	int iPlayer = GetEntPropEnt( iWeapon, Prop_Send, "m_hOwnerEntity" );
	int iViewmodel = GetEntPropEnt( iPlayer, Prop_Send, "m_hViewModel" );
	ParentModel( iParticle, iViewmodel, bIsCModel ? szBoneName : "muzzle" );
	SetEdictFlags( iParticle, 0 );
}

Action Timer_RemoveParticle( Handle hTimer, int iParticleRef ) {
	int iParticle = EntRefToEntIndex( iParticleRef );
	if( iParticle == -1 )
		return Plugin_Continue;

	RemoveEntity( iParticle );
	return Plugin_Continue;
}

//https://github.com/JoinedSenses/SourceMod-IncludeLibrary
stock void TE_SetupParticle(const char[] Name, const float origin[3] = NULL_VECTOR,
			const float start[3] = NULL_VECTOR, const float angles[3] = NULL_VECTOR,
			int entindex = -1, int attachtype = -1, int attachpoint = -1, bool resetParticles = true)
{
	// find string table
	int tblidx = FindStringTable("ParticleEffectNames");
	if (tblidx == INVALID_STRING_TABLE) 
	{
		LogError("Could not find string table: ParticleEffectNames");
		return;
	}
	

	// find particle index
	char tmp[256];
	int count = GetStringTableNumStrings(tblidx);
	int stridx = INVALID_STRING_INDEX;
	for (int i = 0; i < count; i++)
	{
		ReadStringTable(tblidx, i, tmp, sizeof(tmp));
		if (StrEqual(tmp, Name, false))
		{
			stridx = i;
			break;
		}
	}
	if (stridx == INVALID_STRING_INDEX)
	{
		LogError("Could not find particle: %s", Name);
		return;
	}

	TE_Start("TFParticleEffect");
	TE_WriteFloat("m_vecOrigin[0]", origin[0]);
	TE_WriteFloat("m_vecOrigin[1]", origin[1]);
	TE_WriteFloat("m_vecOrigin[2]", origin[2]);
	TE_WriteFloat("m_vecStart[0]", start[0]);
	TE_WriteFloat("m_vecStart[1]", start[1]);
	TE_WriteFloat("m_vecStart[2]", start[2]);
	TE_WriteVector("m_vecAngles", angles);
	TE_WriteNum("m_iParticleSystemIndex", stridx);

	if (entindex != -1)
	{
		TE_WriteNum("entindex", entindex);
	}

	if (attachtype != -1)
	{
		TE_WriteNum("m_iAttachType", attachtype);
	}

	if (attachpoint != -1)
	{
		TE_WriteNum("m_iAttachmentPointIndex", attachpoint);
	}

	TE_WriteNum("m_bResetParticles", resetParticles);
}

stock void TE_Particle(const char[] Name, const float origin[3] = NULL_VECTOR,
		const float start[3] = NULL_VECTOR, const float angles[3] = NULL_VECTOR,
		int entindex = -1, int attachtype = -1, int attachpoint = -1, bool resetParticles = true,
		float delay = 0.0)
{
	TE_SetupParticle(Name, origin, start, angles, entindex,
		attachtype, attachpoint, resetParticles);

	TE_SendToAll(delay);
}

//Wrapper that automatically fails if the SDKCall cannot be created
stock Handle EndPrepSDKCallSafe( const char[] szName ) {
	Handle hCall = EndPrepSDKCall();
	if( !hCall )
		SetFailState( "SDKCall setup for %s failed", szName );

	return hCall;
}
//Wrapper that automatically fails if the detour cannot be created
stock DynamicDetour DynamicDetourFromConfSafe( Handle hGameConf, const char[] szName ) {
	DynamicDetour dtDetour = DynamicDetour.FromConf( hGameConf, szName );
	if( !dtDetour )
		SetFailState( "Detour setup for %s failed", szName );

	return dtDetour;
}
//Wrapper that automatically fails if the hook cannot be created
stock DynamicHook DynamicHookFromConfSafe( Handle hGameConf, const char[] szName ) {
	DynamicHook dhHook = DynamicHook.FromConf( hGameConf, szName );
	if( !dhHook )
		SetFailState( "Hook setup for %s failed", szName );

	return dhHook;
}
//Wrapper that automatically fails if the hook cannot be created
stock int GameConfGetOffsetSafe( Handle hGameConf, const char[] szName )  {
	int iReturn = GameConfGetOffset( hGameConf, szName );
	if( iReturn == -1 )
		SetFailState( "Offset lookup for %s failed", szName );

	return iReturn;
}