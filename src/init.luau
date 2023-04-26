local RunService = game:GetService("RunService")

if RunService:IsServer() then
	return require(script.server)
else
	return require(script.client)
end
