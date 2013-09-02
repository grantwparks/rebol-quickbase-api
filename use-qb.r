REBOL [
	Title: "Sample Quickbase client app"
	File: %use-qb.r
	Purpose: "Using the qb.r Quickbase module"
	Author: "Grant Wesley Parks"
	Home: https://github.com/grantwparks
	Date: 31-Aug-2013
	Version: 0.0.1
]

print ["Using "]
myQb: make qb [appid: "appdbid" signin https://app-domain.quickbase.com useremail "password"]
foreach [id type name] myQb/pages [] [
	; 2 types I know of Text and Home Page - Home Page is a quickbase thing and not our source
	if equal? type "Text" [
		write join %tmp/ name myQb/pages id
	]
]