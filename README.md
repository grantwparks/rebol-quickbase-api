rebol-quickbase-api
===================

Rebol (2) object that provides some Quickbase API access

Spending a few months working with Quickbase APIs led me to write one in Rebol.  I began to write it just like ALL the other APIs -- simply copying the functions available through Quickbase's HTTP API.  Then, while I was looking at RebDB, I got the idea to do something more SQL-like.

rebol-quickbase-api provides several functions you can use to interact with Quickbase in a much more convenient way than the native API.

%qb.r Defines a single object named quickbase that provides a template for each Quickbase application you connect to.  It also defines global functions for simplicity (another cue I took from RebDB):

~~~
>> do %qb.r
Script: "Quickbase SQL Client API" (10-Oct-2013)
connecting to: reb4.me
Script: "AltXML" (7-Jun-2009)
Script: "Utility functions for memory and timing" (22-Oct-2013)

... available functions ...
qb-connect appid [host-url user "password" optional apptoken] - authenticate to your Quickbase application
qb-describe appid | dbid - get metadata about the application or a table
qb-select[/limit] columns dbid [max-rows] - select rows of columns from a table
qb-update dbid columns values record-id - update row(s)
qb-alter [column [choices [choice1 choice2...] fieldproperty propertyvalue...]...] - alter the schema of a table

[18:09:09 7E-3 [103.7 KB] [103.7 KB] [5.7 MB] ["The quickbase API is now loaded." "host: none^/hist: []^/"]]
>> probe quickbase
make object! [
    host: none
    hist: []
]
>>
~~~

(The qb-update and qb-alter are somewhat functional; they do the job, but there might be some hardcoded parts specific to some needs I had.)

* in the future, hist might allow for transactions, across apps
---

#### Authenticate to your Quickbase application with qb-connect

qb-connect appid [host-url user-email "password" apptoken]

Returns a Rebol object representing the Quickbase application.  You can authenticate as different users on the same host (in different Quickbase apps), but not in the same app.

~~~
>> foo: qb-connect cjwidfrb1 [https://myqbdomain.quickbase.com user@domain.net.com "passwordstring" dhks25rdaxugwswv5n2b9byr853b]
GET https://myqbdomain.quickbase.com/db/main?act=API_Authenticate&username=user@domain.net.com&password=passwordstring&hours=24&apptoken=dhks25rdaxugwswv5n2b9byr853b&ticket=none
connecting to: myqbdomain.quickbase.com
>> probe foo
make object! [
    host: https://myqbdomain.quickbase.com
    hist: [{/db/main?act=API_Authenticate&username=user@domain.net.com&password=passwordstring&hours=24&apptoken=dhks25rdaxugwswv5n2b9byr853b&ticket=none}]
    id: 'cjwidfrb1
    ticket: {6_bijbsgzcg_bzr7zh_3ca_dzivxsgd3hx8mqdk3v3cid62spi4be2remjd66779jbyqqfdmbhrixcr}
    apptoken: "&apptoken=dhks25rdaxugwswv5n2b9byr853b"
    tables: func [][
        log-app "getting tables for the first time"
        probe this
        this/tables: qb-desc appid
    ]
]
>> probe cjwidfrb1
make object! [
    host: https://myqbdomain.quickbase.com
    hist: [{/db/main?act=API_Authenticate&username=user@domain.net.com&password=passwordstring&hours=24&apptoken=dhks25rdaxugwswv5n2b9byr853b&ticket=none}]
    id: 'cjwidfrb1
    ticket: {6_bijbsgzcg_bzr7zh_3ca_dzivxsgd3hx8mqdk3v3cid62spi4be2remjd66779jbyqqfdmbhrixcr}
    apptoken: "&apptoken=dhks25rdaxugwswv5n2b9byr853b"
    tables: func [][
        log-app "getting tables for the first time"
        probe this
        this/tables: qb-desc appid
    ]
]
>>
~~~

Notice that a global word has been created for the appid and because I assigned that return to foo, it also references that object.

You can also set the host on the quickbase object before connecting

~~~
>> do %qb.r
Script: "Quickbase SQL Client API" (10-Oct-2013)
== ["The quickbase API is now loaded." "host: none^/hist: []^/"]
>> quickbase/host: https://mydomain.quickbase.com
== https://mydomain.quickbase.com
>> qb-connect bjxajeka3 [qbuser@mydomain.com "mypassword" dyks25rdaxu4wswv5n2t9byr853b]
GET https://mydomain.quickbase.com/db/main?act=API_Authenticate&username=qbuser@mydomain.com&password=mypassword&hours=24&apptoken=dyks25rdaxu4wswv5n2t9byr853b&ticket=none
connecting to: mydomain.quickbase.com
>>
~~~

#### Describe the schema of a Quickbase application or table

qb-desc app|table

qb-describe app|table

Returns a Rebol block that describes metadata of the application or table.  This structure will be evolving as internal needs change, so it's informational right now. What that means is it's useful for display purposes, but don't write code that relies on the return structure.

~~~

~~~

#### Select records from Quickbase tables with qb-select

qb-select columns table 

qb-select/limit columns table nn

~~~
~~~

#### Edit Quickbase records with qb-update

#### Alter a Quickbase table schema

