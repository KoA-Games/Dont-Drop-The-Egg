-- Corrects the pitch-axis direction of the existing BasketSlip_Draft.
-- No keyframes are rebuilt, added, removed, or retimed.
-- Positions, sideways wobble, K preview, arms, BasketHold, and gameplay remain untouched.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local draftsFolder = ReplicatedStorage:FindFirstChild("AnimationDrafts")
assert(draftsFolder and draftsFolder:IsA("Folder"), "AnimationDrafts folder is missing")

local sequence = draftsFolder:FindFirstChild("BasketSlip_Draft")
assert(sequence and sequence:IsA("KeyframeSequence"), "BasketSlip_Draft is missing")
assert(sequence:GetAttribute("PitchAxisCorrectionPass") ~= 1, "Pitch-axis correction already applied")

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

local function setPitch(keyframe, poseName, pitchDegrees)
    local pose = findPose(keyframe, poseName)
    local position = pose.CFrame.Position
    local _, yaw, roll = pose.CFrame:ToOrientation()

    pose.CFrame = CFrame.new(position)
        * CFrame.Angles(math.rad(pitchDegrees), yaw, roll)
    pose.Weight = 1
    pose.EasingStyle = Enum.PoseEasingStyle.Cubic
    pose.EasingDirection = Enum.PoseEasingDirection.InOut
end

-- Positive torso pitch is backward for this R15 rig in the recorded side view.
-- Positive leading-upper-leg pitch sends that shoe toward the facing direction.
local correctedPitch = {
    [0.00] = {
        LowerTorso = 1, UpperTorso = 2, Head = -2,
        LeftUpperLeg = 4, LeftLowerLeg = -5, LeftFoot = 1,
        RightUpperLeg = -3, RightLowerLeg = -7, RightFoot = 2,
    },
    [0.08] = {
        LowerTorso = 4, UpperTorso = 10, Head = -8,
        LeftUpperLeg = 14, LeftLowerLeg = -4, LeftFoot = 7,
        RightUpperLeg = -4, RightLowerLeg = -14, RightFoot = 7,
    },
    [0.14] = {
        LowerTorso = 7, UpperTorso = 20, Head = -15,
        LeftUpperLeg = 25, LeftLowerLeg = -3, LeftFoot = 10,
        RightUpperLeg = -6, RightLowerLeg = -20, RightFoot = 10,
    },
    [0.22] = {
        LowerTorso = 12, UpperTorso = 38, Head = -29,
        LeftUpperLeg = 38, LeftLowerLeg = -2, LeftFoot = 12,
        RightUpperLeg = -7, RightLowerLeg = -28, RightFoot = 13,
    },
    [0.34] = {
        LowerTorso = 14, UpperTorso = 42, Head = -31,
        LeftUpperLeg = 42, LeftLowerLeg = -3, LeftFoot = 13,
        RightUpperLeg = -6, RightLowerLeg = -31, RightFoot = 14,
    },
    [0.48] = {
        LowerTorso = 10, UpperTorso = 30, Head = -22,
        LeftUpperLeg = 32, LeftLowerLeg = -7, LeftFoot = 9,
        RightUpperLeg = -7, RightLowerLeg = -29, RightFoot = 12,
    },
    [0.58] = {
        LowerTorso = 7, UpperTorso = 21, Head = -15,
        LeftUpperLeg = 22, LeftLowerLeg = -11, LeftFoot = 6,
        RightUpperLeg = -6, RightLowerLeg = -24, RightFoot = 9,
    },
    [0.72] = {
        LowerTorso = 3, UpperTorso = 8, Head = -5,
        LeftUpperLeg = 10, LeftLowerLeg = -13, LeftFoot = 3,
        RightUpperLeg = -4, RightLowerLeg = -16, RightFoot = 5,
    },
    [0.90] = {
        LowerTorso = 1, UpperTorso = 1, Head = -1,
        LeftUpperLeg = 3, LeftLowerLeg = -6, LeftFoot = 1,
        RightUpperLeg = -3, RightLowerLeg = -8, RightFoot = 2,
    },
}

for time, posePitches in pairs(correctedPitch) do
    local keyframe = findKeyframeAt(time)
    for poseName, pitchDegrees in pairs(posePitches) do
        setPitch(keyframe, poseName, pitchDegrees)
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

sequence:SetAttribute("PitchAxisCorrectionPass", 1)
print(
    "[BasketSlipDraft] Pitch axis corrected: torso falls backward, "
        .. "leading foot shoots forward, support knee folds underneath, no arm poses."
)
