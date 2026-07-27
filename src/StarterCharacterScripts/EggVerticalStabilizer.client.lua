--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local character = script.Parent

-- Studio-only A/B flag. Change this value, then restart Play.
local VERTICAL_STABILIZER_ENABLED = true

-- Airborne eggs receive no extra force, so their arc always uses the normal,
-- constant Workspace gravity. Stabilization is blended in only close to the
-- basket floor where the welded basket can otherwise deliver a harsh impulse.
local FLOOR_RESTING_CENTER_Y = 0.35
local FLOOR_INFLUENCE_END_Y = 0.72
local UPWARD_RELATIVE_SPEED_START = 2.5
local DOWNWARD_RELATIVE_SPEED_START = 6
local UPWARD_RELATIVE_DAMPING = 4
local LANDING_DAMPING = 1.5
local BASKET_UPWARD_ACCELERATION_START = 25
local BASKET_ACCEL_COMPENSATION = 0.30
local ACCELERATION_SMOOTHING = 0.20
local MAX_BASKET_ACCELERATION = 120
local MAX_EXTRA_VERTICAL_ACCELERATION = 120

-- A Roblox character receives its jump velocity immediately, but loose eggs
-- receive that motion through several solver contacts (floor -> lower eggs ->
-- upper eggs). Match the basket's takeoff velocity with one physical impulse so
-- every egg begins fast at the same instant, then slows only under gravity.
local TAKEOFF_WINDOW = 0.18
local MIN_BASKET_TAKEOFF_VELOCITY = 8
-- Small physical launch speed above the basket makes the loose eggs visibly
-- pop instead of being carried upward at exactly the same speed as the camera.
-- Gravity remains unchanged after this one takeoff impulse.
local TAKEOFF_LIFT_BONUS = 6
local MAX_TAKEOFF_DELTA_VELOCITY = 65
local TAKEOFF_MAX_LOCAL_Y = 1.40

local VERTICAL_FORCE_NAME = "VerticalStabilizerForce"
local INITIALIZATION_FRAMES = 5
local MAX_TRACKED_DELTA_TIME = 0.1
local TELEPORT_DISTANCE = 12

-- Runtime basket outer footprint plus a small center margin. Height is
-- deliberately not capped: an egg rising above the open rim during a jump must
-- not switch gravity modes in the middle of its trajectory. It stops being
-- carried as soon as it clears a side or falls below the floor.
local INSIDE_HALF_WIDTH_X = 1.25
local INSIDE_HALF_DEPTH_Z = 0.95
local INSIDE_MIN_Y = -0.25

type TrackedEgg = {
	collider: BasePart,
	force: VectorForce,
	wasInside: boolean,
}

local trackedEggs: { [BasePart]: TrackedEgg } = {}
local connections: { RBXScriptConnection } = {}
local cleaning = false

local function smoothingAlpha(referenceAlpha: number, deltaTime: number): number
	return 1 - math.pow(1 - referenceAlpha, deltaTime * 60)
end

local function disableForce(tracked: TrackedEgg)
	tracked.force.Force = Vector3.zero
	tracked.force.Enabled = false
end

local function isOwnedEggModel(instance: Instance): boolean
	return instance:IsA("Model")
		and instance:GetAttribute("EggOwnerUserId") == player.UserId
		and instance.Name:match("^BasketEgg_%d+$") ~= nil
end

local function tryTrackEgg(instance: Instance)
	if not isOwnedEggModel(instance) then
		return
	end

	local collider = instance:FindFirstChild("Collider")
	if not collider or not collider:IsA("BasePart") or trackedEggs[collider] then
		return
	end

	local verticalForce = collider:FindFirstChild(VERTICAL_FORCE_NAME)
	if not verticalForce or not verticalForce:IsA("VectorForce") then
		warn("[EggVerticalStabilizer] Missing VectorForce on " .. instance.Name)
		return
	end

	local tracked: TrackedEgg = {
		collider = collider,
		force = verticalForce,
		wasInside = false,
	}
	trackedEggs[collider] = tracked
	disableForce(tracked)

	table.insert(connections, collider.Destroying:Connect(function()
		trackedEggs[collider] = nil
	end))
end

local function getBasketLocalPosition(
	collider: BasePart,
	basketReference: BasePart
): Vector3
	return basketReference.CFrame:PointToObjectSpace(collider.Position)
end

local function isInsideBasket(localPosition: Vector3): boolean
	return math.abs(localPosition.X) <= INSIDE_HALF_WIDTH_X
		and math.abs(localPosition.Z) <= INSIDE_HALF_DEPTH_Z
		and localPosition.Y >= INSIDE_MIN_Y
end

local function smoothStep(value: number): number
	local clamped = math.clamp(value, 0, 1)
	return clamped * clamped * (3 - 2 * clamped)
end

local function getFloorInfluence(localY: number): number
	local influenceRange = FLOOR_INFLUENCE_END_Y - FLOOR_RESTING_CENTER_Y
	local heightAlpha = (localY - FLOOR_RESTING_CENTER_Y) / influenceRange
	return 1 - smoothStep(heightAlpha)
end

local basket = character:WaitForChild("Basket", 15)
if not basket or not basket:IsA("Model") then
	warn("[EggVerticalStabilizer] Runtime Basket was not available")
	return
end

local basketReference = basket:FindFirstChild("Bottom")
if not basketReference or not basketReference:IsA("BasePart") then
	warn("[EggVerticalStabilizer] Basket.Bottom was not available")
	return
end

local humanoid = character:FindFirstChildOfClass("Humanoid")
if not humanoid then
	warn("[EggVerticalStabilizer] Humanoid was not available")
	return
end

for _, instance in Workspace:GetChildren() do
	tryTrackEgg(instance)
end
table.insert(connections, Workspace.ChildAdded:Connect(tryTrackEgg))

local previousBasketVerticalVelocity = basketReference.AssemblyLinearVelocity.Y
local previousBasketPosition = basketReference.Position
local smoothedBasketVerticalAcceleration = 0
local initializationFrames = INITIALIZATION_FRAMES
local clampedAccelerationEvents = 0
local takeoffImpulseEvents = 0
local pendingTakeoffDeadline = 0

local function cleanUp()
	if cleaning then
		return
	end
	cleaning = true

	for _, tracked in trackedEggs do
		if tracked.force.Parent then
			disableForce(tracked)
		end
	end
	for _, connection in connections do
		connection:Disconnect()
	end

	print(
		"[EggVerticalStabilizer] Stopped",
		"clampedAccelerationEvents=" .. tostring(clampedAccelerationEvents),
		"takeoffImpulseEvents=" .. tostring(takeoffImpulseEvents)
	)
end

table.insert(connections, character.Destroying:Connect(cleanUp))
table.insert(connections, basket.Destroying:Connect(cleanUp))
table.insert(connections, humanoid.StateChanged:Connect(function(
	_previousState: Enum.HumanoidStateType,
	newState: Enum.HumanoidStateType
)
	if newState == Enum.HumanoidStateType.Jumping then
		pendingTakeoffDeadline = os.clock() + TAKEOFF_WINDOW
	end
end))

table.insert(connections, RunService.PreSimulation:Connect(function(deltaTime: number)
	if cleaning or not basketReference.Parent then
		cleanUp()
		return
	end

	local trackedDeltaTime = math.min(deltaTime, MAX_TRACKED_DELTA_TIME)
	local basketVerticalVelocity = basketReference.AssemblyLinearVelocity.Y
	local basketPosition = basketReference.Position
	local teleported = (basketPosition - previousBasketPosition).Magnitude > TELEPORT_DISTANCE
		or deltaTime > 0.25

	if teleported then
		previousBasketVerticalVelocity = basketVerticalVelocity
		smoothedBasketVerticalAcceleration = 0
		initializationFrames = INITIALIZATION_FRAMES
	else
		local rawBasketVerticalAcceleration =
			(basketVerticalVelocity - previousBasketVerticalVelocity)
			/ math.max(trackedDeltaTime, 1 / 240)

		if initializationFrames > 0 then
			initializationFrames -= 1
			rawBasketVerticalAcceleration = 0
		end

		local clampedBasketVerticalAcceleration = math.clamp(
			rawBasketVerticalAcceleration,
			-MAX_BASKET_ACCELERATION,
			MAX_BASKET_ACCELERATION
		)
		if clampedBasketVerticalAcceleration ~= rawBasketVerticalAcceleration then
			clampedAccelerationEvents += 1
		end

		local alpha = smoothingAlpha(ACCELERATION_SMOOTHING, trackedDeltaTime)
		smoothedBasketVerticalAcceleration +=
			(clampedBasketVerticalAcceleration - smoothedBasketVerticalAcceleration) * alpha
		previousBasketVerticalVelocity = basketVerticalVelocity
	end
	previousBasketPosition = basketPosition

	-- Transfer the character controller's instantaneous takeoff velocity to all
	-- five loose assemblies at once. ApplyImpulse is a physical impulse; it does
	-- not assign velocity, position, or CFrame and it never runs every frame.
	if pendingTakeoffDeadline > 0 then
		if os.clock() > pendingTakeoffDeadline then
			pendingTakeoffDeadline = 0
		elseif basketVerticalVelocity >= MIN_BASKET_TAKEOFF_VELOCITY then
			local impulseCount = 0
			local targetTakeoffVelocity = basketVerticalVelocity + TAKEOFF_LIFT_BONUS
			for collider in trackedEggs do
				if collider.Parent then
					local localPosition = getBasketLocalPosition(collider, basketReference)
					if isInsideBasket(localPosition)
						and localPosition.Y <= TAKEOFF_MAX_LOCAL_Y
					then
						local deltaVelocity = math.clamp(
							targetTakeoffVelocity - collider.AssemblyLinearVelocity.Y,
							0,
							MAX_TAKEOFF_DELTA_VELOCITY
						)
						if deltaVelocity > 0 then
							collider:ApplyImpulse(Vector3.new(
								0,
								collider.AssemblyMass * deltaVelocity,
								0
							))
							impulseCount += 1
						end
					end
				end
			end
			pendingTakeoffDeadline = 0
			takeoffImpulseEvents += 1
			print(
				"[EggVerticalStabilizer] TakeoffImpulse",
				"eggs=" .. tostring(impulseCount),
				"basketVelocityY=" .. string.format("%.2f", basketVerticalVelocity),
				"targetVelocityY=" .. string.format("%.2f", targetTakeoffVelocity)
			)
		end
	end

	for collider, tracked in trackedEggs do
		if not collider.Parent or not tracked.force.Parent then
			trackedEggs[collider] = nil
			continue
		end

		local localPosition = getBasketLocalPosition(collider, basketReference)
		local insideBasket = isInsideBasket(localPosition)
		if insideBasket ~= tracked.wasInside then
			print(
				"[EggVerticalStabilizer] BasketState",
				collider.Parent and collider.Parent.Name or collider.Name,
				insideBasket and "inside" or "outside"
			)
		end
		tracked.wasInside = insideBasket
		if not VERTICAL_STABILIZER_ENABLED or not insideBasket then
			disableForce(tracked)
			continue
		end

		local eggVerticalVelocity = collider.AssemblyLinearVelocity.Y
		local relativeVerticalVelocity =
			eggVerticalVelocity - basketVerticalVelocity
		local floorInfluence = getFloorInfluence(localPosition.Y)

		-- Only suppress excess motion relative to the basket. Once the egg has
		-- left the floor influence zone, every component below becomes zero and
		-- the egg follows an ordinary, continuous gravity parabola.
		local upwardRelativeDamping = -math.max(
			relativeVerticalVelocity - UPWARD_RELATIVE_SPEED_START,
			0
		) * UPWARD_RELATIVE_DAMPING
		-- Landing assistance is allowed only while the egg is genuinely moving
		-- downward in world space. Previously, an ascending egg that merely lagged
		-- behind the rising basket could receive an upward force here, producing
		-- the visibly impossible slow-then-fast ascent.
		local landingDamping = 0
		if eggVerticalVelocity < 0 then
			landingDamping = math.max(
				-relativeVerticalVelocity - DOWNWARD_RELATIVE_SPEED_START,
				0
			) * LANDING_DAMPING
		end
		local upwardBasketShock = math.max(
			smoothedBasketVerticalAcceleration - BASKET_UPWARD_ACCELERATION_START,
			0
		)
		local basketShockCompensation =
			-upwardBasketShock * BASKET_ACCEL_COMPENSATION

		local totalVerticalAcceleration = floorInfluence * (
			upwardRelativeDamping
				+ landingDamping
				+ basketShockCompensation
		)
		if eggVerticalVelocity >= 0 then
			-- Takeoff already transferred the basket velocity with one impulse.
			-- Do not press a rising egg back into the basket: zero extra force means
			-- its upward speed now decreases naturally under Workspace gravity alone.
			totalVerticalAcceleration = 0
		end
		totalVerticalAcceleration = math.clamp(
			totalVerticalAcceleration,
			-MAX_EXTRA_VERTICAL_ACCELERATION,
			MAX_EXTRA_VERTICAL_ACCELERATION
		)

		tracked.force.RelativeTo = Enum.ActuatorRelativeTo.World
		tracked.force.ApplyAtCenterOfMass = true
		tracked.force.Force = Vector3.new(
			0,
			collider.AssemblyMass * totalVerticalAcceleration,
			0
		)
		tracked.force.Enabled = true
	end
end))

print(
	"[EggVerticalStabilizer] Started",
	"enabled=" .. tostring(VERTICAL_STABILIZER_ENABLED),
	"airborneForce=0",
	"takeoffImpulse=true",
	"floorInfluenceEndY=" .. tostring(FLOOR_INFLUENCE_END_Y),
	"upwardRelativeDamping=" .. tostring(UPWARD_RELATIVE_DAMPING),
	"basketAccelerationCompensation=" .. tostring(BASKET_ACCEL_COMPENSATION)
)
