#if defined _custom_entprops_included
	#endinput
#endif
#define _custom_entprops_included

native void SetCustomProp( int iEntityID, const char[] szPropertyName, any data );
native void SetCustomPropString( int iEntityID, const char[] szPropertyName, const char[] szValue );

native any GetCustomProp( int iEntityID, const char[] szPropertyName );
native void GetCustomPropString( int iEntityID, const char[] szPropertyName, char[] szBuffer, int iBufferSize );