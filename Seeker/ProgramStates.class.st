Class {
	#name : #ProgramStates,
	#superclass : #SkIterableDataTableBase,
	#instVars : [
		'rowReificationBlock',
		'tracer',
		'justRestarted',
		'optimizedRowReificationBlock',
		'excludedFields',
		'protectedColumns'
	],
	#category : #'Seeker-QueryData'
}

{ #category : #'instance creation' }
ProgramStates class >> newWithTracer: tracer [

	| table csi|
	csi := tracer currentStateInterface.
	table := self new.
	"Always returns the same current state interface object"
	table rowReificationBlock: [ csi ]. 
	table tracer: tracer.
	^ table
]

{ #category : #'as yet unclassified' }
ProgramStates >> advanceToNextRow [

	"advances to the next row. returns false if the end of the table (there are no more rows) was reached before trying to advance."

	justRestarted ifTrue: [ 
		justRestarted := false.
		^ true ].
	^ tracer stepBytecode
]

{ #category : #converting }
ProgramStates >> asTableWithMemory [

	| t |
	t := SkExecutionVirtualTableWithMemory
		     newWithRowReificationBlock: rowReificationBlock
		     forTracer: tracer.
	t excluding: self excluding.
	^ t
]

{ #category : #'as yet unclassified' }
ProgramStates >> currentRow [

	^ rowReificationBlock value
]

{ #category : #'as yet unclassified' }
ProgramStates >> dataSourceIsTracedExecution [

	^ true
]

{ #category : #enumerating }
ProgramStates >> do: aBlock [

	"A specilized version of do:, made specifically to be used with queries"

	| currentTracetime preBytecodeStepHook |
	currentTracetime := tracer bytecodeIndex asExecutedBytecodeTraceTime.
	tracer isMapped ifFalse: [ 
		^ self error:
			  'Time traveling needs to be enabled to execute Trace Queries' ].
	preBytecodeStepHook := [ aBlock value: self currentRow ].
	tracer doAndUpdateSessionAfter: [ 
		"reload the initial state"
		SeekerGlobals instance startQueryingFromBytecodeOne
			ifTrue: [ tracer restartAtBytecodeOne ]
			ifFalse: [ tracer timeTravelToUserStart ].
		"In this implementation, the iteration logic is delegated to the debugger (and happens in stepBytecodeToExecutionEnd). And in each step, a hook is called on the currentRow (current program state)."
		tracer addAstPreStepHook: preBytecodeStepHook.
		[ tracer stepBytecodeToExecutionEnd ] ensure: [ 
			tracer removeAstPreStepHook: preBytecodeStepHook.
			tracer timeTravelToTraceTime: currentTracetime ] ]
]

{ #category : #enumerating }
ProgramStates >> doBackup: aBlock [

	"Dont use this. Just a backed up funciton"

	| currentStepDescriptor |
	currentStepDescriptor := tracer currentStepDescriptor.
	[ super do: aBlock ] ensure: [ 
		tracer restartAndStepToIndex: currentStepDescriptor executionIndex ]
]

{ #category : #'as yet unclassified' }
ProgramStates >> endOfTableReached [

	"returns true if the table has no more rows (and advanceToNextRow will return false)"

	^ tracer isExecutionFinished or: [ tracer isRiskyStep ]
]

{ #category : #accessing }
ProgramStates >> excluding [

	^ excludedFields
]

{ #category : #accessing }
ProgramStates >> excluding: anObject [
	excludedFields := anObject
]

{ #category : #'as yet unclassified' }
ProgramStates >> findTracer [

	tracer isMapped ifFalse: [ self error: 'Time Traveling not enabled' ].
	^ tracer
]

{ #category : #'as yet unclassified' }
ProgramStates >> getRelevantFields [

	^ protectedColumns
]

{ #category : #initialization }
ProgramStates >> initialize [

	excludedFields := {  }.
	protectedColumns := {  }
]

{ #category : #'as yet unclassified' }
ProgramStates >> optimizeRowAcquisitionForFields: aCollection [

	"optimizedRowReificationBlock := SkAnonymousTypeHelpers
		                                filterKeepingFields: aCollection
		                                andExcluding: excludedFields
		                                ofInstantiationBlock:
		                                rowReificationBlock"
]

{ #category : #accessing }
ProgramStates >> protectedColumns [

	^ protectedColumns
]

{ #category : #accessing }
ProgramStates >> protectedColumns: anObject [

	protectedColumns := anObject
]

{ #category : #'as yet unclassified' }
ProgramStates >> resetTableTraversing [

	"Puts the table traversing cursor 'before the first row'. one advanceToNextRow is necessary to enter the first row. getting currentRow of a reseted table has unspecified behavior"

	justRestarted := true.
	tracer restartAtBytecodeOne
]

{ #category : #accessing }
ProgramStates >> rowReificationBlock [

	^ rowReificationBlock
]

{ #category : #accessing }
ProgramStates >> rowReificationBlock: anObject [

	optimizedRowReificationBlock := anObject.
	rowReificationBlock := anObject
]

{ #category : #accessing }
ProgramStates >> tracer [

	^ tracer
]

{ #category : #accessing }
ProgramStates >> tracer: anObject [

	tracer := anObject
]
