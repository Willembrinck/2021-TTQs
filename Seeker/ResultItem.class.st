Class {
	#name : #ResultItem,
	#superclass : #Object,
	#instVars : [
		'timeIndex',
		'value'
	],
	#category : #'Seeker-QueryData'
}

{ #category : #accessing }
ResultItem >> timeIndex [

	^ timeIndex
]

{ #category : #accessing }
ResultItem >> timeIndex: anObject [

	timeIndex := anObject
]

{ #category : #accessing }
ResultItem >> value [

	^ value
]

{ #category : #accessing }
ResultItem >> value: anObject [

	value := anObject
]
