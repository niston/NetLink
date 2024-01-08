Scriptname NetLink:GCP:API:ActorRelay extends NetLink:GCP:API:DeviceActor

; The Group Control Protocol V1
; DeviceActor implementation of Open/Close based, NetLink/GCP enabled Relay - Custom scripting by niston

Int Function _GetDeviceType()
	Return GCP_DEVICETYPE_ACTOR_RELAY
EndFunction