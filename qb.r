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
				*** changes call-quickbase error checking and API_DoQuery
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
	Needs: [%sysmon.r http://reb4.me/r/altxml.r]
] 

unless value? 'load-xml [do http://reb4.me/r/altxml.r]
unless value? 'sysmon.r [do %../lib/sysmon.r]

quickbase: use [
	api-header
	buffer
	API_DoQuery
	call-quickbase
	API_GetSchema-app
	API_GetSchema-db
	dataTypeConversions
	open-application
	open-object
	reserved-words
	__APP__

][
	;	----------------------------------------
	;		Default values
	;	----------------------------------------

	buffer: make block! 4096 	; stores values returned from lookup and select

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

	qb-fieldify: func[str [string!] /local search newstr][
		newstr: copy str search: { -().,#:/%}
		forall search [replace/all newstr first search #"_"]
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

	net_columns_requested: func [
		columns [string! word! block!] "Columns to select"
	][
		either columns = '* [
			columns: extract qb-table/columns 2
		][
			;column names should be allowed as "Big Quickbase Field Name"
			if (columns: unique to-block columns) <> intersect columns qb-table/columns [
				to-error join "Invalid select column " [difference columns intersect columns qb-table/columns]
			]
			log-app ["requested columns" columns]
			columns
		]
	]

	;	----------------------------------------
	;		Low-level table handling functions
	;	----------------------------------------

	call-quickbase: func [
		request [block!]
		/mock
		/local api-call errcode errtext errdetail
	] [
		if error? set/any 'err try [
			if not __APP__/host [to error! "No host specified."]
			insert tail quickbase/hist api-call: rejoin ["/db/" rejoin request __APP__/apptoken "&ticket=" __APP__/ticket]
			log-app ["GET" join __APP__/host api-call]

			; mock resonse for testing
			if mock [return "<qdbapi><action>API_AddField</action><errcode>0</errcode><errtext>No error</errtext><fid>245</fid><label>operating_in.Fred2</label></qdbapi>"]
			
			parse quickbase-response: read/custom to-url join __APP__/host api-call api-header
				[["<?xml" thru <errcode> copy errcode to </errcode> thru <errtext> copy errtext to </errtext> thru <errdetail> copy errdetail to </errdetail>]
				 | [thru <font color=red size=+1> copy errtext to </font> thru <div id="response_errormsg"> copy errdetail to </div>]
			]
			if errdetail [to-error reform [errcode errtext errdetail quickbase-response]]
		][
			probe err
		]
		quickbase-response
	]

	open-application: 
		use [tickets][tickets: make block! 5 ; holds all authentication tickets in use.  "static" and "private" to this function
		func [
			"Registers an app with a host, authenticates the user on the host"
			host [url!]
			usr [email!]
			password [string!]
			/local new-ticket
		][
			; need the ticket which is indexed by username, which I think makes sense since you Auth to db/main FIXME should be by host/username
			unless all [new-ticket: select quickbase/apps host new-ticket: select new-ticket usr][
				unless parse call-quickbase
					["main?act=API_Authenticate&username=" usr "&password=" password "&hours=24"] 
					[thru "<ticket>" copy new-ticket to "</ticket>" to end]
				[
					make error! join "Unable to get login ticket! " quickbase-response
				]
				; cache the ticket by host/usr
				insert quickbase/apps head insert/only tail reduce [host] reduce [usr new-ticket]
			]
			new-ticket
		]
	]
	
	; Opening a table the first time gets its schema, after that we return the saved schema.
	open-object: func [
		object [word! path!] "db or table - 'app-dbid | myDb | 'table-dbid | myDb/table-name | db/table-name	; where myDb was set to qb-connect"
	][
		clear buffer: head buffer
		either value? object [
			log-app ["existing open-object" object]
			qb-table: get object qb-table/accessed: now qb-table/accesses: qb-table/accesses + 1
		][
			log-app ["new open-object" object]
			qb-table: set object API_GetSchema-app object
		]
	]

	API_GetSchema-app: 
		use[name label cols][cols: make block! 50
		func [
			dbid [word!]
			/local schema-xml _
		][
			log-app ["API_GetSchema" dbid]
			clear cols: head cols
			schema-xml: second load-xml call-quickbase [to-string dbid "?act=API_GetSchema"]
			either schema-xml/<table>/<fields> [
				; COLUMNS in TABLE
				; TODO if I write a native parse rule for the string I can remove dependency on altxml.r
				foreach [key value] schema-xml/<table>/<fields> [
					cols: insert cols reduce [
						; "key"
						to-word name: qb-fieldify copy label: value/<label> 
						compose/deep [
							id (to-integer value/#id) name (name) label (label) type (to-word value/#field_type)
							choices (any [all [find value <choices> value/<choices>] none])
							formula (if find value <formula> [(to-block value/<formula>)])
						]
					]
				]

				_: schema-xml/<table>

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
				foreach [key value] schema-xml/<table>/<chdbids> [
					cols: insert cols reduce [
						to-word value/%.txt reduce [to-word find/tail value/#name "_dbid_"]
					]
				]
				reduce [accessed: now accesses: 1 columns: copy head cols]
			]
		]
	]

	; I use very simple parsing logic that I think must be damned fast.  
	; It looks simply for the < and > of tags for the number of columns, ignoring column names. 
	; It depends on Quickbase returning the columns in the requested order. 
	API_DoQuery: use[one-column one-row rule ][
		one-column: none one-row: make block! 50
		; I insert and bump row-block during the parse; reset and clear it at the end
		rule: [
			any [thru <record> 
				[XXX-replaced-with-number-of-columns-before-parsing-XXX 
				[thru #">" copy one-column to #"<" to newline (one-row: insert one-row one-column one-column: none)] 
				(buffer: insert/only buffer copy one-row: head one-row clear one-row)] 
			]
		]
		func [
			query-columns [block!] query-options [string! none!] query [string! none!]
		][
			rule/2/3/1: length? query-columns ;this is the number of columns to parse
			parse replace/all
				call-quickbase [qb-table/id "?act=API_DoQuery&options=" query-options 
					"&clist=" next rejoin map-each itm query-columns [rejoin [#"." select column-meta-data: select qb-table/columns itm 'id]]
				] {/>} {><} rule
		] 
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
		'object [word! path!] "db or table - 'app-dbid | myDb | 'table-dbid"
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
				either already?: select qb-table/columns to-word qb-fieldify label [
					new-fid: already?/id
				][
					prin ["Adding column" label attrs/type "... "]
					parse call-quickbase [qb-table/id "?act=API_AddField&label=" label "&type=" attrs/type][thru <fid> copy new-fid to </fid> to end]
				]
				remove/part find attrs 'type 2 
				
				all [_p: find attrs 'choices choices': second _p remove/part _p 2]
				foreach [name val] attrs [qrystr: insert qrystr reduce ["&" name "=" url-encode val]]

				call-quickbase [qb-table/id "?act=API_FieldAddChoices&fid=" new-fid rejoin map-each choice choices' [join "&choice=" choice]]
				call-quickbase [qb-table/id "?act=API_SetFieldProperties" qrystr: head qrystr "&fid=" new-fid ]
			]
		]
	]

	;	----------------------------------------
	;		CONNECT
	;
	; Keeps track of all auth tickets by email address and reuses them.
	; Creates a new instance of quickbase with all the auth info.  
	;	----------------------------------------
	set 'qb-connect use [tickets arg-host arg-usr arg-pass arg-token][
		; holds all authentication tickets in use.  "static" and "private" to this function
		tickets: make block! 5 
		func [
			{
				Authenticates the user (on a per host basis) for 2 hours.^/
				>> qb-connect cjwidfrb1 [https://myqbdomain.quickbase.com user@domain.net.com "password" dhks25rdaxugwswv5n2b9byr853b]
			}
			'appid [word!] "Application DBID"
			'settings [block!] {[host-url user "password" optional apptoken]}
			/show "show state"
		][
			if show [probe tickets return]

			; validation
			unless parse settings [set arg-host opt url! set arg-usr email! set arg-pass string! set arg-token opt word!] [
				? qb-connect
				if not value? 'arg-usr[to-error "missing email to authenticate"]
				if not value? 'arg-pass[to-error "missing password to authenticate"]
				to-error "unrecognized settings"
			]
			; __APP__: context [
			; 	; application object (this allows setting quickbase host before connecting to multiple apps and resaving itwhen connecting)
			; 	host: quickbase/host: any [arg-host quickbase/host]
			; 	id: appid
			; 	tables: none
			; 	ticket: open-application arg-host arg-usr arg-pass
			; 	apptoken: any [all [arg-token join "&apptoken=" arg-token] ""]
			; ] 
			; unset [arg-host arg-usr arg-pass arg-token]
			
			; this: make this [
			; 	; log-app "getting tables for the first time"	
			; 	API_GetSchema-app appid
			; ]
			__APP__: context [
				; application object (this allows setting quickbase host before connecting to multiple apps and resaving itwhen connecting)
				host: quickbase/host: any [arg-host quickbase/host]
				id: appid
				tables: none
				ticket: none
				apptoken: any [all [arg-token join "&apptoken=" arg-token] ""]
			]
			__APP__/ticket: open-application arg-host arg-usr arg-pass

			also set appid __APP__ unset [arg-host arg-usr arg-pass arg-token]
		]
	]

	;	----------------------------------------
	;		Row Retrieval
	;	----------------------------------------
	set 'qb-select func [
		{Returns columns and rows from a table.}
		'columns [function! word! block!] "Column(s) to API_DoQuery, * for all"
		'table [word! path!]
		/limit max-rows [integer!] "Maximum rows to return"
	][
		log-app "qb-select"
		open-object table
		API_DoQuery net_columns_requested columns either limit [join "num-" max-rows][""] none ;encode-predicate predicate
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
		; API_EditRecord needs record_id
		open-object table
		call-quickbase [qb-tabl0e/id "?act=API_EditRecord&rid=" predicate "&_fnm_xx_yy=" values]
	]

	; quickbase is now a container to hold its overall knowledge
	reduce ['host none 'hist make block! 100 'apps make block! 10]
]
print {
   ... available functions ...

 * qb-connect          appid [host-url user "password" optional apptoken]                         authenticate to your Quickbase application
 * qb-describe         appid | dbid                                                               get metadata about the application or a table
 * qb-select[/limit]   columns dbid [max-rows]                                                    select rows of columns from a table
 * qb-update           dbid columns values record-id                                              update row(s)
 * qb-alter            [column [choices [choice1 choice2...] fieldproperty propertyvalue...]...]  alter the schema of a table
}
log-app [system/script/header/title "is loaded." form quickbase]