REBOL [
	Title: "Quickbase RESTy server"
	File: %qb.r
	Purpose: "Handle REST like Quickbase queries"
	Author: "Grant Wesley Parks"
	Home: https://github.com/grantwparks
	Date: 17-May-2013
	Version: 0.0.1
]

if not value? 'load-xml [ 
	do http://reb4.me/r/altxml.r
]

qb: context [
	host: none
	ticket: ""
	apptoken: [ either select self 'token [join "&apptoken=" self/token] [""] ]
	response: 
	errcode:

	get-query: func [
		request [block!]
		/local get-url
	] [
		if error? set/any 'err try [

			get-url: to-url join host rejoin [request do apptoken "&ticket=" self/ticket]
			probe get-url
			if response: read/custom get-url compose/deep [header [Accept: "application/xml" ]] [
				parse response [ thru "<errcode>" copy errcode to "</errcode>" ]
				return response
			]
		] [
			alert join "Unable to " get-url
			probe mold disarm err
		]
	]

	signin: func 
	[ 
		host [url!] 
		email [email!] 
		password [string!]
	] 
	[
		self/host: host
		either parse get-query ["/db/main?act=API_Authenticate&username=" email "&password=" password "&hours=24"] [ thru "<ticket>" copy ticket to "</ticket>" to end ][
			return ticket
		][
			alert join "Unable to get login ticket!" response halt
		]
	]

	query: func 
	[
		{Returns query response}
		'dbid [word!]
		query [string!] 
		clist [string!]
	][
		get-query ["/db/" to-string dbid "?act=API_DoQuery&query=" query "&clist=" clist]
	]

	pages: func 
	[
		{Returns either the list of DB pages or contents of one or more pages.  Pass an empty block to list all pages; pass a page id or block of page ids to get page contents.}
		pages [integer! string! any-block!]
		/local response results id type name pagebody 
	][
		probe pages: to-block	 pages
		results: copy []
		if empty? pages [
			parse get-query ["/db/" self/appid "?act=API_ListDBpages"] 
				[any [thru {<page id="} copy id to {"} thru {type="} copy type to {"} thru {>} copy name to </page> (repend results [id type name])]]
			return results
		]
		foreach page pages [
			if parse get-query ["/db/" self/appid "?act=API_GetDBPage" "&pageid=" page] [thru <pagebody> copy pagebody to </pagebody> to end] [
				append results pagebody
			]
		] 
		return either equal? block! type? pages [results][results/1]
	]

	; dates are in microseconds since Jan 1 1970 so "add 1-Jan-1970 credate / (1000 * 60 * 60 *24)" but need to round the division before adding
	getschema: func 
	[ 
		{Returns an app schema as a block of tbids.  Returns a table schema as a block of ["id" "label"...]}
		/table 'dbid [word!]
		/local pagebody temp results fid label formula appname appid tbname tbid
	][
		either word? dbid [
			
			; parse gblXml: get-query ["/db/" to-string dbid "?act=API_GetSchema"]
			; 	[any [thru {<field id="} copy fid to {"} thru <label> copy label to</label> 
			; 			[none | thru <formula> copy formula to </formula>] to </field> 
			; 			(print [fid label formula] append results reduce [fid label formula])]]

			results: reduce [
				'raw load-xml get-query ["/db/" to-string dbid "?act=API_GetSchema"]
				'fields copy []
			]
			foreach [f field] results/raw/<qdbapi>/<table>/<fields> [ 
				repend results/fields [field/#id field/<label>]
			]
		] [
			results: copy []
			api: get-query ["/db/" self/appid "?act=API_GetSchema"]
			parse api
				[thru <name> copy appname to </name> thru <table_id> copy appid to </table_id> (repend results ['id appid 'name appname 'tables []])
					[any [thru {<chdbid name="} copy tbname to {">} thru {">} copy tbid to </chdbid> (repend results/tables [to-word tbid tbname])]]
				to end]	
		]
		return results
	]
]