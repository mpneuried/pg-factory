# import the external modules
_isArray = require( "lodash/isArray" )
_omit = require( "lodash/omit" )
_bind = require( "lodash/bind" )
pq = require 'pg'
SqlString = require('sqlstring')

# import the internal modules
Table = require "./table"
utils = require( "./utils" )

# # Postgres Dynamo Manager
# ### extends [Basic](basic.coffee.html)

# Manager to organize the tables and connections
module.exports = class PostgresFactory extends require( "./basic" )

	# define the defaults
	defaults: =>
		# extend the parent defaults
		@extend super,
			# **showQueryTime** *Boolean* Log the query time as info log
			showQueryTime: false
			# **the postgres driver pooling options**
			# **host** *String* Postgres server host
			host: 'localhost'
			# **user** *String* Postgres server user
			port: 5432
			# **port** *Number* Postgres server port
			user: 'root'
			# **password** *String* Postgres server password
			password: 'secret'
			# **database** *String* Postgres database to work with
			database: "your-database"
			# **waitForConnections** *Boolean* Wait for connections if the poolsize has been reached
			waitForConnections: true
			# **connectionLimit** *Number* Postgres Connection poolsize
			connectionLimit: 10
			# **connectionLimit** *Number* Postgres maximim limit of queued querys if the poolsize has been reached. `0` = no limit
			queueLimit: 0
			# **timezone** *String|Number* Postgres tiemzone definition
			timezone: "local"

	###	
	## constructor 

	`new PostgresFactory( options, tableSettings )`
	
	Define the configuration by options and defaults, and save the table settings.

	@param {Object} options Basic config object
	@param {Object} tableSettings Configuration of all tabels. For details see the [API docs](http://mpneuried.github.io/mysql-dynamo/)

	###
	constructor: ( options, @tableSettings )->
		super( options )
		return

	###
	## initialize
	
	`factory.initialize()`
	
	Initialize the Postgres pool

	@api private
	###
	initialize: =>
		# `multipleStatements` is required so overwrite it hard
		@pool = new pq.Pool @extend( {}, @config, { multipleStatements: true } )
		
		# set the internal flags
		@connected = false
		@_dbTables = {}
		@_tables = {}

		@log "debug" , "initialized"

		@_initTables()

		return

	# # Public methods

	###
	## exec
	
	`factory.exec( statement[, args], cb )`
	
	Run a sql query by using a connection from the pool
	
	@param { String|Array } statement A Postgres SQL statement or an array of multiple statements
	@param { Array|Object } [args] Query arguments to auto escape. The arguments will directly passed to the `pg.query()` method from pg
	@param { Function } cb Callback function 
	
	@api public
	###
	exec: =>
		_now = Date.now() if @config.showQueryTime
		[ args..., cb ] = arguments

		@debug "run query", args

		# if statements is an Array concat them to a multi statement
		if _isArray( args[ 0 ] )
			args[ 0 ] = args[ 0 ].join( ";\n" )
		
		# get a connection from the pool
		@pool.connect ( err, client, done )=>
			if err
				cb( err )
				return
			args.push( [] )
			# define the return method to release the connection
			args.push =>
				done()
				@info "query time #{ ( Date.now() - _now ) }ms" if @config.showQueryTime
				#console.log('arguments', arguments)
				cb.apply( @, arguments )
				return
			# run the query with `pg`
			client.query.apply( client, args )
			return
		return

	###
	## list
	
	`factory.list( cb )`
	
	List all existing db tables
	
	@param { Function } cb Callback function 
	
	@api public
	###
	list: ( cb )=>
		cb null, Object.keys( @_tables )
		return

	###
	## each
	
	`factory.each( fn )`
	
	Loop troug all tables
	
	@param { Function } fn Method called for every table. Looks like `.each ( key, tableObj )=>`
	
	@api public
	###
	each: ( fn )=>
		for _tblKey, _tbl of @_tables
			fn( _tblKey, _tbl )
		return

	###
	## get
	
	`factory.get( tableName )`
	
	Get a [Table](table.coffee.html) by name
	
	@param { String } tableName Table name to get 
	
	@return { Table } The found [Table](table.coffee.html) object or `null` 
	
	@api public
	###
	get: ( tableName )=>
		if @has( tableName )
			@_tables[ tableName ]
		else
			null

	###
	## has
	
	`factory.has( tableName )`
	
	Check for a defined table
	
	@param { String } tableName Table name 
	
	@return { Boolean } Table exists 
	
	@api public
	###
	has: ( tableName )=>
		@_tables[ tableName ]?

	escape: ( val )->
		return SqlString.escape( val )

	###
	## _initTables
	
	`factory._initTables( tables, cb )`
	
	Initialize the [Table](table.coffee.html) objects defined within the table configuration
	
	@param { Object } [tables=@tableSettings] The Table settings. If `null` it uses the configured tables 
	
	@api private
	###
	_initTables: ( tables = @tableSettings )=>
		# loop through the tables
		for tableName, table of tables
			# destroy existing table
			if @_tables[ tableName ]?
				delete @_tables[ tableName ]
			
			# generate a [Table](table.coffee.html) object for each table-element out of @tableSettings
			_opt =
				factory: @
				logging: @config.logging
				returnFormat: @config.returnFormat
			
			_tblObj = new Table( _omit( table, "events" ), _opt )

			# add all defined event function to the model 
			for events, fn of table.events
				_tblObj.on( event, _bind( fn, _tblObj, event ) ) for event in events.split( ',' )

			@_tables[ tableName ] = _tblObj
			@emit( "tableinit", tableName, _tblObj )
			@debug "tableinit", tableName

			
		@connected = true
		return

	# # Error message mapping
	ERRORS: =>
		@extend super,
			"no-tables-fetched": "Currently not tables fetched. Please run `factory.connect()` first."
			"table-not-found": "Table `<%= tableName %>` not found."
