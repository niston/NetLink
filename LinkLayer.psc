Scriptname NetLink:LinkLayer extends NetLink:API:LinkLayerBase

; NISTRON SNE NETLINK PROTOCOL V1
; NetLink LinkLayer - Custom scripting by niston


;/ 0.48
General: Cleaned and restrucured source code for LinkLayer and NetworkLayer scripts
General: Added implementation stub for IP Protocol
LinkLayer: Added Thread Lock Management for concurrent Frame Type Registry access
LinkLayer: "Public" FTR functions are now Script State dependent
/;

; require SUP F4SE
Import SUP_F4SE


;/
################################
# Section: Various Definitions #
################################
/;
Int Property REQUIRE_SUP_MAJOR = 11 AutoReadOnly					; SUP Accelerator Required Major (unused)
Int Property REQUIRE_SUP_MINOR = 6 AutoReadOnly						; SUP Accelerator Required Minor (unused)

; NetLink protocol implemented by this LinkLayer
Int Property NETLINK_PROTOCOL_VERSION = 1 AutoReadOnly				; NISTRON SNE NETLINK PROTOCOL V1


; PHY Error Codes ("physical" layer)
Int Property ERROR_PHY_WORKSHOP = -1000 AutoReadOnly Hidden			; Failed to acquire local workshop reference
Int Property ERROR_PHY_CONNECTION = -1001 AutoReadOnly Hidden		; No connection to power grid
Int Property ERROR_PHY_NOFRAME = -1002 AutoReadOnly Hidden			; Inexistent (none) Frame
Int Property ERROR_PHY_ACCELERATOR = -1003 AutoReadOnly Hidden		; SUP acceleration failure
Int Property ERROR_PHY_NODEST = -1004 AutoReadOnly Hidden			; destination(s) required, but none supplied


; Link Layer Identification
String Property LINKLAYER_IDENTIFIER = "NetLink" AutoReadOnly Hidden	; The name of the game
Int Property LINKLAYER_VERSION_MAJOR = 0 AutoReadOnly Hidden			; Implementation major
Int Property LINKLAYER_VERSION_MINOR = 52 AutoReadOnly Hidden			; Implementation minor

; LAMP protocol support
Int Property NETLINK_FRAMETYPE_LAMP = 1 AutoReadOnly Hidden				; LAMP FrameType
Int Property LAMP_MT_FLASHREPLY = 0 AutoReadOnly Hidden					; Flash is Ping for Layer 2
Int Property LAMP_MT_FLASHREQUEST = 1 AutoReadOnly Hidden				; Flash is Ping for Layer 2
Int Property LAMP_MT_LOOPDETECT = 7 AutoReadOnly Hidden					; Loop Detection for Bridges
Int Property LAMP_MT_MODECONTROL = 11 AutoReadOnly Hidden				; Station Mode Control
Int Property LAMP_MT_SYSEVENT_WAKEUP = 12 AutoReadOnly Hidden			; WakeUp Message



;/
#######################################
# Section: CK Configurable Properties #
#######################################
/;
Group LinkLayerSettings
	String Property InitialStationName = "" Auto Const
	{ Initial NetLink Station name, leave empty to generate default }
	
	Int Property MaxRegisteredFrameTypes = 256 Auto Const
	{ Maximum number of FrameTypes in FrameType Registry. }
	
	Bool Property DisableAutoLifecycle = false Auto Const
	{ Do not automatically start/stop Link Layer in response to placement/scrapping if true. }
EndGroup



;/
###############################
# Section: Runtime Properties #
###############################
/;
String Property StationName = "" Auto Hidden

Bool Property LinkLayerDisabled Hidden
	Function Set(Bool value)
		If (value != bLinkLayerDisabled)
			; mark as disabled
			bLinkLayerDisabled = value
			
			; stop if started
			String curState = GetState()
			If (value == true)			
				If (curState == "Started")
					; stop link layer
					_Stop()			
				ElseIf (curState == "Starting")
					; request stop after start
					bStopRequestedWhileStarting = true				
				EndIf
			EndIf
		EndIf
	EndFunction
	Bool Function Get()
		Return bLinkLayerDisabled
	EndFunction
EndProperty

String Property StationAddress Hidden
	String Function Get()
		If (Cache_StationAddress != "")
			Return Cache_StationAddress
		Else
			String beginPattern = "< ("
			String endPattern = ")"
			String refText = Self as String
			Int beginPos = SUPStringFind(refText, beginPattern, 0, 0)
			If (beginPos > -1)
				beginPos += 3
				Int endPos = SUPStringFind(refText, endPattern, beginPos, 0)
				If (endPos > -1)
					endPos -= 1
					Cache_StationAddress = StringFindSubString(refText, beginPos, endPos)
					Return Cache_StationAddress
				EndIf
			EndIf
			; caching failed
			Return ""
		EndIf
	EndFunction
EndProperty

Bool Property PromisciousMode = false Auto Hidden
{ Enable promiscious mode on Station }

Bool Property GossipMode = false Auto Hidden
{ Enable gossip mode on Station }

; workshop reference
ObjectReference Property LocalWorkshopReference Auto Hidden
Keyword Property kwdWorkshopItem  Auto Hidden

Bool Property IsStarted Hidden
	Bool Function Get()
		Return bIsStarted
	EndFunction
EndProperty

; Layer 1 power grid ID (result < 0 = no connection)
Int Property L1PowerGridID Hidden
	Int Function Get()
		Return _L1GetPowerGridID()
	EndFunction
EndProperty

; Does Layer 1 have power
Bool Property L1Powered Hidden
	Bool Function Get()
		Return IsPowered()
	EndFunction
EndProperty




;/
###########################
# Section: Event Declares #
###########################
/;
CustomEvent Started
CustomEvent Stopping


;/
######################
# Section: Variables #
######################
/;
; filter arrays
ObjectReference[] filterNone = none
ObjectReference[] filterSelf = none
ObjectReference[] filterNoneAndSelf = none

; active property backers
Bool bLinkLayerDisabled = false

; internal flags
Bool bStopRequestedWhileStarting = false
Bool bStartRequestedWhileStopping = false
Bool bIsStarted = false

; local station address cache
String Cache_StationAddress = ""

; network caches
Int Cache_PowerGridID = -1
NetLink:LinkLayer[] Cache_StationsLocalNetwork = none
ObjectReference[] Cache_StationsLocalNetworkNoSelf = none
NetLink:LinkLayer[] Cache_StationsDirectConnection = none



;/
##########################
# Section: State Stopped #
##########################
/;
Auto State Stopped
	Event OnBeginState(String oldState)
		bStopRequestedWhileStarting = false
		bIsStarted	= false
		If (oldState != "" && oldState != "Starting")
			Debug.Trace(Self + ": INFO - NetLink Link Layer stopped.")
		EndIf
	EndEvent

	Event OnInit()		
		_StartFromInit()
	EndEvent

	Event OnWorkshopObjectPlaced(ObjectReference refWorkshop)
		If (!DisableAutoLifecycle)
			Start()
		EndIf
	EndEvent
	
	Event OnPowerOn(ObjectReference refGenerator)
		Utility.Wait(0.1)
		If (IsPowered())
			_StartFromEmptyState()
		EndIf
	EndEvent
	
	Int Function Start()
		; don't start up disabled interfaces
		If (bLinkLayerDisabled)
			Debug.Trace(Self + ": ERROR - Startup failed: LinkLayer is disabled.")
			Return ERROR_LNK_DISABLED
		EndIf
		
		; starting up
		GoToState("Starting")

		; check and cache station address
		String staAddress = StationAddress
		If (staAddress == "")
			Debug.Trace(Self + ": ERROR - Startup failed: Local Station address could not be read.")
			Return ERROR_LNK_NOADDR
		EndIf
		
		; clear flags
		bStopRequestedWhileStarting = false
		bStartRequestedWhileStopping = false
		bIsStarted = false
		
		; setup thread lock management
		_LocksSetup()
		
		; setup filter arrays
		filterNone = new ObjectReference[1]			
		filterNone[0] = none
		filterSelf = new ObjectReference[1]
		filterSelf[0] = Self
		filterNoneAndSelf = MergeArrays(filterNone as Var[], filterSelf as Var[]) as ObjectReference[]
				
		; setup local workshop reference
		_AcquireWorkshopRef()
		If (LocalWorkshopReference == none)
			Debug.Trace(Self + ": ERROR - Startup failed (ERROR_PHY_WORKSHOP).")			
			_Stop()
			Return ERROR_PHY_WORKSHOP
		EndIf
					
		; register for SUP connection events
		Var[] ConnectEventFilter = new Var[1]
		ConnectEventFilter[0] = LocalWorkshopReference
		Int supRegResult1 = RegisterForSUPEvent("onpowerconnection", Self as Form, "NetLink:LinkLayer", "OnSUPConnectionEvent", true, true, false, 0, ConnectEventFilter)
		If (supRegResult1 != 1)
			; accelerator failure
			Debug.Trace(Self + ": ERROR - RegisterForSUPEvent(OnPowerConnection) returned (" + supRegResult1 + ").")
			Return ERROR_PHY_ACCELERATOR
		EndIf
		
		; setup frame type registry
		_FTRStart()		

		; apply default station name if unspecified
		If (StationName == "")
			If (InitialStationName == "")
				StationName = _GetDefaultStationName()
				Debug.Trace(Self + ": INFO - Set default name for NetLink Station: " + StationName)
			Else
				StationName = InitialStationName
				Debug.Trace(Self + ": INFO - Set initial name for NetLink Station: " + StationName)
			EndIf
		EndIf
		
		GoToState("Started")
		Return OK_NOERROR
	EndFunction
EndState



;/
################################
# Section: Intermediate States #
################################
/;
State Starting
	Event OnBeginState(String oldState)		
		Debug.Trace(Self + ": DEBUG - NetLink Link Layer starting...")
	EndEvent
	
	Function Stop()
		bStopRequestedWhileStarting = true
	EndFunction
	
	Int Function Start()
		If (!LinkLayerDisabled)
			bStopRequestedWhileStarting = false
			Return OK_NOERROR
		Else
			Debug.Trace(Self + ": WARNING - Stop() ignored: Link Layer is disabled.")
			Return ERROR_LNK_DISABLED
		EndIf
	EndFunction
	
	Event OnEndState(String newState)		
		If (bStopRequestedWhileStarting)
			bStopRequestedWhileStarting = false
			If (newState == "Started")		
				Stop()
			EndIf
		EndIf		
	EndEvent
EndState

State Stopping
	Event OnBeginState(String oldState)
		Debug.Trace(Self + ": DEBUG - NetLink Link Layer stopping...")
	EndEvent
	
	Int Function Start()
		If (!LinkLayerDisabled)
			bStartRequestedWhileStopping = true			
			Return OK_NOERROR
		Else
			Debug.Trace(Self + ": WARNING - Start() ignored: Link Layer is disabled.")
			Return ERROR_LNK_DISABLED
		EndIf		
	EndFunction
	
	Function Stop()
		bStartRequestedWhileStopping = false
	EndFunction
	
	Event OnEndState(String newState)		
		If (bStartRequestedWhileStopping)
			bStartRequestedWhileStopping = false
			If (newState == "Stopped")
				Start()
			EndIf
		EndIf		
	EndEvent
EndState




;/
############################
# Section: State "Started" #
############################
/;
State Started
	; # Game Events #
	
	Event OnBeginState(String oldState)		
		bStartRequestedWhileStopping = false
		bIsStarted = true
		SendCustomEvent("Started", new Var[0])
		Debug.Trace(Self + ": INFO - NetLink Link Layer (" + LINKLAYER_IDENTIFIER + " " + LINKLAYER_VERSION_MAJOR + "." + LINKLAYER_VERSION_MINOR + ") started.")
	EndEvent
	
	; # SUP events #
	Function OnSUPConnectionEvent(bool bAdded, ObjectReference refEventWorkshop, ObjectReference refA, ObjectReference refB, ObjectReference refSpline, int refAPgID, Float refAPgLoad, Float refAPgCapacity, Int refBPgID, Float refBPgLoad, Float refBPgCapacity, Bool IsSnapped)	
		; get uncached powergrid ID
		Int localPgId = _L1GetPowerGridID(noCache = true)
		
		; filters
		If (localPgId < -1)
			; not on grid anymore, don't process
			Return
		EndIf
		; reference 
		If (refAPgID != localPgId && refBPgID != localPgId) 
			; event does not concern our power grid
			Return
		EndIf
		
		; connections made/cut on local network, invalidate caches
		; Debug.Trace(Self + ": DEBUG - Connection event received for local powergrid. Purging network state caches...")
		_PurgeNetworkStateCaches()
	EndFunction

	; # Layer 2 Functions #
	
	Function Stop()
		_Stop()
	EndFunction
	
	; Frame Type Registry Public Functions
	Int Function FTRRegisterNetworkLayerForFrameType(NetLink:API:NetworkLayerBase newProtocol, Int frameType)
		Return _FTRRegisterNetworkLayerForFrameType(newProtocol, frameType)
	EndFunction
	
	Function FTRUnregisterNetworkLayerForFrameType(NetLink:API:NetworkLayerBase refProtocol, Int frameType)
		_FTRUnregisterNetworkLayerForFrameType(refProtocol, frameType)
	EndFunction
	
	Function FTRUnregisterNetworkLayerForAllFrameTypes(NetLink:API:NetworkLayerBase refProtocol)
		_FTRUnregisterNetworkLayerForAllFrameTypes(refProtocol)
	EndFunction
	
	Bool Function FTRIsProtocolRegistered(NetLink:API:NetworkLayerBase refProtocol)
		Return _FTRIsProtocolRegistered(refProtocol)
	EndFunction

	; transmit data (unicast, broadcast)
	Int Function LinkSend(ObjectReference refDestination, Int frameType, Var data)
		If (CheckFrameTypeValid(frameType))
			NetLinkFrame outFrame = new NetLinkFrame
			outFrame.Version = NETLINK_PROTOCOL_VERSION
			outFrame.Source = Self as ObjectReference
			outFrame.Destination = refDestination
			outFrame.LNet = 0 ; reserved
			outFrame.FrameType = frameType
			outFrame.Payload = data
			Return _L1TX(outFrame)
		Else
			Return ERROR_LNK_FRAMETYPE
		EndIf
	EndFunction

	; transmit data (multicast)
	Int Function LinkSendMulti(ObjectReference[] refDestinations, Int frameType, Var data)
		If (CheckFrameTypeValid(frameType))
			If (refDestinations == none || refDestinations.Length == 0)
				Return 0 ; delivered to 0 stations
			EndIf
			NetLinkFrame outFrame = new NetLinkFrame
			outFrame.Version = NETLINK_PROTOCOL_VERSION
			outFrame.Source = Self as ObjectReference
			outFrame.Destination = none
			outFrame.LNet = 0 ; reserved
			outFrame.FrameType = frameType
			outFrame.Payload = data
			Return _L1MC(outFrame, refDestinations)
		Else
			Return ERROR_LNK_FRAMETYPE
		EndIf
	EndFunction
	
	; transmit data (local broadcast to directly connected stations only)
	Int Function LinkSendDirect(Int frameType, Var data)
		NetLinkFrame outFrame = new NetLinkFrame
		outFrame.Version = NETLINK_PROTOCOL_VERSION	
		outFrame.Source = Self as ObjectReference
		outFrame.Destination = none
		outFrame.LNet = 0
		outFrame.FrameType = frameType
		outFrame.Payload = none
		Return _L1DC(outFrame)
	EndFunction

	; # Layer 1 Functions #
	
	; # enumerate NetLink stations on local network #
	L1EnumStationsResult Function _L1EnumStations(Bool directConnectionsOnly = false)
		L1EnumStationsResult result = new L1EnumStationsResult
		
		If (directConnectionsOnly)	; enumerate remote stations with a DIRECT connection to the local station only
			
			If (Cache_StationsDirectConnection != none)
				; return success from cache hit
				result.Code = OK_NOERROR
				result.Stations = Cache_StationsDirectConnection
				Return result					
			EndIf
			
			; get direct connected stations only and filter for NetLink:LinkLayer type
			ObjectReference[] directStations = (GetDirectGridConnectionsRefs(LocalWorkshopReference, Self) as NetLink:LinkLayer[]) as ObjectReference[]
			directStations = FilterObjectRefArrayByRefs(directStations, filterNone)

			; cache directly connected stations info
			Cache_StationsDirectConnection = directStations as NetLink:LinkLayer[]

			; prepare and return result
			result.Code = OK_NOERROR
			result.Stations = Cache_StationsDirectConnection
			Return result		
		
		Else						; enumerate ALL remote stations on the local network (direct and indirect connections)
		
			; Check StationsLocalNetwork cache
			If (Cache_StationsLocalNetwork != none)
				; return success from cache hit
				result.Code = OK_NOERROR
				result.Stations = Cache_StationsLocalNetwork
				Return result			
			EndIf

			; get querier powergrid information
			PowerGridInstance senderGrid = GetPowerGridForObject(LocalWorkshopReference, Self)            
			If (senderGrid == none)
				Debug.Trace(Self + ": ERROR - Accelerator failure: GetPowerGridForObject returned none.")
				result.Code = ERROR_PHY_ACCELERATOR
				Return result
			EndIf
			If (senderGrid.ID < 0)
				; sender is not connected to any powergrid; 0 nodes
				result.Code = ERROR_PHY_CONNECTION
				Return result
			EndIf
			
			; cache power grid information
			Cache_PowerGridID = senderGrid.ID

			; get power grid nodes and filter for netlink stations
			NetLink:LinkLayer[] gridStations = GetPowerGridElements(LocalWorkshopReference, senderGrid.ID) as NetLink:LinkLayer[]		; cast to NetLink:LinkLayer		
			gridStations = FilterObjectRefArrayByRefs(gridStations as ObjectReference[], filterNone) as NetLink:LinkLayer[]		; drop none (cast failed) entries
					
			If (gridStations == none)
				result.Code = ERROR_PHY_ACCELERATOR
				Return result
			EndIf
			
			; cache local network stations information
			Cache_StationsLocalNetwork = gridStations
			
			; return success
			result.Code = OK_NOERROR
			result.Stations = gridStations	
			Return result
			
		EndIf
	EndFunction


	; # transmit frame on layer 1 (PHY) - loopback, unicast, broadcast #
	; returns the number of stations the frame was delievered to, or an error code
	Int Function _L1TX(NetLinkFrame frame)	
		; check for frame
		If (frame == none)
			Return ERROR_PHY_NOFRAME
		EndIf
		
		; create _L1RX function invoke parameters
		Var[] invokeParams = new Var[2]
		invokeParams[0] = Self
		invokeParams[1] = frame

		; local loopback path, works w/o a power grid connection and (theoretically) without a workshop
		If (frame.Destination == (Self as ObjectReference))
			;Debug.Trace(Self + ": DEBUG - L1TX: Transmitting Frame to Local Loopback...")
			NotifyReferenceScripts(filterSelf, "NetLink:LinkLayer", "_L1RX", invokeParams)
			Debug.Trace(Self + ": DEBUG - L1TX: NetLink Frame transmitted to Local Loopback.") 
			Return 1 ; delivered to 1 station
		EndIf

		; frame delivered to rxCount stations
		Int rxCount = 0
		
		; for easy access, all netlink stations on local net as objectref array
		ObjectReference[] stations
		
		; frame is broadcast or unknown unicast?
		If (frame.Destination == none || !HasSharedPowerGrid(frame.Destination) || GossipMode)
			; Yes, broadcast the frame...
			
			; update broadcast targets cache
			If (Cache_StationsLocalNetworkNoSelf == none)
				; enumerate stations on local network
				L1EnumStationsResult enumStationsResult = _L1EnumStations()
				If (enumStationsResult.Code != OK_NOERROR)
					Debug.Trace(Self + ": ERROR - L1TX failed: L1EnumStations returned (" + enumStationsResult.Code + ").")
					Return enumStationsResult.Code
				EndIf

				; filter self from list of stations on local net
				Cache_StationsLocalNetworkNoSelf = FilterObjectRefArrayByRefs(enumStationsResult.Stations as ObjectReference[], filterSelf)
			EndIf
			
			; exit if no network destinations remaining
			If (Cache_StationsLocalNetworkNoSelf.Length == 0)
				Return 0 ; delivered to 0 stations (no other stations on network)
			EndIf
			
			; broadcast frame to all stations, except self
			rxCount = NotifyReferenceScripts(Cache_StationsLocalNetworkNoSelf, "NetLink:LinkLayer", "_L1RX", invokeParams)				
			Debug.Trace(Self + ": DEBUG - L1TX: NetLink Frame broadcasted to (" + rxCount + ") stations.")
			
			Return rxCount
			
		Else
			; No, unicast the frame...
			
			; sole recipient node
			stations = new ObjectReference[1]
			stations[0] = frame.Destination
			
			; transmit unicast frame to destination on local network
			rxCount = NotifyReferenceScripts(stations, "NetLink:LinkLayer", "_L1RX", invokeParams)
			Debug.Trace(Self + ": DEBUG - L1TX: NetLink Frame unicasted to (" + rxCount + ") stations.")

			Return rxCount
			
		EndIf
	EndFunction

	; # multicast transmission #
	; note: multicast to self is not supported
	Int Function _L1MC(NetLinkFrame frame, ObjectReference[] destinationNodes)	
		; check for frame
		If (frame == none)
			Return ERROR_PHY_NOFRAME
		EndIf
		
		; check for destinations supplied
		If (destinationNodes == none || destinationNodes.Length == 0)
			Return ERROR_PHY_NODEST
		EndIf
		
		; obtain local power grid id
		Int localGridID = _L1GetPowerGridID()
		If (localGridID < 0)
			; failure, pass through error code
			Return localGridID
		EndIf
		
		; multicast frames always have destination none (looks like a broadcast frame to recipient)
		frame.Destination = none
		
		; create _L1RX function invoke parameters
		Var[] invokeParams = new Var[2]
		invokeParams[0] = Self
		invokeParams[1] = frame

		; frame delivered to rxCount stations
		Int rxCount = 0
		
		; cast destination nodes through NetLink:LinkLayer type
		destinationNodes = (destinationNodes as NetLink:LinkLayer[]) as ObjectReference[]
		
		; remove none (failed casts) and self entries from destinationNodes
		destinationNodes = FilterObjectRefArrayByRefs(destinationNodes, filterNoneAndSelf)

		; any destinations remaining?
		If (destinationNodes.Length == 0)
			Return 0 ; delivered to 0 stations
		EndIf
				
		; filter list for stations on same power grid
		ObjectReference[] stations = FilterObjectRefArrayBySharedPowergrid(destinationNodes, LocalWorkshopReference, localGridID)
		
		; any non-local stations removed by powergrid filter?
		If (stations.Length != destinationNodes.Length)
		
			; yep, broadcast frame instead
			Debug.Trace(Self + ": WARNING - L1MC: NetLink Frame multicast to at least one destination not on local network. Broadcasting frame instead...")
			
			; enumerate stations on local network
			L1EnumStationsResult enumStationsResult = _L1EnumStations()
			If (enumStationsResult.Code != OK_NOERROR)
				Debug.Trace(Self + ": ERROR - L1MC failed: L1EnumStations returned (" + enumStationsResult.Code + ").")
				Return enumStationsResult.Code
			EndIf
						
			; filter self from list of stations on local net
			stations = FilterObjectRefArrayByRefs(enumStationsResult.Stations as ObjectReference[], filterSelf)
			
			; exit if no network destinations remaining
			If (stations.Length == 0)
				Return 0 ; delivered to 0 stations (no other stations on network)
			EndIf
			
			; transmit broadcast frame to all stations, except self
			rxCount = NotifyReferenceScripts(stations, "NetLink:LinkLayer", "_L1RX", invokeParams)				
			Debug.Trace(Self + ": DEBUG - L1MC: NetLink Frame broadcasted to (" + rxCount + ") stations.")
			
			Return rxCount
			
		EndIf
		
		; transmit frame to filtered stations list
		rxCount = NotifyReferenceScripts(stations, "NetLink:LinkLayer", "_L1RX", invokeParams)
		Debug.Trace(Self + ": DEBUG - L1MC: NetLink Frame multicasted to (" + rxCount + ") stations.")
		Return rxCount;
	EndFunction

	; # local broadcast transmission #
	Int Function _L1DC(NetLinkFrame frame)
		If (frame == none)
			Return ERROR_PHY_NOFRAME		
		EndIf
		
		; frame destination must be none for local cast
		frame.Destination = none
		
		; TODO: enable cache
		; get direct connected stations
		ObjectReference[] directStations = (GetDirectGridConnectionsRefs(LocalWorkshopReference, Self) as NetLink:LinkLayer[]) as ObjectReference[]
		directStations = FilterObjectRefArrayByRefs(directStations, filterNone)

		If (directStations.Length == 0)
			Return 0	; delivered to 0 stations
		EndIf

		; create _L1RX function invoke parameters
		Var[] invokeParams = new Var[2]
		invokeParams[0] =  Self
		invokeParams[1] = frame
		
		; transmit frame
		Return NotifyReferenceScripts(directStations, "NetLink:LinkLayer", "_L1RX", invokeParams)	
	EndFunction

	; # receive frame from layer 1 (PHY) #
	Function _L1RX(Var[] data)
		If (data == none)
			Debug.Trace(Self + ": WARNING - L1RX: Null data discarded.")
			Return 		
		EndIf
		
		; extract NetLinkFrame
		NetLinkFrame frame = data[1] as NetLinkFrame
		If (!frame)		
			Debug.Trace(Self + ": WARNING - L1RX: Invalid or null Frame discarded.")		
			Return
		EndIf
	
		; validate if source is of NetLink:LinkLayerBase type
		If (!frame.Source is NetLink:API:LinkLayerBase)
			Debug.Trace(Self + ": WARNING - L1RX: NetLink Frame with invalid Source (" + frame.Source + ") discarded.")
			Return
		EndIf
		
		; check frame destination if not in promiscious mode
		If (!PromisciousMode && (frame.Destination != none) && (frame.Destination != Self))
			; not addressed to local Station, and not a broadcast/multicast frame either
			Return
		EndIf			
		
		; check frame version
		If (frame.Version != NETLINK_PROTOCOL_VERSION)
			Debug.Trace(Self + ": WARNING - L1RX: NetLink Frame with unsupported version (" + frame.Version + ") from (" + frame.Source + ") discarded.")
			Return
		EndIf
		
		; valid frame version, debug chatter
		;Debug.Trace(Self + ": DEBUG - L1RX: NetLink Frame received from (" + frame.Source + ").")
		
		; deliver frame to upper level protocols via frametype registry
		_FTRDeliverFrameToNetworkLayers(frame)
	EndFunction
EndState




;/
########################
# Section: Empty State #
########################
/;
Event OnPowerOn(ObjectReference refGenerator)
	_StartFromEmptyState()
EndEvent

Event OnWorkshopObjectGrabbed(ObjectReference refWorkshop)
	_StartFromEmptyState()
EndEvent

Int Function Start()
	Return ERROR_LNK_STATE
EndFunction

Function Stop()
	; do nothing
EndFunction
	
Int Function LinkSend(ObjectReference refDestination, Int frameType, Var data)
	Return ERROR_LNK_NOTSTARTED
EndFunction

Int Function LinkSendMulti(ObjectReference[] refDestinations, Int frameType, Var data)
	Return ERROR_LNK_NOTSTARTED
EndFunction

Int Function LinkSendDirect(Int frameType, Var data)
	Return ERROR_LNK_NOTSTARTED
EndFunction

Int Function RegisterProtocol(Int frameType, ObjectReference refProtocol)
	Return ERROR_LNK_NOTSTARTED
EndFunction

Bool Function CheckFrameTypeValid(Int frameType)
	Return (frameType > 0 && frameType < 256)
EndFunction

L1EnumStationsResult Function _L1EnumStations(Bool directConnectionsOnly = false)
	L1EnumStationsResult result = new L1EnumStationsResult
	result.Code = ERROR_LNK_NOTSTARTED
	result.Stations = new NetLink:LinkLayer[0]
	Return result
EndFunction

Int Function _L1TX(NetLinkFrame frame)
	Return ERROR_LNK_NOTSTARTED
EndFunction

Int Function _L1MC(NetLinkFrame frame, ObjectReference[] destinationNodes)	
	Return ERROR_LNK_NOTSTARTED
EndFunction

Int Function _L1DC(NetLinkFrame frame)
	Return ERROR_LNK_NOTSTARTED
EndFunction

Function _L1RX(Var[] data)
	; do nothing
EndFunction

Function OnSUPConnectionEvent(bool bAdded, ObjectReference refEventWorkshop, ObjectReference refA, ObjectReference refB, ObjectReference refSpline, int refAPgID, Float refAPgLoad, Float refAPgCapacity, Int refBPgID, Float refBPgLoad, Float refBPgCapacity, Bool IsSnapped)	
	; do nothing
EndFunction

Int Function FTRRegisterNetworkLayerForFrameType(NetLink:API:NetworkLayerBase newProtocol, Int frameType)
	Return ERROR_LNK_NOTSTARTED
EndFunction

Function FTRUnregisterNetworkLayerForFrameType(NetLink:API:NetworkLayerBase refProtocol, Int frameType)
	; do nothing
EndFunction

Function FTRUnregisterNetworkLayerForAllFrameTypes(NetLink:API:NetworkLayerBase refProtocol)
	; do nothing
EndFunction

Bool Function FTRIsProtocolRegistered(NetLink:API:NetworkLayerBase refProtocol)
	Return False
EndFunction



;/
###################################################
# Section: All State Event Handlers And Overrides #
###################################################
/;
Event OnWorkshopObjectDestroyed(ObjectReference refWorkshop)
	If (!DisableAutoLifecycle)
		_Stop()
	EndIf
	Parent.OnWorkshopObjectDestroyed(refWorkshop)
EndEvent

Function Delete()
	If (!DisableAutoLifecycle)
		_Stop()
	EndIf
	Parent.Delete()
EndFunction




;/
###############################
# Section: Internal Functions #
###############################

ATTN: Do not call these functions externally.

/;
Function _Stop()	
	GoToState("Stopping")	
	; stop issuing new locks
	_LocksHalt()

	; clear flags
	bIsStarted = false
	bStartRequestedWhileStopping = false
	bStopRequestedWhileStarting = false
			
	; notify L3 protocols about imminent LinkLayer shutdown
	SendCustomEvent("Stopping", new Var[0])
	
	; stop frame type registry
	_FTRStop()
	
	; unregister for SUP events
	RegisterForSUPEvent("onpowerconnection", (Self as ObjectReference) as Form, "NetLink:LinkLayer", "OnSUPConnectionEvent", false, true, false, 0, none)	

	; clear station address cache
	Cache_StationAddress = ""

	; clear network state caches
	_PurgeNetworkStateCaches()

	; discard filters
	If (filterNoneAndSelf != none)
		filterNoneAndSelf.Clear()
		filterNoneAndSelf = none
	EndIf
	If (filterNone != none)
		filterNone.Clear()
		filterNone = none
	EndIf
	If (filterSelf != none)
		filterSelf.Clear()
		filterSelf = none
	EndIf
	
	; discard local workshop ref and reflink keyword
	LocalWorkshopReference = none
	kwdWorkshopItem = none
	
	; clear locks
	_LocksClear()
	
	GoToState("Stopped")
EndFunction

Int Function _L1GetPowerGridID(Bool noCache = false)
	If (LocalWorkshopReference != none)
		If (!noCache && Cache_PowerGridID > -1)
			; cache hit
			Return Cache_PowerGridID
		EndIf
		
		PowerGridInstance myGrid = GetPowerGridForObject(LocalWorkshopReference, Self)
		If (myGrid != none)
		
			If (!noCache)
				; write to cache
				Cache_PowerGridID = myGrid.ID
			EndIf
			
			Return myGrid.ID
		Else
			; sup failed
			Debug.Trace(Self + ": L1GetPowerGridID() failed: Accelerator failure.")
			Return ERROR_PHY_ACCELERATOR
		EndIf
	Else
		Return ERROR_PHY_WORKSHOP
	EndIf
EndFunction

String Function _GetDefaultStationName()
	String staAddr = StationAddress
	If (staAddr == "")
		Return "STA_NOADDRESS"
	Else
		Return "STA_" + staAddr
	EndIf
EndFunction

Function _AcquireWorkshopRef()
	kwdWorkshopItem = Game.GetForm(0x54ba6) as Keyword
	LocalWorkshopReference = Self.GetLinkedRef(kwdWorkshopItem)
	If (LocalWorkshopReference == none)
		Debug.Trace(Self + ": WARNING - AcquireWorkshopRef returned none.")
	EndIf
EndFunction

Function _StartFromInit()
	; auto lifecycle management enabled?
	If (!DisableAutoLifecycle)
		; reference placed in editor?
		If (!IsCreated())
			; yep, start on init
			Start()
		EndIf
	EndIf
EndFunction

Function _PurgeNetworkStateCaches()
	Cache_PowerGridID = -1
	If (Cache_StationsLocalNetwork != none)
		Cache_StationsLocalNetwork.Clear()
		Cache_StationsLocalNetwork = none
	EndIf
	If (Cache_StationsLocalNetworkNoSelf != none)
		Cache_StationsLocalNetworkNoSelf.Clear()
		Cache_StationsLocalNetworkNoSelf = none
	EndIf
	If (Cache_StationsDirectConnection != none)
		Cache_StationsDirectConnection.Clear()
		Cache_StationsDirectConnection = none
	EndIf	
EndFunction

String Function ResolveErrorCode(Int code)
	; netlink general
	If (code == OK_NOERROR)
		Return "OK_NOERROR"	
	ElseIf (code == ERROR_UNAVAILABLE)
		Return "ERROR_UNAVAILABLE"
	
	; layer 1
	ElseIf (code == ERROR_PHY_CONNECTION)
		Return "ERROR_PHY_CONNECTION"
	ElseIf (code == ERROR_PHY_WORKSHOP)
		Return "ERROR_PHY_WORKSHOP"
	ElseIf (code == ERROR_PHY_NOFRAME)
		Return "ERROR_PHY_NOFRAME"
	ElseIf (code == ERROR_PHY_ACCELERATOR)
		Return "ERROR_PHY_ACCELERATOR"
	ElseIf (code == ERROR_PHY_NODEST)
		Return "ERROR_PHY_NODEST"

	; layer 2
	ElseIf (code == ERROR_LNK_DISABLED)
		Return "ERROR_LNK_DISABLED"
	ElseIf (code == ERROR_LNK_NOTSTARTED)
		Return "ERROR_LNK_NOTSTARTED"
	ElseIf (code == ERROR_LNK_STATE)
		Return "ERROR_LNK_STATE"
	ElseIf (code == ERROR_LNK_FRAMETYPE)
		Return "ERROR_LNK_FRAMETYPE"
	ElseIf (code == "ERROR_LNK_NOPROTO")
		Return "ERROR_LNK_NOPROTO"
	ElseIf (code == "ERROR_LNK_FTREGMAX")
		Return "ERROR_LNK_FTREGMAX"
	ElseIf (code == "ERROR_LNK_NOADDR")
		Return "ERROR_LNK_NOADDR"
	
	; unknown code
	Else
		Return "CODE_UNKNOWN (" + code + ")"
	EndIf
EndFunction

Bool Function CheckSuccessCode(Int code)
	Return (code > -1)
EndFunction














