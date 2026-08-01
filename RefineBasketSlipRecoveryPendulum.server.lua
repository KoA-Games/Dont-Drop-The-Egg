-- Refines only the recovery section of the existing BasketSlip_Draft.
-- The slip onset and maximum pose through 0.34 seconds remain unchanged.
-- Arms, BasketHold, K preview, gameplay movement, baskets, and eggs are untouched.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local draftsFolder = ReplicatedStorage:FindFirstChild("AnimationDrafts")
assert(draftsFolder and draftsFolder:IsA("Folder"), "AnimationDrafts folder is missing")

local sequence = draftsFolder:FindFirstChild("BasketSlip_Draft")
assert(sequence and sequence:IsA("KeyframeSequence"), "BasketSlip_Draft is missing")
assert(
    sequence:GetAttribute("RecoveryPendulumPass") ~= 1,
    "The recovery-pendulum pass was already applied"
)

local function transform(position, rotationDegrees)
    return CFrame.new(position[1], position[2], position[3])
        * CFrame.Angles(
            math.rad(rotationDegrees[1]),
            math.rad(rotationDegrees[2]),
            math.rad(rotationDegrees[3])
        )
end

local function findKeyframeAt(time)
    for _, keyframe in ipairs(sequence:GetKeyframes()) do
        if math.abs(keyframe.Time - time) < 0.001 then
            return keyframe
        end
    end
    error(("Missing keyframe at %.2f seconds"):format(time))
end

local function findPose(keyframe, poseName)
    for _, descendant in ipairs(keyframe:GetDescendants()) do
        if descendant:IsA("Pose") and descendant.Name == poseName then
            return descendant
        end
    end
    error(("%s is missing pose %s"):format(keyframe.Name, poseName))
end

local function setPose(keyframe, poseName, position, rotationDegrees)
    local pose = findPose(keyframe, poseName)
    pose.CFrame = transform(position, rotationDegrees)
    pose.Weight = 1
    pose.EasingStyle = Enum.PoseEasingStyle.Cubic
    pose.EasingDirection = Enum.PoseEasingDirection.InOut
end

-- Keep references before retiming the existing recovery keyframes.
local forwardCatch = findKeyframeAt(0.48)
local firstRebound = findKeyframeAt(0.58)
local secondRebound = findKeyframeAt(0.72)
local balanceCatch = findKeyframeAt(0.90)

for _, keyframe in ipairs(sequence:GetKeyframes()) do
    assert(
        math.abs(keyframe.Time - 1.10) >= 0.001,
        "A 1.10-second settled keyframe already exists"
    )
end

forwardCatch.Name = "ForwardCounterSwing"

firstRebound.Name = "BackwardBalanceRebound"
firstRebound.Time = 0.62

secondRebound.Name = "SmallerForwardWobble"
secondRebound.Time = 0.76

balanceCatch.Name = "FinalBalanceCatch"
balanceCatch.Time = 0.92

local settled = balanceCatch:Clone()
settled.Name = "SettledReturnToRun"
settled.Time = 1.10
settled.Parent = sequence

local recoveryFrames = {
    -- Momentum carries the torso past neutral and forward after the backward slip.
    [0.48] = {
        HumanoidRootPart = {{-0.035, -0.075, 0.220}, { 0, 0,  0}},
        LowerTorso       = {{ 0.000, -0.025, 0.035}, {-7, 1, -7}},
        UpperTorso       = {{ 0.000,  0.000, 0.000}, {-22, 1, -9}},
        Head             = {{ 0.000,  0.000, 0.000}, { 16, 0,  6}},
        LeftUpperLeg     = {{ 0.000, -0.020, -0.060}, { 16, 0,  1}},
        LeftLowerLeg     = {{ 0.000,  0.000, 0.000}, {-13, 0,  0}},
        LeftFoot         = {{ 0.000, -0.025, -0.020}, {  5, 0, -1}},
        RightUpperLeg    = {{ 0.000, -0.025, 0.025}, { -5, 0, -1}},
        RightLowerLeg    = {{ 0.000,  0.000, 0.000}, {-24, 0,  0}},
        RightFoot        = {{ 0.000, -0.060, 0.030}, { 10, 0,  2}},
    },
    -- First rebound: the body passes back through neutral with the opposite roll.
    [0.62] = {
        HumanoidRootPart = {{0.045, -0.055, 0.145}, { 0,  0,  0}},
        LowerTorso       = {{0.000, -0.018, 0.025}, { 5, -1,  8}},
        UpperTorso       = {{0.000,  0.000, 0.000}, {14,  0, 10}},
        Head             = {{0.000,  0.000, 0.000}, {-10, 0, -7}},
        LeftUpperLeg     = {{0.000, -0.018, -0.035}, { 6, 0, -1}},
        LeftLowerLeg     = {{0.000,  0.000, 0.000}, {-18, 0, 0}},
        LeftFoot         = {{0.000, -0.020, -0.010}, { 5, 0, 1}},
        RightUpperLeg    = {{0.000, -0.018, 0.018}, {-5, 0, 1}},
        RightLowerLeg    = {{0.000,  0.000, 0.000}, {-15, 0, 0}},
        RightFoot        = {{0.000, -0.045, 0.020}, { 7, 0, -2}},
    },
    -- Second wobble: a smaller forward overshoot in the original roll direction.
    [0.76] = {
        HumanoidRootPart = {{-0.025, -0.035, 0.080}, { 0, 0,  0}},
        LowerTorso       = {{ 0.000, -0.012, 0.015}, {-3, 0, -5}},
        UpperTorso       = {{ 0.000,  0.000, 0.000}, {-8, 0, -6}},
        Head             = {{ 0.000,  0.000, 0.000}, { 6, 0,  4}},
        LeftUpperLeg     = {{ 0.000, -0.012, -0.020}, {-6, 0,  0}},
        LeftLowerLeg     = {{ 0.000,  0.000, 0.000}, {-12, 0, 0}},
        LeftFoot         = {{ 0.000, -0.012, 0.000}, { 3, 0, 0}},
        RightUpperLeg    = {{ 0.000, -0.012, 0.010}, { 3, 0, 0}},
        RightLowerLeg    = {{ 0.000,  0.000, 0.000}, {-12, 0, 0}},
        RightFoot        = {{ 0.000, -0.028, 0.012}, { 5, 0, 0}},
    },
    -- Last small correction before normal running resumes.
    [0.92] = {
        HumanoidRootPart = {{0.008, -0.012, 0.025}, { 0, 0, 0}},
        LowerTorso       = {{0.000, -0.004, 0.005}, { 1, 0,  2}},
        UpperTorso       = {{0.000,  0.000, 0.000}, { 4, 0,  3}},
        Head             = {{0.000,  0.000, 0.000}, {-3, 0, -2}},
        LeftUpperLeg     = {{0.000, -0.004, -0.005}, { 3, 0, 0}},
        LeftLowerLeg     = {{0.000,  0.000, 0.000}, {-8, 0, 0}},
        LeftFoot         = {{0.000, -0.004, 0.000}, { 2, 0, 0}},
        RightUpperLeg    = {{0.000, -0.004, 0.004}, {-2, 0, 0}},
        RightLowerLeg    = {{0.000,  0.000, 0.000}, {-9, 0, 0}},
        RightFoot        = {{0.000, -0.010, 0.004}, { 3, 0, 0}},
    },
    [1.10] = {
        HumanoidRootPart = {{0, 0, 0}, {0, 0, 0}},
        LowerTorso       = {{0, 0, 0}, { 0, 0, 0}},
        UpperTorso       = {{0, 0, 0}, { 0, 0, 0}},
        Head             = {{0, 0, 0}, { 0, 0, 0}},
        LeftUpperLeg     = {{0, 0, 0}, { 1, 0, 0}},
        LeftLowerLeg     = {{0, 0, 0}, {-4, 0, 0}},
        LeftFoot         = {{0, 0, 0}, { 0, 0, 0}},
        RightUpperLeg    = {{0, 0, 0}, {-1, 0, 0}},
        RightLowerLeg    = {{0, 0, 0}, {-5, 0, 0}},
        RightFoot        = {{0, 0, 0}, { 1, 0, 0}},
    },
}

for time, poseValues in pairs(recoveryFrames) do
    local keyframe = findKeyframeAt(time)
    for poseName, values in pairs(poseValues) do
        setPose(keyframe, poseName, values[1], values[2])
    end
end

local forbiddenArmPoses = {
    LeftUpperArm = true,
    LeftLowerArm = true,
    LeftHand = true,
    RightUpperArm = true,
    RightLowerArm = true,
    RightHand = true,
}

local keyframeCount = 0
local lastTime = 0
for _, keyframe in ipairs(sequence:GetKeyframes()) do
    keyframeCount += 1
    lastTime = math.max(lastTime, keyframe.Time)

    for _, descendant in ipairs(keyframe:GetDescendants()) do
        if descendant:IsA("Pose") then
            assert(
                not forbiddenArmPoses[descendant.Name],
                ("Forbidden arm pose found: %s"):format(descendant.Name)
            )
        end
    end
end

assert(keyframeCount == 10, ("Expected 10 keyframes, got %d"):format(keyframeCount))
assert(math.abs(lastTime - 1.10) < 0.001, "Animation duration must be 1.10 seconds")

sequence:SetAttribute("RecoveryPendulumPass", 1)
sequence:SetAttribute("RecoveryWobbleCount", 3)
print(
    "[BasketSlipDraft] Recovery pendulum applied: backward max -> forward catch -> "
        .. "backward rebound -> smaller forward wobble -> balance catch -> settled at 1.10s; no arm poses."
)
