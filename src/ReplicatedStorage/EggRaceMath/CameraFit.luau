--!strict

-- Fits a complete 3D awards scene below a UI banner without hard-coded camera
-- coordinates. This is the production math module used by the ceremony view.
local CameraFit = {}
CameraFit.FieldOfView = 40

function CameraFit.Corners(frame: CFrame, size: Vector3): { Vector3 }
	local points = {}
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				table.insert(points, frame:PointToWorldSpace(size * Vector3.new(x, y, z) * 0.5))
			end
		end
	end
	return points
end

function CameraFit.Collect(stage: Instance, participants: { Player }): { Vector3 }
	local points = {}
	local function box(frame: CFrame, size: Vector3)
		for _, point in CameraFit.Corners(frame, size) do
			table.insert(points, point)
		end
	end
	for _, item in stage:GetDescendants() do
		if item:IsA("BasePart") then
			if item.Transparency < 0.99 then
				box(item.CFrame, item.Size)
			end
			if item.Name:match("^Podium_%d+$")
				or item.Name:match("^Watcher_%d+$")
				or item.Name:match("^Kneel_%d+$")
			then
				box(CFrame.new(item.Position + Vector3.new(0, 1, 0)), Vector3.new(5, 8, 5))
			end
		end
	end
	for _, participant in participants do
		local character = participant.Character
		if character and character:GetAttribute("EggRaceCeremonyActive") == true then
			for _, item in character:GetDescendants() do
				if item:IsA("BasePart") and item.Transparency < 0.99 then
					box(item.CFrame, item.Size)
				end
			end
		end
	end
	return points
end

function CameraFit.Solve(
	points: { Vector3 },
	front: Vector3,
	viewport: Vector2,
	bannerBottom: number,
	minimumDistance: number?,
	fixedCenter: Vector3?
): (CFrame, number, Vector3)
	assert(#points > 0, "Ceremony camera needs scene bounds")
	local low, high = points[1], points[1]
	for _, point in points do
		low = low:Min(point)
		high = high:Max(point)
	end
	local center = fixedCenter or (low + high) * 0.5
	local flat = front * Vector3.new(1, 0, 1)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	local basis = CFrame.lookAt(Vector3.zero, -(flat.Unit + Vector3.new(0, 0.32, 0)).Unit)
	local tanY = math.tan(math.rad(CameraFit.FieldOfView * 0.5))
	local tanX = tanY * math.max(viewport.X, 1) / math.max(viewport.Y, 1)
	local top = math.clamp(1 - 2 * (bannerBottom + 0.04), -0.15, 0.82)
	local bottom, side = -0.90, 0.90
	local shift = -(top + bottom) * 0.5
	local distance = 8
	for _, point in points do
		local delta = point - center
		local x = delta:Dot(basis.RightVector)
		local y = delta:Dot(basis.UpVector)
		local z = delta:Dot(basis.LookVector)
		distance = math.max(
			distance,
			1 - z,
			math.abs(x) / (tanX * side) - z,
			(y - top * tanY * z) / (tanY * (top + shift)),
			(bottom * tanY * z - y) / (-tanY * (bottom + shift))
		)
	end
	distance = math.max(distance + 1, minimumDistance or 0)
	local position = center - basis.LookVector * distance + basis.UpVector * (shift * distance * tanY)
	return CFrame.new(position) * basis.Rotation, distance, center
end

return CameraFit
