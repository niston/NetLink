Scriptname NetLink:GCP:ChannelMember extends ObjectReference Hidden

; The Group Control Protocol V1
; GCP ChannelMember Base Class - Custom scripting by niston

; 0.47
; GCP:ChannelMember: Removed error codes 3301 and 3302

; require SUP
Import SUP_F4SE

Group GCPChannelMemberSettings
	ObjectReference Property GCPGroupMemberReference = none Auto
	{ GCPGroupMember reference, Self if left <none> }

	Int Property GCPChannel = 1 Auto
	{ GCP Group Channel Number (1...127) }
EndGroup

; NetLink codes
Int Property OK_NOERROR = 0 AutoReadOnly Hidden										; operation completed successfully without error
Int Property ERROR_UNAVAILABLE = -90000 AutoReadOnly Hidden							; bound game object is unavailable
Int Property ERROR_PROHIBITED = - 90001 AutoReadOnly Hidden							; prohibited by script logic

; GCP error codes
Int Property ERROR_GCP_CHANNEL_NOTSTARTED = -3300 AutoReadOnly Hidden				; operation failed because GCP is not started
Int Property ERROR_GCP_CHANNEL_NOGROUPMEMBER = -3303 AutoReadOnly Hidden			; failed to acquire group member reference
Int Property ERROR_GCP_CHANNEL_CONFIG = -3304 AutoReadOnly Hidden					; invalid GCP Channel configuration

Int Property IMPL_VERSION_MAJOR = 0 AutoReadOnly Hidden								; GCP group channel member implementation version major
Int Property IMPL_VERSION_MINOR = 53 AutoReadOnly Hidden	    					; GCP group channel member implementation version minor

; channel functions

; GCP group member reference
NetLink:GCP:GroupMember Property gcpGroup Auto Hidden

Bool bStarted = false

Bool Property IsStarted
	Bool Function Get()
		Return bStarted
	EndFunction
EndProperty

Event OnWorkshopObjectPlaced(ObjectReference refWorkshop)
	Start()
EndEvent

Event OnWorkshopObjectDestroyed(ObjectReference refWorkshop)	
	Stop()
EndEvent


Int Function Start()
	If (IsBoundGameObjectAvailable())
		If (bStarted)		
			Return OK_NOERROR
		Else
			Utility.Wait(0.5)
		
			; startup		
			If (GCPGroupMemberReference != none)
				gcpGroup = GCPGroupMemberReference as NetLink:GCP:GroupMember
			Else
				; default to self
				gcpGroup = (Self as ObjectReference) as NetLink:GCP:GroupMember
			EndIf
			If (gcpGroup == none)
				Debug.Trace(Self + ": ERROR - Failed to acquire GCPGroupMember reference. GCPGroupMember script attached?")
				Return ERROR_GCP_CHANNEL_NOGROUPMEMBER
			EndIf
			
			; check channel config
			If (!gcpGroup.gcpProtocol.CheckChannelAssignable(GCPChannel))
				Debug.Trace(Self + ": ERROR - Start() failed: Invalid GCPChannel configuration.")
				Return ERROR_GCP_CHANNEL_CONFIG
			EndIf
			
			; register channel with group
			Int regResult = gcpGroup.RegisterChannelMember(Self)
			If (!CheckSuccessCode(regResult))
				Debug.Trace(Self + ": ERROR - Start failed: Unable to register GCP channel (" + GCPChannel + ") with group (" + gcpGroup + "). Code (" + regResult + ") returned.")				
				Return regResult
			EndIf
			
			; listen for group receive event
			RegisterForCustomEvent(gcpGroup, "GCPGroupReceive")
			
			; success
			bStarted = true
			Debug.Trace(Self + ": DEBUG - ChannelMember started.")
			Return OK_NOERROR				
		EndIf
	EndIf
EndFunction

Function Stop()
	If (bStarted)
		If (gcpGroup != none)
			bStarted = false
			UnRegisterForCustomEvent(gcpGroup, "GCPGroupReceive")
			If (gcpGroup.IsBoundGameObjectAvailable() && gcpGroup.IsStarted)			
				gcpGroup.UnRegisterChannelMember(Self)			
			EndIf			
			gcpGroup = none			
		Else			
			Debug.Trace(Self + ": WARNING - Unregistering from GCPGroup (<none>) failed.")
			UnRegisterForAllCustomEvents()
			bStarted = false
		EndIf
		Debug.Trace(Self + ": DEBUG - ChannelMember stopped.")
	EndIf
EndFunction

;/
Int Function _GetChannelValueFromChannelStats(Int channelId, GCP:GCChannelStatus[] channelStats)
	Int channelIndex = channelStats.FindStruct("ChannelID", channelId)
	If (channelIndex > -1)
		Return (channelStats[channelIndex].ChannelEnabled) as Int
	Else
		; channelid not found in channelstats
		Return -1
	EndIf
EndFunction
/;

; gcp channel commands

; send ON command to group channel
Int Function GCPChannelOn()
	If (bStarted)
		Return gcpGroup.SendGroupCommand(GCPChannel, gcpGroup.gcpProtocol.CMD_CHN_ON, none)
	Else
		Return ERROR_GCP_CHANNEL_NOTSTARTED
	EndIf
EndFunction

; send TOGGLE command to group channel
Int Function GCPChannelToggle()	
	If (bStarted)		
		Return gcpGroup.SendGroupCommand(GCPChannel, gcpGroup.gcpProtocol.CMD_CHN_TOGGLE, none)
	Else
		Return ERROR_GCP_CHANNEL_NOTSTARTED
	EndIf
EndFunction

; send OFF command to group channel
Int Function GCPChannelOff()
	If (bStarted)
		Return gcpGroup.SendGroupCommand(GCPChannel, gcpGroup.gcpProtocol.CMD_CHN_OFF, none)
	Else
		Return ERROR_GCP_CHANNEL_NOTSTARTED
	EndIf
EndFunction

Event NetLink:GCP:GroupMember.GCPGroupReceive(NetLink:GCP:GroupMember refEventOrigin, Var[] inEventArgs)
	If (bStarted)
		ObjectReference refSender = inEventArgs[0] as ObjectReference
		ObjectReference refRecipient = inEventArgs[1] as ObjectReference	
		NetLink:GCP:Protocol:GCPPacket gcpPacket = inEventArgs[2] as NetLink:GCP:Protocol:GCPPacket

		; GCP Packet concerns my channel, or all channels?
		If (gcpPacket.Channel == GCPChannel || gcpPacket.Channel == 0)
			; yep, process
			OnGCPChannelReceive(refSender, refRecipient, gcpPacket.GroupName, gcpPacket.Channel, gcpPacket.Command, gcpPacket.Data)		
		EndIf
	EndIf
EndEvent

; GCP channel command rx
Function OnGCPChannelReceive(ObjectReference refSender, ObjectReference refRecipient, String groupName, Int channelId, Int command, Var data)
	; needs to be overridden in derived class to receive data
EndFunction

String Function ResolveErrorCode(Int code)
	If (code == OK_NOERROR)
		Return "OK_NOERROR"
	ElseIf (code == ERROR_GCP_CHANNEL_NOTSTARTED)
		Return "ERROR_GCP_CHANNEL_NOTSTARTED"
	ElseIf (code ==  ERROR_GCP_CHANNEL_NOGROUPMEMBER)
		Return "ERROR_GCP_CHANNEL_NOGROUPMEMBER"
	ElseIf (code == ERROR_GCP_CHANNEL_CONFIG)
		Return "ERROR_GCP_CHANNEL_CONFIG"
	Else
		If (gcpGroup)
			Return gcpGroup.ResolveErrorCode(code)
		Else
			Return "CODE_UNRESOLVABLE (" + code + ")"
		EndIf
	EndIf
EndFunction

Bool Function CheckSuccessCode(Int code)
	Return (code > -1)
EndFunction