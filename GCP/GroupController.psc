Scriptname NetLink:Implements:GCPGroupController extends NetLink:Implements:GCPGroupMember

Import SUP_F4SE

CustomEvent ChannelUpdate

Int Property GCChannels = 8 Auto Const
{ Number of channels this Group Controller supports; 1 - 127. }

Float Property GCAcquireTimeout = 1.25 Auto Hidden

Bool Property Started Auto Hidden

Bool[] Property ChannelStatusArray Auto Hidden

; group members table
GroupMemberInfo[] Property GroupMembersTable Auto Hidden


Event OnInit()
	Startup()
	Parent.OnInit()
EndEvent

Event OnWorkshopObjectPlaced(ObjectReference refWorkshop)
	Startup()
	Parent.OnWorkshopObjectPlaced(refWorkshop)
EndEvent

Event OnWorkshopObjectDestroyed(ObjectReference refWorkshop)
	Shutdown()
	Parent.OnWorkshopObjectDestroyed(refWorkshop)
EndEvent

Bool Function Startup()
	If (!Started)
		If (GCChannels > 127 || GCChannels < 1)
			Debug.Trace(Self + ": ERROR - Invalid configuration (GCChannels): Value must be between 1 and 127.")
			Return False
		EndIf
		; initialize channel status array
		ChannelStatusArray = new Bool[GCChannels + 1]
		; array index 0 is always zero
		ChannelStatusArray[0] = 0
		; set GCP channel to zero
		GCPChannel = 0		
		; set GCP controller to none (we don't have a controller, we ARE a controller)
		GCPGroupController = none
		; started
		Started = true
		Return True
	Else
		Return True
	EndIf
EndFunction

Function Shutdown()
	If (Started)		
		ChannelStatusArray.Clear()
		ChannelStatusArray = none
		GroupMembersTable.Clear()
		GroupMembersTable = none
		Started = false
	EndIf
EndFunction


State Stopped

EndState

State Starting

EndState

State Acquire

EndState

State Primary

EndState

State Standby

EndState

State Fault

EndState

; override GCPGroupMember GC command handler
Bool Function _HandleGCCommand(ObjectReference refSender, ObjectReference refRecipient, String groupName, Int channel, Int command, Var data)
	If (command == pGCP.CMD_GC_QUERY)
		; group controller query, reply with broadcast announcement 
		pGCP.SendGCAnnouncement(none, GCPGroupName, ChannelStatusArray)
		Return True

	ElseIf (command == pGCP.CMD_GC_ANNOUNCE)				
		; Collision: Announcement from other controller for this group received

	ElseIf (command == pGCP.CMD_GC_PART)
		; member parted the controller

	ElseIf (command == pGCP.CMD_GC_JOIN)
		; member joined the controller

	EndIf
	Return False
EndFunction

Function OnGCPCommandReceived(ObjectReference refSender, ObjectReference refRecipient, String groupName, Int channel, Int command, Var data)
	; must be addressed to controller (self)
	If (refRecipient == Self as ObjectReference)
		If (command == pGCP.CMD_TOGGLE)
			ChannelStatusArray[channel] = !ChannelStatusArray[channel]
			If (ChannelStatusArray[channel] == true)
				If (pGCP.SendChannelOn(none, GCPGroupName, channel))
					Debug.Trace(Self + ": DEBUG - Sent Channel ON command to group (" + GCPGroupName +"), channel (" + channel + ").")
				EndIf
			Else
				If (pGCP.SendChannelOff(none, GCPGroupName, channel))
					Debug.Trace(Self + ": DEBUG - Sent Channel OFF command to group.")
				EndIf			
			EndIf			
			
		ElseIf (command == pGCP.CMD_ON)
			ChannelStatusArray[channel] = true
			If (pGCP.SendChannelOn(none, GCPGroupName, channel))
				Debug.Trace(Self + ": DEBUG - Sent Channel ON command to group (" + GCPGroupName +"), channel (" + channel + ").")
			EndIf
		
		ElseIf (command == pGCP.CMD_OFF)
			ChannelStatusArray[channel] = false
			If (pGCP.SendChannelOff(none, GCPGroupName, channel))
				Debug.Trace(Self + ": DEBUG - Sent Channel OFF command to group.")
			EndIf			
			
		EndIf
	EndIf
EndFunction


Bool Function MemberJoin(ObjectReference joiningMember)
	If (GroupMembersTable.FindStruct("Member", joiningMember) < 0)
		; bypass 128 elements limit via SUP
		GroupMemberInfo[] newMembers = new GroupMemberInfo[1]
		newMembers[0].Member = joiningMember
		newMembers[0].JoinDate = Utility.GetCurrentGameTime()
		newMembers[0].LastSeen = newMembers[0].JoinDate
		GroupMembersTable = MergeArrays(GroupMembersTable as Var[], newMembers as Var[]) as GroupMemberInfo[]
		Debug.Trace(Self + ": INFO - Group member (" + joiningMember + ") joined group (" + GCPGroupName + "); Group has (" + GroupMembersTable.Length + ") members now.")
		Return True
	EndIf
	Return False
EndFunction

; refresh lastseen timestamp
Bool Function MemberUpdate(ObjectReference updateMember)
	Int mIndex = GroupMembersTable.FindStruct("Member", updateMember)
	If (mIndex >= 0)
		GroupMembersTable[mIndex].LastSeen = Utility.GetCurrentGameTime()
	EndIf
EndFunction


Bool Function MemberPart(ObjectReference partingMember)
	Int mIndex = GroupMembersTable.FindStruct("Member", partingMember)
	If ( mIndex >= 0)
		GroupMembersTable.Remove(mIndex)
		Debug.Trace(Self + ": INFO - Group member (" + partingMember + ") left group (" + GCPGroupName + "); Group has (" + GroupMembersTable.Length + ") members now.")
	EndIf
EndFunction


Struct GroupMemberInfo
	ObjectReference Member
	Float JoinDate
	Float LastSeen
EndStruct