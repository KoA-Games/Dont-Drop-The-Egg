local ContentProvider = game:GetService("ContentProvider")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")

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
track.Looped = true
track.Priority = Enum.AnimationPriority.Action4

track:Play(0, 1, 1)
track:AdjustWeight(1, 0)

print("[BasketHold] 재생 요청 완료:", ANIMATION_ID)

task.delay(2, function()
	print("[BasketHold] IsPlaying:", track.IsPlaying)
	print("[BasketHold] Length:", track.Length)
end)

humanoid.Died:Connect(function()
	if track.IsPlaying then
		track:Stop(0)
	end
end)