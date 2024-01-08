Scriptname NetLink:GCP:Protocol extends NetLink:API:NetworkLayerBase

; The Group Control Protocol V1
; GCP protocol implementation - Custom scripting by niston

; 0.49
; GCP:Protocol: Fix minor bug in OnLinkReceive
; GCP:Protocol: Fix some useless log spam in Stop procedure


; require SUP
Import SUP_F4SE

; Implementation version info
Int Property IMPL_VERSION_MAJOR = 0 AutoReadOnly Hidden		; GCP implementation version major (should match LinkLayer version)
Int Property IMPL_VERSION_MINOR = 52 AutoReadOnly Hidden	; GCP implementation version minor (should match LinkLayer version)

; GCP protocol identifiers
Int Property NETLINK_FRAMETYPE_GCP = 10 AutoReadOnly Hidden	; GCP protocol uses netlink frametype 10
Int Property PROTOCOL_VERSION = 1 AutoReadOnly Hidden		; GCP protocol version

; GCP error codes
Int Property ERROR_GCP_NOTSTARTED = -3100 AutoReadOnly Hidden		; GCP protocol not started
Int Property ERROR_GCP_NOPOWER = -3101 AutoReadOnly Hidden			; GCP device not powered
Int Property ERROR_GCP_LINKLAYER = -3102 AutoReadOnly Hidden		; LinkLayer reference is unavailable

; GCP channel commands
Int Property CMD_CHN_NOP = 0 AutoReadOnly Hidden			; no operation
Int Property CMD_CHN_OFF = 1 AutoReadOnly Hidden			; set channel OFF
Int Property CMD_CHN_ON = 2 AutoReadOnly Hidden				; set channel ON
Int Property CMD_CHN_TOGGLE = 3 AutoReadOnly Hidden			; toggle channel
Int Property CMD_CHN_QUERY = 4 AutoReadOnly Hidden			; query channel status (ON/OFF)

; GCP extended channel commands
Int Property CMD_CHN_SET = 20 AutoReadOnly Hidden		    ; set named channel setting value
Int Property CMD_CHN_GET = 21 AutoReadOnly Hidden		    ; get named channel setting value

; GCP group controller commands
Int Property CMD_GC_ANNOUNCE = 1001 AutoReadOnly Hidden		; group controller announces itself
Int Property CMD_GC_JOIN = 1002 AutoReadOnly Hidden			; group member joins group controller
Int Property CMD_GC_PART = 1003 AutoReadOnly Hidden			; group member parts group controller
Int Property CMD_GC_ACQUIRE = 1004 AutoReadOnly Hidden		; group controller wants to acquire group
Int Property CMD_GC_STANDBY = 1005 AutoReadOnly Hidden		; group controller announces standby operation
Int Property CMD_GC_QUERY = 1006 AutoReadOnly Hidden 		; query for group controller members
Int Property CMD_GC_REPORT = 1007 AutoReadOnly Hidden		; group controller member report

; GCP Group Controller statuses
Int Property GC_STATUS_NONE = 0 AutoReadOnly Hidden			; not a group controller
Int Property GC_STATUS_ACTIVE = 1 AutoReadOnly Hidden 		; active group controller
Int Property GC_STATUS_STANDBY = 2 AutoReadOnly Hidden		; standby group controller
Int Property GC_STATUS_FAILED = 99 AutoReadOnly Hidden		; failed group controller

; GCP hardcoded settings
Int Property CONST_GROUPMAXLEN = 64 AutoReadOnly Hidden		; maximum groupname length (characters)


; GCP packet
Struct GCPPacket
	Int Version
	String GroupName
	Int Channel
	Int Command
	Var Data
EndStruct

; Group Controller ChannelStatus Data
Struct ChannelStatusStruct
	Int ChannelID
	Bool ChannelON
EndStruct

Struct GCMemberReportStruct
	String MemberIdentifier
	Int GroupControllerStatus
	ChannelStatusStruct ChannelStats
EndStruct

Struct ChannelSettingStruct
	String SettingName
	Int SettingType
	Var SettingValue
EndStruct

String Function GetGCPCommandName(Int cmdType)
	If (cmdType == CMD_CHN_NOP)
		Return "CMD_CHN_NOP"
	ElseIf (cmdType == CMD_CHN_OFF)
		Return "CMD_CHN_OFF"
	ElseIf (cmdType == CMD_CHN_ON)
		Return "CMD_CHN_ON"
	ElseIf (cmdType == CMD_CHN_TOGGLE)
		Return "CMD_CHN_TOGGLE"
	ElseIf (cmdType == CMD_CHN_QUERY)
		Return "CMD_CHN_QUERY"
	ElseIf (cmdType == CMD_GC_ANNOUNCE)
		Return "CMD_GC_ANNOUNCE"
	ElseIf (cmdType == CMD_GC_JOIN)
		Return "CMD_GC_JOIN"
	ElseIf (cmdType == CMD_GC_PART)
		Return "CMD_GC_PART"
	ElseIf (cmdType == CMD_GC_ACQUIRE)
		Return "CMD_GC_ACQUIRE"	
	ElseIf (cmdType == CMD_GC_STANDBY)
		Return "CMD_GC_STANDBY"		
	ElseIf (cmdType == CMD_GC_QUERY)
		Return "CMD_GC_QUERY"
	Else
		Return "UNKNOWN [" + cmdType + "]"
	EndIf
EndFunction

; L3 protocol overrides
String Function GetIdentifier()
	Return "GCP"
EndFunction

String Function GetIdentifierDesc()
	Return "The Group Control Protocol"
EndFunction

Int Function GetVersionMajor()
	Return IMPL_VERSION_MAJOR
EndFunction

Int Function GetVersionMinor()
	Return IMPL_VERSION_MINOR
EndFunction


; GCP command received event
CustomEvent Started
CustomEvent Stopping
CustomEvent GCPReceive

Group GCPProtocolSettings
	Bool Property RequirePower = true Auto Const
	{ If true, attached reference must be powered for GCP to work }
EndGroup

; true while GCP protocol is started
Bool Property IsStarted Hidden
	Bool Function Get()
		Return bStarted
	EndFunction
EndProperty

Bool bStarted = false

Event OnInit()
	Int result = Start()
EndEvent

Event OnWorkshopObjectPlaced(ObjectReference refWorkshop)
	Int result = Start()
EndEvent

Event OnWorkshopObjectDestroyed(ObjectReference refWorkshop)
	Stop()
EndEvent

Event NetLink:LinkLayer.Started(NetLink:LinkLayer refLinkLayer, Var[] noneArgs)
	; link layer has started
	If (bStarted)	; GCP protocol still started?
	
		; register GCP protocol with LinkLayer for FrameType NETLINK_FRAMETYPE_GCP
		_FrameTypeRegistration()
	EndIf
EndEvent

Event NetLink:LinkLayer.Stopping(NetLink:LinkLayer refLinkLayer, Var[] noneArgs)
	If (bStarted)
		; unregister GCP protocol with LinkLayer for FrameType NETLINK_FRAMETYPE_GCP
		_FrameTypeRegistration(unregisterFrameType = true)	
	EndIf
EndEvent

Int Function Start()
	If (!IsBoundGameObjectAvailable())
		Return ERROR_UNAVAILABLE
	EndIf
	
	If (bStarted)
		; already started
		Return OK_NOERROR
	EndIf	
	
	; start networklayer base
	Int result = Parent.Start()
	If (!CheckSuccessCode(result))
		; failed
		Return result
	EndIf
	
	; register for link layer lifecycle events
	RegisterForCustomEvent(LinkLayer, "Started")
	RegisterForCustomEvent(LinkLayer, "Stopping")
	
	; if linklayer is started, register networklayer frametypes
	If (LinkLayer.IsStarted)
		result = _FrameTypeRegistration()
		If (!CheckSuccessCode(result))
			Debug.Trace(Self + ": ERROR - Protocol Start failed: FTR for FrameType (" + LinkLayer.NETLINK_FRAMETYPE_GCP + ") failed with code (" + ResolveErrorCode(result) + ").")
			Return result
		EndIf
	EndIf
	
	;Debug.Trace(Self + ": DEBUG - My scriptname is (" + NetworkLayerScriptname + ").")
	
	; log chatter
	Debug.Trace(Self + ": INFO - Protocol started.")
	
	; GCP protocol started
	bStarted = true
	
	SendCustomEvent("Started", new Var[0])
	
	Return OK_NOERROR
EndFunction

Function Stop()
	If (bStarted)
		; GCP protocol no longer started
		bStarted = false

		SendCustomEvent("Stopping", new Var[0])

		; unregister this networklayer for frametype 10 from LinkLayer FTR
		If (LinkLayer != none)

			If (LinkLayer.IsStarted)
				_FrameTypeRegistration(unregisterFrameType = true)
			EndIf
		
			; unregister link layer lifecycle events
			UnRegisterForCustomEvent(LinkLayer, "Started")
			UnRegisterForCustomEvent(LinkLayer, "Stopping")
		EndIf
		
		; stop NetworkLayer base class
		Parent.Stop()

		; log chatter
		Debug.Trace(Self + ": INFO - Protocol stopped.")		
	EndIf
EndFunction

; send a gcp command to a group/channel
Int Function SendGCPCommand(ObjectReference refRecipient, String groupName, Int channelId, Int command, Var data)
	If (!_IsDevicePowered())
		Debug.Trace(Self + ": WARNING - SendGCPCommand() skipped: GCP device not powered.")
		Return ERROR_GCP_NOPOWER
	EndIf
	If (!bStarted)
		Debug.Trace(Self + ": ERROR - SendGCPCommand() failed: GCP protocol not started.")
		Return ERROR_GCP_NOTSTARTED	
	EndIf

	; prepare outgoing GCP packet
	GCPPacket txPacket = New GCPPacket
	txPacket.Version = PROTOCOL_VERSION
	txPacket.GroupName = groupName
	txPacket.Channel = channelId
	txPacket.Command = command			
	txPacket.Data = data
	
	; hand GCP packet down to NetLink LinkLayer for transmission
	Debug.Trace(Self + ": DEBUG - Sending GCP Command (" + GetGCPCommandName(txPacket.Command) + ") for Group/Channel (" + txPacket.GroupName + "/" + txPacket.Channel + ") to Link Layer...")
	Return LinkLayer.LinkSend(refRecipient, NETLINK_FRAMETYPE_GCP, txPacket)
EndFunction

; function to transmit "raw" GPC packets
Int Function SendGCPPacket(ObjectReference refRecipient, GCPPacket outPacket)
	If (!bStarted)
		Debug.Trace(Self + ": ERROR - SendGCPPacket() failed: GCP protocol not started.")
		Return ERROR_GCP_NOTSTARTED
	EndIf
	If (!_IsDevicePowered())
		Return ERROR_GCP_NOPOWER
	EndIf

	Debug.Trace(Self + ": DEBUG - Sending GCP Packet (" + outPacket + ") for Group/Channel (" + outPacket.GroupName + "/" + outPacket.Channel + ") to Link Layer...")
	Int success = LinkLayer.LinkSend(refRecipient, NETLINK_FRAMETYPE_GCP, outPacket)
	Return success	
EndFunction

;Function OnLinkReceive(Var[] eventArgs)
Function OnLinkReceive(NetLink:API:LinkLayerBase:NRSE_InvokeArgs eventArgs)
	
	; SUP accelerated version
	;NetLink:LinkLayer srcLinkLayer = eventArgs[0] as NetLink:LinkLayer
	;NetLink:LinkLayer:NetLinkFrame inFrame = eventArgs[1] as NetLink:LinkLayer:NetLinkFrame

	; PAPYRUS VERSION
	NetLink:API:LinkLayerBase srcLinkLayer = eventArgs.callbackArgs[0] as NetLink:LinkLayer
	NetLink:API:LinkLayerBase:NetLinkFrame inFrame = eventArgs.callbackArgs[1] as NetLink:API:LinkLayerBase:NetLinkFrame


	; RX filters
	If (srcLinkLayer == none)
		; missing or invalid source linklayer: discard frame.
		Return
	EndIf
	If (inFrame == none)
		; missing or non-netlink frame: discard.
		Return
	EndIf
	If (inFrame.FrameType != NETLINK_FRAMETYPE_GCP)
		; not a GCP type NetLink Frame: discard.
		Return
	EndIf
	
	; protocol started?
	If (!bStarted)
		;Debug.Trace(Self + ": WARNING - GCP type Frame discarded: Protocol not started.")
		Return
	EndIf
	
	; device powered?
	If (!_IsDevicePowered())
		;Debug.Trace(Self + ": WARNING - GCP type Frame discarded: Device not powered.")
		Return
	EndIf

	; GCP FrameType received, extract GCP packet payload
	GCPPacket gcpPacket = inFrame.Payload as GCPPacket	

	If (gcpPacket == none)
		Debug.Trace(Self + ": WARNING - GCP type Frame discarded: Null Payload.")
		Return
	EndIf

	; GCP type frame has proper GCP protocol version?
	If (gcpPacket.Version != PROTOCOL_VERSION)								
		Debug.Trace(Self + ": WARNING - GCP type Frame discarded: GCP Protocol version (" + gcpPacket.VERSION + ") not supported.")
		Return
	EndIf
	
	;Debug.Trace(Self + ": DEBUG - Received GCP type Frame from Link Layer.")

	; generate packetrx event
	Var[] outEventArgs = new Var[3]
	outEventArgs[0] = inFrame.Source			; netlink source ref
	outEventArgs[1] = inFrame.Destination		; netlink destination ref
	outEventArgs[2] = gcpPacket					; gcp packet received
	SendCustomEvent("GCPReceive", outEventArgs)
EndFunction

; helper functions
Bool Function CheckChannelValid(Int channelID)		; check if channelID is a valid GCP Channel ID (0...127)
	Return (channelID >= 0 && channelID <= 127)	
EndFunction

Bool Function CheckChannelAssignable(Int channelID)	; check if channelID is an assignable GCP Channel ID (1...127)
	Return (channelID >= 1 && channelID <= 127)	
EndFunction

Bool Function CheckGroupValid(String groupName)		; check if groupName is a valid GCP Group Name
	groupName = StringRemoveWhitespace(groupName)
	If (StringGetLength(groupName) > CONST_GROUPMAXLEN)
		Return False
	EndIf
	If (groupName == "")								; empty groupname not allowed
		Return False
	ElseIf (groupName == "P2P Mode")					; prohibited name
		Return False
	EndIf
	Return True
EndFunction

String Function ResolveErrorCode(Int code)				; resolve GCP protocol error codes
	If (code == OK_NOERROR)
		Return "OK_NOERROR"	
	ElseIf (code == ERROR_GCP_NOPOWER)
		Return "ERROR_GCP_NOPOWER"
	ElseIf (code == ERROR_GCP_NOTSTARTED)
		Return "ERROR_GCP_NOTSTARTED"
	Else
		Return Parent.ResolveErrorCode(code)
	EndIf
EndFunction


; internal functions
Bool Function _IsDevicePowered()
	If (!RequirePower)
		Return True
	Else
		Return IsPowered()
	EndIf
EndFunction

Int Function _FrameTypeRegistration(Bool unregisterFrameType = false)
	If (!LinkLayer)
		Return ERROR_GCP_LINKLAYER
	EndIf
	Int nlCode = OK_NOERROR
	If (unregisterFrameType == true)	; unregister frame type
		LinkLayer.FTRUnregisterNetworkLayerForFrameType(Self, LinkLayer.NETLINK_FRAMETYPE_GCP)
	Else
		nlCode = LinkLayer.FTRRegisterNetworkLayerForFrameType(Self, LinkLayer.NETLINK_FRAMETYPE_GCP)
	EndIf
	Return nlCode
EndFunction