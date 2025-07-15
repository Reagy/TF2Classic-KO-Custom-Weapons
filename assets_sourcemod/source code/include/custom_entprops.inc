#if defined _custom_entprops_included
	#endinput
#endif
#define _custom_entprops_included

native void SetCustomProp( int iEntityID, const char[] szPropertyName, any data );
native void SetCustomPropString( int iEntityID, const char[] szPropertyName, const char[] szValue ); //unimplemented
native void SetCustomPropHandle( int iEntityID, const char[] szPropertyName, Handle hData ); //stored handles are tracked seperately and cleaned up automatically when the entity is destroyed

native bool GetCustomProp( int iEntityID, const char[] szPropertyName, any &data = 0 );
native void GetCustomPropString( int iEntityID, const char[] szPropertyName, char[] szBuffer, int iBufferSize ); //unimplemented
native bool GetCustomPropHandle( int iEntityID, const char[] szPropertyName, Handle &hData );

native bool HasCustomProp( int iEntityID, const char[] szPropertyName );