local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local plr = Players.LocalPlayer
local cam = workspace.CurrentCamera

-- all the feel stuff is up here so u can tweak it without digging XD
local RADIUS = 3
local MAX_SPEED = 62
local JUMP_POWER = 76
local JUMP_CUT = 260
local EXTRA_GRAVITY = 70
local CAM_DIST = 30
local MIN_ZOOM, MAX_ZOOM = 14, 60
local BASE_FOV = 70

local JUMP_SOUND = "rbxassetid://5603258258"
local ROLL_SOUND = "rbxassetid://134443058228922"

local ball, controls, dust, rollSound
local spawnId = 0
local grounded, jumping, jumpHeld = false, false, false
local lastGround, jumpPressedAt, lastFallSpeed = -10, -10, 0
local yaw, pitch, camDist = 0, -0.3, CAM_DIST
local keys, rightMouse, touchMove = {}, false, Vector2.zero
local stickTouch, lookTouch

-- RespectCanCollide so invisible trigger parts dont count as floor or walls lol
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

-- tiny helper so i dont have to type Instance.new + 5 lines every time XD
local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do o[k] = v end
	o.Parent = parent
	return o
end

-- new sound each time so fast jumps can overlap instead of cutting each other off
local function playSound(id, volume, speed)
	local s = make("Sound", {SoundId = id, Volume = volume, PlaybackSpeed = speed}, SoundService)
	s:Play()
	Debris:AddItem(s, 5)
end

-- empty on purpose, the touch block fills it in (pc players dont need it)
local resetStick = function() end

-- roblox never tells us about key releases during menu/chat/alt-tab, so wipe everything or the ball keeps rolling XD
local function resetInput()
	jumpHeld = false
	jumpPressedAt = -10 -- also kill the buffered jump or it fires when the menu closes lol
	rightMouse = false
	touchMove = Vector2.zero
	stickTouch, lookTouch = nil, nil
	table.clear(keys)
	UIS.MouseBehavior = Enum.MouseBehavior.Default
	resetStick()
end

-- no moving while ur typing or the ESC menu is open
local function inputEnabled()
	return not GuiService.MenuIsOpen and not UIS:GetFocusedTextBox()
end

local function pressJump()
	jumpPressedAt = os.clock()
	jumpHeld = true
end

local function releaseJump()
	jumpHeld = false
end

-- the clamp stops the camera flipping upside down
local function look(dx, dy, sens)
	yaw -= dx * sens
	pitch = math.clamp(pitch - dy * sens, -1.3, 0.2)
end

GuiService.MenuOpened:Connect(resetInput)
GuiService.MenuClosed:Connect(resetInput)
UIS.WindowFocusReleased:Connect(resetInput)
UIS.TextBoxFocused:Connect(resetInput)

UIS.InputBegan:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and inputEnabled() then
		rightMouse = true
		UIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		-- processed = roblox already used it (like chat typing), so wasd in chat wont move the ball
	elseif not processed then
		keys[input.KeyCode] = true
		if input.KeyCode == Enum.KeyCode.Space then
			pressJump()
		end
	end
end)

UIS.InputEnded:Connect(function(input)
	keys[input.KeyCode] = nil -- always clear it, even if processed, or the key gets stuck forever
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rightMouse = false
		UIS.MouseBehavior = Enum.MouseBehavior.Default
	elseif input.KeyCode == Enum.KeyCode.Space then
		releaseJump()
	end
end)

UIS.InputChanged:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseMovement and rightMouse then
		look(input.Delta.X, input.Delta.Y, 0.005)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		camDist = math.clamp(camDist - input.Position.Z * 3, MIN_ZOOM, MAX_ZOOM)
	end
end)

-- touch: left side = stick, right side = look, big button = jump
if UIS.TouchEnabled then
	local gui = make("ScreenGui", {Name = "TouchGui", ResetOnSpawn = false}, plr:WaitForChild("PlayerGui"))
	local round = {CornerRadius = UDim.new(1, 0)}
	local center = Vector2.new(0.5, 0.5)

	local base = make("Frame", {
		Size = UDim2.fromOffset(150, 150), AnchorPoint = center, Position = UDim2.new(0, 130, 1, -130),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.75,
	}, gui)
	make("UICorner", round, base)

	local knob = make("Frame", {
		Size = UDim2.fromOffset(64, 64), AnchorPoint = center, Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.25,
	}, base)
	make("UICorner", round, knob)

	local jumpButton = make("TextButton", {
		Size = UDim2.fromOffset(110, 110), AnchorPoint = center, Position = UDim2.new(1, -110, 1, -120),
		BackgroundColor3 = Color3.fromRGB(255, 200, 60), Text = "JUMP", Font = Enum.Font.FredokaOne,
		TextScaled = true, TextColor3 = Color3.fromRGB(60, 30, 0),
	}, gui)
	make("UICorner", round, jumpButton)
	jumpButton.MouseButton1Down:Connect(pressJump)
	jumpButton.MouseButton1Up:Connect(releaseJump)
	jumpButton.MouseLeave:Connect(releaseJump) -- finger slid off the button, still counts as letting go

	local stickStart
	resetStick = function()
		knob.Position = UDim2.fromScale(0.5, 0.5)
	end

	UIS.TouchStarted:Connect(function(touch, processed)
		if processed then return end -- jump button touches show up as processed so they dont steal the stick
		local onLeft = touch.Position.X < cam.ViewportSize.X * 0.4 -- 40% split so both thumbs have their own side
		if onLeft and not stickTouch then
			stickTouch = touch
			stickStart = Vector2.new(touch.Position.X, touch.Position.Y)
		elseif not onLeft and not lookTouch then
			lookTouch = touch
		end
	end)

	UIS.TouchMoved:Connect(function(touch)
		if touch == stickTouch then
			local offset = Vector2.new(touch.Position.X, touch.Position.Y) - stickStart
			if offset.Magnitude > 60 then offset = offset.Unit * 60 end
			knob.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
			touchMove = Vector2.new(offset.X / 60, -offset.Y / 60)
		elseif touch == lookTouch then
			look(touch.Delta.X, touch.Delta.Y, 0.007)
		end
	end)

	UIS.TouchEnded:Connect(function(touch)
		if touch == stickTouch then
			stickTouch, touchMove = nil, Vector2.zero
			resetStick()
		elseif touch == lookTouch then
			lookTouch = nil
		end
	end)

	-- backup in case a touch ends and we never hear about it (stops the stick sticking XD)
	local function dead(t)
		return t.UserInputState == Enum.UserInputState.End or t.UserInputState == Enum.UserInputState.Cancel
	end
	RunService.Heartbeat:Connect(function()
		if stickTouch and dead(stickTouch) then
			stickTouch, touchMove = nil, Vector2.zero
			resetStick()
		end
		if lookTouch and dead(lookTouch) then lookTouch = nil end
	end)
end

-- the default controls would put a 2nd joystick on mobile, so nope
task.spawn(function()
	local ok, result = pcall(function()
		local module = plr:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		return require(module):GetControls()
	end)
	if ok and result then
		controls = result
		controls:Disable()
	end
end)

-- wasd is relative to the camera so W always goes "into the screen"
local function getMoveDirection()
	local x, y = touchMove.X, touchMove.Y
	if inputEnabled() then
		local function down(key) return keys[key] and 1 or 0 end
		x += down(Enum.KeyCode.D) + down(Enum.KeyCode.Right) - down(Enum.KeyCode.A) - down(Enum.KeyCode.Left)
		y += down(Enum.KeyCode.W) + down(Enum.KeyCode.Up) - down(Enum.KeyCode.S) - down(Enum.KeyCode.Down)
	end

	local input = Vector2.new(x, y)
	if input.Magnitude > 1 then input = input.Unit end -- diagonals would be 1.4x faster otherwise XD

	local forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	return right * input.X + forward * input.Y
end

local function onCharacter(char)
	spawnId += 1 -- if u die again while this is still loading, the old run quits instead of fighting the new one
	local id = spawnId
	ball = nil

	local hum = char:WaitForChild("Humanoid", 10)
	local newBall = char:WaitForChild("Ball", 20)
	if id ~= spawnId or not hum or not newBall then return end

	hum.PlatformStand = true -- stops the humanoid trying to walk/stand up on its own
	if controls then controls:Disable() end

	-- effects live on the ball so they get deleted with the character, no cleanup needed XD
	local left = make("Attachment", {Position = Vector3.new(-1.7, -0.6, 0)}, newBall)
	local right = make("Attachment", {Position = Vector3.new(1.7, -0.6, 0)}, newBall)
	make("Trail", {
		Attachment0 = left, Attachment1 = right, Lifetime = 0.35, LightEmission = 0.7, FaceCamera = false,
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1)}),
	}, newBall)

	dust = make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/smoke_main.dds", Enabled = false, Drag = 6,
		Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(6, 14),
		SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Top,
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1)}),
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3)}),
	}, make("Attachment", {Position = Vector3.new(0, -RADIUS, 0)}, newBall))

	rollSound = make("Sound", {SoundId = ROLL_SOUND, Volume = 0, Looped = true}, newBall)
	rollSound:Play()

	-- wipe leftovers from last life or a big fall death makes a fake landing thud on spawn lol
	grounded, jumping, jumpHeld = false, false, false
	lastGround, jumpPressedAt, lastFallSpeed = -10, -10, 0
	pitch = -0.3
	yaw = math.atan2(-newBall.CFrame.LookVector.X, -newBall.CFrame.LookVector.Z)
	cam.FieldOfView = BASE_FOV
	cam.CameraSubject = newBall
	cam.CameraType = Enum.CameraType.Scriptable
	rayParams.FilterDescendantsInstances = {char}

	-- drop the ball the moment it dies so the loops dont poke a deleted part
	newBall.AncestryChanged:Connect(function()
		if not newBall:IsDescendantOf(workspace) and ball == newBall then ball = nil end
	end)
	ball = newBall
end

plr.CharacterAdded:Connect(onCharacter)
if plr.Character then task.spawn(onCharacter, plr.Character) end

RunService.Heartbeat:Connect(function(dt)
	if not ball then return end

	local vel = ball.AssemblyLinearVelocity
	local flat = Vector3.new(vel.X, 0, vel.Z)
	local now = os.clock()

	-- ray is a bit longer than the radius so slopes still count as ground
	local hit = workspace:Raycast(ball.Position, Vector3.new(0, -(RADIUS + 0.9), 0), rayParams)
	local wasGrounded = grounded
	grounded = hit ~= nil and vel.Y < 30 -- the vel check stops us counting as grounded while launching upward

	if grounded then
		lastGround = now
		if not wasGrounded and lastFallSpeed < -40 then
			dust:Emit(15)
			playSound(JUMP_SOUND, 0.3, 0.55)
		end
	end

	-- lerp = easy smooth accel with no fancy math. bigger number = snappier, smaller = floatier XD
	local direction = getMoveDirection()
	local ease = grounded and 4 or 1.5
	if direction.Magnitude < 0.05 then ease = grounded and 0.8 or 0.3 end
	flat = flat:Lerp(direction * MAX_SPEED, math.min(ease * dt, 1))

	-- falling faster than rising feels way snappier
	local vy = vel.Y
	if not grounded and vy < 5 then
		vy -= EXTRA_GRAVITY * dt
	end

	-- buffer + coyote time = forgiving jump timing so it never feels like the game ate ur press
	if now - jumpPressedAt < 0.16 and now - lastGround < 0.13 then
		vy = JUMP_POWER
		jumpPressedAt, lastGround = -10, -10
		grounded, jumping = false, true
		dust:Emit(8)
		playSound(JUMP_SOUND, 0.35, 1)
	end

	-- let go early = short hop. only counts for our own jumps so ramps and springs dont get chopped
	if jumping then
		if grounded then
			jumping = false
		elseif vy > 0 and not jumpHeld then
			vy -= JUMP_CUT * dt
		end
	end

	ball.AssemblyLinearVelocity = Vector3.new(flat.X, vy, flat.Z)
	if grounded and flat.Magnitude > 0.5 then
		ball.AssemblyAngularVelocity = Vector3.yAxis:Cross(flat) / RADIUS -- spin matches speed so it actually looks like its rolling
	end
	lastFallSpeed = vy
end)

-- the +1 makes us run after roblox's own camera so ours wins XD
RunService:BindToRenderStep("BallCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not ball then return end
	cam.CameraType = Enum.CameraType.Scriptable

	local vel = ball.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude

	local target = ball.Position + Vector3.new(0, 2.5, 0)
	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local backward = rotation:VectorToWorldSpace(Vector3.zAxis)

	-- wall behind us? move the cam closer so we dont see through it. min 4 so its never inside the ball
	local distance = camDist
	local hit = workspace:Raycast(target, backward * camDist, rayParams)
	if hit then distance = math.max(4, hit.Distance - 1.5) end

	cam.CFrame = CFrame.lookAt(target + backward * distance, target)

	-- fov widens a lil when ur fast so it feels faster
	local goalFov = BASE_FOV + math.min(speed * 0.2, 15)
	cam.FieldOfView += (goalFov - cam.FieldOfView) * math.min(dt * 5, 1)

	rollSound.Volume = grounded and math.min(speed / MAX_SPEED, 1) * 0.35 or 0
	rollSound.PlaybackSpeed = 0.8 + speed / 70
end)