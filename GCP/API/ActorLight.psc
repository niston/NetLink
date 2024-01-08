Scriptname NetLink:GCP:API:ActorLight extends NetLink:GCP:API:DeviceActor

; The Group Control Protocol V1
; DeviceActor implementation of Open/Close based, NetLink/GCP enabled Lightsources - Custom scripting by niston

;/ 0.48
GCP:API:ActorLight: Fix OnPlayerLoadGame event passthrough to Parent
GCP:API:ActorLight: More reliable usage of SyncLight() on Load
/;

Import SUP_F4SE

Group ActorLightSettings
	Float Property AnimationDuration = 0.034 Auto Const
	{ Duration of on/off animations }
	SpawnedLightInfo[] Property AdditionalLights Auto Const
	{ Additional Lights }
EndGroup

Struct SpawnedLightInfo
	Light LightForm
	String AttachNodeName
EndStruct

ObjectReference[] spawnedLightRefs = none

Int Function Start()
	spawnedLightRefs = new ObjectReference[AdditionalLights.Length]	
	
	_UpdateAdditionalLights(_OutputEnabled)
	Return Parent.Start()
EndFunction

Function Stop()	
	_DeleteAllAdditionalLights()
	Parent.Stop()
EndFunction

Event OnWorkshopObjectPlaced(ObjectReference refWorkshop)
	RegisterForRemoteEvent(Game.GetPlayer(), "OnPlayerLoadGame")
	Parent.OnWorkshopObjectPlaced(refWorkshop)
	
	WaitFor3DLoad()
	_SyncLight()
	_UpdateAdditionalLightsOpenState()
EndEvent

Event OnWorkshopObjectDestroyed(ObjectReference refWorkshop)	
	UnRegisterForRemoteEvent(Game.GetPlayer(), "OnPlayerLoadGame")
	
	; despawn additional lights
	_UpdateAdditionalLights(despawnLights = true)
	spawnedLightRefs.Clear()
	spawnedLightRefs = none
	
	Parent.OnWorkshopObjectDestroyed(refWorkshop)
EndEvent

Event Actor.OnPlayerLoadGame(Actor refSender)
	; can't call remote event on parent, use proxy function instead
	HandleOnPlayerLoadGame()
EndEvent

Event OnLoad()
	_SyncLight()
	_UpdateAdditionalLightsOpenState()
EndEvent

Event OnPowerOn(ObjectReference refGenerator)
	_UpdateAdditionalLightsOpenState()
	Parent.OnPowerOn(refGenerator)
EndEvent

Event OnPowerOff()
	_UpdateAdditionalLights(false)
	Parent.OnPowerOff()
EndEvent

Function HandleOnPlayerLoadGame()
	WaitFor3DLoad()
	_SyncLight()
	Parent.HandleOnPlayerLoadGame()	
EndFunction

Function OnCircuitOpenChange(Bool isOpen)
	_UpdateAdditionalLights(isOpen)
EndFunction

Function _UpdateAdditionalLightsOpenState()
	Int s = GetOpenState()
	If (s == 1 || s == 2)
		; open, despawn
		_UpdateAdditionalLights(true)
	Else
		; closed, spawn
		_UpdateAdditionalLights(false)
	EndIf
EndFunction

Function _UpdateAdditionalLights(Bool despawnLights)
	If (AdditionalLights != none && AdditionalLights.Length > 0 && spawnedLightRefs != none )	; has additional lights, and reference array was initialized
		Int i = 0
		Bool isNotPoweredOrDestroyed = !IsPowered() || IsDestroyed()
		While (i < AdditionalLights.Length)
			ObjectReference curLight = spawnedLightRefs[i]
			SpawnedLightInfo curLightInf = AdditionalLights[i]
			Var[] cfnwArgs = new Var[0]
			If (isNotPoweredOrDestroyed || despawnLights)
				; despawn
				If (curLight != none)
					Debug.Trace(Self + ": DEBUG - Despawning light (" + curLightInf.LightForm + ") from node (" + curLightInf.AttachNodeName + "): " + curLight)					
					curLight.CallFunctionNoWait("Delete", cfnwArgs)
					;curLight.Delete()					
					curLight = none
				EndIf
			Else
				; spawn
				If (curLight == none)
					curLight = PlaceAtNode(curLightInf.AttachNodeName, curLightInf.LightForm, 1, true, false, false, true)					
					Debug.Trace(Self + ": DEBUG - Light (" + curLightInf.LightForm + ") spawned at node (" + curLightInf.AttachNodeName + "): " + curLight)
				EndIf
			EndIf						
			spawnedLightRefs[i] = curLight
			i+= 1
		EndWhile
	EndIf
EndFunction

Function _DeleteAllAdditionalLights()
	Int limit = spawnedLightRefs.Length
	While (spawnedLightRefs.Length > 0 && limit > 1)
		spawnedLightRefs[0].Delete()
		spawnedLightRefs[0] = none
		spawnedLightRefs.Remove(0)	
		limit -= 1
	EndWhile
EndFunction


Function _SyncLight()
	; sync workshop attachlight with emissive status, but only when 3d is loaded (breaks emission animation otherwise)
	; works around some engine or behavior graph issue, where some workshop attachlights are always on after loading a save, 
	; even though they were off when making the save and the light's getopenstate() is in fact still OPEN on load (unpowered/no emission)
	; emits a brief flicker - this is normal operation.
	If (Is3DLoaded())
		SetOpen(false)
		Utility.Wait(AnimationDuration)
		SetOpen(true)
		Utility.Wait(AnimationDuration)
		SetOpen(!OutputEnabled)
	EndIf
EndFunction

; overrides
Int Function _GetDeviceType()
	Return GCP_DEVICETYPE_ACTOR_LIGHT
EndFunction

String Function _GetDeviceStatus()
	Int openState = GetOpenState()
	If (openState == 1 || openState == 2)
		Return "OFF"
	ElseIf (openState == 3 || openState == 4)
		Return "ON"
	Else
		Return "N/A"
	EndIf
EndFunction