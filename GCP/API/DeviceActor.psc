Scriptname NetLink:GCP:API:DeviceActor extends NetLink:GCP:API:Device Hidden

; The Group Control Protocol V1
; Base class for NetLink/GCP enabled, OpenState based acting device (nothing to do with Creation Engine Actors) - Custom scripting by niston

; require SUP F4SE
Import SUP_F4SE


Group DeviceActorSettings
	Bool Property OutputInitialState = true Auto Const
	{ Initial output enable state. }
EndGroup

Bool Property OutputEnabled Hidden
	{ (read-only) Current Output Enable State }
	Bool Function Get()
		Return _OutputEnabled
	EndFunction
EndProperty

Event OnInit()
	; set initial enable state
	_OutputEnabled = OutputInitialState
EndEvent

Event OnPowerOn(ObjectReference refGenerator)
	; on power on, sync output enable state
	SetOpen(!_OutputEnabled)
EndEvent

; GCP command received
Function OnGCPChannelReceive(ObjectReference refSender, ObjectReference refRecipient, String groupName, Int channelId, Int command, Var data)
	Debug.Trace(Self + ": DEBUG - GCP Actor on Group/Channel (" + gcpGroup.GCPGroupName + "/" + GCPChannel + ") received command (" + gcpGroup.gcpProtocol.GetGCPCommandName(command) + ").")

	; process channel command
	If (command == gcpGroup.gcpProtocol.CMD_CHN_OFF)
		; open circuit
		CircuitOpen(True)
	ElseIf (command == gcpGroup.gcpProtocol.CMD_CHN_ON)
		; close circuit
		CircuitOpen(False)				
	ElseIf (command == gcpGroup.gcpProtocol.CMD_CHN_TOGGLE)
		CircuitToggle()
	Else
		Debug.Trace(Self + ": ERROR - Reference has no OpenState. WorkshopSwitchActivatorKeyword attached?")
	EndIf	
EndFunction

Int Function _GetDeviceType()	; override
	Return GCP_DEVICETYPE_ACTOR
EndFunction

String Function _GetDeviceStatus()	; override
	Int openState = GetOpenState()
	If (openState == 1 || openState == 2)
		Return "OPEN"
	ElseIf (openState == 3 || openState == 4)
		Return "CLOSED"
	Else
		Return "N/A"
	EndIf
EndFunction