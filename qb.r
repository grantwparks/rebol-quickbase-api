REBOL [
	Title: "Quickbase SQL Client API"
	File: %qb.r
	Purpose: "Provide a SQL like interface to Quickbase HTTP API"
	Author: "Grant Wesley Parks"
	Home: https://github.com/grantwparks
	Date: 10-Oct-2013
	Version: 0.4.0
	History: {
		0.1.0	2nd generation release based on SQL instead of mimicing the QB calls
				It can connect (authenticate) to an app and select from any table (with optional limit)
		0.1.1	Added 	['qb-desc 'qb-describe] function for app and table metadata
		0.1.2 	Will be trying to use this for qb2rebdb
		0.1.3 	Sets the appid that gets passed to qb-connect as a global word that will begin
				to contain everything about that app/db
		0.2.0	Trying CSV on select instead of DoQuery's XML to shrink the data 
				*** changes get-query error checking and fetch
		0.3.0 	dbids become global set words 
				Added qb-alter
				Added qb-update
				both of the above have some hardcoded parts
		0.4.0	Going back to XML response so I can do LIMIT (csv doesn't allow it).  Hopefully making an even simpler
				parsing block just looking at the "<" "/>" and not the tag names 
				(since we know they come back in request order)
	}
	{
		qb is a simple object consisting of properties that might 	
			* have a shared value across all QB apps
			* be overriden with app instance values, through make from the existing
		quickbase is set with a use [][] construct to hide all the local values and the result
		of the 2nd block becomes quickbase.  It's sort of like the JS module pattern.

		The qb functions are set in quickbase's body.  I opted to make the user functions global instead
		of instance functions of the app connection, following RebDB.  In fact, I give 
		total credit for the API design and inspiration to go beyond the Quickbase HTTP
		API to RebDB.
	}
	Needs: [%system.r]
]

unless value? 'load-xml [do http://reb4.me/r/altxml.r]
unless value? 'system.r [do %../lib/system.r]

quickbase: use [
	api-header
	; api-response
	buffer
	fetch
	get-query
	get-schema
	get-db-schema
	dataTypeConversions
	open-object
	reserved-words
	; things
	this
	; all-table-schemas
][
	;	----------------------------------------
	;		Default values
	;	----------------------------------------

	buffer: make block! 4096 	; stores values returned from lookup and select
	; dataRowBlock: make block! 50
	things: make block! 50

	; THIS IS GLOBAL DURING DEV
	all-table-schemas:	make block! 32 * 2 * 2 ; table name / definition, table_id / definition block pairs

	; somehow want to actually set the value of the word checkbox to to-logic! and then code can just do checkbox
	dataTypeConversions: [
		checkbox logic!
		currency money!
		date date!
		dblink 
		duration integer!
		email email!
		file file!
		float decimal!
		multiuserid string!
		percent decimal!
		phone issue!
		recordid integer!
		text string!
		timestamp date!
		url url!
		userid [= TV] integer! foreign key?
	]

	api-header: compose/deep [header [Accept: "application/xml" ]] 

	;	----------------------------------------
	;		Helper functions
	;	----------------------------------------

	qb-fieldify: func[str [string!] search [string!] nc [char!] /local newstr][
		newstr: copy str
		forall search [replace/all newstr first search nc]
		lowercase newstr
	]

	make-date: func [
		epoch [string! integer!]
		/local days days2 time hours minutes minutes2 seconds time2
	][
		days: divide to-integer epoch 86400000
	    days2: make integer! days

	    time: (days - days2) * 24
	    hours: make integer! time
	    minutes: (time - hours) * 60
	    minutes2: make integer! minutes
	    seconds: make integer! (minutes - minutes2) * 60
	    time2: make time! ((((hours * 60) + minutes2) * 60) + seconds)
		return 1-Jan-1970 + days2
	]

	requested-columns: func [columns [string! word! block!] "Columns to select" /local result "final list of columns"] [
		;	ensure columns is a block of valid column names
		either columns = '* [
			; columns: collect [foreach [colname colmetadata] qb-table/columns [keep colname]]
			result: extract qb-table/columns 2
		][
			;column names should be allowed as "Big Quickbase Field Name"
			result: intersect columns: to-block columns qb-table/columns
			columns: difference columns result
			if not empty? columns [print ["missed" columns]]
log-app ["requested columns" columns]
		]
	]

	;	----------------------------------------
	;		Low-level table handling functions
	;	----------------------------------------

	get-query: func [
		request [block!]
		/nohttp
		/local api-call errcode errtext errdetail
	] [
		if error? set/any 'err try [
			if not this/host [to error! "No host specified."]
			insert tail this/hist api-call: rejoin ["/db/" rejoin request this/apptoken "&ticket=" this/ticket]
			log-app ['GET join this/host api-call]

			if nohttp [
				return "<qdbapi><action>API_AddField</action><errcode>0</errcode><errtext>No error</errtext><fid>245</fid><label>operating_in.Fred2</label></qdbapi>"
			]
			
			parse api-response: read/custom to-url join this/host api-call api-header
				[["<?xml" thru <errcode> copy errcode to </errcode> thru <errtext> copy errtext to </errtext> thru <errdetail> copy errdetail to </errdetail>]
				 | [thru <font color=red size=+1> copy errtext to </font> thru <div id="response_errormsg"> copy errdetail to </div>]]
			if errdetail [to-error reform [errcode errtext errdetail]]

			return api-response
		][
			probe err
		]
	]

	open-object: func [
		object [word! path!] "db or table - 'app-dbid | myDb | 'table-dbid | myDb/table-name | db/table-name	; where myDb was set to qb-connect"
	][
		clear buffer: head buffer
		either all [value? object find things object] [
			prin "things " probe things
			qb-table: get object qb-table/accessed: now qb-table/accesses: qb-table/accesses + 1
		][
			remove find things object
			insert things object
			qb-table: set object get-schema object
	] 
	]
	
	get-db-schema: use[accesses][
		; Build structure to hold db info with a 'tables 2 x block 
		none	
	]

	get-schema: use[name label cols][
		cols: make block! 50
		func [
			dbid [word!]
			/local procs _
		][
			clear cols: head cols
			api-response: second load-xml get-query [to-string dbid "?act=API_GetSchema"]

			either api-response/<table>/<fields> [
				; COLUMNS in TABLE
				foreach [key value] api-response/<table>/<fields> [
					cols: insert cols reduce [
						; "key"
						to-word name: qb-fieldify copy label: value/<label> { -().,#:/%} #"_"
						compose/deep [
							id (to-integer value/#id) name (name) label (label) type (to-word value/#field_type)
							choices (any [all [find value <choices> value/<choices>] none])
							formula (if find value <formula> [(to-block value/<formula>)])
						]
		]
	]

				_: api-response/<table>

				make object! [
					accessed: now accesses: 1
					columns: copy head cols
					created: make-date _/<original>/<cre_date>
					default: reduce ['sort_fid to-integer _/<original>/<def_sort_fid> 'sort_order to-integer _/<original>/<def_sort_order>]
					id: to-word _/<original>/<table_id>
					name: to-string _/<name>
					next: reduce [
						'record_id to-integer _/<original>/<next_record_id> 
						'field_id to-integer _/<original>/<next_field_id> 
						'query_id to-integer _/<original>/<next_query_id>
					]
					updated: make-date _/<original>/<mod_date>
					variables: if error? try [copy _/<variables>][copy []]
				]
	][
				; ALL TABLES in APP/DB
				foreach [key value] api-response/<table>/<chdbids> [
					cols: insert cols reduce [
						to-word value/%.txt reduce [to-word find/tail value/#name "_dbid_"]; all-table-schemas/(value/%.txt)]
					]
				]
				make object! [accessed: now accesses: 1 columns: copy head cols]
			]
		]
	]

	rule: use[column-value row-block][
		column-value: none
		row-block: make block! 50 
	[
			any [
				thru <record> [XXX-of-columns-XXX 
					[thru #">" copy column-value to #"<" to newline (row-block: insert row-block column-value column-value: none)] 
					(buffer: insert/only buffer copy row-block: head row-block clear row-block)]
			]
		]
	]

	fetch: func [
		"Fetches all rows of selected column(s)"
		query-columns [block!]
		query-options [string! none!]
		query [string! none!]
	][
		rule/2/3/1: length? query-columns ;this is the number of fields in each row
		parse xml: replace/all get-query 
			[qb-table/id "?act=API_DoQuery&options=" query-options "&clist=" next rejoin map-each itm query-columns[rejoin [#"." select column-meta-data: select qb-table/columns itm 'id]]] 
			{/>} {><} rule
	]

	;	Informational
	;		db-desc			Information about the columns of a table.
	;		db-describe		Information about the columns of a table.
	;		qb-table		Returns the meta-data for the currently open table
	;	Table Management
	;		qb-alter		Add/change columns in a table
	;       qb-connect		
	;	Row Retrieval
	;		qb-select		Returns rows from a table.
	;	Row Management
	;		qb-update		Updates field(s) in a row

	;	----------------------------------------
	;		Informational
	;	----------------------------------------
	
	set [qb-desc qb-describe] func [
		"Returns db (app) or table information"
		'object [word! path!] "db or table - 'app-dbid | myDb | 'table-dbid | myDb/table-name | db/table-name	; where myDb was set to qb-connect"
	][
		open-object object
		return qb-table/columns
	]
	
	set 'qb-table "no open tables"
	
	;	----------------------------------------
	;		Table Management
	;	----------------------------------------
	
	set 'qb-alter use [qrystr already? new-fid][
		qrystr: make string! 50
		func [
			'table [word!]
			columns [block!]
			/local _p choices'
	][
			print "qb-alter" ?? table ?? columns
			open-object table ; need to be able to clear cache or make it optional
			clear qrystr
			foreach [label attrs] columns [
				unless all [already?: select qb-table/columns to-word qb-fieldify label { -().,#:/%} #"_" new-fid: already?/id][
					prin ["Adding column" label attrs/type "... "]
					parse get-query [qb-table/id "?act=API_AddField&label=" label "&type=" attrs/type][thru <fid> copy new-fid to </fid> to end]
		]
				remove/part find attrs 'type 2 
				
				all [_p: find attrs 'choices choices': second _p remove/part _p 2]
				foreach [name val] attrs [qrystr: insert qrystr reduce ["&" name "=" url-encode val]]

				get-query [qb-table/id "?act=API_FieldAddChoices&fid=" new-fid rejoin map-each choice choices' [join "&choice=" choice]]
				get-query [qb-table/id "?act=API_SetFieldProperties" qrystr: head qrystr "&fid=" new-fid ]
			]
		] 
	]

	set 'qb-connect use [tickets ticket' host' apptoken' user pswd][

		; holds all authentication tickets in use.  "static" and "private" to this function
		tickets: make block! 5 

		func [
			"Authenticates the user and obtains an auth ticket for 2 hours.  Augments this qb instance with settings and results."
			'appid [word!] "Application DBID"
			'settings [block!] {[host-url user "password" optional apptoken]}
		][
			unless parse settings [set host' opt url! set user email! set pswd string! set apptoken' opt word!] [
				if not [user][? qb-connect to-error "missing email to authenticate"]
				if not [pswd][? qb-connect to-error "missing password to authenticate"]
			]

			this: make quickbase [
				host: any [host' quickbase/host] 
				id: appid 
				ticket: ""
				apptoken: any [all [apptoken' join "&apptoken=" apptoken'] ""]
				tables: does [
					log-app "getting tables for the first time"
					probe this
					this/tables: qb-desc appid
			]
			]

			unless this/ticket: select tickets user [
				unless parse api-response: get-query 
					["main?act=API_Authenticate&username=" user "&password=" pswd "&hours=24"] 
					[thru "<ticket>" copy ticket' to "</ticket>" to end (this/ticket: ticket')] [
					make error! join "Unable to get login ticket! " api-response
				]
				insert tail tickets reduce [user ticket']
			]
			ticket': host': apptoken': user: pswd: none
			recycle
			set appid this
		]
	]

	;	----------------------------------------
	;		Row Retrieval
	;	----------------------------------------
	set 'qb-select func [
		{Returns columns and rows from a table.}
		'columns [function! word! block!] "Column(s) to fetch, * for all"
		'table [word! path!]
		/limit max-rows [integer!] "Maximum rows to return"
	][
		open-object table
		requested-columns columns

		;	ensure columns is a block of valid column names
		either columns = '* [
			columns: extract qb-table/columns 2
		][
			;column names should be allowed as "Big Quickbase Field Name"
			if (unique columns: to-block columns) <> intersect columns qb-table/columns [
				to-error join "Invalid select column" [difference columns intersect columns qb-table/columns]
			]
		]

		;	execute query
		fetch columns either limit [join "num-" max-rows][""] none ;encode-predicate predicate
		print ["memory for fetch" memuse qb-select]
		also copy buffer: head buffer recycle
	]

	;	----------------------------------------
	;		Row Management
	;	----------------------------------------
	set 'qb-update func [
		"Updates row(s) in a table."
		'table [word!]
		'columns [word! block!] "Columns to set"
		values [any-type!] "Values to use"
		predicate [any-type!] "Value or block of values"
		; /where "Treat predicate as a block of search conditions"
	][
		; API_EditRecord need record_id
		open-object table
		get-query [qb-table/id "?act=API_EditRecord&rid=" predicate "&_fnm_vendor_status=" values]
	]

	; this is the base db object definition,
	; but this instance is only used to make
	; the new instance in 'qb-connect
	context [host: none hist: make block! 50]
]

log-app ["The quickbase API is now loaded." form quickbase]
print {
... available functions ...
qb-connect appid [host-url user "password" optional apptoken] - authenticate to your Quickbase application
qb-describe appid | dbid - get metadata about the application or a table
qb-select[/limit] columns dbid [max-rows] - select rows of columns from a table
qb-update dbid columns values record-id - update row(s)
qb-alter [column [choices [choice1 choice2...] fieldproperty propertyvalue...]...] - alter the schema of a table
}