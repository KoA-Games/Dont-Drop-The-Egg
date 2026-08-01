--[[
    ONE-SHOT REFINEMENT FOR THE EXISTING BasketSlip_Draft

    This script edits the existing KeyframeSequence in place. It does not
    recreate the sequence, touch the K-key preview, or modify any gameplay,
    egg, basket, movement, BasketHoldPlayer, or BasketHold animation objects.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local draftsFolder = ReplicatedStorage:FindFirstChild("AnimationDrafts")
assert(draftsFolder and draftsFolder:IsA("Folder"), "AnimationDrafts folder is missing")

local sequence = draftsFolder:FindFirstChild("BasketSlip_Draft")
assert(sequence and sequence:IsA("KeyframeSequence"), "BasketSlip_Draft is missing")
assert(sequence:GetAttribute("BasketSlipRefinementPass") ~= 1, "The one-shot refinement was already applied")

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

local refinedFrames = {
    [0.00] = {
        LowerTorso    = {{0,  0.000, 0.000}, {-2, 0,  0}},
        UpperTorso    = {{0,  0.000, 0.000}, {-4, 0,  0}},
        Head          = {{0,  0.000, 0.000}, { 3, 0,  0}},
        LeftUpperLeg  = {{0,  0.000, 0.000}, {-10, 0, 0}},
        LeftLowerLeg  = {{0,  0.000, 0.000}, { 8, 0,  0}},
        LeftFoot      = {{0,  0.000, 0.000}, {-1, 0,  0}},
        RightUpperLeg = {{0,  0.000, 0.000}, { 5, 0,  0}},
        RightLowerLeg = {{0,  0.000, 0.000}, {12, 0,  0}},
        RightFoot     = {{0,  0.000, 0.000}, {-2, 0,  0}},
    },
    [0.08] = {
        LowerTorso    = {{0, -0.030, 0.010}, {-5, 0,  0}},
        UpperTorso    = {{0,  0.000, 0.000}, {-17, 0, 0}},
        Head          = {{0,  0.000, 0.000}, {12, 0,  0}},
        LeftUpperLeg  = {{0,  0.000, 0.000}, {-30, 0, 0}},
        LeftLowerLeg  = {{0,  0.000, 0.000}, { 5, 0,  0}},
        LeftFoot      = {{0,  0.000, 0.000}, {-9, 0,  0}},
        RightUpperLeg = {{0,  0.000, 0.000}, { 7, 0,  0}},
        RightLowerLeg = {{0,  0.000, 0.000}, {28, 0,  0}},
        RightFoot     = {{0,  0.000, 0.000}, {-14, 0, 0}},
    },
    [0.22] = {
        LowerTorso    = {{0, -0.070, 0.030}, {-8, 0,  2}},
        UpperTorso    = {{0,  0.000, 0.000}, {-36, 0, 3}},
        Head          = {{0,  0.000, 0.000}, {26, 0, -2}},
        LeftUpperLeg  = {{0,  0.000, 0.000}, {-46, 0, 0}},
        LeftLowerLeg  = {{0,  0.000, 0.000}, { 4, 0,  0}},
        LeftFoot      = {{0,  0.000, 0.000}, {-12, 0, 0}},
        RightUpperLeg = {{0,  0.000, 0.000}, { 9, 0,  0}},
        RightLowerLeg = {{0,  0.000, 0.000}, {40, 0,  0}},
        RightFoot     = {{0,  0.000, 0.000}, {-22, 0, 0}},
    },
    [0.48] = {
        LowerTorso    = {{0, -0.055, 0.020}, {-6, 3, -11}},
        UpperTorso    = {{0,  0.000, 0.000}, {-28, 1, -13}},
        Head          = {{0,  0.000, 0.000}, {20, 0,   7}},
        LeftUpperLeg  = {{0,  0.000, 0.000}, {-34, 0,  2}},
        LeftLowerLeg  = {{0,  0.000, 0.000}, {10, 0,   0}},
        LeftFoot      = {{0,  0.000, 0.000}, {-8, 0,  -2}},
        RightUpperLeg = {{0,  0.000, 0.000}, { 7, 0,  -2}},
        RightLowerLeg = {{0,  0.000, 0.000}, {38, 0,   0}},
        RightFoot     = {{0,  0.000, 0.000}, {-20, 0,  3}},
    },
    [0.72] = {
        LowerTorso    = {{0, -0.020, 0.005}, {-3, 0, -1}},
        UpperTorso    = {{0,  0.000, 0.000}, {-11, 0, -2}},
        Head          = {{0,  0.000, 0.000}, { 7, 0,  1}},
        LeftUpperLeg  = {{0,  0.000, 0.000}, {-15, 0, 0}},
        LeftLowerLeg  = {{0,  0.000, 0.000}, {17, 0,  0}},
        LeftFoot      = {{0,  0.000, 0.000}, {-3, 0,  0}},
        RightUpperLeg = {{0,  0.000, 0.000}, { 4, 0,  0}},
        RightLowerLeg = {{0,  0.000, 0.000}, {18, 0,  0}},
        RightFoot     = {{0,  0.000, 0.000}, {-7, 0,  0}},
    },
    [0.90] = {
        LowerTorso    = {{0, 0.000, 0.000}, {-1, 0, 0}},
        UpperTorso    = {{0, 0.000, 0.000}, {-1, 0, 0}},
        Head          = {{0, 0.000, 0.000}, { 1, 0, 0}},
        LeftUpperLeg  = {{0, 0.000, 0.000}, {-4, 0, 0}},
        LeftLowerLeg  = {{0, 0.000, 0.000}, { 7, 0, 0}},
        LeftFoot      = {{0, 0.000, 0.000}, {-1, 0, 0}},
        RightUpperLeg = {{0, 0.000, 0.000}, { 3, 0, 0}},
        RightLowerLeg = {{0, 0.000, 0.000}, { 9, 0, 0}},
        RightFoot     = {{0, 0.000, 0.000}, {-2, 0, 0}},
    },
}

for time, jointValues in pairs(refinedFrames) do
    local keyframe = findKeyframeAt(time)
    for poseName, values in pairs(jointValues) do
        setPose(keyframe, poseName, values[1], values[2])
    end
end

-- Clone the corrected 0.22 maximum pose, then retain roughly 90% of it
-- through 0.34 seconds. This produces a 0.12-second readable maximum hold.
assert(not pcall(findKeyframeAt, 0.34), "A 0.34-second hold keyframe already exists")
local holdKeyframe = findKeyframeAt(0.22):Clone()
holdKeyframe.Name = "MaximumPoseHold"
holdKeyframe.Time = 0.34
holdKeyframe.Parent = sequence

local holdValues = {
    LowerTorso    = {{0, -0.065, 0.028}, {-7, 0, -2}},
    UpperTorso    = {{0,  0.000, 0.000}, {-33, 0, -3}},
    Head          = {{0,  0.000, 0.000}, {24, 0,  2}},
    LeftUpperLeg  = {{0,  0.000, 0.000}, {-43, 0, 0}},
    LeftLowerLeg  = {{0,  0.000, 0.000}, { 5, 0,  0}},
    LeftFoot      = {{0,  0.000, 0.000}, {-11, 0, 0}},
    RightUpperLeg = {{0,  0.000, 0.000}, { 8, 0,  0}},
    RightLowerLeg = {{0,  0.000, 0.000}, {39, 0,  0}},
    RightFoot     = {{0,  0.000, 0.000}, {-21, 0, 0}},
}
for poseName, values in pairs(holdValues) do
    setPose(holdKeyframe, poseName, values[1], values[2])
end

local forbiddenArmPoses = {
    LeftUpperArm = true,
    LeftLowerArm = true,
    LeftHand = true,
    RightUpperArm = true,
    RightLowerArm = true,
    RightHand = true,
}

local lastTime = 0
local keyframeCount = 0
for _, keyframe in ipairs(sequence:GetKeyframes()) do
    keyframeCount += 1
    lastTime = math.max(lastTime, keyframe.Time)

    local rootPose = findPose(keyframe, "HumanoidRootPart")
    assert(rootPose.CFrame:FuzzyEq(CFrame.identity, 0.00001), "Root motion must remain identity")

    for _, descendant in ipairs(keyframe:GetDescendants()) do
        if descendant:IsA("Pose") then
            assert(
                not forbiddenArmPoses[descendant.Name],
                ("Forbidden arm pose found: %s"):format(descendant.Name)
            )
        end
    end
end

assert(keyframeCount == 7, ("Expected 7 keyframes after refinement, got %d"):format(keyframeCount))
assert(math.abs(lastTime - 0.90) < 0.001, "Animation duration must remain 0.90 seconds")

sequence.Loop = false
sequence.Priority = Enum.AnimationPriority.Action2
sequence:SetAttribute("BasketSlipRefinementPass", 1)
sequence:SetAttribute("MaximumPoseHoldSeconds", 0.12)

print("[BasketSlipDraft] One correction pass applied: 7 keyframes, 0.90s, 0.12s max-pose hold, no arm poses.")
