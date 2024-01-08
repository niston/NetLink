Scriptname NetLink:GCP:API:SensorButton extends NetLink:GCP:API:DeviceSensor

; The Group Control Protocol V1
; DeviceSensor implementation of activation based, NetLink/GCP enabled Multitap Button - Custom scripting by niston

Import SUP_F4SE

Group SensorButtonSettings
	Float Property MultitapDelay = 0.2 Auto
	{ Multitap detection delay in seconds }

	Int Property MultitapCommand = 0 Auto
	{ Button Multitap Command (0 = OFF, 1 = ON, 2 = TOGGLE) }

	String Property ActivationAnimationName = "Activate" Auto Const
	{ Name of the Gamebryo animation to be played upon button activation }
EndGroup

Int activationCount = 0
ObjectReference myActivator = none

Event OnWorkshopObjectDestroyed(ObjectReference refWorkshop)
	CancelTimer(0)
	myActivator = none
	Parent.OnWorkshopObjectDestroyed(refWorkshop)
EndEvent

Event OnActivate(ObjectReference refActivatedBy)	; override
	; button animation
	PlayGamebryoAnimation("Activate", true)
	
	If (IsPowered())	
		; count activation
		activationCount += 1
		myActivator = refActivatedBy
	
		; start processing timer
		StartTimer(MultitapDelay)
	EndIf
EndEvent

Event OnTimer(Int timerId)	
	; action depends on number of button presses	
	If (activationCount == 1)			; NORMAL activation (1x button press)
		
			Parent.OnActivate(myActivator)
			
	ElseIf (activationCount >= 2)		; MULTITAP activation (>1x button press)
		
		; multitap: button pressed 2x or more
		If (MultitapCommand == 1)		; MULTITAP ON
			Debug.Trace(Self + ": DEBUG - Multitap (>1x): Channel ON.")
			Int code = GCPChannelOn()			
			If !CheckSuccessCode(code)
				Debug.Trace(Self + ": ERROR - GCPChannelOn() failed: Code (" + ResolveErrorCode(code) + ") returned.")
			EndIf
		
		ElseIf (MultitapCommand == 2)	; MULTITAP TOGGLE
			Debug.Trace(Self + ": DEBUG - Multitap (>1x): Channel TOGGLE.")
			Int code = GCPChannelToggle()			
			If !CheckSuccessCode(code)
				Debug.Trace(Self + ": ERROR - GCPChannelOn() failed: Code (" + ResolveErrorCode(code) + ") returned.")
			EndIf			
	
		Else							; MULTITAP OFF
			; press 2x or more = channel off
			Debug.Trace(Self + ": DEBUG - Multitap (>1x): Channel OFF.")
			Int code = GCPChannelOff()
			If !CheckSuccessCode(code)
				Debug.Trace(Self + ": ERROR - GCPChannelOff() failed: Code (" + ResolveErrorCode(code) + ") returned.")
			EndIf
		EndIf
	EndIf
	
	; reset activation count
	activationCount = 0
	myActivator = none
EndEvent

Function Stop()
	CancelTimer()
	myActivator = none
	Parent.Stop()
EndFunction

Int Function _GetDeviceType()			; override gcp sensor
	Return GCP_DEVICETYPE_SENSOR_BUTTON
EndFunction