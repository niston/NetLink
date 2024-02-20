Scriptname NetLink:GCP:GroupMember extends ObjectReference

; The Group Control Protocol V1
; GCP GroupMember implementation - Custom scripting by niston


; 0.47
; GCP:GroupMember: Changed return type of Start function to Int
; GCP:GroupMember: Changed return type of RegisterChannelMember to Int
; GCP:GroupMember: Added retcode ERROR_GCP_GROUPMEMBER_NOPROTOCOL
; GCP:GroupMember: Added retcode ERROR_GCP_GROUPMEMBER_CHANREGFAIL
; GCP:GroupMember: Added retcode ERROR_GCP_GROUPMEMBER_CONFIG

Import SUP_F4SE

Int Property IMPL_VERSION_MAJOR = 0 AutoReadOnly Hidden		; GCP group member implementation version major
Int Property IMPL_VERSION_MINOR = 53 AutoReadOnly Hidden	; GCP group member implementation version minor

CustomEvent GCPGroupReceive
CustomEvent GCPGroupControllerJoin
CustomEvent GCPGroupControllerPart
CustomEvent Started
CustomEvent Stopping

Group GroupMemberSettings
ObjectReference Property GCPProtocolLayer = none Auto
{ GCP protocol layer reference, Self if left <none> }

ObjectReference Property GCPGroupController = none Auto
{ GCP Group Controller reference. Leave at 'none' for dynamic discovery. }


String Property GCPGroupName = "DEFAULTGROUP" Auto
{ GCP Group Name }
EndGroup

; NetLink General Error Codes
Int Property OK_NOERROR = 0 AutoReadOnly Hidden										; operation succeeded without error
Int Property ERROR_UNAVAILABLE = -90000 AutoReadOnly Hidden							; bound game object is unavailable
Int Property ERROR_PROHIBITED = - 90001 AutoReadOnly Hidden							; prohibited by script logic


; GCP group member error codes
Int Property ERROR_GCP_GROUPMEMBER_NOTSTARTED = -3200 AutoReadOnly Hidden			; group member not started
Int Property ERROR_GCP_GROUPMEMBER_NOPROTOCOL = -3201 AutoReadOnly Hidden			; GCP Protocol reference unavailable
Int Property ERROR_GCP_GROUPMEMBER_CHANREGFAIL = -3202 AutoReadOnly Hidden			; ChannelMember registration failed
Int Property ERROR_GCP_GROUPMEMBER_CONFIG = -3203 AutoReadOnly Hidden				; invalid GCP Group configuration


; GCP protocol reference
NetLink:GCP:Protocol Property gcpProtocol Auto Hidden


Bool Property IsStarted Hidden
	Bool Function Get()
		Return bStarted
	EndFunction
EndProperty

; internal stuff
Bool bStarted = false
NetLink:GCP:ChannelMember[] _ChannelMembers 

Event OnWorkshopObjectPlaced(ObjectReference refWorkshop)
	Start()
EndEvent

Event OnWorkshopObjectDestroyed(ObjectReference refWorkshop)
	Stop()
EndEvent

Int Function Start()
	If (!IsBoundGameObjectAvailable())
		Return ERROR_UNAVAILABLE
	EndIf
	If (bStarted)		
		Return OK_NOERROR
	EndIf
	If (GCPProtocolLayer != none)
		gcpProtocol = GCPProtocolLayer as NetLink:GCP:Protocol
	Else
		; default to self
		gcpProtocol = (Self as ObjectReference) as NetLink:GCP:Protocol
	EndIf
	If (gcpProtocol == none)
		Debug.Trace(Self + ": ERROR - Failed to acquire GCP protocol reference. GCP.psc script attached?")
		Return ERROR_GCP_GROUPMEMBER_NOPROTOCOL
	EndIf
	
	; validate configured groupname
	If (!gcpProtocol.CheckGroupValid(GCPGroupName))
		Return ERROR_GCP_GROUPMEMBER_CONFIG
	EndIf
	
	; register for GCPReceive event
	RegisterForCustomEvent(gcpProtocol, "GCPReceive")
	
	; setup channelmember registry
	_ChannelMembers = new NetLink:GCP:ChannelMember[0]
	
	; success
	bStarted = true
	SendCustomEvent("Started", new Var[0])
	Debug.Trace(Self + ": DEBUG - GroupMember started.")
	Return OK_NOERROR
EndFunction

Bool Function Stop()
	If (bStarted)
		If (gcpProtocol != none)			
			SendCustomEvent("Stopping", new Var[0])		
			UnRegisterForCustomEvent(gcpProtocol, "GCPReceive")			
			_ChannelMembers.Clear()
			_ChannelMembers = none
			GCPGroupController = none 
			gcpProtocol = none
			bStarted = false			
			Debug.Trace(Self + ": DEBUG - GroupMember stopped.")
			Return True
		Else
			Debug.Trace(Self + ": ERROR - Stop() failed: Can't unregister from GCPProtocol instance (null reference).")
			Return False
		EndIf
	Else
		Return True
	EndIf
EndFunction

Int Function RegisterChannelMember(NetLink:GCP:ChannelMember channelMember)
	If (bStarted)
		If (gcpProtocol.CheckChannelAssignable(channelMember.GCPChannel))
			If (_ChannelMembers.Find(channelMember) < 0)
				; TODO: break 128 element limit
				_ChannelMembers.Add(channelMember)
				Return OK_NOERROR
			Else
				Debug.Trace(Self + ": WARNING - RegisterChannelMember() skipped: Channel member (" + channelMember + ") already registered.")
				Return OK_NOERROR
			EndIf
		Else
			Debug.Trace(Self + ": ERROR - RegisterChannelMember() failed: Invalid channel (" + channelMember.GCPChannel + ").")
			Return ERROR_GCP_GROUPMEMBER_CHANREGFAIL
		EndIf
	Else	
		Debug.Trace(Self + ": ERROR - RegisterChannelMember() failed: GroupMember not started.")
		Return ERROR_GCP_GROUPMEMBER_NOTSTARTED
	EndIf
EndFunction

Function UnRegisterChannelMember(NetLink:GCP:ChannelMember channelMember)
	If (bStarted)
		Int index = _ChannelMembers.Find(channelMember)
		If (index > -1)
			_ChannelMembers.Remove(index)
		Else
			Debug.Trace(Self + ": WARNING - UnRegisterChannelMember() failed: Channel member (" + channelMember + ") is not registered.")
		EndIf
	EndIf
EndFunction

; group TX function
Int Function SendGroupCommand(Int channel, Int command, Var data)
	If (bStarted)
		Return gcpProtocol.SendGCPCommand(GCPGroupController, GCPGroupName, channel, command, data)
	Else
		;Debug.Trace(Self + ": ERROR - SendGroupCommand() failed: GroupMember not started.")
		Return ERROR_GCP_GROUPMEMBER_NOTSTARTED
	EndIf
EndFunction

; group RX event
Event NetLink:GCP:Protocol.GCPReceive(NetLink:GCP:Protocol sourceProtocol, Var[] inEventArgs)
	If (bStarted)
		NetLink:GCP:Protocol:GCPPacket gcpPacket = inEventArgs[2] as NetLink:GCP:Protocol:GCPPacket
		
		; concerns my group ?
		If (gcpPacket.GroupName == GCPGroupName)			
			
			; yes, extract sender/recipient
			ObjectReference refNetLinkSender = inEventArgs[0] as ObjectReference
			ObjectReference refNetLinkRecipient = inEventArgs[1] as ObjectReference	

			; TODO: optimize
			; process commands for my group
			
			; pre controller filter processing
			If (!_OnGCPPacketPreControllerFilter(refNetLinkSender, refNetLinkRecipient, gcpPacket))
				
				; packet was not handled by pre controller filter processing. raise group command received event
				
				; if we have a group controller, accept commands from it only - else accept commands from everyone
				If (GCPGroupController == none || (GCPGroupController != none && refNetLinkSender == GCPGroupController))
					; group command accepted
					Var[] outEventArgs = new Var[3]
					outEventArgs[0] = refNetLinkSender
					outEventArgs[1] = refNetLinkRecipient
					outEventArgs[2] = gcpPacket
					SendCustomEvent("GCPGroupReceive", outEventArgs)					
				EndIf
			EndIf
		EndIf
	EndIf
EndEvent

String Function ResolveErrorCode(Int code)	
	If (code == OK_NOERROR)
		Return "OK_NOERROR"
	ElseIf (code == ERROR_GCP_GROUPMEMBER_NOTSTARTED)
		Return "ERROR_GCP_GROUPMEMBER_NOTSTARTED"
	ElseIf (code == ERROR_GCP_GROUPMEMBER_NOPROTOCOL)
		Return "ERROR_GCP_GROUPMEMBER_NOPROTOCOL"
	ElseIf (code == ERROR_GCP_GROUPMEMBER_CHANREGFAIL)
		Return "ERROR_GCP_GROUPMEMBER_CHANREGFAIL"
	ElseIf (code == ERROR_GCP_GROUPMEMBER_CONFIG)
		Return "ERROR_GCP_GROUPMEMBER_CONFIG"
	Else
		If (gcpProtocol)
			Return gcpProtocol.ResolveErrorCode(code)
		Else
			Return "CODE_UNRESOLVABLE (" + code + ")"
		EndIf
	EndIf
EndFunction

Bool Function CheckSuccessCode(Int code)
	Return (code > -1)
EndFunction


; default processor for group controller commands
Bool Function _OnGCPPacketPreControllerFilter(ObjectReference refSender, ObjectReference refRecipient, NetLink:GCP:Protocol:GCPPacket gcpPacket)
	; TODO: optimize (cache access to gcpProtocol)
	Int cmdId = gcpPacket.Command
	If (cmdId == gcpProtocol.CMD_GC_ANNOUNCE)		; group controller announcement received for own group		
		; join the group controller / become member of the controlled group
		If (refSender != GCPGroupController)
			; new group controller announced, join it
			GCPGroupController = refSender			

			; send GC join command to controller, to notify them about us having joined them
			gcpProtocol.SendGCPCommand(refSender, GCPGroupName, 0, gcpProtocol.CMD_GC_JOIN, none)

			; notify upper layers			
			Var[] outEventArgs = new Var[2]
			outEventArgs[0] = GCPGroupController
			outEventArgs[1] = gcpPacket.GroupName
			SendCustomEvent("GCPGroupControllerJoin", outEventArgs)			
		EndIf	

		; command was handled		
		Return True

	ElseIf (cmdId == gcpProtocol.CMD_GC_PART)		; group controller part command received
		If (refSender == GCPGroupController)
			; sender was group controller, clear group controller reference
			GCPGroupController = none						
			
			; notify upper layers
			Var[] outEventArgs = new Var[2]
			outEventArgs[0] = refSender
			outEventArgs[1] = GCPGroupName
			SendCustomEvent("GCPGroupControllerPart", outEventArgs)			
		EndIf

		; command was handled
		Return True
				
	ElseIf (cmdId == gcpProtocol.CMD_GC_QUERY)	; group controller member query received
		If ((GCPGroupController == none) || (GCPGroupController != none && refSender == GCPGroupController))
			; sender is group controller, reply to gc query with gc report			
			NetLink:GCP:Protocol:GCMemberReportStruct gcReportData = new NetLink:GCP:Protocol:GCMemberReportStruct
			;gcReportData.MemberIdentifier = MemberIdentifier
			; TODO: Obtain channel stats
			gcReportData.ChannelStats = none			
			; send GMC_GC_REPORT reply
			gcpProtocol.SendGCPCommand(refSender, GCPGroupName, 0, gcpProtocol.CMD_GC_REPORT, gcReportData)
		EndIf
		
		; command was handled
		Return True		
	
	ElseIf (cmdId == gcpProtocol.CMD_GC_ACQUIRE || cmdId == gcpProtocol.CMD_GC_STANDBY || cmdId == gcpProtocol.CMD_GC_JOIN)
		; command was ignored
		Return True
	EndIf
	
	; command not handled or ignored
	Return False
EndFunction