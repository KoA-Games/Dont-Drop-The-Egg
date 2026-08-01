--[[
    IN-PLACE BANANA-SLIP REFINEMENT

    Updates only the existing BasketSlip_Draft KeyframeSequence.
    The K-key preview, BasketHoldPlayer, BasketHold animation, gameplay
    movement, baskets, eggs, and every arm/hand joint remain untouched.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local draftsFolder = ReplicatedStorage:FindFirstChild("AnimationDrafts")
assert(draftsFolder and draftsFolder:IsA("Folder"), "AnimationDrafts folder is missing")

local sequence = draftsFolder:FindFirstChild("BasketSlip_Draft")
assert(sequence and sequence:IsA("KeyframeSequence"), "BasketSlip_Draft is missing")
assert(
    sequence:GetAttribute("BananaSlipPhysicsPass") ~= 1,
    "The banana-slip physics refinement was already applied"
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
    error(("Missing BasketSlip_Draft keyframe at %.2f seconds"):format(time))
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

local function addClonedKeyframe(sourceTime, newTime, newName)
    for _, keyframe in ipairs(sequence:GetKeyframes()) do
        assert(
            math.abs(keyframe.Time - newTime) >= 0.001,
            ("A %.2f-second keyframe already exists"):format(newTime)
        )
    end

    local clone = findKeyframeAt(sourceTime):Clone()
    clone.Name = newName
    clone.Time = newTime
    clone.Parent = sequence
    return clone
end

-- A real banana-slip begins with the shoe shooting forward while momentum
-- leaves the center of mass behind. Root-pose translation here is visual
-- only: it offsets the animated body relative to the HumanoidRootPart and
-- does not alter gameplay movement or the character's world position.
local frames = {
    [0.00] = {
        HumanoidRootPart = {{0,  0.000,  0.000}, {0, 0, 0}},
        LowerTorso       = {{0,  0.000,  0.000}, {-1, 0, 0}},
        UpperTorso       = {{0,  0.000,  0.000}, {-2, 0, 0}},
        Head             = {{0,  0.000,  0.000}, { 2, 0, 0}},
        LeftUpperLeg     = {{0,  0.000,  0.000}, {-4, 0, 0}},
        LeftLowerLeg     = {{0,  0.000,  0.000}, { 5, 0, 0}},
        LeftFoot         = {{0,  0.000,  0.000}, {-1, 0, 0}},
        RightUpperLeg    = {{0,  0.000,  0.000}, { 3, 0, 0}},
        RightLowerLeg    = {{0,  0.000,  0.000}, { 7, 0, 0}},
        RightFoot        = {{0,  0.000,  0.000}, {-2, 0, 0}},
    },
    [0.08] = {
        HumanoidRootPart = {{0, -0.015,  0.045}, {0, 0, 0}},
        LowerTorso       = {{0, -0.010,  0.010}, {-4, 0, 0}},
        UpperTorso       = {{0,  0.000,  0.000}, {-10, 0, 0}},
        Head             = {{0,  0.000,  0.000}, { 8, 0, 0}},
        LeftUpperLeg     = {{0, -0.010, -0.025}, {-14, 0, 0}},
        LeftLowerLeg     = {{0,  0.000,  0.000}, { 4, 0, 0}},
        LeftFoot         = {{0, -0.015, -0.015}, {-7, 0, 0}},
        RightUpperLeg    = {{0, -0.010,  0.000}, { 4, 0, 0}},
        RightLowerLeg    = {{0,  0.000,  0.000}, {14, 0, 0}},
        RightFoot        = {{0, -0.025,  0.010}, {-7, 0, 0}},
    },
    [0.14] = {
        HumanoidRootPart = {{0, -0.040,  0.115}, {0, 0, 0}},
        LowerTorso       = {{0, -0.020,  0.025}, {-7, 0, 1}},
        UpperTorso       = {{0,  0.000,  0.000}, {-20, 0, 2}},
        Head             = {{0,  0.000,  0.000}, {15, 0, -1}},
        LeftUpperLeg     = {{0, -0.020, -0.070}, {-25, 0, 0}},
        LeftLowerLeg     = {{0,  0.000,  0.000}, { 3, 0, 0}},
        LeftFoot         = {{0, -0.025, -0.030}, {-10, 0, 0}},
        RightUpperLeg    = {{0, -0.020,  0.010}, { 6, 0, 0}},
        RightLowerLeg    = {{0,  0.000,  0.000}, {20, 0, 0}},
        RightFoot        = {{0, -0.045,  0.020}, {-10, 0, 0}},
    },
    [0.22] = {
        HumanoidRootPart = {{0, -0.080,  0.255}, {0, 0, 0}},
        LowerTorso       = {{0, -0.035,  0.050}, {-11, 0, 2}},
        UpperTorso       = {{0,  0.000,  0.000}, {-34, 0, 3}},
        Head             = {{0,  0.000,  0.000}, {26, 0, -2}},
        LeftUpperLeg     = {{0, -0.030, -0.125}, {-36, 0, 0}},
        LeftLowerLeg     = {{0,  0.000,  0.000}, { 2, 0, 0}},
        LeftFoot         = {{0, -0.040, -0.040}, {-12, 0, 0}},
        RightUpperLeg    = {{0, -0.025,  0.025}, { 7, 0, 0}},
        RightLowerLeg    = {{0,  0.000,  0.000}, {28, 0, 0}},
        RightFoot        = {{0, -0.070,  0.035}, {-13, 0, 0}},
    },
    [0.34] = {
        HumanoidRootPart = {{0, -0.115,  0.340}, {0, 0, 0}},
        LowerTorso       = {{0, -0.040,  0.065}, {-13, 0, -2}},
        UpperTorso       = {{0,  0.000,  0.000}, {-38, 0, -3}},
        Head             = {{0,  0.000,  0.000}, {29, 0,  2}},
        LeftUpperLeg     = {{0, -0.035, -0.145}, {-40, 0, 0}},
        LeftLowerLeg     = {{0,  0.000,  0.000}, { 3, 0, 0}},
        LeftFoot         = {{0, -0.045, -0.045}, {-13, 0, 0}},
        RightUpperLeg    = {{0, -0.030,  0.035}, { 6, 0, 0}},
        RightLowerLeg    = {{0,  0.000,  0.000}, {31, 0, 0}},
        RightFoot        = {{0, -0.080,  0.045}, {-14, 0, 0}},
    },
    [0.48] = {
        HumanoidRootPart = {{-0.045, -0.090, 0.275}, {0, 0, 0}},
        LowerTorso       = {{ 0.000, -0.030, 0.045}, {-10, 2, -10}},
        UpperTorso       = {{ 0.000,  0.000, 0.000}, {-30, 1, -14}},
        Head             = {{ 0.000,  0.000, 0.000}, {22, 0,   8}},
        LeftUpperLeg     = {{ 0.000, -0.025, -0.105}, {-32, 0,  2}},
        LeftLowerLeg     = {{ 0.000,  0.000, 0.000}, { 7, 0,   0}},
        LeftFoot         = {{ 0.000, -0.035, -0.030}, {-9, 0, -2}},
        RightUpperLeg    = {{ 0.000, -0.025, 0.030}, { 7, 0,  -2}},
        RightLowerLeg    = {{ 0.000,  0.000, 0.000}, {29, 0,   0}},
        RightFoot        = {{ 0.000, -0.065, 0.035}, {-12, 0,  3}},
    },
    [0.58] = {
        HumanoidRootPart = {{0.035, -0.060, 0.180}, {0, 0, 0}},
        LowerTorso       = {{0.000, -0.020, 0.030}, {-7, -1,  6}},
        UpperTorso       = {{0.000,  0.000, 0.000}, {-21, 0,  8}},
        Head             = {{0.000,  0.000, 0.000}, {15, 0, -5}},
        LeftUpperLeg     = {{0.000, -0.020, -0.065}, {-22, 0, -1}},
        LeftLowerLeg     = {{0.000,  0.000, 0.000}, {11, 0,  0}},
        LeftFoot         = {{0.000, -0.025, -0.020}, {-6, 0,  1}},
        RightUpperLeg    = {{0.000, -0.020, 0.020}, { 6, 0,  1}},
        RightLowerLeg    = {{0.000,  0.000, 0.000}, {24, 0,  0}},
        RightFoot        = {{0.000, -0.050, 0.025}, {-9, 0, -2}},
    },
    [0.72] = {
        HumanoidRootPart = {{0, -0.025, 0.065}, {0, 0, 0}},
        LowerTorso       = {{0, -0.010, 0.010}, {-3, 0, -1}},
        UpperTorso       = {{0,  0.000, 0.000}, {-8, 0, -2}},
        Head             = {{0,  0.000, 0.000}, { 5, 0,  1}},
        LeftUpperLeg     = {{0, -0.010, -0.020}, {-10, 0, 0}},
        LeftLowerLeg     = {{0,  0.000, 0.000}, {13, 0, 0}},
        LeftFoot         = {{0, -0.010,  0.000}, {-3, 0, 0}},
        RightUpperLeg    = {{0, -0.010,  0.005}, { 4, 0, 0}},
        RightLowerLeg    = {{0,  0.000,  0.000}, {16, 0, 0}},
        RightFoot        = {{0, -0.020,  0.010}, {-5, 0, 0}},
    },
    [0.90] = {
        HumanoidRootPart = {{0, 0, 0}, {0, 0, 0}},
        LowerTorso       = {{0, 0, 0}, {-1, 0, 0}},
        UpperTorso       = {{0, 0, 0}, {-1, 0, 0}},
        Head             = {{0, 0, 0}, { 1, 0, 0}},
        LeftUpperLeg     = {{0, 0, 0}, {-3, 0, 0}},
        LeftLowerLeg     = {{0, 0, 0}, { 6, 0, 0}},
        LeftFoot         = {{0, 0, 0}, {-1, 0, 0}},
        RightUpperLeg    = {{0, 0, 0}, { 3, 0, 0}},
        RightLowerLeg    = {{0, 0, 0}, { 8, 0, 0}},
        RightFoot        = {{0, 0, 0}, {-2, 0, 0}},
    },
}

addClonedKeyframe(0.08, 0.14, "SlipAcceleration")
addClonedKeyframe(0.48, 0.58, "CounterBalanceWobble")

for time, jointValues in pairs(frames) do
    local keyframe = findKeyframeAt(time)
    for poseName, values in pairs(jointValues) do
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

assert(keyframeCount == 9, ("Expected 9 keyframes, got %d"):format(keyframeCount))
assert(math.abs(lastTime - 0.90) < 0.001, "Animation duration must remain 0.90 seconds")

sequence.Loop = false
sequence.Priority = Enum.AnimationPriority.Action2
sequence:SetAttribute("BananaSlipPhysicsPass", 1)
sequence:SetAttribute("ButtFallBranchReadyAt", 0.34)
sequence:SetAttribute("VisualBackwardTravelStuds", 0.34)

print(
    "[BasketSlipDraft] Banana-slip physics pass applied in place: "
        .. "9 keyframes, 0.90s, 0.34-stud visual backward travel, "
        .. "butt-fall branch ready at 0.34s, no arm poses."
)
