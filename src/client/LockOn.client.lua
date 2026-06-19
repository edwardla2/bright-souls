--[[
	LockOn.client.lua  (StarterPlayer.StarterPlayerScripts)

	Phase 5.6a: souls-style lock-on targeting. F (Config.LOCKON_KEY) toggles lock onto
	the nearest enemy/boss in front of the camera; Tab (Config.LOCKON_SWITCH_KEY) cycles
	to the next-nearest target. Keyboard-only so it works on a trackpad (no mouse). While
	locked: the camera frames the target, a gold diamond reticle floats over it, and the
	character faces it (AutoRotate off) so movement becomes strafe/circle. Lock
	auto-breaks if the target dies, gets too far, or you toggle off / respawn.

	Control scheme:
	  Move: WASD/arrows | Attack: LMB | Dodge: Q | Sprint: LShift | Flask: R |
	  Lock-on: F | Switch target: Tab

	The current target is sent to the server via "LockTarget" (target or nil) so future
	server systems (directional dodge, backstab) can read the player's lock state.

	Additive: it READS the existing enemy/boss tags and does NOT change the dodge — the
	locked camera makes WASD target-relative, so the existing MoveDirection-based dodge
	already rolls around/away from the target.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LockTarget = Remotes:WaitForChild("LockTarget")

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(212, 175, 55)

local lockedTarget = nil -- Model or nil
local reticle = nil -- BillboardGui

local function getRoot()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- Candidate enemies/bosses: tagged Enemy or Boss, or named "Rig" (same way the other
-- systems identify them).
local function getCandidates()
	local set = {}
	for _, m in ipairs(CollectionService:GetTagged("Enemy")) do
		set[m] = true
	end
	for _, m in ipairs(CollectionService:GetTagged("Boss")) do
		set[m] = true
	end
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Model") and inst.Name == "Rig" then
			set[inst] = true
		end
	end
	return set
end

local function isValidTarget(model)
	if not (model and model.Parent) then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and humanoid.Health > 0 and root ~= nil
end

-- Nearest valid target in front of the camera (optionally excluding one, for switching).
local function acquireTarget(exclude)
	local root = getRoot()
	if not root then
		return nil
	end
	local camera = workspace.CurrentCamera
	local best, bestDist = nil, math.huge
	for model in pairs(getCandidates()) do
		if model ~= exclude and isValidTarget(model) then
			local troot = model:FindFirstChild("HumanoidRootPart")
			local toTarget = troot.Position - root.Position
			local dist = toTarget.Magnitude
			if dist > 0 and dist <= Config.LOCKON_RANGE then
				local inFront = (not camera) or camera.CFrame.LookVector:Dot(toTarget.Unit) > 0.1
				if inFront and dist < bestDist then
					best, bestDist = model, dist
				end
			end
		end
	end
	return best
end

local function clearReticle()
	if reticle then
		reticle:Destroy()
		reticle = nil
	end
end

local function showReticle(target)
	clearReticle()
	local adornee = target:FindFirstChild("Head") or target:FindFirstChild("HumanoidRootPart")
	if not adornee then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "LockReticle"
	bb.Size = UDim2.new(0, 24, 0, 24)
	bb.AlwaysOnTop = true
	bb.Adornee = adornee
	bb.Parent = player:WaitForChild("PlayerGui")

	local diamond = Instance.new("Frame")
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.new(0.5, 0, 0.5, 0)
	diamond.Size = UDim2.new(0, 14, 0, 14)
	diamond.Rotation = 45
	diamond.BackgroundColor3 = GOLD
	diamond.BorderSizePixel = 0
	diamond.Parent = bb

	reticle = bb
end

local function setTarget(target)
	lockedTarget = target
	local humanoid = getHumanoid()
	local camera = workspace.CurrentCamera

	if target then
		showReticle(target)
		if humanoid then
			humanoid.AutoRotate = false
		end
		if camera then
			camera.CameraType = Enum.CameraType.Scriptable
		end
	else
		clearReticle()
		if humanoid then
			humanoid.AutoRotate = true
		end
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
	end
	LockTarget:FireServer(target) -- server records lock state for future systems
end

----------------------------------------------------------------------
-- Input: toggle (MB3) + switch (wheel)
----------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return -- ignore presses consumed by other UI (text fields, ProximityPrompts...)
	end
	if input.KeyCode == Config.LOCKON_KEY then
		-- F: toggle lock on/off.
		if lockedTarget then
			setTarget(nil)
		else
			local t = acquireTarget(nil)
			if t then
				setTarget(t)
			end
		end
	elseif input.KeyCode == Config.LOCKON_SWITCH_KEY then
		-- Tab: cycle to the next-nearest target (only while already locked).
		if lockedTarget then
			local nextTarget = acquireTarget(lockedTarget)
			if nextTarget then
				setTarget(nextTarget)
			end
		end
	end
end)

-- Break the lock cleanly on respawn.
player.CharacterAdded:Connect(function()
	if lockedTarget then
		setTarget(nil)
	end
end)

----------------------------------------------------------------------
-- Per-frame: framing, facing, break conditions
----------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	if not lockedTarget then
		return
	end

	local root = getRoot()
	local troot = isValidTarget(lockedTarget) and lockedTarget:FindFirstChild("HumanoidRootPart")
	if not root or not troot then
		setTarget(nil) -- target died / despawned / we have no body
		return
	end
	if (troot.Position - root.Position).Magnitude > Config.LOCKON_BREAK_RANGE then
		setTarget(nil) -- target ran away
		return
	end

	-- Camera: sit behind the player along the player->target line, look at a midpoint.
	local camera = workspace.CurrentCamera
	if camera then
		local flat = (troot.Position - root.Position) * Vector3.new(1, 0, 1)
		flat = (flat.Magnitude > 0.1) and flat.Unit or root.CFrame.LookVector
		local camPos = root.Position - flat * Config.LOCKON_CAM_DISTANCE + Vector3.new(0, Config.LOCKON_CAM_HEIGHT, 0)
		local lookAt = root.Position:Lerp(troot.Position, 0.5) + Vector3.new(0, 2, 0)
		camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(camPos, lookAt), Config.LOCKON_CAM_SMOOTH)
	end

	-- Face the target (Y-locked). lookAt is at the CURRENT position, so only rotation
	-- lerps — movement (camera-relative WASD) still strafes around the target.
	local faceAt = Vector3.new(troot.Position.X, root.Position.Y, troot.Position.Z)
	if (faceAt - root.Position).Magnitude > 0.1 then
		root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, faceAt), 0.3)
	end
end)
