--!strict

-- TEMPORARY STUDIO-ONLY READ-ONLY PHYSICS AUDIT LOGGER.
-- This script never writes CFrame, Position, velocity, force, gravity, or ownership.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then
	return
end

local SAMPLE_INTERVAL = 0.05
local REPORT_TIMEOUT_AFTER_LANDING = 1.5
local POSITION_RESIDUAL_THRESHOLD = 0.35
local EGG_VELOCITY_STEP_THRESHOLD = 15
local BASKET_VELOCITY_STEP_THRESHOLD = 20

type Sample = {
	t: number,
	rootY: number,
	rootVY: number,
	basketY: number,
	basketVY: number,
	eggY: number,
	eggVY: number,
	owner: string,
	floorContact: boolean,
}

local player = Players.LocalPlayer
local completed = false

local function ownerLabel(collider: BasePart): string
	local ok, owner = pcall(function()
		return collider:GetNetworkOwner()
	end)
	if ok then
		local ownerPlayer = owner :: Player?
		return ownerPlayer and ownerPlayer.Name or "server"
	end

	local ownerUserId = collider.Parent and collider.Parent:GetAttribute("EggOwnerUserId")
	if typeof(ownerUserId) == "number" then
		return "userId:" .. tostring(ownerUserId) .. "(attribute)"
	end
	return "unavailable"
end

local function isOnBasketFloor(bottom: BasePart, collider: BasePart): boolean
	local localCenter = bottom.CFrame:PointToObjectSpace(collider.Position)
	local colliderBottom = localCenter.Y - collider.Size.Y * 0.5
	local floorTop = bottom.Size.Y * 0.5
	return math.abs(localCenter.X) <= bottom.Size.X * 0.5
		and math.abs(localCenter.Z) <= bottom.Size.Z * 0.5
		and colliderBottom >= floorTop - 0.08
		and colliderBottom <= floorTop + 0.08
end

local function reportBindings()
	local jumpBindings = {}
	local defaultJumpBound = false
	local ok, bindings = pcall(function()
		return ContextActionService:GetAllBoundActionInfo()
	end)
	if ok then
		for actionName, actionInfo in bindings do
			local lowerName = string.lower(actionName)
			local serialized = string.lower(tostring(actionInfo))
			if string.find(lowerName, "jump", 1, true)
				or string.find(serialized, "space", 1, true)
				or string.find(serialized, "buttona", 1, true)
			then
				table.insert(jumpBindings, actionName)
				if actionName ~= "KoAVariableJump" then
					defaultJumpBound = true
				end
			end
		end
	end
	table.sort(jumpBindings)
	print(
		"[PhysicsAudit] InputBindings",
		"count=" .. tostring(#jumpBindings),
		"names=" .. table.concat(jumpBindings, ","),
		"defaultJumpBound=" .. tostring(defaultJumpBound),
		"customSinkActive=" .. tostring(table.find(jumpBindings, "KoAVariableJump") ~= nil)
	)
end

local function descendantSummary(container: Instance): string
	local items = {}
	for _, descendant in container:GetDescendants() do
		table.insert(items, descendant.Name .. ":" .. descendant.ClassName)
	end
	table.sort(items)
	return table.concat(items, "|")
end

local function auditCharacter(character: Model)
	if completed then
		return
	end

	local humanoid = character:WaitForChild("Humanoid", 15)
	local root = character:WaitForChild("HumanoidRootPart", 15)
	local basket = character:WaitForChild("Basket", 15)
	if not humanoid or not humanoid:IsA("Humanoid") then
		warn("[PhysicsAudit] Humanoid unavailable")
		return
	end
	if not root or not root:IsA("BasePart") then
		warn("[PhysicsAudit] HumanoidRootPart unavailable")
		return
	end
	if not basket or not basket:IsA("Model") then
		warn("[PhysicsAudit] Basket unavailable")
		return
	end
	local bottom = basket:WaitForChild("Bottom", 10)
	if not bottom or not bottom:IsA("BasePart") then
		warn("[PhysicsAudit] Basket.Bottom unavailable")
		return
	end

	local selectedEgg: Model? = nil
	local collider: BasePart? = nil
	local eggDeadline = os.clock() + 10
	repeat
		local candidate = Workspace:FindFirstChild("BasketEgg_1")
		if candidate and candidate:IsA("Model") then
			local candidateCollider = candidate:FindFirstChild("Collider")
			if candidateCollider and candidateCollider:IsA("BasePart") then
				selectedEgg = candidate
				collider = candidateCollider
			end
		end
		if not collider then
			task.wait(0.05)
		end
	until collider or os.clock() >= eggDeadline
	if not selectedEgg or not collider then
		warn("[PhysicsAudit] BasketEgg_1.Collider unavailable")
		return
	end

	print(
		"[PhysicsAudit] Settings",
		"gravity=" .. tostring(Workspace.Gravity),
		"stepping=" .. tostring(Workspace.PhysicsSteppingMethod),
		"useJumpPower=" .. tostring(humanoid.UseJumpPower),
		"jumpPower=" .. tostring(humanoid.JumpPower),
		"jumpHeight=" .. tostring(humanoid.JumpHeight),
		"selectedEgg=" .. selectedEgg:GetFullName(),
		"owner=" .. ownerLabel(collider)
	)
	local colliderProperties = collider.CurrentPhysicalProperties
	local basketOwner = ownerLabel(bottom)
	local physicalBasePartCount = 0
	for _, descendant in selectedEgg:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant.Massless then
			physicalBasePartCount += 1
		end
	end
	print(
		"[PhysicsAudit] BasketStructure",
		"primaryPart=" .. (basket.PrimaryPart and basket.PrimaryPart.Name or "nil"),
		"assemblyRoot=" .. (bottom.AssemblyRootPart and bottom.AssemblyRootPart.Name or "nil"),
		"assemblyMass=" .. string.format("%.6f", bottom.AssemblyMass),
		"owner=" .. basketOwner,
		"hierarchy=" .. descendantSummary(basket)
	)
	print(
		"[PhysicsAudit] EggStructure",
		"primaryPart=" .. (selectedEgg.PrimaryPart and selectedEgg.PrimaryPart.Name or "nil"),
		"physicalBaseParts=" .. tostring(physicalBasePartCount),
		"connectedParts=" .. tostring(#collider:GetConnectedParts(true)),
		"assemblyRoot=" .. (collider.AssemblyRootPart and collider.AssemblyRootPart.Name or "nil"),
		"assemblyMass=" .. string.format("%.6f", collider.AssemblyMass),
		"colliderSize=" .. tostring(collider.Size),
		"colliderShape=" .. tostring((collider :: Part).Shape),
		"density=" .. tostring(colliderProperties.Density),
		"friction=" .. tostring(colliderProperties.Friction),
		"elasticity=" .. tostring(colliderProperties.Elasticity),
		"collisionGroup=" .. collider.CollisionGroup,
		"owner=" .. ownerLabel(collider),
		"hierarchy=" .. descendantSummary(selectedEgg)
	)
	reportBindings()

	local samples: { Sample } = {}
	local anomalies: { string } = {}
	local markers: { [string]: number } = {}
	local ownerAtStart = ownerLabel(collider)
	local jumpStarted = false
	local landedAt: number? = nil
	local previousContact = isOnBasketFloor(bottom, collider)
	local previousSample: Sample? = nil
	local startTime = 0
	local accumulator = 0

	local function mark(name: string, elapsed: number)
		if markers[name] == nil then
			markers[name] = elapsed
		end
	end

	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(deltaTime: number)
		if completed or not character.Parent or humanoid.Health <= 0 then
			connection:Disconnect()
			return
		end

		if not jumpStarted then
			local state = humanoid:GetState()
			if state == Enum.HumanoidStateType.Jumping then
				jumpStarted = true
				startTime = os.clock()
				mark("jumpBegins", 0)
			end
			return
		end

		accumulator += deltaTime
		if accumulator < SAMPLE_INTERVAL then
			return
		end
		accumulator -= SAMPLE_INTERVAL

		local elapsed = os.clock() - startTime
		local contact = isOnBasketFloor(bottom, collider)
		local sample: Sample = {
			t = elapsed,
			rootY = root.Position.Y,
			rootVY = root.AssemblyLinearVelocity.Y,
			basketY = bottom.Position.Y,
			basketVY = bottom.AssemblyLinearVelocity.Y,
			eggY = collider.Position.Y,
			eggVY = collider.AssemblyLinearVelocity.Y,
			owner = ownerLabel(collider),
			floorContact = contact,
		}
		table.insert(samples, sample)

		if previousContact and not contact then
			mark("eggLeavesFloor", elapsed)
		elseif not previousContact and contact then
			mark("eggContactsBasketAgain", elapsed)
		end
		previousContact = contact

		if previousSample then
			local dt = sample.t - previousSample.t
			if previousSample.rootVY > 0 and sample.rootVY <= 0 then
				mark("characterApex", elapsed)
			end
			if previousSample.eggVY > 0 and sample.eggVY <= 0 then
				mark("eggApex", elapsed)
			end
			if dt > 0 then
				local predictedEggDelta = (previousSample.eggVY + sample.eggVY) * 0.5 * dt
				local measuredEggDelta = sample.eggY - previousSample.eggY
				if math.abs(measuredEggDelta - predictedEggDelta) > POSITION_RESIDUAL_THRESHOLD then
					table.insert(anomalies, string.format(
						"t=%.2f eggPositionResidual=%.3f",
						sample.t,
						measuredEggDelta - predictedEggDelta
					))
				end
			end
			local eggVelocityStep = sample.eggVY - previousSample.eggVY
			if math.abs(eggVelocityStep) > EGG_VELOCITY_STEP_THRESHOLD then
				table.insert(anomalies, string.format(
						"t=%.2f eggVelocityStep=%.3f",
						sample.t,
						eggVelocityStep
					))
			end
			local basketVelocityStep = sample.basketVY - previousSample.basketVY
			if math.abs(basketVelocityStep) > BASKET_VELOCITY_STEP_THRESHOLD then
				table.insert(anomalies, string.format(
						"t=%.2f basketVelocityStep=%.3f",
						sample.t,
						basketVelocityStep
					))
			end
		end
		previousSample = sample

		if sample.owner ~= ownerAtStart then
			table.insert(anomalies, string.format(
				"t=%.2f ownerChanged=%s->%s",
				sample.t,
				ownerAtStart,
				sample.owner
			))
			ownerAtStart = sample.owner
		end

		local currentState = humanoid:GetState()
		if not landedAt
			and elapsed > 0.1
			and (currentState == Enum.HumanoidStateType.Landed
				or currentState == Enum.HumanoidStateType.Running
				or currentState == Enum.HumanoidStateType.RunningNoPhysics)
		then
			landedAt = elapsed
			mark("characterLands", elapsed)
		end

		if landedAt
			and (markers.eggContactsBasketAgain ~= nil
				or elapsed - landedAt >= REPORT_TIMEOUT_AFTER_LANDING)
		then
			completed = true
			connection:Disconnect()
			print("[PhysicsAudit] BEGIN ONE-JUMP REPORT")
			for _, item in samples do
				print(string.format(
					"[PhysicsAudit] t=%.2f rootY=%.3f rootVY=%.3f basketY=%.3f basketVY=%.3f eggY=%.3f eggVY=%.3f owner=%s floor=%s",
					item.t,
					item.rootY,
					item.rootVY,
					item.basketY,
					item.basketVY,
					item.eggY,
					item.eggVY,
					item.owner,
					tostring(item.floorContact)
				))
			end
			for name, markerTime in markers do
				print(string.format("[PhysicsAudit] MARK %s t=%.2f", name, markerTime))
			end
			if #anomalies == 0 then
				print("[PhysicsAudit] ANOMALIES none")
			else
				for _, anomaly in anomalies do
					print("[PhysicsAudit] ANOMALY " .. anomaly)
				end
			end
			print(
				"[PhysicsAudit] STATIC_WRITE_CHECK",
				"eggVelocityWrites=false",
				"eggCFrameWritesAfterSpawn=false"
			)
			print("[PhysicsAudit] END ONE-JUMP REPORT")
		end
	end)
end

player.CharacterAdded:Connect(function(character: Model)
	task.spawn(auditCharacter, character)
end)

if player.Character then
	task.spawn(auditCharacter, player.Character)
end
