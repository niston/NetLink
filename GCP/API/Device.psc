Scriptname NetLink:GCP:API:Device extends NetLink:GCP:ChannelMember Hidden

; The Group Control Protocol V1
; Base Class for single channel NetLink/GCP enabled Device - Custom scripting by niston


;/ 0.51
GCP:API:Device: Added OnCircuitOpenChanged function.
GCP:API:Device: Fix bug in CircuitToggle
GCP:API:Device: Fix superfluous logging in CircuitOpen
GCP:API:Device: Added API field update/restart capabilities
GCP:API:Device: Added support for Auxilliary Channels 1-3
/;

; require SUP
Import SUP_F4SE

; device version, mismatch will trigger automatic field update/restart
Int Property GCP_DEVICE_VERSION_MAJOR = 0 AutoReadOnly Hidden
Int Property GCP_DEVICE_VERSION_MINOR = 52 AutoReadOnly Hidden

; GCP device types
Int Property GCP_DEVICETYPE_UNKNOWN = 0 AutoReadOnly Hidden
Int Property GCP_DEVICETYPE_CONTROLLER = 100 AutoReadOnly Hidden
Int Property GCP_DEVICETYPE_SENSOR = 1000 AutoReadOnly Hidden
Int Property GCP_DEVICETYPE_SENSOR_BUTTON = 1001 AutoReadOnly Hidden
Int Property GCP_DEVICETYPE_SENSOR_LEVER = 1002 AutoReadOnly Hidden
Int Property GCP_DEVICETYPE_SENSOR_LINE = 1003 AutoReadOnly Hidden
Int Property GCP_DEVICETYPE_ACTOR = 10000 AutoReadOnly Hidden
Int Property GCP_DEVICETYPE_ACTOR_RELAY = 10001 AutoReadOnly Hidden
Int Property GCP_DEVICETYPE_ACTOR_LIGHT = 10002 AutoReadOnly Hidden
Int Property GCP_DEVICETYPE_ACTOR_FAN = 10003 AutoReadOnly Hidden

;/
###########################
# Section: Event Declares #
###########################
/;
CustomEvent Updated

;/
#######################################
# Section: CK Configurable Properties #
#######################################
/;
Group DeviceSettings
	String Property DeviceNameOverride = "" Auto Const
	{ Set to override DeviceName, useful for LIGHT record based lamps and fixtures. Leave empty for activators. }
	
	Bool Property DontClearOutputOnRestart = False Auto Const
	{ Set to true to prevent device output being turned off during restart. }
EndGroup

Int Property DeviceType Hidden
	Int Function Get()
		Return  _GetDeviceType()
	EndFunction
EndProperty

String Property DeviceLabel Hidden
	String Function Get()
		Return _DeviceLabel
	EndFunction
	Function Set(String value)
		If (value != _DeviceLabel)
			_UpdateDeviceLabel(value)
		EndIf	
	EndFunction
EndProperty

String Property DeviceName Hidden
	String Function Get()
		If (DeviceNameOverride != "")
			Return DeviceNameOverride
		Else
			String myName = GetDisplayName()
			If (myName == "")
				myName = GetBaseObject().GetName()
			EndIf
			If (myName == "")
				Return "Smart " + DeviceTypeName
			Else
				Return myName
			EndIf
		EndIf
	EndFunction
EndProperty

String Property DeviceTypeName Hidden
	String Function Get()
		Return ResolveGCPDeviceType(_GetDeviceType())	
	EndFunction
EndProperty

String Property DeviceStatus Hidden
	String Function Get()
		Return _GetDeviceStatus()
	EndFunction
EndProperty

Int Property AuxChannelCount
	Int Function Get()
		Return _AuxChannels.Length
	EndFunction
EndProperty


; Auxilliary Channels
NetLink:GCP:API:AuxChannels:Base[] _AuxChannels


; property backers
String _DeviceLabel = ""
Int _GCPDeviceVersionMajor = 0
Int _GCPDeviceVersionMinor = 0

; "protected" output enable state property
Bool Property _OutputEnabled = false Auto Hidden


Event Actor.OnPlayerLoadGame(Actor refPlayer)
	HandleOnPlayerLoadGame()
EndEvent

;Function DebugPersistence()
;	String[] formsList = GetPersistentPromoters(Self, false)
;	Int i = 0
;	While (i < formsList.Length)
;		Debug.Trace(Self + ": DEBUG - PP by (" + formsList[i] + ")")
;		i += 1
;	EndWhile
;EndFunction




;/
#####################################
# Section: Base Class Functionality #
#####################################
/;
Int Function Start()
	; game loaded event
	RegisterForRemoteEvent(Game.GetPlayer(), "OnPlayerLoadGame")
	
	; update version info
	_GCPDeviceVersionMajor = GCP_DEVICE_VERSION_MAJOR
	_GCPDeviceVersionMinor = GCP_DEVICE_VERSION_MINOR
	
	Int result = AuxChannelsAcquire()
	If (!CheckSuccessCode(result))
		Debug.Trace(Self + ": ERROR - Failed to acquire Auxilliary Channels: Code (" + ResolveErrorCode(result) + " returned.")
		Return result
	EndIf
	
	; invoke parent
	Return Parent.Start()
EndFunction

Function Stop()
	UnRegisterForRemoteEvent(Game.GetPlayer(), "OnPlayerLoadGame")
		
	AuxChannelsRelease()
	
	Parent.Stop()
EndFunction

String Function ResolveGCPDeviceType(Int deviceTypeId)
	If (deviceTypeId == GCP_DEVICETYPE_ACTOR)
		Return "Actor"
	ElseIf (deviceTypeId == GCP_DEVICETYPE_ACTOR_LIGHT)
		Return "Light"
	ElseIf (deviceTypeId == GCP_DEVICETYPE_ACTOR_FAN)
		Return "Fan"
	ElseIf (deviceTypeId == GCP_DEVICETYPE_ACTOR_RELAY)
		Return "Relay"
	ElseIf (deviceTypeId == GCP_DEVICETYPE_CONTROLLER)
		Return "Controller"
	ElseIf (deviceTypeId == GCP_DEVICETYPE_SENSOR)
		Return "Sensor"
	ElseIf (deviceTypeId == GCP_DEVICETYPE_SENSOR_BUTTON)
		Return "Button"
	ElseIf (deviceTypeId == GCP_DEVICETYPE_SENSOR_LEVER)
		Return "Lever"
	ElseIf (deviceTypeId == GCP_DEVICETYPE_SENSOR_LINE)
		Return "Line Sense"
	Else
		Return "Device Type (" + deviceTypeId + ")"
	EndIf
EndFunction

; set reference openstate
Function CircuitOpen(Bool open)
	; set open state
	SetOpen(open)	
	; keep track of open state
	_OutputEnabled = !open
	; log trace
	_WriteDeviceStatusLog()	
	; notify derived classes
	OnCircuitOpenChange(open)
EndFunction

; toggle reference openstate
Function CircuitToggle()
	Int curOpenState = GetOpenState()
	If (curOpenState == 1 || curOpenState == 2)
		SetOpen(false)
		_OutputEnabled =  true
		_WriteDeviceStatusLog()
		; notify derived classes
		OnCircuitOpenChange(false)
	ElseIf (curOpenState == 3 || curOpenState == 4)
		SetOpen(true)
		_OutputEnabled = false
		_WriteDeviceStatusLog()
		; notify derived classes
		OnCircuitOpenChange(true)
	EndIf
EndFunction

Int Function AuxChannelsAcquire()

	; prepare aux channel array
	_AuxChannels = new NetLink:GCP:API:AuxChannels:Base[0]

	; channel startup result code
	Int startResult 

	NetLink:GCP:API:AuxChannels:A auxChanA = (Self as ObjectReference) as NetLink:GCP:API:AuxChannels:A	
	If (auxChanA != none)
		startResult = auxChanA.Start()
		If (!CheckSuccessCode(startResult))
			Debug.Trace(Self + ": ERROR - Auxilliary Channel (A) configured, but failed to start with code (" + startResult + ").")
			Return startResult
		EndIf
		auxChanA.Notify = Self
		_AuxChannels.Add(auxChanA)
	EndIf

	NetLink:GCP:API:AuxChannels:B auxChanB = (Self as ObjectReference) as NetLink:GCP:API:AuxChannels:B
	If (auxChanB != none)
		startResult = auxChanB.Start()
		If (!CheckSuccessCode(startResult))
			Debug.Trace(Self + ": ERROR - Auxilliary Channel (B) configured, but failed to start with code (" + startResult + ").")
			Return startResult
		EndIf
		auxChanB.Notify = Self
		_AuxChannels.Add(auxChanB)
	EndIf

	NetLink:GCP:API:AuxChannels:C auxChanC = (Self as ObjectReference) as NetLink:GCP:API:AuxChannels:C
	If (auxChanC != none)
		startResult = auxChanC.Start()
		If (!CheckSuccessCode(startResult))
			Debug.Trace(Self + ": ERROR - Auxilliary Channel (C) configured, but failed to start with code (" + startResult + ").")
			Return startResult
		EndIf
		auxChanC.Notify = Self
		_AuxChannels.Add(auxChanC)
	EndIf
		
	If (_AuxChannels.Length > 0)
		Debug.Trace(Self + ": DEBUG - Acquired (" + _AuxChannels.Length + ") Auxilliary Channels.")
	EndIf

	Return OK_NOERROR
EndFunction

Function AuxChannelsRelease()
	
	Int hadAuxChans = _AuxChannels.Length
	While (IsBoundGameObjectAvailable() && _AuxChannels.Length > 0)
		_AuxChannels[0].Notify = none
		_AuxChannels[0].Stop()
	    _AuxChannels[0] = none
		_AuxChannels.Remove(0)
	EndWhile
	If (hadAuxChans > 0)
		Debug.Trace(Self + ": DEBUG - Released (" + hadAuxChans + ") Auxilliary Channels.")
	EndIf
EndFunction
NetLink:GCP:API:AuxChannels:Base Function AuxChannelGetByDeviceType(Int channelDeviceType)
	Int i = 0
	While (i < _AuxChannels.Length)
		If (_AuxChannels[i].ChannelDeviceType == channelDeviceType)
			Return _AuxChannels[i]
		EndIf
		i += 1
	EndWhile
	Return none
EndFunction

NetLink:GCP:API:AuxChannels:Base Function AuxChannelGetByIndex(Int auxChannelIndex)
	If (_AuxChannels.Length == 0)
		Return none
	EndIf
	If (auxChannelIndex >= _AuxChannels.Length || auxChannelIndex < 0)	
		Return none
	EndIf
	Return _AuxChannels[auxChannelIndex]
EndFunction


;/
######################################################
# Section: Abstract Functions & Base Implementations #
######################################################
/;
Int Function _GetDeviceType()		; must be overridden by implementing device
	Return GCP_DEVICETYPE_UNKNOWN
EndFunction

String Function _GetDeviceStatus()	; may be overridden by implementing device
	Return ""	; device does not have a status
EndFunction

Function OnCircuitOpenChange(Bool isOpen)
	; override as needed
EndFunction

; remote event can be overridden in derived class, but cant be invoked on the parent.
; so we use this proxy function to handle onplayerloadgame actor event instead
Function HandleOnPlayerLoadGame()		; ATTN: Overrides MUST call Parent.HandleOnPlayerLoadGame()
	; Update Device if API versions mismatch
	UpdateDeviceAPI()
EndFunction

; # FOR PRE-RESTART API UPDATE STEPS #
Int Function OnAPIUpdatePreRestart()	; may override in derived classes, as needed. MUST call Parent.
	Return OK_NOERROR
EndFunction

; # FOR POST-RESTART API UPDATE STEPS #
Int Function OnAPIUIpdatePostRestart()	; may override in derived classes, as needed. MUST call Parent.
	Return OK_NOERROR
EndFunction

Function OnAuxChannelReceive(NetLink:GCP:API:AuxChannels:Base auxChannel, ObjectReference refSender, ObjectReference refRecipient, String groupName, Int channelId, Int command, Var data)
	; must override in device implementation
EndFunction

;/
###############################
# Section: Internal Functions #
###############################
/;
Bool Function _UpdateDeviceLabel(String newLabel)
	_DeviceLabel = newLabel
EndFunction

Function _WriteDeviceStatusLog()
	If (DeviceStatus != "")
		Debug.Trace(Self + ": INFO - " + DeviceTypeName + " Status: " + DeviceStatus + ".")
	EndIf
EndFunction




;/
###############################################
# Section: Device API Field Update Capability #
###############################################
/;
Int Function Restart()	; must call parent from override!

	NetLink:GCP:GroupMember nlGCPGroup 
	NetLink:GCP:Protocol nlGCPProto 
	NetLink:LinkLayer nlLinkLayer 

	; try using existing references and avoid spamming log if they're corrupted
	nlGCPGroup = gcpGroup	
	If (nlGCPGroup != none)
		nlGCPProto = gcpGroup.gcpProtocol
		If (nlGCPProto != none)
			nlLinkLayer = gcpGroup.gcpProtocol.LinkLayer		
		EndIf
	EndIf
	
	If (!nlLinkLayer || !nlGCPProto || !nlGCPGroup)
		Debug.Trace(Self + ": WARNING - Device has invalid internal references; Performing cold start.")
		nlLinkLayer = (Self as ObjectReference) as NetLink:LinkLayer
		nlGCPProto = (Self as ObjectReference) as NetLink:GCP:Protocol
		nlGCPGroup = (Self as ObjectReference) as NetLink:GCP:GroupMember
		If (!nlLinkLayer || !nlGCPProto || !nlGCPGroup)
			Debug.Trace(Self + ": ERROR - Cold start failed: Unable to acquire network references.")
			Return -90000
		EndIf
	EndIf
	
	
	Int result = 0
	
	Bool wasOutputEnabled = _OutputEnabled
	
	If (!DontClearOutputOnRestart)
		; open device circuit
		CircuitOpen(true)
	EndIf
	
	; stopping channel member
	Stop()
	
	; stopping group member
	nlGCPGroup.Stop()
	
	; stopping GCP protocol
	nlGCPProto.Stop()
	
	; stopping Link Layer
	nlLinkLayer.Stop()
	
	; check for empty state on LinkLayer
	If (nlLinkLayer.GetState() == "")
		; force stopped state
		nlLinkLayer._Stop()
	EndIf
		
	; starting netlink linklayer
	result = nlLinkLayer.Start()
	If (!CheckSuccessCode(result))
		Debug.Trace(Self + ": ERROR - Restart (NetLink:LinkLayer) failed with code (" + ResolveErrorCode(result) + ").")
		Return result
	EndIf
	
	; starting GCP
	result = nlGCPProto.Start()
	If (!CheckSuccessCode(result))
		Debug.Trace(Self + ": ERROR - Restart (GCP:Protocol) failed with code (" + ResolveErrorCode(result) + ").")
		Return result
	EndIf

	; starting GroupMember
	result = nlGCPGroup.Start()
	If (!CheckSuccessCode(result))
		Debug.Trace(Self + ": ERROR - Restart (GCP:GroupMember) failed with code (" + ResolveErrorCode(result) + ").")
		Return result
	EndIf
		
	; starting self (channel)
	result = Start()
	If (!CheckSuccessCode(result))
		Debug.Trace(Self + ": ERROR - Restart (GCP:ChannelMember) failed with code (" + ResolveErrorCode(result) + ").")
		Return result
	EndIf
	
	; restore output state
	CircuitOpen(!wasOutputEnabled)
	
	; fire updated event
	SendCustomEvent("Updated", new Var[0])
	
	Return result
EndFunction

Function UpdateDeviceAPI()
	Debug.Trace(Self + ": DEBUG - Checking for GCP Device API update...")
	If (GCP_DEVICE_VERSION_MAJOR != _GCPDeviceVersionMajor) || (GCP_DEVICE_VERSION_MINOR != _GCPDeviceVersionMinor)
		
		Debug.Trace(Self + ": INFO - Device API version mismatch detected. Performing update...")

		; # PRE-RESTART UPDATE STEPS #		
		Int result = OnAPIUpdatePreRestart()
		If (!CheckSuccessCode(result))
			Debug.Trace(Self + ": ERROR - UpdateDeviceAPI failed: Restart after Device API upgrade returned code (" + ResolveErrorCode(result) + "). Device may not work properly.")
			Return
		EndIf
				
		; random delay restart (0...2 seconds) 
		Float randomDelay = Utility.RandomFloat(0, 2)
		Utility.Wait(randomDelay)
		
		Debug.Trace(Self + ": WARNING - Restarting Device to finalize API update...")		
		
		; perform restart
		result = Restart()
		If (!CheckSuccessCode(result))
			Debug.Trace(Self + ": ERROR - UpdateDeviceAPI failed: Restart after Device API upgrade returned code (" + ResolveErrorCode(result) + "). Device may not work properly.")
			Return
		EndIf
		
		; # POST RESTART UPDATE STEPS #		
		result = OnAPIUpdatePreRestart()
		If (!CheckSuccessCode(result))
			Debug.Trace(Self + ": ERROR - UpdateDeviceAPI failed: Restart after Device API upgrade returned code (" + ResolveErrorCode(result) + "). Device may not work properly.")
			Return
		EndIf		
		
		
		; success
		Debug.Trace(Self + ": INFO - Device successfully updated to API version (" + GCP_DEVICE_VERSION_MAJOR + "." + GCP_DEVICE_VERSION_MINOR + ").")
		_GCPDeviceVersionMajor = GCP_DEVICE_VERSION_MAJOR
		_GCPDeviceVersionMinor = GCP_DEVICE_VERSION_MINOR
		
		; update notification
		SendCustomEvent("Updated", new Var[0])
	Else
		Debug.Trace(Self + ": DEBUG - Device API is up to date (Version " + _GCPDeviceVersionMajor + "." + _GCPDeviceVersionMinor + ").")
	EndIf
EndFunction

