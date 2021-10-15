"
SeekerQuery
Its an object that represents a query against data. Follows stardard terminology while also providing a language integrated API to create expressions.
Seeker Queries are only processed when issuing the results.

Example:

|myQuery|
myQuery := SeekerQuery from: DataSource where: [:dataSourceRow| dataSetRow id = 100] select: [:dataSourceRow| dataSetRow].

Will create a query object with a datasource, a row matching predicate 'where', and a projection function 'select'.

The query will not execute unless an operation is specified:
|result|

""Operation: #asTable""
result := myQuery asTable. 
Will iterate through the rows of the datasource while storing the matching rows projectiong in a resulting table.

""Operation: #count""
result := myQuery count. 
Will iteration though the rows of the datasource while counting the matching rows.

DataSource are objects that represent a table. They must reply to currentRow message, and provide an iteration logic.

Rows:
Rows can be of any type of object.

AnoymousType integration.
Queries experessions are compatible with AnonymousTypes. Providing freedom to express the result types while keeping a standard syntax.

"
Class {
	#name : #Query,
	#superclass : #SkIterableDataTableBase,
	#instVars : [
		'fromDataSource',
		'resultBuffer',
		'result',
		'onQueryRowMatch',
		'operationType',
		'disableOptimization',
		'timeIt',
		'customPreparationBlock',
		'selectionBlock',
		'projectionBlock'
	],
	#classInstVars : [
		'identityProjection',
		'alwaysMatch'
	],
	#category : #'Seeker-QueryData'
}

{ #category : #accessing }
Query class >> alwaysMatch [

	alwaysMatch ifNil: [ alwaysMatch := [ :anArg | true ] ].
	^ alwaysMatch
]

{ #category : #'instance creation' }
Query class >> from: aDataSource [

	"Creates a query that can be issued over aDataSource. aDataSource is an object whose class inherits from SkIterableDataTableBase"

	^ self
		  from: aDataSource
		  select: self alwaysMatch
		  collect: self identityProjection
]

{ #category : #'instance creation' }
Query class >> from: aDataSource select: aRowPredicateBlock collect: aProjectionBlock [

	"A more 'Pharo-like' version of the classic From Select Collect style"

	^ self
		  from: aDataSource
		  where: aRowPredicateBlock
		  select: aProjectionBlock
]

{ #category : #'instance creation' }
Query class >> from: aSeekerDataSet where: aPredicateBlock select: aProjectionBlock [

	| q |
	q := self new.
	q disableOptimization: true.
	q selectBlock: aProjectionBlock.
	q whereBlock: aPredicateBlock.
	q disableOptimization: false.
	q fromDataSource: aSeekerDataSet.
	^ q
]

{ #category : #accessing }
Query class >> identityProjection [

	identityProjection ifNil: [ identityProjection := [ :anArg | anArg ] ].
	^ identityProjection
]

{ #category : #'as yet unclassified' }
Query >> advanceToNextRow [

	"advances to the next row. returns false if the end of the table (there are no more rows) was reached before trying to advance."

	^fromDataSource advanceToNextRow 
]

{ #category : #converting }
Query >> asCollection [
  ^ self asTableForTimeTravel rows
]

{ #category : #converting }
Query >> asCsvFile [

	| aFileReference |
	aFileReference := Smalltalk imageDirectory / 'tempCvsResult.csv'.
	operationType := #asCsv.
	aFileReference writeStreamDo: [ :aStream | 
		| firstResult |
		firstResult := true.
		resultBuffer := ''.

		self onQueryRowMatch: [ 
			| row |
			row := self currentRow.
			firstResult ifTrue: [ 
				firstResult := false.
				row headersAsCsvPrintOn: aStream ].
			row asCsvPrintOn: aStream ].
		self resolve ].
	result := aFileReference.

	^ self result
]

{ #category : #converting }
Query >> asCsvInClipboard [

	| str |
	operationType := #asCsv.
	str := String streamContents: [ :aStream | 
		       | firstResult |
		       firstResult := true.
		       resultBuffer := ''.

		       self onQueryRowMatch: [ 
			       | transformedRow |
			       transformedRow := self currentRow.
			       firstResult ifTrue: [ 
				       firstResult := false.
				       transformedRow headersAsCsvPrintOn: aStream.
				       aStream nextPutAll: String cr ].
			       transformedRow asCsvPrintOn: aStream.
			       aStream nextPutAll: String cr ].
		       self resolve ].
	result := str.
	Clipboard clipboardText: result.

	^ self result
]

{ #category : #converting }
Query >> asQueryWithMemory [

	| q |
	q := QueryWithMemory
		     from: fromDataSource
		     select: selectionBlock
		     collect: projectionBlock.
	q excluding: self excluding.
	^ q
]

{ #category : #operation }
Query >> asTTQResult [

	"Triggers the evaluation of the query, creating a collection of ResultItems"


	| tracer createResultItem |
	tracer := self findTracer.
	createResultItem := [ :row | 
	                       | t |
	                       t := ResultItem new.
	                       t value: row.
	                       t timeIndex: tracer bytecodeIndex ].
	operationType := #asCollection.
	resultBuffer := OrderedCollection new.

	self onQueryRowMatch: [ 
		resultBuffer add: (createResultItem value: self currentRow) ].

	self resolve.

	^ self result
]

{ #category : #operation }
Query >> asTable [

	"Triggers the solution of the query"

	"a result operation"

	operationType := #asTable.
	resultBuffer := OrderedCollection new.

	self onQueryRowMatch: [ resultBuffer add: self currentRow ].
	self resolve.

	^ self result
]

{ #category : #operation }
Query >> asTableForTimeTravel [

	"Triggers the solution of the query"

	"a result operation"

	| tracer makeItForTimeTravel |
	tracer := self findTracer.
	makeItForTimeTravel := [ :row | 
	                       | t |
	                       t := AnonymousTypeForTimeTravel
		                            newWith: {  }
		                            forTracer: tracer.
	                       t mergeWith: row.
	                       t privateExecutedBytecode: row bytecodeIndex ].
	operationType := #asTable.
	resultBuffer := OrderedCollection new.

	self onQueryRowMatch: [ 
		resultBuffer add: (makeItForTimeTravel value: self currentRow) ].

	self resolve.

	^ self result
]

{ #category : #enumerating }
Query >> collect: aBlock [

	"A lazy version of collect: of Pharo collections, applicable to queries"

	| q composedProjection selfisIdentity blockIsIdentity |
	selfisIdentity := selectionBlock == self class identityProjection.
	blockIsIdentity := aBlock == self class identityProjection.
	composedProjection := [ true ] switchCase: { 
			                      ([ selfisIdentity and: blockIsIdentity ]
			                       -> [ projectionBlock ]).
			                      ([ selfisIdentity and: blockIsIdentity not ]
			                       -> [ aBlock ]).
			                      ([ selfisIdentity not and: blockIsIdentity ]
			                       -> [ projectionBlock ]).
			                      ([ 
			                       selfisIdentity not and: blockIsIdentity not ]
			                       -> [ 
			                       [ :anArg1 | 
			                       aBlock cull: (projectionBlock cull: anArg1) ] ]) }.
	q := self class
		     from: self fromDataSource
		     select: selectionBlock
		     collect: composedProjection.

	^ q
]

{ #category : #accessing }
Query >> columnLabels [
	^result columnLabels 
]

{ #category : #operation }
Query >> count [

	"a result operation"

	operationType := #count.
	resultBuffer := 0.
	self onQueryRowMatch: [ resultBuffer := resultBuffer + 1 ].
	self resolve.
	^ self result
]

{ #category : #'as yet unclassified' }
Query >> currentDataSourceRow [

	"Part of the iterable data set interface. Used for queries nesting. returns the rowgetter result"

	^ fromDataSource currentRow
]

{ #category : #'as yet unclassified' }
Query >> currentRow [

	"Part of the iterable data set interface. Used for queries nesting. returns the rowgetter result"

	^ projectionBlock cull: fromDataSource currentRow
]

{ #category : #accessing }
Query >> customPreparationBlock [
	^ self customPreparationBlock 
]

{ #category : #accessing }
Query >> customPreparationBlock: aBlock [
	customPreparationBlock 
]

{ #category : #'as yet unclassified' }
Query >> dataSourceIsTracedExecution [
	^fromDataSource dataSourceIsTracedExecution 
]

{ #category : #accessing }
Query >> disableOptimization [

	^ disableOptimization
]

{ #category : #accessing }
Query >> disableOptimization: anObject [

	disableOptimization := anObject
]

{ #category : #enumerating }
Query >> do: aBlock [

	"Performs aBlock on the underlying condition matching rows. To simulate that, the onQueryRowMatch mechanism is used."

	| originalOnQueryRowMatch |
	originalOnQueryRowMatch := onQueryRowMatch. "we don't perform the original onQueryRowMatch because this is not a resolve situation"
	"Ablock is a method that takes orgument (the iteration row). Hoever, OnQueryRow match is a block that receives no arguments. (might change this in the future)"
	onQueryRowMatch := [ aBlock value: self currentRow ].
	"The idea here is to simulate that we will iterate over the datasources filtered items. So aBlock will only be executed for the items that matchnthe where clause"
	customPreparationBlock value."Beware here"
	[ fromDataSource do: [ :row | self doQueryOnRow: row ] ] ensure: [ 
		onQueryRowMatch := originalOnQueryRowMatch ]
]

{ #category : #'as yet unclassified' }
Query >> doQueryOnRow: aRow [

	"performs the query in the specified row"

	selectionBlock numArgs = 0
		ifTrue: [ selectionBlock value ifTrue: onQueryRowMatch ]
		ifFalse: [ (selectionBlock value: aRow) ifTrue: onQueryRowMatch ]
]

{ #category : #'as yet unclassified' }
Query >> doQueryRow [

	"performs the query in the current row of the input"

	selectionBlock numArgs = 0
		ifTrue: [ selectionBlock value ifTrue: onQueryRowMatch ]
		ifFalse: [ 
			| row |
			row := self currentDataSourceRow.
			(selectionBlock value: row) ifTrue: onQueryRowMatch ]
]

{ #category : #'as yet unclassified' }
Query >> endOfTableReached [

	"returns true if the table has no more rows (and advanceToNextRow will return false)"

	^ fromDataSource endOfTableReached
]

{ #category : #'as yet unclassified' }
Query >> ensureReceiverAliases [

	self selfAndChildrenDo: [ :t | 
		(t class inheritsFromOrSameAs: SkExecutionVirtualTable) ifTrue: [ 
			| protectedColumns |
			protectedColumns := Set new.
			protectedColumns addAll: t protectedColumns.
			protectedColumns add: #receiverAlias.
			t protectedColumns: protectedColumns ] ]
]

{ #category : #accessing }
Query >> excluding [

	^ fromDataSource excluding
]

{ #category : #accessing }
Query >> excluding: aCollection [
	
	fromDataSource excluding: aCollection 
]

{ #category : #'as yet unclassified' }
Query >> findTracer [

	^ fromDataSource findTracer
]

{ #category : #operations }
Query >> first [

	"finds the first matching row in the table and returns it. The table will continue to be iterated until it finishes"

	| found |
	operationType := #first.
	found := false.
	resultBuffer := nil.
	self onQueryRowMatch: [ 
		found ifFalse: [ 
			found := true.
			resultBuffer := self currentRow ] ].
	self resolve.
	^ self result
]

{ #category : #'as yet unclassified' }
Query >> fromDataSource [
	^fromDataSource
]

{ #category : #'as yet unclassified' }
Query >> fromDataSource: anObject [

	fromDataSource := anObject.
	self optimizeRowAcquisitionForFields: self getRelevantFields
]

{ #category : #'as yet unclassified' }
Query >> getRelevantFields [

	"Returns a collection of the fields (when using anonymous type rows) that are used in the selectBlock or whereBlock. it will search recursivelly in every nested block"

	| selectFields whereFields fromRelevantFields mergedSet |
	selectFields := SkAnonymousTypeHelpers 
		                listOfFieldsInAnonymousTypeBlock: projectionBlock.
	whereFields := SkAnonymousTypeHelpers 
		               listOfFieldsInAnonymousTypeBlock: selectionBlock.
	fromRelevantFields := fromDataSource
		                      ifNotNil: [ fromDataSource getRelevantFields ]
		                      ifNil: [ {  } ].
	mergedSet := Set new.
	mergedSet addAll: selectFields.
	mergedSet addAll: whereFields.
	mergedSet addAll: fromRelevantFields.
	^ mergedSet asOrderedCollection
]

{ #category : #initialization }
Query >> initialize [

	operationType := #defaultOperation.
	disableOptimization := false.
	timeIt := #dontTimeIt.
	customPreparationBlock := [  ].
	super initialize
]

{ #category : #'as yet unclassified' }
Query >> isCurrentRowAMatch [

	"returns true if the current row matches the query predicate without triggering the onQueryRowMatch handler"

	selectionBlock numArgs = 0
		ifTrue: [ selectionBlock value ifTrue: [ ^ true ] ]
		ifFalse: [ 
			| row |
			row := self currentDataSourceRow.
			(selectionBlock value: row) ifTrue: [ ^ true ] ].
	^ false
]

{ #category : #'as yet unclassified' }
Query >> isRowAMatch: aRow [

	"returns true if the given row matches the query predicate without triggering the onQueryRowMatch handler"

	selectionBlock numArgs = 0
		ifTrue: [ selectionBlock value ifTrue: [ ^ true ] ]
		ifFalse: [ 
			(selectionBlock value: aRow) ifTrue: [ ^ true ] ].
	^ false
]

{ #category : #accessing }
Query >> onQueryRowMatch [

	^ onQueryRowMatch
]

{ #category : #accessing }
Query >> onQueryRowMatch: anObject [

	onQueryRowMatch := anObject
]

{ #category : #'as yet unclassified' }
Query >> optimizeRowAcquisitionForFields: aCollection [

	disableOptimization ifTrue: [ ^ self ].
	fromDataSource ifNotNil: [ 
		fromDataSource optimizeRowAcquisitionForFields: aCollection ]
]

{ #category : #accessing }
Query >> processResult [

	result := [ operationType ] switchCase: { 
			          (#asTable
			           -> [ 
			           SkDataTable newForAnonymousTypeObjects: resultBuffer ]).
			          (#asCollection -> [ resultBuffer ]).
			          (#count -> [ resultBuffer ]).
			          (#first -> [ resultBuffer ]).
			          (#asCsv -> [ resultBuffer ]).
			          (#defaultCase -> [ #operationCompleted ]) }
]

{ #category : #'as yet unclassified' }
Query >> resetTableTraversing [

	"Puts the table traversing cursor 'before the first row'. one advanceToNextRow is necessary to enter the first row. A reseted table should reply currentRow nil always."

	^ fromDataSource resetTableTraversing
]

{ #category : #navigating }
Query >> resolve [

	| runIt |
	runIt := timeIt = #timeItDetailed
		         ifTrue: [ 
			         [ 
			         | startingTime originalProjectionBlock |
			         originalProjectionBlock := projectionBlock.
			         startingTime := Time now.
			         customPreparationBlock value. "Beware here"
			         self optimizeRowAcquisitionForFields:
				         self getRelevantFields.
			         "TODO: modify the select so it adds the time rows. Need to track time since starting time and row time (so I need the time whene every row query started)"
			         projectionBlock := projectionBlock numArgs = 0
				                        ifTrue: [ [  ] ]
				                        ifFalse: [ [  ] ].
			         fromDataSource do: [ :row | self doQueryOnRow: row ].
			         self processResult ] ]
		         ifFalse: [ 
			         [ 
			         customPreparationBlock value. "Beware here"
			         self optimizeRowAcquisitionForFields:
				         self getRelevantFields.
			         fromDataSource do: [ :row | self doQueryOnRow: row ].
			         self processResult ] ].
	(timeIt = #timeIt or: [ timeIt = #timeItDetailed ])
		ifTrue: [ runIt timeToRun inspect ]
		ifFalse: runIt.
	^ self
]

{ #category : #accessing }
Query >> result [

^ result
]

{ #category : #accessing }
Query >> result: anObject [

	result := anObject
]

{ #category : #enumerating }
Query >> select: aBlock [

	"A lazy version of select: of Pharo collections, applicable to queries"

	"Creates a new query with a composition of row matching condition"

	| q composedWhereBlock selfTrue aBlockTrue |
	selfTrue := selectionBlock == self class alwaysMatch.
	aBlockTrue := aBlock == self class alwaysMatch.
	"If an always-true predicate is involved, don't include it in the new query"
	composedWhereBlock := [ true ] switchCase: { 
			                      ([ selfTrue and: aBlockTrue ]
			                       -> [ selectionBlock ]).
			                      ([ selfTrue and: aBlockTrue not ]
			                       -> [ aBlock ]).
			                      ([ selfTrue not and: aBlockTrue ]
			                       -> [ selectionBlock ]).
			                      ([ selfTrue not and: aBlockTrue not ] -> [ 
			                       [ :anArg1 | 
			                       (selectionBlock value: anArg1) and: [ 
				                       aBlock value: anArg1 ] ] ]) }.
	q := self class
		     from: self fromDataSource
		     select: composedWhereBlock
		     collect: projectionBlock.

	^ q
]

{ #category : #'as yet unclassified' }
Query >> selectBlock [
	^projectionBlock 
]

{ #category : #'as yet unclassified' }
Query >> selectBlock: anObject [

	projectionBlock := anObject = #*
		               ifTrue: [ Query identityProjection ]
		               ifFalse: [ anObject ].
	self optimizeRowAcquisitionForFields: self getRelevantFields
]

{ #category : #enumerating }
Query >> selfAndChildrenDo: aBlock [
	aBlock value: self.
	fromDataSource ifNotNil: [ fromDataSource selfAndChildrenDo: aBlock ]
]

{ #category : #accessing }
Query >> timeIt [

	timeIt := #timeIt.
	^ self
]

{ #category : #accessing }
Query >> timeItDetailed [
	timeIt := #timeItDetailed.
	^ self
]

{ #category : #'as yet unclassified' }
Query >> whereBlock [

	^ selectionBlock
]

{ #category : #'as yet unclassified' }
Query >> whereBlock: anObject [

	selectionBlock := anObject = #*
		              ifTrue: [ self class alwaysMatch ]
		              ifFalse: [ anObject ].
	self optimizeRowAcquisitionForFields: self getRelevantFields
]
