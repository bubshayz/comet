local Signal = require(script.Parent.Parent.Signal)
local Promise = require(script.Parent.Parent.Promise)
local network = require(script.Parent.Parent.network)
local sharedEnums = require(script.Parent.sharedEnums)

local server = script.Parent.server
local controllersReady = {}
local services = {}
local stagedControllers

local client = {
	onControllerInitializing = Signal.new(),
	onControllerInitialized = Signal.new(),
	network = network.client,
}

type Controller = {
	name: string,
	start: (() -> ())?,
	init: (() -> ())?,
}

local function retrieveServices()
	return Promise.new(function(resolve)
		-- Wait for the server to start so there is a guarantee all services have
		-- been initialized and ready to be used:
		if not server:GetAttribute(sharedEnums.Attribute.started) then
			server:GetAttributeChangedSignal(sharedEnums.Attribute.started):Wait()
		end

		for serviceName, service in network.client.allFromParent(sharedEnums.Parent.service) do
			services[serviceName] = service
		end

		resolve()
	end)
end

local function readyUpControllers()
	local controllerInitPromises = {}

	if stagedControllers then
		for _, controller in stagedControllers do
			table.insert(
				controllerInitPromises,
				Promise.new(function(resolve)
					client.onControllerInitializing:Fire(controller)

					if typeof(controller.init) == "function" then
						debug.setmemorycategory(controller.name)
						controller.init()
					end

					controllersReady[controller.name] = controller
					stagedControllers[controller.name] = nil
					client.onControllerInitialized:Fire(controller)
					resolve()
				end)
			)
		end
	end

	return Promise.all(controllerInitPromises),
		function()
			if not stagedControllers then
				return
			end

			for _, controller in controllersReady do
				if typeof(controller.start) ~= "function" then
					continue
				end

				task.spawn(function()
					debug.setmemorycategory(controller.name)
					controller.start()
				end)
			end
		end
end

--[=[ 
    Returns a boolean on whether Comet has started or not.
]=]

function client.started()
	return script:GetAttribute(sharedEnums.Attribute.started) == true
end

--[=[ 
    Waits for all serverside services (their **client counterpart**) to be replicated
    to the client, then initializes all controllers **one by one** and then starts them 
    up in 1 go.

    Returns a promise which is resolved when this process fully completes.
]=]

function client.start()
	assert(not client.started(), `Comet has already started!`)

	return Promise.new(function(resolve)
		local clockStampBeforeStart = os.clock()

		local wasSuccessfull, response = retrieveServices():await()

		if not wasSuccessfull then
			warn(tostring(response))
		end

		local controllersInitializedPromise, startupServices = readyUpControllers()
		local wasSuccessfull, response = controllersInitializedPromise:await()

		if not wasSuccessfull then
			warn(tostring(response))
		end

		startupServices()
		script:SetAttribute(sharedEnums.Attribute.started, true)
		resolve(os.clock() - clockStampBeforeStart)
	end)
end

--[=[ 
    Returns a promise which is resolved when Comet is fully started.
]=]

function client.onStart()
	if client.started() then
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
    Registers the given array of controllers.
]=]

function client.registerControllers(controllers: { Controller } | { [string]: Controller })
	assert(not client.started(), `Can only register controllers before Comet is started.`)
	assert(stagedControllers == nil, `Controllers have already been registered!`)
	assert(
		typeof(controllers) == "table",
		`Bad argument #1 to 'controllers'. Expected type table, but got type {typeof(controllers)} instead!`
	)

	stagedControllers = controllers
end

--[=[ 
    Returns a controller of the given name, if found.
]=]

function client.controller(controllerName: string): Controller
	local controller = controllersReady[controllerName]
	assert(client.started(), `Can only get controllers after Comet has started.`)
	assert(controller, `Controller "{controllerName}" was not found!`)

	return controller
end

--[=[ 
    Returns the **client counter part** of the service with the given name, if found.
]=]

function client.service(serviceName: string)
	local service = services[serviceName]
	assert(service, `Service "{serviceName}" was not found!`)

	return service
end

return table.freeze(client)
