local Signal = require(script.Parent.Parent.Signal)
local Promise = require(script.Parent.Parent.Promise)
local network = require(script.Parent.Parent.network)
local sharedEnums = require(script.Parent.sharedEnums)

local servicesReady = {}
local stagedServices

local server = {
	onServiceInitializing = Signal.new(),
	onServiceInitialized = Signal.new(),
	network = network.Server,
}

type Service = {
	name: string,
	client: { [string]: any }?,
	start: (() -> ())?,
	init: (() -> ())?,
	middleware: {
		inbound: { () -> boolean? }?,
		outbound: { () -> any }?,
	}?,
}

local function setupServiceNetwork(service)
	if typeof(service.client) ~= "table" then
		return nil
	end

	local serviceNetwork = network.Server.new(service.name, service.middleware)

	for key, value in service.client do
		serviceNetwork:append(key, value)
	end

	return serviceNetwork
end

local function readyUpServices()
	local serviceInitPromises = {}

	if stagedServices then
		for _, service in stagedServices do
			table.insert(
				serviceInitPromises,
				Promise.new(function(resolve)
					server.onServiceInitializing:Fire(service)

					if typeof(service.init) == "function" then
						debug.setmemorycategory(service.name)
						service.init()
					end

					local serviceNetwork = setupServiceNetwork(service)

					if serviceNetwork then
						serviceNetwork:dispatch(sharedEnums.Parent.service)
					end

					servicesReady[service.name] = service
					stagedServices[service.name] = nil
					server.onServiceInitialized:Fire(service)
					resolve()
				end)
			)
		end
	end

	return Promise.all(serviceInitPromises),
		function()
			for _, service in servicesReady do
				if typeof(service.start) ~= "function" then
					continue
				end

				task.spawn(function()
					debug.setmemorycategory(service.name)
					service.start()
				end)
			end
		end
end

--[=[ 
    Returns a boolean on whether Comet has started or not.
]=]

function server.started()
	return script:GetAttribute(sharedEnums.Attribute.started) == true
end

--[=[ 
    Initializes all services **one by one** and then starts them up in 1 go.
    Returns a promise which is resolved when this process fully completes.
]=]

function server.start()
	assert(not server.started(), `Comet has already started!`)

	return Promise.new(function(resolve)
		local beforeStartClockStamp = os.clock()
		local servicesInitializedPromise, startupServices = readyUpServices()

		local wasSuccessfull, response = servicesInitializedPromise:await()

		if not wasSuccessfull then
			warn(tostring(response))
		end

		script:SetAttribute(sharedEnums.Attribute.started, true)
		startupServices()
		resolve(os.clock() - beforeStartClockStamp)
	end)
end

--[=[ 
    Returns a promise which is resolved when Comet is fully started.
]=]

function server.onStart()
	if server.started() then
		return Promise.resolve(0)
	else
		return Promise.new(function(resolve)
			local beforeStartClockStamp = os.clock()
			script:GetAttributeChangedSignal(sharedEnums.Attribute.started):Wait()
			resolve(os.clock() - beforeStartClockStamp)
		end)
	end
end

--[=[ 
    Registers the given array of services.
]=]

function server.registerServices(services: { Service } | { [string]: Service })
	assert(not server.started(), `Can only register services before Comet is started.`)
	assert(stagedServices == nil, `Services have already been registered!`)
	assert(
		typeof(services) == "table",
		`Bad argument #1 to 'services'. Expected type table, but got type {typeof(services)} instead!`
	)

	stagedServices = services
end

--[=[ 
    Returns a service of the given name, if found.
]=]

function server.service(serviceName: string): Service
	local service = servicesReady[serviceName]
	assert(server.started(), `Can only get services after Comet has started.`)
	assert(service, `Service "{serviceName}" was not found!`)

	return service
end

return table.freeze(server)
