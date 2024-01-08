Scriptname NetLink:API:NetworkLayerBase extends ObjectReference Hidden

; NISTRON SNE NETLINK PROTOCOL V1
; NetLink:API:NetworkLayer Base Class For Layer 3 Protocol Implementations - Custom scripting by niston

; require SUP
Import SUP_F4SE

; property backers
String _ScriptnameCache = ""										; caches the local scriptname

; CK configurable properties
NetLink:LinkLayer Property LinkLayer = none Auto
{ Leave at 'none' to use NetLink:LinkLayer instance attached to Self. }

; NetLink General Error Codes
Int Property OK_NOERROR = 0 AutoReadOnly Hidden						; operation succeeded without error
Int Property ERROR_UNAVAILABLE = -90000 AutoReadOnly Hidden			; bound game object is unavailable
Int Property ERROR_PROHIBITED = - 90001 AutoReadOnly Hidden			; prohibited by script logic


; NetLink NetworkLayer Error Codes (generic)
Int Property ERROR_NET_SCRIPTNAMELOOKUP = -3000 AutoReadOnly Hidden	; script name lookup failed
Int Property ERROR_NET_NOLINKLAYER = -3001 AutoReadOnly Hidden		; NetLink:LinkLayer reference is unavailable


;/
###############################
# Section: Runtime Properties #
###############################
/;
String Property NetworkLayerScriptname Hidden						; provides (cached) name of NetworkLayer implementation script
	String Function Get()		
		; name is cached?
		If (_ScriptnameCache != "")
			; yes, return from cache
			Return _ScriptnameCache
		Else
			; no, build name and cache
			String beginPattern = "["
			String endPattern = " < ("
			String refText = Self as String
			Int beginPos = SUPStringFind(refText, beginPattern, 0, 0)
			If (beginPos > -1)
				beginPos += 1 ; beginpattern length
				Int endPos = SUPStringFind(refText, endPattern, beginPos, 0)
				If (endPos > -1)
					endPos -= 1
					_ScriptnameCache = StringFindSubString(refText, beginPos, endPos)
					; success
					Return _ScriptnameCache
				EndIf
			EndIf
		EndIf
	EndFunction
EndProperty

;/
#####################################
# Section: Base Class Functionality #
#####################################
/;
Int Function Start()
	; ensure scriptname lookup works
	If (NetworkLayerScriptname == "")
		; failure to lookup and cache local scriptname
		Debug.Trace(Self + ": ERROR - NetworkLayer Script Name lookup failed.")
		Return ERROR_NET_SCRIPTNAMELOOKUP
	EndIf	
	
	; Connect to linklayer on attached reference if no specific reference is given
	If (LinkLayer == none)
		LinkLayer = (Self as ObjectReference) as NetLink:LinkLayer
	EndIf	
	; LinkLayer must resolve properly
	If (LinkLayer == none)
		; can't work without a NetLink Layer 2 implementation
		Debug.Trace(Self + ": ERROR - NetworkLayer base failed to start: NetLink:LinkLayer script not attached and no remote reference specified.")
		Return ERROR_NET_NOLINKLAYER
	EndIf	
	
	; startup survived, no error
	Return OK_NOERROR
EndFunction

Function Stop()
	; clear LinkLayer reference
	LinkLayer = none
	; clear scriptname cache
	_ScriptnameCache = ""
EndFunction

Bool Function CheckSuccessCode(Int code)													; check netlink return code for success
	Return (code > -1)
EndFunction

String Function ResolveErrorCode(Int code)													; resolves NetworkLayer base class error codes
	If (code == OK_NOERROR)
		Return "OK_NOERROR"	
	ElseIf (code == ERROR_UNAVAILABLE)
		Return "ERROR_UNAVAILABLE"
	ElseIf (code == ERROR_NET_SCRIPTNAMELOOKUP)
		Return "ERROR_NET_SCRIPTNAMELOOKUP"
	ElseIf (code == ERROR_NET_NOLINKLAYER)
		Return "ERROR_NET_NOLINKLAYER"
	Else
		If (LinkLayer)
			Return LinkLayer.ResolveErrorCode(code)
		Else
			Return "CODE_UNRESOLVABLE (" + code + ")"
		EndIf
	EndIf
EndFunction


;/
##########################################################
# Section: Abstract Methods, Derived Class MUST Override #
##########################################################
/;
String Function GetIdentifier()																; ABSTRACT: Network Layer Protocol Identification String
	Return "NetworkLayerBase"
EndFunction

String Function GetIdentifierDesc()
	Return "NetLink:NetworkLayer Base Class"
EndFunction

Int Function GetVersionMajor()																; ABSTRACT: Network Layer Protocol Version (major)
	Return 0
EndFunction

Int Function GetVersionMinor()																; ABSTRACT: Network Layer Protocol Version (minor)
	Return 0
EndFunction

;Function OnLinkReceive(Var[] eventArgs)													; ABSTRACT: FTR frame receiver function	
Function OnLinkReceive(NetLink:API:LinkLayerBase:NRSE_InvokeArgs eventArgs)							; ABSTRACT: FTR frame receiver function	(PAPYRUS VERSION until SUP acceleration is ready)
	Debug.Trace(Self + ": WARNING - OnLinkReceive invoked on NetworkLayer Base Class. Frame discarded.")
EndFunction

