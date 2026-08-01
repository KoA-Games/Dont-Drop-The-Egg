-- Replaces the spring-like recovery of the existing BasketSlip_Draft.
-- The slip onset and maximum backward pose through 0.34 seconds are untouched.
-- Recovery now moves forward once, stays forward while wobbling sideways,
-- then gradually settles upright. Arms and gameplay systems remain untouched.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local draftsFolder = ReplicatedStorage:FindFirstChild("AnimationDrafts")
assert(draftsFolder and draftsFolder:IsA("Folder"), "AnimationDrafts folder is missing")

local sequence = draftsFolder:FindFirstChild("BasketSlip_Draft")
assert(sequence and sequence:IsA("KeyframeSequence"), "BasketSlip_Draft is missing")
assert(sequence:GetAttribute("HumanRecoveryPass") ~= 1, "Human recovery was already applied")

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

-- Retain the same five recovery keyframes, but give the body enough time to
-- travel forward and make several imperfect balance corrections.
local forwardCatch = findKeyframeAt(0.48)
local rightWobble = findKeyframeAt(0.62)
local leftWobble = findKeyframeAt(0.76)
local finalCorrection = findKeyframeAt(0.92)
local upright = findKeyframeAt(1.10)

forwardCatch.Name = "ForwardMomentumCatch"
forwardCatch.Time = 0.52

rightWobble.Name = "UnsteadyRightStep"
rightWobble.Time = 0.70

leftWobble.Name = "UnsteadyLeftStep"
leftWobble.Time = 0.86

finalCorrection.Name = "FinalSmallCorrection"
finalCorrection.Time = 1.02

upright.Name = "BalancedUpright"
upright.Time = 1.20

local recoveryFrames = {
    -- One decisive forward overshoot. The pelvis moves past neutral instead
    -- of rebounding backward again.
    [0.52] = {
        HumanoidRootPart = {{-0.025, -0.070, -0.100}, { 0, 0,  0}},
        LowerTorso       = {{ 0.000, -0.025, -0.025}, {-5, 1, -8}},
        UpperTorso       = {{ 0.000,  0.000, -0.030}, {-18, 1, -9}},
        Head             = {{ 0.000,  0.000,  0.010}, { 13, 0,  6}},
        LeftUpperLeg     = {{ 0.000, -0.020, -0.030}, { 10, 0,  1}},
        LeftLowerLeg     = {{ 0.000,  0.000,  0.000}, {-18, 0,  0}},
        LeftFoot         = {{ 0.000, -0.030, -0.010}, {  6, 0, -1}},
        RightUpperLeg    = {{ 0.000, -0.025,  0.020}, { -8, 0, -1}},
        RightLowerLeg    = {{ 0.000,  0.000,  0.000}, {-22, 0,  0}},
        RightFoot        = {{ 0.000, -0.060,  0.025}, {  9, 0,  2}},
    },
    -- The torso remains forward. Balance loss is shown mainly with the
    -- opposite sideways roll and a corrective right-foot step.
    [0.70] = {
        HumanoidRootPart = {{0.050, -0.055, -0.115}, { 0,  0,  0}},
        LowerTorso       = {{0.000, -0.020, -0.020}, {-4, -1,  8}},
        UpperTorso       = {{0.000,  0.000, -0.025}, {-14, 0, 10}},
        Head             = {{0.000,  0.000,  0.008}, { 10, 0, -7}},
        LeftUpperLeg     = {{0.000, -0.018,  0.010}, { -4, 0, -1}},
        LeftLowerLeg     = {{0.000,  0.000,  0.000}, {-16, 0, 0}},
        LeftFoot         = {{0.000, -0.022,  0.008}, { 5, 0, 1}},
        RightUpperLeg    = {{0.000, -0.018, -0.030}, { 6, 0, 1}},
        RightLowerLeg    = {{0.000,  0.000,  0.000}, {-15, 0, 0}},
        RightFoot        = {{0.000, -0.045, -0.020}, { 6, 0, -2}},
    },
    -- A smaller correction to the other side; the forward lean is reduced
    -- but never flips into another backward spring motion.
    [0.86] = {
        HumanoidRootPart = {{-0.035, -0.038, -0.070}, { 0, 0,  0}},
        LowerTorso       = {{ 0.000, -0.014, -0.012}, {-3, 0, -5}},
        UpperTorso       = {{ 0.000,  0.000, -0.015}, {-9, 0, -6}},
        Head             = {{ 0.000,  0.000,  0.005}, { 6, 0,  4}},
        LeftUpperLeg     = {{ 0.000, -0.014, -0.020}, { 5, 0,  0}},
        LeftLowerLeg     = {{ 0.000,  0.000,  0.000}, {-13, 0, 0}},
        LeftFoot         = {{ 0.000, -0.016, -0.010}, { 4, 0, 0}},
        RightUpperLeg    = {{ 0.000, -0.014,  0.010}, {-3, 0, 0}},
        RightLowerLeg    = {{ 0.000,  0.000,  0.000}, {-13, 0, 0}},
        RightFoot        = {{ 0.000, -0.032,  0.010}, { 5, 0, 0}},
    },
    -- The final wobble is deliberately small and still slightly forward.
    [1.02] = {
        HumanoidRootPart = {{0.012, -0.018, -0.025}, { 0, 0, 0}},
        LowerTorso       = {{0.000, -0.006, -0.005}, {-1, 0,  2}},
        UpperTorso       = {{0.000,  0.000, -0.005}, {-4, 0,  3}},
        Head             = {{0.000,  0.000,  0.002}, { 3, 0, -2}},
        LeftUpperLeg     = {{0.000, -0.006, -0.004}, { 2, 0, 0}},
        LeftLowerLeg     = {{0.000,  0.000,  0.000}, {-9, 0, 0}},
        LeftFoot         = {{0.000, -0.006,  0.000}, { 2, 0, 0}},
        RightUpperLeg    = {{0.000, -0.006,  0.004}, {-2, 0, 0}},
        RightLowerLeg    = {{0.000,  0.000,  0.000}, {-10, 0, 0}},
        RightFoot        = {{0.000, -0.014,  0.004}, { 3, 0, 0}},
    },
    [1.20] = {
        HumanoidRootPart = {{0, 0, 0}, {0, 0, 0}},
        LowerTorso       = {{0, 0, 0}, {0, 0, 0}},
        UpperTorso       = {{0, 0, 0}, {0, 0, 0}},
        Head             = {{0, 0, 0}, {0, 0, 0}},
        LeftUpperLeg     = {{0, 0, 0}, { 1, 0, 0}},
        LeftLowerLeg     = {{0, 0, 0}, {-4, 0, 0}},
        LeftFoot         = {{0, 0, 0}, {0, 0, 0}},
        RightUpperLeg    = {{0, 0, 0}, {-1, 0, 0}},
        RightLowerLeg    = {{0, 0, 0}, {-5, 0, 0}},
        RightFoot        = {{0, 0, 0}, {1, 0, 0}},
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
assert(math.abs(lastTime - 1.20) < 0.001, "Animation duration must be 1.20 seconds")

sequence:SetAttribute("HumanRecoveryPass", 1)
sequence:SetAttribute("RecoveryWobbleCount", 3)
print(
    "[BasketSlipDraft] Human recovery applied: one forward momentum catch, "
        .. "three shrinking sideways corrections, upright at 1.20s, no spring rebound, no arm poses."
)
