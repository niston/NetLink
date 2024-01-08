Scriptname NetLink:IP:Protocol extends NetLink:API:NetworkLayerBase

; The Interlink Protocol - custom scripting by niston

; Implementation version info
Int Property IMPL_VERSION_MAJOR = 0 AutoReadOnly Hidden				; IP implementation version major (should match LinkLayer version)
Int Property IMPL_VERSION_MINOR = 0 AutoReadOnly Hidden				; IP implementation version minor (should match LinkLayer version)

; IP protocol identifiers
Int Property NETLINK_FRAMETYPE_IP = 11 AutoReadOnly Hidden			; IP protocol uses netlink frametype 11
Int Property PROTOCOL_VERSION = 4 AutoReadOnly Hidden				; IP protocol version 4


; IP Protocol Structs

Struct IPPacket														; IP packet
	Int Version
	IPPacketTOS TOS
	Int TTL
	Int Protocol
	IPAddress Source		
	IPAddress Destination
	IPPacketOption[] Options
	Var Payload
EndStruct

Struct IPPacketTOS
	Int Reliability
	Int Throughput
	Int Delay	
EndStruct

Struct IPPacketOption
	Int OptionType
	Var OptionData
EndStruct

Struct IPAddress
	Int Octet1
	Int Octet2
	Int Octet3
	Int Octet4
EndStruct

; protocol functions
Int Function Start()
	; start networklayer base
	Int result = Parent.Start()
	If (!CheckSuccessCode(result))
		; failed
		Return result
	EndIf
	
	Return OK_NOERROR
EndFunction

Function Stop()
	; stop networklayer base
	Parent.Stop()
EndFunction