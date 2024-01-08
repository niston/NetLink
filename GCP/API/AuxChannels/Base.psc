Scriptname NetLink:GCP:API:AuxChannels:Base extends NetLink:GCP:ChannelMember

Int Property ChannelDeviceType Auto Hidden
NetLink:GCP:API:Device Property Notify Auto Hidden

Function OnGCPChannelReceive(ObjectReference refSender, ObjectReference refRecipient, String groupName, Int channelId, Int command, Var data)
	If (Notify != none)
		Notify.OnAuxChannelReceive(Self, refSender, refRecipient, groupName, channelId, command, data)
	EndIf
EndFunction
