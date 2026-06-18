--[[
	CameraShake.client.lua  (StarterPlayer.StarterPlayerScripts)

	Phase 5.5 (game feel): client-side camera shake. Listens for the server's
	ShakeCamera remote (intensity in studs, duration in seconds) and offsets the
	camera with a decaying random wobble for that duration. Multiple shakes stack.

	It binds AFTER the default camera (RenderPriority.Camera + 1) and offsets the
	camera's CFrame each frame, then UNBINDS the moment no shakes remain — so it never
	fights or permanently overrides Roblox's camera. Nothing to restore: when it
	unbinds, the default camera simply takes over again.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShakeCamera = Remotes:WaitForChild("ShakeCamera")

local BIND_NAME = "BrightSoulsCameraShake"
local shakes = {} -- list of { magnitude, duration, elapsed }
local bound = false

local function onRender(dt)
	-- Sum the (decaying) magnitude of every active shake; drop finished ones.
	local total = 0
	local i = 1
	while i <= #shakes do
		local s = shakes[i]
		s.elapsed += dt
		if s.elapsed >= s.duration then
			table.remove(shakes, i)
		else
			total += s.magnitude * (1 - s.elapsed / s.duration)
			i += 1
		end
	end

	if #shakes == 0 then
		RunService:UnbindFromRenderStep(BIND_NAME)
		bound = false
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local ox = (math.random() - 0.5) * 2 * total
	local oy = (math.random() - 0.5) * 2 * total
	local roll = (math.random() - 0.5) * 2 * total * 0.015
	camera.CFrame = camera.CFrame * CFrame.new(ox, oy, 0) * CFrame.Angles(0, 0, roll)
end

ShakeCamera.OnClientEvent:Connect(function(intensity, duration)
	if not intensity or not duration then
		return
	end
	table.insert(shakes, { magnitude = intensity, duration = duration, elapsed = 0 })
	if not bound then
		bound = true
		RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, onRender)
	end
end)
