Scriptname NetLink:GCP:API:DeviceSensor extends NetLink:GCP:API:Device Hidden

; The Group Control Protocol V1
; DeviceSensor Base Class for Activation based, NetLink/GCP enabled sensing device - Custom scripting by niston

Group DeviceSettings
	Int Property ActivationCommand = 2 Auto
	{ Command sent on activation (0 = OFF, 1 = ON, 2 = TOGGLE) }
EndGroup

Bool bActivating = false
Event OnActivate(ObjectReference refActivatedBy)	
	If (bActivating)
		Return
	EndIf
	bActivating = true

	; action depends on configured command	
	If (ActivationCommand == 2) 		; CHN_CMD_TOGGLE
		Debug.Trace(Self + ": DEBUG - Activated: Channel TOGGLE.")
		Int code = GCPChannelToggle()
		If !CheckSuccessCode(code)
			Debug.Trace(Self + ": ERROR - GCPChannelToggle() failed: Code (" + ResolveErrorCode(code) + ") returned.")
		EndIf	
	ElseIf (ActivationCommand == 1)		; CHN_CMD_ON
		Debug.Trace(Self + ": DEBUG - Activated: Channel ON.")
		Int code = GCPChannelOn()
		If !CheckSuccessCode(code)
			Debug.Trace(Self + ": ERROR - GCPChannelOn() failed: Code (" + ResolveErrorCode(code) + ") returned.")
		EndIf	
	Else								; CHN_CMD_OFF
		Debug.Trace(Self + ": DEBUG - Activated: Channel OFF.")
		Int code = GCPChannelOff()
		If !CheckSuccessCode(code)
			Debug.Trace(Self + ": ERROR - GCPChannelOff() failed: Code (" + ResolveErrorCode(code) + ") returned.")
		EndIf		
	EndIf
	
	bActivating = false
EndEvent

Int Function _GetDeviceType()			; override gcp device
	Return GCP_DEVICETYPE_SENSOR
EndFunction