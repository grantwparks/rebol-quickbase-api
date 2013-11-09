rebol-quickbase-api
===================

Rebol (2) object that provides some Quickbase API access

Spending a few months working with Quickbase APIs led me to write one in Rebol.  I began to write it just like ALL the other APIs -- simply copying the functions available through Quickbase's HTTP API.  Then, while I was looking at RebDB, I got the idea to do something more SQL-like.

rebol-quickbase-api provides several functions you can use to interact with Quickbase in a much more convenient way than Quickbase.

qb-connect - authenticate to your Quickbase application
qb-describe - get metadata about the application or a table
qb-select - select rows of columns from a table
qb-update - update row(s)
qb-alter - alter the schema of a table

The last 2 barely function right now; they do the job, but there's several hardcoded parts specific to some needs I had.

%qb.r Defines a single object, quickbase and then defines the qb functions globally for simplicity (another cue I took from RebDB)

#Authenticate to your Quickbase application with qb-connect

qb-connect appid [host-url user-email "password" apptoken]

~~~
>> qb-connect bjxajeka3 [https://mydomain.quickbase.com qbuser@mydomain.com "mypassword" caks25xdaxugwsbvwn2b9byr833b]
GET https://mydomain.quickbase.com/db/main?act=API_Authenticate&username=qbuser@mydomain.com&password=mypassword&hours=24&apptoken=caks25xdaxugwsbvwn2b9byr833b&ticket=none
connecting to: westower.quickbase.com
~~~

#Describe the schema of a Quickbase application or table

#Select records from Quickbase tables with qb-select

#Edits Quickbase records with qb-update

#Alter a Quickbase table schema

