local ContentProvider = game:GetService("ContentProvider")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")
local FALL_BASKET_RELEASED_ATTRIBUTE = "FallBasketReleased"

-- 숫자 부분만 네 애니메이션 ID로 교체
local ANIMATION_ID = "rbxassetid://78788082464822"

if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
	warn("[BasketHold] 캐릭터가 R15가 아닙니다.")
	return
end

local animation = Instance.new("Animation")
animation.Name = "BasketHold"
animation.AnimationId = ANIMATION_ID

local preloadSuccess, preloadError = pcall(function()
	ContentProvider:PreloadAsync({ animation })
end)

if not preloadSuccess then
	warn("[BasketHold] 애니메이션 사전 로드 실패:", preloadError)
end

local loadSuccess, trackOrError = pcall(function()
	return animator:LoadAnimation(animation)
end)

if not loadSuccess then
	warn("[BasketHold] 애니메이션 로드 실패:", trackOrError)
	return
end

local track = trackOrError
track.Name = "BasketHold"
track.Looped = true
track.Priority = Enum.AnimationPriority.Action4

local function stopReleasedBasketPose()
	if track.IsPlaying then
		track:Stop(0.03)
	end
end

local function syncBasketHoldState()
	-- BasketHold is an arm-only Action4 overlay. Once the basket is released it
	-- must not remain active underneath a fall/get-up animation, otherwise both
	-- Action4 tracks blend the shoulder and elbow rotations into a twisted pose.
	if character:GetAttribute(FALL_BASKET_RELEASED_ATTRIBUTE) == true then
		stopReleasedBasketPose()
		return
	end

	if not track.IsPlaying then
		track:Play(0.05, 1, 1)
	end
	track:AdjustWeight(1, 0.05)
end

character:GetAttributeChangedSignal(FALL_BASKET_RELEASED_ATTRIBUTE):Connect(syncBasketHoldState)
syncBasketHoldState()

print("[BasketHold] 재생 요청 완료:", ANIMATION_ID)

task.delay(2, function()
	print("[BasketHold] IsPlaying:", track.IsPlaying)
	print("[BasketHold] Length:", track.Length)
end)

humanoid.Died:Connect(function()
	stopReleasedBasketPose()
end)
