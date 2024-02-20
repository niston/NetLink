Scriptname NetLink:API:LinkLayerBase extends ObjectReference

; NISTRON SNE NETLINK PROTOCOL V1
; NetLink LinkLayer Base Class - Custom scripting by niston

; TODO: Move more stuff here

; require SUP
Import SUP_F4SE

; function result structs
Struct L1EnumStationsResult			; enum stations call result
	Int Code
	NetLink:LinkLayer[] Stations
EndStruct

; NetLink General Error Codes
Int Property OK_NOERROR = 0 AutoReadOnly Hidden						; operation succeeded without error
Int Property ERROR_LOCK_ACQFAIL = -101 AutoReadOnly Hidden			; AcquireLock operation failed
Int Property ERROR_UNAVAILABLE = -90000 AutoReadOnly Hidden			; bound game object is unavailable
Int Property ERROR_PROHIBITED = - 90001 AutoReadOnly Hidden			; prohibited by script logic

; LNK Error Codes (link layer)
Int Property ERROR_LNK_NOTSTARTED = -2000 AutoReadOnly Hidden		; link layer is not started
Int Property ERROR_LNK_DISABLED = -2001 AutoReadOnly Hidden			; link layer is disabled
Int Property ERROR_LNK_STATE = -2002 AutoReadOnly Hidden			; operation invalid in current state
Int Property ERROR_LNK_FRAMETYPE = -2003 AutoReadOnly Hidden 		; invalid frametype
Int Property ERROR_LNK_NOPROTO = -2004 AutoReadOnly Hidden			; Inexistent (none) network layer protocol
Int Property ERROR_LNK_FTREGMAX = -2005 AutoReadOnly Hidden			; Maximum number of frametypes registered
Int Property ERROR_LNK_NOADDR = - 2006 AutoReadOnly Hidden			; Station address cannot be determined
Int Property ERROR_LNK_FTREGACCEL = -2007 AutoReadOnly Hidden		; Frame Type Registry acceleration failure


; known protocols
Int Property NETLINK_FRAMETYPE_GCP = 10 AutoReadOnly Hidden			; GCP protocol uses netlink frametype 10


;/
#####################################
# Section: NetLink Protocol Structs #
#####################################
/;
Struct NetLinkFrame					; netlink layer 2 frame format
	Int Version
	ObjectReference Destination
	ObjectReference Source	
	Int LNET
	Int FrameType
	Var Payload
EndStruct

Struct LAMPFrame					; link layer management protocol
	Int MessageType
	Int MessageCode
	Var MessageData
EndStruct

Struct LAMPFrameDataEcho
	Int Identifier
	Int sequenceNumber
	String Data
EndStruct


;/
######################
# Section: Variables #
######################
/;
; framtype/protocol registry
FrameTypeRegistration[] _FTRegistry = none


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
#############################
# Section: Helper Functions #
#############################
/;
Function _StartFromEmptyState()
	If (GetState() == "")		
		Debug.Trace(Self + ": DEBUG - Initializing from empty state...")
		GoToState("Stopped")
		Start()
	EndIf
EndFunction




;/ 
################################
# Section: Frame Type Registry #
################################
/;
Bool _FTRIsStarted = false

Struct FrameTypeRegistration
	Int FrameType										; frametype this registration is for
	NetLink:API:NetworkLayerBase[] NetworkLayerRefs		; registered networklayer implementation references
	String[] NetworkLayerScriptnames					; ...and their scriptnames
EndStruct

Function _FTRStart()	
	_FTRegistry = new FrameTypeRegistration[0]
	_FTRIsStarted = true
	Debug.Trace(Self + ": DEBUG - FTR: Subsystem statrted.")
EndFunction

Function _FTRStop()
	_FTRIsStarted = false
	_FTRUnregisterAll()	
	If (_FTRegistry != none)
		_FTRegistry.Clear()
		_FTRegistry = none
	EndIf
	Debug.Trace(Self + ": DEBUG - FTR: Subsystem stopped.")
EndFunction

Int Function _FTRRegisterNetworkLayerForFrameType(NetLink:API:NetworkLayerBase newProtocol, Int frameType)
	; is frametype valid?
	If (!CheckFrameTypeValid(frameType))
		Debug.Trace(Self + ": ERROR - RegisterL3Protocol() failed: Invalid frametype (" + frameType + ").")
		Return ERROR_LNK_FRAMETYPE
	EndIf
	
	; is protocol valid?
	If (newProtocol == none)
		Debug.Trace(Self + ": ERROR - RegisterL3Protocol() failed: newProtocol is none.")
		Return ERROR_LNK_NOPROTO
	EndIf
	
	String newProtocolScriptname = newProtocol.NetworkLayerScriptname
	
	; acquire read/write lock on registry
	If (!_LockAcquire(LOCK_FTR, lockReads = true, lockWrites = true))
		Debug.Trace(Self + ": ERROR - FTR: DeliverFrameToNetworkLayers failed to acquire LOCK_FTR for read/write. Registration failed.")
		Return ERROR_LOCK_ACQFAIL
	EndIf		
	
	; find frametype in registry
	Int frameTypeIndex = _FTRegistry.FindStruct("FrameType", frameType)
	If (frameTypeIndex == -1)
		
		; frametype not in registry, create new registration
		FrameTypeRegistration newRegistration = new FrameTypeRegistration
		newRegistration.FrameType = frameType
		newRegistration.NetworkLayerRefs = new NetLink:API:NetworkLayerBase[1]
		newRegistration.NetworkLayerScriptnames = new String[1]
		newRegistration.NetworkLayerRefs[0] = newProtocol
		newRegistration.NetworkLayerScriptnames[0] = newProtocolScriptname
		
		; _FTRegistry is empty?
		If (_FTRegistry.Length == 0)
			; add first entry
			_FTRegistry.Add(newRegistration)
		Else
			; add to registry, bypassing 128 elements limit
			FrameTypeRegistration[] newRegistrationArray = new FrameTypeRegistration[1]
			newRegistrationArray[0] = newRegistration
			_FTRegistry = MergeArrays(_FTRegistry as Var[], newRegistrationArray as Var[]) as FrameTypeRegistration[]
		EndIf		

		Debug.Trace(Self + ": INFO - FTR: Registered Network Layer Protocol (" + newProtocol + ") for FrameType (" + frameType + ").")
		
		; success
		_LockRelease(LOCK_FTR)
		Return OK_NOERROR
	
	Else
		; frametype found in registry, get it's FrameTypeRegistration
		FrameTypeRegistration frameTypeReg = _FTRegistry[frameTypeIndex]
		
		; refProtocol already registered for FrameType?			
		If (_FTRIsProtocolInFrameTypeReg(frameTypeReg, newProtocol))

			; refProtocol is already registered for frameType			
			Debug.Trace(Self + ": WARNING - FTR: Network Layer Protocol (" + newProtocol + ":" + ") already registered for FrameType (" + frameType + "). Registration ignored.")		

			; not a failure
			_LockRelease(LOCK_FTR)
			Return OK_NOERROR
		
		EndIf				

		; no, add new protocol for frametype to registry
		Var[] newNLRefAry = new Var[1]
		Var[] newStringnameAry = new Var[1]
		newNLRefAry[0] = newProtocol							
		newStringnameAry[0] = newProtocolScriptname
		frameTypeReg.NetworkLayerRefs = MergeArrays(frameTypeReg.NetworkLayerRefs as Var[], newNLRefAry) as NetLink:API:NetworkLayerBase[]
		frameTypeReg.NetworkLayerScriptnames = MergeArrays(frameTypeReg.NetworkLayerScriptnames as Var[], newStringnameAry) as String[]
		
		Debug.Trace(Self + ": INFO - FTR: Registered Network Layer Protocol (" + newProtocol + ") for FrameType (" + frameType + ").")
		
		; success			
		_LockRelease(LOCK_FTR)
		Return OK_NOERROR			
	EndIf
EndFunction

; ######### ATTN: must acquire FTR write lock manually #########
Bool Function _FTRIsProtocolInFrameTypeReg(FrameTypeRegistration frameTypeReg, NetLink:API:NetworkLayerBase refProtocol)
	Return (_FTRFindProtocolInFrameTypeReg(frameTypeReg, refProtocol) != -1)
EndFunction

; ######### ATTN: must acquire FTR write lock manually #########
Int Function _FTRFindProtocolInFrameTypeReg(FrameTypeRegistration frameTypeReg, NetLink:API:NetworkLayerBase refProtocol)

	String refProtocolScriptname = refProtocol.NetworkLayerScriptname
	
	Int listenerIndex = frameTypeReg.NetworkLayerRefs.Find(refProtocol)			
	Bool exitSearch = (listenerIndex == -1)
	While (!exitSearch)
		If (frameTypeReg.NetworkLayerScriptnames[listenerIndex] == refProtocolScriptname)
			exitSearch = true
		Else
			; 
			If (listenerIndex < frameTypeReg.NetworkLayerRefs.Length)
				; get next find result
				listenerIndex = frameTypeReg.NetworkLayerRefs.Find(refProtocol, listenerIndex + 1)			
				If (listenerIndex == -1)
					; no more find results
					exitSearch = true
				EndIf
			Else
				; reached end of listener array without match
				exitSearch = true
			EndIf
		EndIf
	EndWhile
	
	Return listenerIndex	
EndFunction

Bool Function _FTRIsProtocolRegistered(NetLink:API:NetworkLayerBase refProtocol)
	; acquire write lock on ft registry
	If (!_LockAcquire(LOCK_FTR, lockReads = false, lockWrites = true))
		Debug.Trace(Self + ": ERROR - FTR: FTRIsProtocolRegistered failed to acquire LOCK_FTR for read/write..")
		Return False
	EndIf	

	; iterate frametype registrations
	If (_FTRegistry == none || _FTRegistry.Length == 0)
		Int i = 0
		While (i < _FTRegistry.Length)
			; current registration has the protocol we are looking for?
			FrameTypeRegistration ftRegInfo = _FTRegistry[i]
			If (ftRegInfo != none)
				If (_FTRIsProtocolInFrameTypeReg(ftRegInfo, refProtocol))
					
					; yes, done
					_LockRelease(LOCK_FTR)
					Return True
				EndIF
			EndIf			
			i += 1
		EndWhile		
	EndIf
	
	; not found
	_LockRelease(LOCK_FTR)
	Return False
EndFunction

Function _FTRUnregisterNetworkLayerForFrameType(NetLink:API:NetworkLayerBase refProtocol, Int frameType)
	; is frametype valid?
	If (!CheckFrameTypeValid(frameType))
		Debug.Trace(Self + ": WARNING - FTR: UnregisterNetworkLayerForFrameType with invalid FrameType (" + frameType + ") ignored.")
		Return
	EndIf

	; acquire read/write lock on ft registry
	If (!_LockAcquire(LOCK_FTR, lockReads = true, lockWrites = true))
		Debug.Trace(Self + ": ERROR - FTR: UnregisterNetworkLayerForFrameType failed to acquire LOCK_FTR for read/write. De-Registration failed.")
		Return
	EndIf				
			
	; find frametype in registry
	Int frameTypeIndex = _FTRegistry.FindStruct("FrameType", frameType)
	If (frameTypeIndex < 0)
		; not found
		Debug.Trace(Self + ": WARNING - FTR: UnregisterNetworkLayerForFrameType for unregistered FrameType (" + frameType + ") ignored.")
		_LockRelease(LOCK_FTR)
		Return
	EndIf
	
	; found frametype		
	FrameTypeRegistration ftReg = _FTRegistry[frameTypeIndex]
	NetLink:API:NetworkLayerBase[] nlRefs = ftReg.NetworkLayerRefs
	String[] nlSNames = ftReg.NetworkLayerScriptnames
	
	; Find registered protocol
	;Int protoIndex = nlRefs.Find(refProtocol)		
	Int protoRefIndex = _FTRFindProtocolInFrameTypeReg(ftReg, refProtocol)	; uses reference AND scriptname for matching
	If (protoRefIndex < 0)
		Debug.Trace(Self + ": WARNING - FTR: UnregisterNetworkLayerForFrameType for unregistered protocol (" + refProtocol + ") ignored.")
		_LockRelease(LOCK_FTR)
		Return
	Else
		; unregister the protocol
		nlRefs.Remove(protoRefIndex)		; protocol reference
		nlSNames.Remove(protoRefIndex)		; protocol scriptname
	EndIf
	
	; no more protocols registered for frametype ?
	If (nlRefs.Length == 0)
		; remove frametype registry entry
		_FTRegistry.Remove(frameTypeIndex)
	EndIf		
	
	_LockRelease(LOCK_FTR)
EndFunction

Function _FTRUnregisterNetworkLayerForAllFrameTypes(NetLink:API:NetworkLayerBase refProtocol)
	; acquire read/write lock on ft registry
	If (!_LockAcquire(LOCK_FTR, lockReads = true, lockWrites = true))
		Debug.Trace(Self + ": ERROR - FTR: UnregisterNetworkLayerForAllFrameTypes failed to acquire LOCK_FTR for read/write. De-Registration failed.")
		Return
	EndIf			
	
	Int i = _FTRegistry.Length - 1
	Int u = 0
	While (i > -1)
		FrameTypeRegistration ftReg = _FTRegistry[i]
		Int protoIndex = ftReg.NetworkLayerRefs.Find(refProtocol)
		If (protoIndex > -1)
			ftReg.NetworkLayerRefs.Remove(protoIndex)
			ftReg.NetworkLayerScriptnames.Remove(protoIndex)
			u += 1
		EndIf
		; last protocol for frametype removed?
		If (ftReg.NetworkLayerRefs.Length == 0)
			; yes, remove frametype
			ftReg.NetworkLayerRefs = none
			; ensure scriptnames are cleared as well
			ftReg.NetworkLayerScriptnames.Clear()
			ftReg.NetworkLayerScriptnames = none
			_FTRegistry.Remove(i)
		EndIf
		i -= 1
	EndWhile
	If (u > 0)
		Debug.Trace(Self + ": INFO - FTR: Unregistered (" + u + ") FrameTypes for NetworkLayer (" + refProtocol + ").")
	EndIf
	
	_LockRelease(LOCK_FTR)
EndFunction

Function _FTRUnregisterAllNetworkLayersForFrameType(Int frameType)
	; acquire read/write lock on ft registry
	If (!_LockAcquire(LOCK_FTR, lockReads = true, lockWrites = true))
		Debug.Trace(Self + ": ERROR - FTR: UnregisterAllNetworkLayerForFrameType failed to acquire LOCK_FTR for read/write. Registration failed.")
		Return
	EndIf

	Int u = 0
	Int frameTypeIndex = _FTRegistry.FindStruct("FrameType", frameType)
	If (frameTypeIndex > -1)
		FrameTypeRegistration ftReg = _FTRegistry[frameTypeIndex]
		u = ftReg.NetworkLayerRefs.Length
		ftReg.NetworkLayerRefs.Clear()
		ftReg.NetworkLayerScriptnames.Clear()
		ftReg.NetworkLayerRefs = none
		ftReg.NetworkLayerScriptnames = none
		_FTRegistry.Remove(frameTypeIndex)
		Debug.Trace(Self + ": INFO - FTR unregistered (" + u + ") NetworkLayers for FrameType (" + frameType + ").")
	EndIf
	
	_LockRelease(LOCK_FTR)
EndFunction

Function _FTRUnregisterAll()
	; acquire read/write lock on ft registry
	If (_FTRegistry.Length != 0)
		If (!_LockAcquire(LOCK_FTR, lockReads = true, lockWrites = true))
			Debug.Trace(Self + ": ERROR - FTR: UnregisterAll failed to acquire LOCK_FTR for read/write. Registration failed.")
			Return
		EndIf
	
		; While frame type registry is not empty
		Int ftRegLen = _FTRegistry.Length
		Int nlRemoved = 0;
		While (ftRegLen > 0)
			; clear first frametype in registry
			FrameTypeRegistration ftReg = _FTRegistry[0]
			If (ftReg != none && ftReg.NetworkLayerRefs != none)
				nlRemoved += ftReg.NetworkLayerRefs.Length
				ftReg.NetworkLayerRefs.Clear()
				ftReg.NetworkLayerScriptnames.Clear()
				ftReg.NetworkLayerRefs = none
				ftReg.NetworkLayerScriptnames = none
			EndIf
			; remove first frametype from registry
			_FTRegistry.Remove(0)
			ftRegLen = _FTRegistry.Length
		EndWhile
		Debug.Trace(Self + ": INFO - FTR unregistered (" + nlRemoved + ") NetworkLayers for (" + ftRegLen + ") FrameTypes.")
		
		_LockRelease(LOCK_FTR)
	EndIf
EndFunction

Int Function _FTRDeliverFrameToNetworkLayers(NetLinkFrame frame)
	; get write only lock, so others can't write while we read
	If (!_LockAcquire(LOCK_FTR, lockReads = false, lockWrites = true))
		Debug.Trace(Self + ": ERROR - FTR: DeliverFrameToNetworkLayers failed to acquire LOCK_FTR for write only. Frame discarded.")
		Return ERROR_LOCK_ACQFAIL
	EndIf
	
	; find frametype in registry
	Int frameTypeIndex = _FTRegistry.FindStruct("FrameType", frame.FrameType)
	If (frameTypeIndex == -1)			
		; frame type is not registered, deliver to 0 protocols
		_LockRelease(LOCK_FTR)
		Return 0
		
	Else					
		; get registered protocols for frametype
		NetLink:API:NetworkLayerBase[] ftProtocols = _FTRegistry[frameTypeIndex].NetworkLayerRefs						

		; any protocols registered for frameType?
		If (ftProtocols.Length == 0)
			; no, frametype delivered to 0 protocols
			_LockRelease(LOCK_FTR)
			Return 0
		EndIf

		; create OnLinkReceive invoke parameters
		Var[] invokeParams = new Var[2]
		invokeParams[0] = Self
		invokeParams[1] = frame				
		
		; deliver frame to registered protocols
		Int rxCount = NotifyReferenceScriptsEx(ftProtocols as ObjectReference[], _FTRegistry[frameTypeIndex].NetworkLayerScriptnames, "OnLinkReceive", invokeParams)		
		If (rxCount < 0)
			Debug.Trace(Self + ": ERROR - FTR: Acceleration failure (" + rxCount + ").")
			_LockRelease(LOCK_FTR)
			Return ERROR_LNK_FTREGACCEL
		Else
			_LockRelease(LOCK_FTR)
			Return rxCount
		EndIf
		
		; ### DEPRECATED: old non-accelerated event delivery method ###
		; working version not sup accelerated yet:
		;_LockRelease(LOCK_FTR)
		;Return _NotifyReferenceScriptsEx(ftProtocols as ObjectReference[], _FTRegistry[frameTypeIndex].NetworkLayerScriptnames, "OnLinkReceive", invokeParams)
	EndIf
EndFunction





;/
##################################################
# Section: Waiting for SUP accelerator functions #
##################################################
/;
Int Function _NotifyReferenceScriptsEx(ObjectReference[] references, String[] scriptNames, String callbackName, Var[] callbackArgs)
	; validate parameters
	If (references.Length == 0)
		Return 0 ; no references to notify
	EndIf
	If (references.Length != scriptNames.Length)
		; TODO: check error code
		Debug.Trace(Self + ": ERROR - FTR/NRSEx: Length of scriptNames array does not match length of references array. Rejected.")
		Return -90101	; 901 debug code
	EndIf
	If (callbackName == "")
		Debug.Trace(Self + ": ERROR - FTR/NRSEx: Argument callbackName not specified. Rejected.")
		Return -90102	; 901 debug code
	EndIf	
	
	If (callbackArgs == none)
		Debug.Trace(Self + ": ERROR - FTR/NRSEx: callbackArgs is none. Rejected.")
		Return -90103	; 901 debug code
	EndIf
	
	; crap to support passing var array through papyrus CallFunctionNoWait, meh :|
	NRSE_InvokeArgs argStruct = new NRSE_InvokeArgs		; CallFunctionNoWait can't pass Var[] parameters at all, must stuff into intermediate struct instead
	argStruct.callbackArgs = callbackArgs				; Parameters Var[] goes into struct (needs compiler patch to compile)
	Var[] invokeParams = new Var[1]						; dedicated invoke parameters Var[] for CallFunctionNoWait
	invokeParams[0] = argStruct							; intermediate struct goes into invoke parameters array - it just works
	
	Int r = 0
	Int c = 0
	While (r < references.Length)
		; we want specific script by name from network layer reference
		ScriptObject target = references[r].CastAs(scriptNames[r])
		If (target == none)
			Debug.Trace(Self + ": WARNING - FTR/NRSEx failed: Unable to cast reference (" + references[r] + ") as scriptname (" + scriptNames[r] + "). Reference skipped.")
		Else
			;Debug.Trace(Self + ": DEBUG - FTR/NRSEx invoking " + target + ".CallFunctionNoWait(" + callbackName + ", " + invokeParams + ")...")
			target.CallFunctionNoWait(callbackName, invokeParams)
			c += 1
		EndIf
		r += 1
	EndWhile
	
	; return count of notified stations
	Return c
EndFunction

; more crap to support PAPYRUS VERSION of FTR delivery to network layers
Struct NRSE_InvokeArgs
	Var[] callbackArgs
EndStruct









;/
###################################
# Section: Thread Lock Management #
###################################
/;

; lock type definitions
Int Property LOCK_FTR = 0 AutoReadonly Hidden			; frametype registry lock


; locks
LockInfo[] _Locks = none

Struct LockInfo
	Bool LockRead
	Bool LockWrite
EndStruct

; hardcoded config
Int LOCKS_TIMEOUT = 15 Const 	; cycles
Float LOCKS_SLEEP = 0.01 Const 	; seconds

; TLM halting flag
Bool _LocksHalting = false		; halt flag prevents issuing new locks

Function _LocksSetup()
	_Locks = new LockInfo[1]
	_Locks[LOCK_FTR] = new LockInfo
	_LocksHalting = false
	Debug.Trace(Self + ": DEBUG - TLM: Subsystem started.")
EndFunction

Function _LocksHalt()
	_LocksHalting = true
	Debug.Trace(Self + ": DEBUG - TLM: Halting; Waiting for (" + _Locks.Length + ") locks to release...")
	Int limit = LOCKS_TIMEOUT
	While (_Locks != none && _Locks.Length > 0 && limit > 0)
		Utility.Wait(LOCKS_SLEEP)
		limit -= 1
	EndWhile
EndFunction

Function _LocksClear()	
	_LocksHalting = true
	Int lockCount = 0
	If (_Locks != none)
		lockCount = _Locks.Length
		_Locks.Clear()
		_Locks = none	
	EndIf
	Debug.Trace(Self + ": DEBUG - TLM Subsystem stopped, (" + lockCount + ") locks cleared.")
EndFunction

Function _LockRelease(Int lockType)
	If (_Locks.Length == 0)
		Return ; no locks in list
	EndIf

	LockInfo lock = _Locks[lockType]
	If (!lock)
		Debug.Trace(Self + ": WARNING - TLM: LockRelease(" + lockType + ") failed: No such lock type.")
		Return
	EndIf
	
	; release
	lock.LockRead = false
	lock.LockWrite = false
	
	If (_LocksHalting == true)
		; clear up on halt
		_Locks.Remove(lockType)
	EndIf
EndFunction

Bool Function _LockAcquire(Int lockType, Bool lockReads, Bool lockWrites)
	; TLM halting?
	If (_LocksHalting)
		Debug.Trace(Self + ": ERROR - TLM: LockAcquire(" + lockType + ", " + lockReads + ", " + lockWrites + ") failed: Subsystem halting.")
		Return False
	EndIf	
	
	; any locks defined?
	If (_Locks.Length == 0)
		Debug.Trace(Self + ": ERROR - TLM: LockAcquire(" + lockType + ", " + lockReads + ", " + lockWrites + ") failed: No locks defined.")
		Return False ; no locks in list
	EndIf
	
	; verify requested lock type exists
	LockInfo lock = _Locks[lockType]
	If (!lock)
		Debug.Trace(Self + ": ERROR - TLM: LockAcquire(" + lockType + ", " + lockReads + ", " + lockWrites + ") failed: No such lock type.")
		Return False
	EndIf

	; maximum number of cycles to wait for lock release
	Int limit = LOCKS_TIMEOUT	
	
	;  acquire requested locks
	If (lockReads && !lockWrites)				; prevent foreign reads only, probably useless
		; wait for lock to be available
		While (limit > 0 && lock.LockRead)
			Utility.Wait(LOCKS_SLEEP)
			limit -= 1
		EndWhile		
		
		; lock free?
		If (!lock.LockRead)
			; yes, acquire
			lock.LockRead = true
			; lock acquired
			Return True				
		EndIf
		
		Debug.Trace(Self + ": ERROR - TLM: LockAcquire(" + lockType + ", " + lockReads + ", " + lockWrites + ") failed with timeout.")
		Return False					
		
	ElseIf (lockReads && lockWrites)			; prevent foreign reads and writes
	
		; wait for locks to be available
		While (limit > 0 && (lock.LockRead || lock.LockWrite))
			Utility.Wait(LOCKS_SLEEP)
			limit -= 1		
		EndWhile
		
		; locks free?
		If (!lock.LockRead && !lock.LockWrite)
			; yes, acquire
			lock.LockWrite = true
			lock.LockRead = true
			; lock acquired
			Return True				
		EndIf
		
		; wasn't free
		Debug.Trace(Self + ": ERROR - TLM: LockAcquire(" + lockType + ", " + lockReads + ", " + lockWrites + ") failed with timeout.")
		Return False					
			
	ElseIf (!lockReads && lockWrites)			; prevent foreign writes
	
		; wait for lock to be available
		While (limit > 0 && lock.LockWrite)
			Utility.Wait(LOCKS_SLEEP)
			limit -= 1
		EndWhile		
		
		; lock free?
		If (!lock.LockWrite)
			; yes, acquire
			lock.LockWrite = true
			; lock acquired
			Return True				
		EndIf
		
		Debug.Trace(Self + ": ERROR - TLM: LockAcquire(" + lockType + ", " + lockReads + ", " + lockWrites + ") failed with timeout.")
		Return False					
	
	ElseIf  (!lockReads && !lockWrites)			; prevent nothing, just wait for lock to be available
		; wait for locks to be available
		While (limit > 0 && (lock.LockWrite || lock.LockRead))
			Utility.Wait(LOCKS_SLEEP)
			limit -= 1
		EndWhile		

		; locks free?
		If (lock.LockWrite || lock.LockRead)
			Debug.Trace(Self + ": ERROR - TLM: LockAcquire(" + lockType + ", " + lockReads + ", " + lockWrites + ") failed with timeout.")
			Return False
		EndIf

		; was not locked, or lock released
		Return True
	EndIf	
EndFunction