local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ServerStorage = game:GetService("ServerStorage")

local RADIUS = 3
local SIZE = RADIUS * 2
local BALL_COLOR = Color3.fromRGB(255, 196, 61)
local STRIPE_COLOR = Color3.fromRGB(40, 40, 60)
local KILL_Y = -100

-- with ENFORCE = false this ONLY LOGS to Output, it does NOT stop cheaters XD
-- playtest normal stuff first (jumps, slopes, springs), raise MAX_FLAT_SPEED above anything legit, then flip it to true
local ENFORCE = false
local MAX_FLAT_SPEED = 130 -- ball tops out around 62, the rest is slack so real players dont get flagged

-- chars and balls ignore each other, only the map is solid. no ball bumping
for _, name in {"Char", "Balls"} do
	pcall(PhysicsService.RegisterCollisionGroup, PhysicsService, name)
end
PhysicsService:CollisionGroupSetCollidable("Char", "Default", false)
PhysicsService:CollisionGroupSetCollidable("Char", "Char", false)
PhysicsService:CollisionGroupSetCollidable("Char", "Balls", false)
PhysicsService:CollisionGroupSetCollidable("Balls", "Balls", false)

local built = setmetatable({}, {__mode = "k"}) -- weak keys so old characters get cleaned up on their own

-- hide the normal body, we only want the ball visible
local function hide(obj)
	if obj:IsA("BasePart") then
		obj.Massless = true
		obj.CanCollide = false
		obj.CanQuery = false
		obj.CanTouch = false
		obj.CollisionGroup = "Char"
		obj.Transparency = 1
	elseif obj:IsA("Decal") then
		obj.Transparency = 1
	end
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1, w.Parent = a, b, b
	return w
end

local function buildBall(plr, char)
	if built[char] then return end -- CharacterAdded and the startup loop can both call this, so dont build twice
	built[char] = true

	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hrp or not hum or not char:IsDescendantOf(workspace) then
		built[char] = nil -- setup failed, un-mark it so a later try can work
		return
	end

	hum.PlatformStand = true
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	for _, d in char:GetDescendants() do hide(d) end

	-- invisible ball is the real physics part, everything visible just rides on it
	local start = hrp.CFrame * CFrame.new(0, 2, 0)
	local ball = Instance.new("Part")
	ball.Name = "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * SIZE
	ball.Transparency = 1
	ball.CollisionGroup = "Balls"
	ball.CustomPhysicalProperties = PhysicalProperties.new(1.2, 1.6, 0.05, 100, 1) -- grippy with almost no bounce, so it sticks to the ground
	ball.CFrame = start

	-- put a part named BallSkin in ServerStorage to use ur own look XD
	local visual = Instance.new("Folder")
	visual.Name = "BallVisual"

	local function addPart(p, offset)
		p.CFrame = start * (offset or CFrame.identity)
		p.Anchored = false
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CollisionGroup = "Char"
		p.Parent = visual
	end

	local skin = ServerStorage:FindFirstChild("BallSkin")
	if skin and skin:IsA("BasePart") then
		local s = skin:Clone()
		s.Size = Vector3.one * SIZE * 1.02
		addPart(s)
	else
		local d = SIZE * 1.02 -- 2% bigger than the physics ball so it never clips into the floor
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Shape = Enum.PartType.Ball
		body.Size = Vector3.one * d
		body.Color = BALL_COLOR
		body.Material = Enum.Material.SmoothPlastic
		addPart(body)

		local turns = {CFrame.identity, CFrame.Angles(0, 0, math.pi / 2), CFrame.Angles(0, math.pi / 2, 0)}
		for i, turn in turns do
			local band = Instance.new("Part")
			band.Name = "Band" .. i
			band.Shape = Enum.PartType.Cylinder
			band.Size = Vector3.new(0.5, d + 0.1, d + 0.1)
			band.Color = STRIPE_COLOR
			band.Material = Enum.Material.SmoothPlastic
			addPart(band, turn)
		end
	end

	visual.Parent = ball
	ball.Parent = char

	-- weld AFTER parenting or the offsets get all messed up lol
	for _, p in visual:GetChildren() do weld(ball, p) end
	hrp.CFrame = ball.CFrame
	weld(ball, hrp).Parent = ball
	char.PrimaryPart = hrp

	-- the player's own pc drives the ball so it feels instant, no lag
	local ok, err = pcall(ball.SetNetworkOwner, ball, plr)
	if not ok then
		warn("couldn't give", plr.Name, "ownership of their ball:", err)
	end

	-- hats and accessories load late so catch them too
	char.DescendantAdded:Connect(function(d)
		if d ~= ball and not d:IsDescendantOf(ball) then hide(d) end
	end)
end

local function setupPlayer(plr)
	plr.CharacterAdded:Connect(function(char) buildBall(plr, char) end)
	if plr.Character then task.spawn(buildBall, plr, plr.Character) end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, plr in Players:GetPlayers() do setupPlayer(plr) end

-- one loop does both the fall check and the speed check, 4x a second is plenty
local respawning = {}
local lastSeen = {} -- [plr] = {ball = ball, pos = Vector3, t = number}
local INTERVAL = 0.25

local function checkMovement(plr, ball)
	local now = os.clock()
	local prev = lastSeen[plr]
	local pos = ball.Position

	-- first sample for a new ball (spawn/respawn) so we just remember it, nothing to compare yet
	if not prev or prev.ball ~= ball then
		lastSeen[plr] = {ball = ball, pos = pos, t = now}
		return
	end

	local delta = pos - prev.pos
	local dt = now - prev.t
	-- ignore downward movement, falling super fast is totally normal XD
	local moved = Vector3.new(delta.X, math.max(delta.Y, 0), delta.Z).Magnitude / dt

	if moved > MAX_FLAT_SPEED then
		warn(("%s moved %.0f studs/sec (limit %d)"):format(plr.Name, moved, MAX_FLAT_SPEED))
		if ENFORCE then
			-- snap them back to where they were
			ball.AssemblyLinearVelocity = Vector3.zero
			ball.CFrame = CFrame.new(prev.pos)
			pos = prev.pos
		end
	end
	lastSeen[plr] = {ball = ball, pos = pos, t = now}
end

task.spawn(function()
	while true do
		task.wait(INTERVAL)
		for _, plr in Players:GetPlayers() do
			local ball = plr.Character and plr.Character:FindFirstChild("Ball")
			if ball then
				if ball.Position.Y < KILL_Y then
					-- the flag stops us calling LoadCharacter 4x a second while one respawn is already happening
					if not respawning[plr] then
						respawning[plr] = true
						task.spawn(function()
							plr:LoadCharacter()
							respawning[plr] = nil
						end)
					end
				else
					checkMovement(plr, ball)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	respawning[plr] = nil
	lastSeen[plr] = nil
end)