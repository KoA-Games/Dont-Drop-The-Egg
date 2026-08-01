--[[
    ONE-SHOT STUDIO COMMAND BAR SCRIPT

    Creates only:
      ReplicatedStorage/AnimationDrafts/BasketSlip_Draft (KeyframeSequence)
      StarterPlayer/StarterPlayerScripts/BasketSlipDraftPreview (LocalScript)

    It intentionally does not touch BasketHoldPlayer, EggSlipController,
    SlipHitbox, movement settings, UI, egg/basket objects, or any published asset.
    Run this once from Studio's View > Command Bar while NOT in Play mode.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local KEYFRAME_SEQUENCE_NAME = "BasketSlip_Draft"
local PREVIEW_SCRIPT_NAME = "BasketSlipDraftPreview"

local function getOrCreateFolder(parent, name)
    local existing = parent:FindFirstChild(name)
    if existing then
        assert(existing:IsA("Folder"), ("%s must be a Folder"):format(existing:GetFullName()))
        return existing
    end

    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end

local function transform(position, rotationDegrees)
    return CFrame.new(position[1], position[2], position[3])
        * CFrame.Angles(
            math.rad(rotationDegrees[1]),
            math.rad(rotationDegrees[2]),
            math.rad(rotationDegrees[3])
        )
end

local function createPose(parent, name, poseTransform, easingStyle, easingDirection)
    local pose = Instance.new("Pose")
    pose.Name = name
    pose.CFrame = poseTransform
    pose.Weight = 1
    pose.EasingStyle = easingStyle
    pose.EasingDirection = easingDirection
    pose.Parent = parent
    return pose
end

-- Rotation convention used for a standard R15 rig:
--   +X torso pitch = backward lean
--   -X head pitch  = forward compensation
--   +X upper leg   = leg forward
--   -X lower leg   = knee flexion
--   +X foot pitch  = toes upward
--   -Z torso roll  = lean toward the character's right
local frames = {
    {
        name = "NearNeutralEntry",
        time = 0.00,
        easingStyle = Enum.PoseEasingStyle.Cubic,
        easingDirection = Enum.PoseEasingDirection.Out,
        joints = {
            LowerTorso   = transform({ 0,  0.00, 0.00 }, {  3, 0,  0 }),
            UpperTorso   = transform({ 0,  0.00, 0.00 }, {  4, 0,  0 }),
            Head         = transform({ 0,  0.00, 0.00 }, { -3, 0,  0 }),
            LeftUpperLeg = transform({ 0,  0.00, 0.00 }, { 10, 0,  0 }),
            LeftLowerLeg = transform({ 0,  0.00, 0.00 }, {-10, 0,  0 }),
            LeftFoot     = transform({ 0,  0.00, 0.00 }, {  1, 0,  0 }),
            RightUpperLeg= transform({ 0,  0.00, 0.00 }, { -7, 0,  0 }),
            RightLowerLeg= transform({ 0,  0.00, 0.00 }, {-15, 0,  0 }),
            RightFoot    = transform({ 0,  0.00, 0.00 }, {  2, 0,  0 }),
        },
    },
    {
        name = "FootLosesGrip",
        time = 0.08,
        easingStyle = Enum.PoseEasingStyle.Cubic,
        easingDirection = Enum.PoseEasingDirection.Out,
        joints = {
            LowerTorso   = transform({ 0, -0.06, 0.02 }, {  6, 0,  0 }),
            UpperTorso   = transform({ 0,  0.00, 0.00 }, { 12, 0,  0 }),
            Head         = transform({ 0,  0.00, 0.00 }, { -8, 0,  0 }),
            LeftUpperLeg = transform({ 0,  0.00, 0.00 }, { 26, 0,  0 }),
            LeftLowerLeg = transform({ 0,  0.00, 0.00 }, { -7, 0,  0 }),
            LeftFoot     = transform({ 0,  0.00, 0.00 }, { 13, 0,  0 }),
            RightUpperLeg= transform({ 0,  0.00, 0.00 }, {-10, 0,  0 }),
            RightLowerLeg= transform({ 0,  0.00, 0.00 }, {-26, 0,  0 }),
            RightFoot    = transform({ 0,  0.00, 0.00 }, {  6, 0,  0 }),
        },
    },
    {
        name = "MaximumBackwardLean",
        time = 0.22,
        easingStyle = Enum.PoseEasingStyle.Cubic,
        easingDirection = Enum.PoseEasingDirection.Out,
        joints = {
            LowerTorso   = transform({ 0, -0.13, 0.05 }, {  9, 0, -2 }),
            UpperTorso   = transform({ 0,  0.00, 0.00 }, { 26, 0, -3 }),
            Head         = transform({ 0,  0.00, 0.00 }, {-15, 0,  2 }),
            LeftUpperLeg = transform({ 0,  0.00, 0.00 }, { 43, 0,  0 }),
            LeftLowerLeg = transform({ 0,  0.00, 0.00 }, { -7, 0,  0 }),
            LeftFoot     = transform({ 0,  0.00, 0.00 }, { 20, 0,  0 }),
            RightUpperLeg= transform({ 0,  0.00, 0.00 }, {-16, 0,  0 }),
            RightLowerLeg= transform({ 0,  0.00, 0.00 }, {-40, 0,  0 }),
            RightFoot    = transform({ 0,  0.00, 0.00 }, { 14, 0,  0 }),
        },
    },
    {
        name = "SidewaysBalanceWobble",
        time = 0.48,
        easingStyle = Enum.PoseEasingStyle.Cubic,
        easingDirection = Enum.PoseEasingDirection.InOut,
        joints = {
            LowerTorso   = transform({ 0, -0.10, 0.04 }, {  7, 3, -8 }),
            UpperTorso   = transform({ 0,  0.00, 0.00 }, { 20, 1, -9 }),
            Head         = transform({ 0,  0.00, 0.00 }, {-10, 0,  5 }),
            LeftUpperLeg = transform({ 0,  0.00, 0.00 }, { 34, 0,  2 }),
            LeftLowerLeg = transform({ 0,  0.00, 0.00 }, {-15, 0,  0 }),
            LeftFoot     = transform({ 0,  0.00, 0.00 }, { 12, 0, -2 }),
            RightUpperLeg= transform({ 0,  0.00, 0.00 }, {-10, 0, -2 }),
            RightLowerLeg= transform({ 0,  0.00, 0.00 }, {-42, 0,  0 }),
            RightFoot    = transform({ 0,  0.00, 0.00 }, { 16, 0,  3 }),
        },
    },
    {
        name = "Recovery",
        time = 0.72,
        easingStyle = Enum.PoseEasingStyle.Cubic,
        easingDirection = Enum.PoseEasingDirection.InOut,
        joints = {
            LowerTorso   = transform({ 0, -0.03, 0.01 }, {  4, 0, -1 }),
            UpperTorso   = transform({ 0,  0.00, 0.00 }, { 10, 0, -2 }),
            Head         = transform({ 0,  0.00, 0.00 }, { -2, 0,  1 }),
            LeftUpperLeg = transform({ 0,  0.00, 0.00 }, { 16, 0,  0 }),
            LeftLowerLeg = transform({ 0,  0.00, 0.00 }, {-19, 0,  0 }),
            LeftFoot     = transform({ 0,  0.00, 0.00 }, {  3, 0,  0 }),
            RightUpperLeg= transform({ 0,  0.00, 0.00 }, { -4, 0,  0 }),
            RightLowerLeg= transform({ 0,  0.00, 0.00 }, {-19, 0,  0 }),
            RightFoot    = transform({ 0,  0.00, 0.00 }, {  5, 0,  0 }),
        },
    },
    {
        name = "ReturnToNormal",
        time = 0.90,
        easingStyle = Enum.PoseEasingStyle.Cubic,
        easingDirection = Enum.PoseEasingDirection.InOut,
        joints = {
            LowerTorso   = transform({ 0, 0, 0 }, {  1, 0, 0 }),
            UpperTorso   = transform({ 0, 0, 0 }, {  1, 0, 0 }),
            Head         = transform({ 0, 0, 0 }, { -1, 0, 0 }),
            LeftUpperLeg = transform({ 0, 0, 0 }, {  4, 0, 0 }),
            LeftLowerLeg = transform({ 0, 0, 0 }, { -8, 0, 0 }),
            LeftFoot     = transform({ 0, 0, 0 }, {  1, 0, 0 }),
            RightUpperLeg= transform({ 0, 0, 0 }, { -3, 0, 0 }),
            RightLowerLeg= transform({ 0, 0, 0 }, {-10, 0, 0 }),
            RightFoot    = transform({ 0, 0, 0 }, {  2, 0, 0 }),
        },
    },
}

local draftsFolder = getOrCreateFolder(ReplicatedStorage, "AnimationDrafts")
local oldSequence = draftsFolder:FindFirstChild(KEYFRAME_SEQUENCE_NAME)
if oldSequence then
    oldSequence:Destroy()
end

local sequence = Instance.new("KeyframeSequence")
sequence.Name = KEYFRAME_SEQUENCE_NAME
sequence.Loop = false
sequence.Priority = Enum.AnimationPriority.Action2

for _, frame in ipairs(frames) do
    local keyframe = Instance.new("Keyframe")
    keyframe.Name = frame.name
    keyframe.Time = frame.time

    -- Standard R15 pose tree. HumanoidRootPart is always identity; therefore
    -- this animation cannot translate the complete character through the world.
    local root = createPose(
        keyframe,
        "HumanoidRootPart",
        CFrame.identity,
        frame.easingStyle,
        frame.easingDirection
    )
    local lowerTorso = createPose(
        root,
        "LowerTorso",
        frame.joints.LowerTorso,
        frame.easingStyle,
        frame.easingDirection
    )
    local upperTorso = createPose(
        lowerTorso,
        "UpperTorso",
        frame.joints.UpperTorso,
        frame.easingStyle,
        frame.easingDirection
    )
    createPose(
        upperTorso,
        "Head",
        frame.joints.Head,
        frame.easingStyle,
        frame.easingDirection
    )

    local leftUpperLeg = createPose(
        lowerTorso,
        "LeftUpperLeg",
        frame.joints.LeftUpperLeg,
        frame.easingStyle,
        frame.easingDirection
    )
    local leftLowerLeg = createPose(
        leftUpperLeg,
        "LeftLowerLeg",
        frame.joints.LeftLowerLeg,
        frame.easingStyle,
        frame.easingDirection
    )
    createPose(
        leftLowerLeg,
        "LeftFoot",
        frame.joints.LeftFoot,
        frame.easingStyle,
        frame.easingDirection
    )

    local rightUpperLeg = createPose(
        lowerTorso,
        "RightUpperLeg",
        frame.joints.RightUpperLeg,
        frame.easingStyle,
        frame.easingDirection
    )
    local rightLowerLeg = createPose(
        rightUpperLeg,
        "RightLowerLeg",
        frame.joints.RightLowerLeg,
        frame.easingStyle,
        frame.easingDirection
    )
    createPose(
        rightLowerLeg,
        "RightFoot",
        frame.joints.RightFoot,
        frame.easingStyle,
        frame.easingDirection
    )

    keyframe.Parent = sequence
end

-- Validate the result before placing it into ReplicatedStorage.
local allowedPoseNames = {
    HumanoidRootPart = true,
    LowerTorso = true,
    UpperTorso = true,
    Head = true,
    LeftUpperLeg = true,
    LeftLowerLeg = true,
    LeftFoot = true,
    RightUpperLeg = true,
    RightLowerLeg = true,
    RightFoot = true,
}
local expectedTimes = { 0.00, 0.08, 0.22, 0.48, 0.72, 0.90 }
local keyframes = sequence:GetKeyframes()
table.sort(keyframes, function(a, b)
    return a.Time < b.Time
end)
assert(#keyframes == #expectedTimes, "BasketSlip_Draft must contain exactly six keyframes")
for index, keyframe in ipairs(keyframes) do
    assert(
        math.abs(keyframe.Time - expectedTimes[index]) < 0.0001,
        ("Unexpected keyframe time at index %d"):format(index)
    )
    local rootPose = keyframe:FindFirstChild("HumanoidRootPart")
    assert(rootPose and rootPose:IsA("Pose"), "Each keyframe must have a HumanoidRootPart Pose")
    assert(rootPose.CFrame == CFrame.identity, "HumanoidRootPart Pose must remain at identity")
end
for _, descendant in ipairs(sequence:GetDescendants()) do
    if descendant:IsA("Pose") then
        assert(allowedPoseNames[descendant.Name], "Forbidden Pose found: " .. descendant.Name)
    end
end

sequence.Parent = draftsFolder

local previewSource = [==[
local PREVIEW_ENABLED = true
local PREVIEW_KEY = Enum.KeyCode.K
local PREVIEW_FADE_IN = 0.05
local PREVIEW_FADE_OUT = 0.10
local PREVIEW_SPEED = 1.0

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local localPlayer = Players.LocalPlayer
local sequence = ReplicatedStorage
    :WaitForChild("AnimationDrafts")
    :WaitForChild("BasketSlip_Draft")

local currentCharacter = nil
local currentTrack = nil
local currentAnimation = nil
local setupGeneration = 0

local registrationSucceeded, temporaryAnimationId = pcall(function()
    return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
end)

if not registrationSucceeded then
    warn(
        "[BasketSlipDraftPreview] Unsupported API: "
            .. "KeyframeSequenceProvider:RegisterKeyframeSequence(KeyframeSequence). "
            .. "The completed BasketSlip_Draft was preserved. Exact error: "
            .. tostring(temporaryAnimationId)
    )
    return
end

local function cleanTrack()
    if currentTrack then
        if currentTrack.IsPlaying then
            currentTrack:Stop(PREVIEW_FADE_OUT)
        end
        currentTrack:Destroy()
        currentTrack = nil
    end
    if currentAnimation then
        currentAnimation:Destroy()
        currentAnimation = nil
    end
    currentCharacter = nil
end

local function setupCharacter(character)
    setupGeneration += 1
    local thisGeneration = setupGeneration
    cleanTrack()

    local humanoid = character:WaitForChild("Humanoid")
    character:WaitForChild("HumanoidRootPart")
    if thisGeneration ~= setupGeneration or character.Parent == nil then
        return
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = humanoid:WaitForChild("Animator")
    end
    if thisGeneration ~= setupGeneration or character.Parent == nil then
        return
    end

    local animation = Instance.new("Animation")
    animation.Name = "BasketSlip_Draft_TemporaryPreview"
    animation.AnimationId = temporaryAnimationId

    local loadedTrack = animator:LoadAnimation(animation)
    loadedTrack.Priority = Enum.AnimationPriority.Action2
    loadedTrack.Looped = false

    currentCharacter = character
    currentAnimation = animation
    currentTrack = loadedTrack
end

localPlayer.CharacterAdded:Connect(setupCharacter)
localPlayer.CharacterRemoving:Connect(function(character)
    if character == currentCharacter then
        setupGeneration += 1
        cleanTrack()
    end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    if gameProcessedEvent or not PREVIEW_ENABLED or input.KeyCode ~= PREVIEW_KEY then
        return
    end
    if not currentTrack then
        warn("[BasketSlipDraftPreview] Character animation track is not ready yet.")
        return
    end

    if currentTrack.IsPlaying then
        currentTrack:Stop(PREVIEW_FADE_OUT)
    end
    currentTrack:Play(PREVIEW_FADE_IN, 1, PREVIEW_SPEED)
end)

if localPlayer.Character then
    task.spawn(setupCharacter, localPlayer.Character)
end
]==]

local starterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local oldPreview = starterPlayerScripts:FindFirstChild(PREVIEW_SCRIPT_NAME)
if oldPreview then
    oldPreview:Destroy()
end

local preview = Instance.new("LocalScript")
preview.Name = PREVIEW_SCRIPT_NAME
preview.Source = previewSource
preview.Parent = starterPlayerScripts

print(
    "[BasketSlipDraft] Created ReplicatedStorage.AnimationDrafts.BasketSlip_Draft "
        .. "and StarterPlayer.StarterPlayerScripts.BasketSlipDraftPreview. "
        .. "Press Play, then K, to preview once."
)
