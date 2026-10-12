local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config.Movement)

local player = Players.LocalPlayer

-- Articulaciones que animan el mortal y el gancho (nombres R15 y R6; R6 no tiene codos ni rodillas). La raíz se detecta aparte.
-- Giro en X: en caderas y hombros, positivo lleva la extremidad al frente; en rodillas, negativo la dobla hacia atrás;
-- en codos, positivo dobla el antebrazo al frente. Giro en Z: en el hombro izquierdo, negativo abre el brazo hacia afuera.
local POSE_JOINTS = {
	LeftHip = "LeftHip",
	["Left Hip"] = "LeftHip",
	RightHip = "RightHip",
	["Right Hip"] = "RightHip",
	LeftKnee = "LeftKnee",
	RightKnee = "RightKnee",
	LeftShoulder = "LeftShoulder",
	["Left Shoulder"] = "LeftShoulder",
	RightShoulder = "RightShoulder",
	["Right Shoulder"] = "RightShoulder",
	LeftElbow = "LeftElbow",
	RightElbow = "RightElbow",
}

-- Pose del gancho tipo Spider-Man, en grados por articulación: { X, Z }. Brazo del gancho estirado hacia la cuerda,
-- el otro abierto y doblado, una rodilla encogida al pecho y la otra pierna estirada hacia abajo.
local GRAPPLE_POSE = {
	RightShoulder = { 90, 0 }, -- sumado a la pose de sostener herramienta (brazo al frente) queda apuntando a la cuerda
	RightElbow = { 0, 0 },
	LeftShoulder = { 20, -70 },
	LeftElbow = { 70, 0 },
	RightHip = { 85, 0 },
	RightKnee = { -110, 0 },
	LeftHip = { -15, 0 },
	LeftKnee = { -30, 0 },
}

-- Pose de reposo de cada articulación, guardada la primera vez que se toca. El mortal y el gancho parten
-- siempre de aquí, así no se "contagian" si uno empieza mientras el otro está a medias.
local restPose: { [Instance]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

-- Pieza "padre" de una articulación y el objeto/propiedad cuyo CFrame la mueve (en el espacio de esa pieza):
-- Motor6D clásico -> su C0; avatares nuevos (AnimationConstraint) -> el CFrame de su Attachment0.
local function getJointPivot(joint: Instance): (BasePart?, Instance?, string?)
	if joint:IsA("Motor6D") then
		return joint.Part0, joint, "C0"
	elseif joint:IsA("AnimationConstraint") and joint.Attachment0 then
		return joint.Attachment0.Parent :: BasePart?, joint.Attachment0, "CFrame"
	end
	return nil, nil, nil
end

type PoseJoint = { target: Instance, property: string, rest: CFrame, kind: string }

local function collectJoints(character: Model, root: BasePart): { PoseJoint }
	local joints = {}
	for _, joint in character:GetDescendants() do
		local part0, target, property = getJointPivot(joint)
		if not (target and property) then
			continue
		end
		local kind = if part0 == root then "Root" else POSE_JOINTS[joint.Name]
		if kind then
			local rest = restPose[target]
			if not rest then
				rest = (target :: any)[property]
				restPose[target] = rest
			end
			table.insert(joints, { target = target, property = property, rest = rest, kind = kind })
		end
	end
	return joints
end

local function setJoint(joint: PoseJoint, cframe: CFrame)
	local target: any = joint.target
	target[joint.property] = cframe
end

-- Gira un CFrame sobre su propio punto (la articulación) en los ejes X y Z de la pieza padre.
local function rotateInPlace(original: CFrame, angle: number, angleZ: number?): CFrame
	return CFrame.new(original.Position) * CFrame.Angles(angle, 0, angleZ or 0) * original.Rotation
end

-- Mortal hacia el frente encogiendo las piernas: gira la articulación raíz una vuelta completa
-- y dobla caderas y rodillas, que se estiran de nuevo al terminar el giro.
local function playFlip(character: Model, root: BasePart, humanoid: Humanoid)
	if character:GetAttribute("Flipping") then
		return
	end

	local joints = {}
	local hasRoot = false
	for _, joint in collectJoints(character, root) do
		if joint.kind == "Root" or joint.kind:find("Hip") or joint.kind:find("Knee") then
			hasRoot = hasRoot or joint.kind == "Root"
			table.insert(joints, joint)
		end
	end
	if not hasRoot then
		warn("[Movement] no se encontró la articulación raíz del personaje; no se puede hacer el mortal")
		return
	end

	character:SetAttribute("Flipping", true)
	local hipAngle = math.rad(Config.DoubleJumpTuckHip)
	local kneeAngle = -math.rad(Config.DoubleJumpTuckKnee)

	local elapsed = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local alpha = math.min(elapsed / Config.DoubleJumpFlipTime, 1)
		local done = alpha >= 1 or humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Landed
		if done then
			connection:Disconnect()
			for _, joint in joints do
				setJoint(joint, joint.rest)
			end
			character:SetAttribute("Flipping", nil)
			return
		end

		local spin = TweenService:GetValue(alpha, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		-- Las piernas se encogen hasta la mitad del giro y se estiran antes de terminar.
		local tuck = math.sin(math.pi * alpha)
		for _, joint in joints do
			if joint.kind == "Root" then
				setJoint(joint, CFrame.Angles(-math.pi * 2 * spin, 0, 0) * joint.rest)
			elseif joint.kind:find("Hip") then
				setJoint(joint, rotateInPlace(joint.rest, hipAngle * tuck))
			else
				setJoint(joint, rotateInPlace(joint.rest, kneeAngle * tuck))
			end
		end
	end)
end

-- Pose al ser jalado por el gancho, tipo Spider-Man (ver GRAPPLE_POSE): el cuerpo se inclina hacia el punto
-- y las extremidades toman la pose. Entra y sale suavemente.
-- Devuelve la función para terminarla.
local activeGrapplePose: { [Model]: RBXScriptConnection } = {}

local function startGrapplePose(character: Model, root: BasePart, getDirection: () -> Vector3?): () -> ()
	if activeGrapplePose[character] then
		activeGrapplePose[character]:Disconnect()
	end
	local joints = collectJoints(character, root)
	local maxLean = math.rad(Config.GrapplePoseLean)
	local weight, goal = 0, 1
	local direction = Vector3.yAxis

	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		weight += (goal - weight) * math.min(dt * 12, 1)
		if goal == 0 and weight < 0.02 then
			connection:Disconnect()
			activeGrapplePose[character] = nil
			for _, joint in joints do
				setJoint(joint, joint.rest)
			end
			return
		end
		-- Si hay un mortal en curso, él manda sobre las articulaciones.
		if character:GetAttribute("Flipping") then
			return
		end

		-- Dirección al punto en el espacio del HumanoidRootPart; al soltar se conserva la última.
		local world = getDirection()
		if world and world.Magnitude > 0.01 then
			direction = root.CFrame:VectorToObjectSpace(world.Unit)
		end
		-- Inclina el cuerpo para que la cabeza apunte hacia el punto, sin pasar de maxLean.
		local axis = Vector3.yAxis:Cross(direction)
		local tilt = CFrame.identity
		if axis.Magnitude > 1e-3 then
			local angle = math.min(math.acos(math.clamp(direction.Y, -1, 1)), maxLean)
			tilt = CFrame.fromAxisAngle(axis.Unit, angle * weight)
		end

		for _, joint in joints do
			if joint.kind == "Root" then
				setJoint(joint, tilt * joint.rest)
			else
				local angles = GRAPPLE_POSE[joint.kind]
				setJoint(joint, rotateInPlace(joint.rest, math.rad(angles[1]) * weight, math.rad(angles[2]) * weight))
			end
		end
	end)
	activeGrapplePose[character] = connection

	return function()
		goal = 0
	end
end
-- Suelta el gancho del personaje actual (lo asigna setupGrapple); el doble salto lo usa para saltar desde la cuerda.
local activeGrappleRelease: (() -> ())? = nil

-- Doble salto: un salto extra en el aire, se recarga al tocar el suelo.
-- Colgado del gancho siempre hay un salto disponible: suelta la cuerda y lanza al personaje.
local function setupDoubleJump(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart

	local canDoubleJump = false
	local hasDoubleJumped = false
	local lastDoubleJump = -math.huge

	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed then
			canDoubleJump = false
			hasDoubleJumped = false
		elseif new == Enum.HumanoidStateType.Freefall then
			-- Pequeña espera para que el mismo toque del primer salto no dispare el segundo.
			task.delay(Config.DoubleJumpDelay, function()
				if humanoid:GetState() == Enum.HumanoidStateType.Freefall then
					canDoubleJump = true
				end
			end)
		end
	end)

	local jumpConnection = UserInputService.JumpRequest:Connect(function()
		if humanoid.Health <= 0 then
			return
		end
		local releaseGrapple = if character:GetAttribute("Grappling") then activeGrappleRelease else nil
		if not releaseGrapple then
			if not canDoubleJump or hasDoubleJumped then
				return
			end
			if os.clock() - lastDoubleJump < Config.DoubleJumpCooldown then
				return
			end
		else
			releaseGrapple()
		end
		hasDoubleJumped = true
		lastDoubleJump = os.clock()
		canDoubleJump = false

		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, Config.DoubleJumpPower, velocity.Z)

		playFlip(character, root, humanoid)
	end)
	-- JumpRequest es global: se desconecta al morir para no acumular conexiones entre respawns.
	humanoid.Died:Once(function()
		jumpConnection:Disconnect()
	end)
end

-- Correr: mientras se mantiene Shift la velocidad sube a SprintSpeed y vuelve a la normal al soltar.
local SPRINT_KEYS = {
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.RightShift] = true,
}

local function setupSprint(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local walkSpeed = humanoid.WalkSpeed

	local function setSprinting(sprinting: boolean)
		humanoid.WalkSpeed = if sprinting then Config.SprintSpeed else walkSpeed
		character:SetAttribute("Sprinting", sprinting or nil)
	end

	local began = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and SPRINT_KEYS[input.KeyCode] then
			setSprinting(true)
		end
	end)
	local ended = UserInputService.InputEnded:Connect(function(input)
		if SPRINT_KEYS[input.KeyCode] then
			setSprinting(false)
		end
	end)
	-- InputBegan/Ended son globales: se desconectan al morir para no acumular conexiones entre respawns.
	humanoid.Died:Once(function()
		began:Disconnect()
		ended:Disconnect()
	end)
end

-- Paleta del lanzagancho: metal pavonado, carbono oscuro, acentos de neón (config) y la cuerda enrollada en el carrete.
local HOOK_GUNMETAL = Color3.fromRGB(62, 66, 74)
local HOOK_CARBON = Color3.fromRGB(28, 30, 34)
local HOOK_STEEL = Color3.fromRGB(150, 156, 165)
local HOOK_TRIGGER = Color3.fromRGB(255, 140, 40)
local CLAW_OPEN = 35 -- grados que se abren las puntas de la garra
local CLAW_CLOSED = -20 -- negativo: las puntas se cierran sobre la superficie
local PROJECTILE_SCALE = 2 -- la garra que vuela es más grande que la del arma para que se vea de lejos

-- Los cilindros de Roblox tienen el eje en X; con esto apuntan al frente (-Z).
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Shape = shape or Enum.PartType.Block
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	return part
end

type ClawPiece = {
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?,
}

-- Forma de la garra relativa a su centro (-Z al frente): cubo de acero con núcleo de neón y cuatro puntas,
-- cada una con la punta afilada doblada hacia atrás. `open` son los grados que se abren; negativos la cierran.
local function clawLayout(open: number, scale: number): { ClawPiece }
	local layout: { ClawPiece } = {
		{ name = "ClawHub", size = Vector3.new(0.22, 0.34, 0.34) * scale, offset = ALONG_Z, color = HOOK_STEEL, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder },
		{ name = "ClawCore", size = Vector3.one * 0.2 * scale, offset = CFrame.new(0, 0, -0.1 * scale), color = Config.GrappleAccentColor, material = Enum.Material.Neon, shape = Enum.PartType.Ball },
	}
	for i = 0, 3 do
		local around = CFrame.Angles(0, 0, math.rad(45 + i * 90))
		local prong = around
			* CFrame.new(0.14 * scale, 0, -0.1 * scale)
			* CFrame.Angles(0, math.rad(-open), 0)
			* CFrame.new(0, 0, -0.2 * scale)
		table.insert(layout, { name = "Prong", size = Vector3.new(0.07, 0.07, 0.42) * scale, offset = prong, color = HOOK_GUNMETAL, material = Enum.Material.Metal })
		local tip = prong * CFrame.new(0, 0, -0.2 * scale) * CFrame.Angles(0, math.rad(75), 0) * CFrame.new(0, 0, 0.09 * scale)
		table.insert(layout, { name = "ProngTip", size = Vector3.new(0.06, 0.06, 0.2) * scale, offset = tip, color = HOOK_STEEL, material = Enum.Material.Metal })
	end
	return layout
end

local function newClawPart(piece: ClawPiece): Part
	return newPart(piece.name, piece.size, piece.color, piece.material, piece.shape)
end

-- Pieza decorativa del lanzagancho, soldada al Handle. `offset` es relativo al Handle (su -Z apunta al frente).
local function addToolPart(handle: BasePart, part: Part, offset: CFrame): Part
	part.CFrame = handle.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = part
	part.Parent = handle
	return part
end

-- Aura sutil del lanzagancho: un resplandor suave que "respira" desde el núcleo y destellos finos que flotan
-- lentamente alrededor del cuerpo y se desvanecen. Pocas partículas, pequeñas y lentas para que se vea elegante.
local function addAura(body: BasePart, core: BasePart)
	local accent = Config.GrappleAccentColor

	local glow = Instance.new("PointLight")
	glow.Color = accent
	glow.Range = 7
	glow.Brightness = 0.8
	glow.Shadows = false
	glow.Parent = core
	TweenService:Create(glow, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Brightness = 2,
		Range = 9,
	}):Play()

	local motes = Instance.new("ParticleEmitter")
	motes.Name = "Aura"
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface -- desde la superficie, para que no nazcan ocultos dentro
	motes.Rate = 7
	motes.Lifetime = NumberRange.new(1.2, 2)
	motes.Speed = NumberRange.new(0.2, 0.5)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.SpreadAngle = Vector2.new(25, 25)
	motes.Acceleration = Vector3.new(0, 0.4, 0)
	motes.Drag = 1
	motes.Rotation = NumberRange.new(0, 360)
	motes.RotSpeed = NumberRange.new(-30, 30)
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.13),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	motes.Color = ColorSequence.new(accent, Color3.new(1, 1, 1))
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Parent = body
end

-- Lanzagancho sci-fi: el Handle es la empuñadura (lo que sujeta la mano); encima va el cuerpo con riel y
-- franjas de neón, un carrete lateral con la cuerda enrollada, núcleo de energía atrás y cañón con anillos al frente.
-- Devuelve la herramienta, el punto de salida de la cuerda y las piezas de la garra (se ocultan al dispararla).
local function buildGrappleTool(): (Tool, Attachment, { BasePart })
	local tool = Instance.new("Tool")
	tool.Name = "Gancho"
	tool.ToolTip = "Click apuntando a una estructura para enganchar; click de nuevo para soltar; salto para impulsarte"
	tool.CanBeDropped = false
	tool:SetAttribute("Crosshair", true) -- Weapon muestra la mira mientras está equipado
	tool.TextureId = Config.GrappleIconId -- ícono de la barra (assets/icons/gancho.png subido a Roblox)

	local accent = Config.GrappleAccentColor
	local metal, neon = Enum.Material.Metal, Enum.Material.Neon

	local handle = newPart("Handle", Vector3.new(0.3, 0.75, 0.42), HOOK_CARBON, Enum.Material.SmoothPlastic)
	handle.Parent = tool

	-- Empuñadura: tapa inferior y gatillo.
	addToolPart(handle, newPart("GripCap", Vector3.new(0.34, 0.08, 0.48), HOOK_GUNMETAL, metal), CFrame.new(0, -0.4, 0.02))
	addToolPart(handle, newPart("Trigger", Vector3.new(0.06, 0.18, 0.07), HOOK_TRIGGER, Enum.Material.SmoothPlastic), CFrame.new(0, 0.28, -0.3))
	addToolPart(handle, newPart("TriggerGuard", Vector3.new(0.08, 0.05, 0.42), HOOK_GUNMETAL, metal), CFrame.new(0, 0.18, -0.36))

	-- Cuerpo principal con riel superior y franjas de neón a los lados.
	local bodyY = 0.6
	local body = addToolPart(handle, newPart("Body", Vector3.new(0.46, 0.46, 1.5), HOOK_GUNMETAL, metal), CFrame.new(0, bodyY, -0.4))
	addToolPart(handle, newPart("BodyPlate", Vector3.new(0.5, 0.2, 1.1), HOOK_CARBON, Enum.Material.DiamondPlate), CFrame.new(0, bodyY - 0.16, -0.5))
	addToolPart(handle, newPart("Rail", Vector3.new(0.18, 0.08, 1.3), HOOK_CARBON, metal), CFrame.new(0, bodyY + 0.27, -0.4))
	addToolPart(handle, newPart("StripLeft", Vector3.new(0.02, 0.05, 1.1), accent, neon), CFrame.new(-0.24, bodyY + 0.08, -0.45))
	addToolPart(handle, newPart("StripRight", Vector3.new(0.02, 0.05, 1.1), accent, neon), CFrame.new(0.24, bodyY + 0.08, -0.45))

	-- Carrete lateral: dos discos de metal con la cuerda enrollada entre ellos.
	local spool = CFrame.new(0.38, bodyY, 0.05)
	addToolPart(handle, newPart("SpoolCable", Vector3.new(0.26, 0.44, 0.44), Config.GrappleRopeColor, Enum.Material.Fabric, Enum.PartType.Cylinder), spool)
	addToolPart(handle, newPart("SpoolInner", Vector3.new(0.04, 0.58, 0.58), HOOK_STEEL, metal, Enum.PartType.Cylinder), spool * CFrame.new(-0.15, 0, 0))
	addToolPart(handle, newPart("SpoolOuter", Vector3.new(0.04, 0.58, 0.58), HOOK_STEEL, metal, Enum.PartType.Cylinder), spool * CFrame.new(0.15, 0, 0))
	addToolPart(handle, newPart("SpoolCap", Vector3.new(0.05, 0.16, 0.16), accent, neon, Enum.PartType.Cylinder), spool * CFrame.new(0.18, 0, 0))

	-- Núcleo de energía en la parte trasera.
	addToolPart(handle, newPart("CoreHousing", Vector3.new(0.12, 0.44, 0.44), HOOK_STEEL, metal, Enum.PartType.Cylinder), CFrame.new(0, bodyY, 0.36) * ALONG_Z)
	local core = addToolPart(handle, newPart("Core", Vector3.one * 0.32, accent, neon, Enum.PartType.Ball), CFrame.new(0, bodyY, 0.42))

	-- Cañón con dos anillos de neón y freno de boca.
	addToolPart(handle, newPart("Barrel", Vector3.new(0.85, 0.28, 0.28), HOOK_CARBON, metal, Enum.PartType.Cylinder), CFrame.new(0, bodyY, -1.5) * ALONG_Z)
	addToolPart(handle, newPart("BarrelRing1", Vector3.new(0.05, 0.34, 0.34), accent, neon, Enum.PartType.Cylinder), CFrame.new(0, bodyY, -1.3) * ALONG_Z)
	addToolPart(handle, newPart("BarrelRing2", Vector3.new(0.05, 0.34, 0.34), accent, neon, Enum.PartType.Cylinder), CFrame.new(0, bodyY, -1.6) * ALONG_Z)
	addToolPart(handle, newPart("MuzzleBrake", Vector3.new(0.16, 0.4, 0.4), HOOK_STEEL, metal, Enum.PartType.Cylinder), CFrame.new(0, bodyY, -1.9) * ALONG_Z)

	addAura(body, core)

	-- Garra lista en la boca del cañón.
	local clawMount = CFrame.new(0, bodyY, -2.05)
	local claws = {}
	for _, piece in clawLayout(CLAW_OPEN, 1) do
		table.insert(claws, addToolPart(handle, newClawPart(piece), clawMount * piece.offset))
	end

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = clawMount.Position
	muzzle.Parent = handle

	return tool, muzzle, claws
end

local function setClawsVisible(claws: { BasePart }, visible: boolean)
	for _, claw in claws do
		claw.Transparency = if visible then 0 else 1
	end
end

-- Garra que vuela del cañón al punto y se cierra al llegar. Sus piezas van ancladas y se colocan cada frame con poseHook.
local function buildHookProjectile(): (Folder, { BasePart }, Attachment)
	local folder = Instance.new("Folder")
	folder.Name = "GrappleProjectile"
	local parts = {}
	for _, piece in clawLayout(CLAW_OPEN, PROJECTILE_SCALE) do
		local part = newClawPart(piece)
		part.Anchored = true
		part.Parent = folder
		table.insert(parts, part)
	end
	local ropeEnd = Instance.new("Attachment")
	ropeEnd.Name = "RopeEnd"
	ropeEnd.Parent = parts[1]
	return folder, parts, ropeEnd
end

local function poseHook(parts: { BasePart }, cframe: CFrame, open: number)
	for i, piece in clawLayout(open, PROJECTILE_SCALE) do
		parts[i].CFrame = cframe * piece.offset
	end
end
-- Gancho: herramienta en la barra; con ella equipada, un click apuntando a una estructura dispara la garra:
-- vuela hasta el punto, se cierra al agarrarse y entonces jala al personaje hacia ahí.
-- Se suelta al llegar, con otro click, o saltando (doble salto); se conserva el impulso.
local function setupGrapple(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }
	rayParams.RespectCanCollide = true

	local tool, muzzle, claws = buildGrappleTool()

	local lastGrapple = -math.huge
	local hook: Attachment?
	local rope: Beam?
	local projectile: Folder?
	local grappleConnection: RBXScriptConnection?
	local stopPose: (() -> ())?

	local function release()
		if grappleConnection then
			grappleConnection:Disconnect()
			grappleConnection = nil
		end
		if rope then
			rope:Destroy()
			rope = nil
		end
		if projectile then
			projectile:Destroy()
			projectile = nil
		end
		if hook then
			hook:Destroy()
			hook = nil
		end
		if stopPose then
			stopPose()
			stopPose = nil
		end
		setClawsVisible(claws, true)
		character:SetAttribute("Grappling", nil)
	end

	local function fire()
		if hook or humanoid.Health <= 0 or os.clock() - lastGrapple < Config.GrappleCooldown then
			return
		end

		-- Rayo desde la cámara a través del mouse; el alcance se mide desde el personaje.
		local camera = workspace.CurrentCamera
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local maxDistance = Config.GrappleRange + (camera.CFrame.Position - root.Position).Magnitude
		local result = workspace:Raycast(ray.Origin, ray.Direction * maxDistance, rayParams)
		if not result or (result.Position - root.Position).Magnitude > Config.GrappleRange then
			return
		end
		lastGrapple = os.clock()

		-- El punto se ancla a la pieza golpeada, así sigue enganchado aunque la pieza se mueva.
		local newHook = Instance.new("Attachment")
		newHook.Name = "GrappleHook"
		newHook.Parent = result.Instance
		newHook.WorldPosition = result.Position
		hook = newHook

		-- La garra del arma se oculta: es la que sale volando.
		local newProjectile, hookParts, ropeEnd = buildHookProjectile()
		poseHook(hookParts, CFrame.lookAt(muzzle.WorldPosition, newHook.WorldPosition), CLAW_OPEN)
		newProjectile.Parent = workspace
		projectile = newProjectile
		setClawsVisible(claws, false)

		local newRope = Instance.new("Beam")
		newRope.Attachment0 = muzzle
		newRope.Attachment1 = ropeEnd
		newRope.Width0 = 0.15
		newRope.Width1 = 0.15
		newRope.FaceCamera = true
		newRope.Segments = 12
		newRope.Color = ColorSequence.new(Config.GrappleRopeColor)
		newRope.LightEmission = 1
		newRope.Parent = root
		rope = newRope

		character:SetAttribute("Grappling", true)

		local flightTime = (newHook.WorldPosition - muzzle.WorldPosition).Magnitude / Config.GrappleHookSpeed
		local elapsed = 0
		local pulling = false
		grappleConnection = RunService.Heartbeat:Connect(function(dt)
			-- Se suelta si la pieza desaparece o el personaje muere.
			if not newHook.Parent or humanoid.Health <= 0 then
				release()
				return
			end
			elapsed += dt
			local target = newHook.WorldPosition
			local origin = muzzle.WorldPosition
			local facing = CFrame.lookAt(origin, target).Rotation

			-- 1) Vuelo: la garra va abierta y la cuerda floja se tensa conforme se acerca.
			if elapsed < flightTime then
				local alpha = elapsed / flightTime
				poseHook(hookParts, CFrame.new(origin:Lerp(target, alpha)) * facing, CLAW_OPEN)
				newRope.CurveSize0 = Config.GrappleRopeSlack * (1 - alpha)
				newRope.CurveSize1 = -Config.GrappleRopeSlack * (1 - alpha)
				return
			end

			-- 2) Agarre: las puntas se cierran sobre la superficie.
			newRope.CurveSize0 = 0
			newRope.CurveSize1 = 0
			local clamp = math.min((elapsed - flightTime) / Config.GrappleClampTime, 1)
			local eased = TweenService:GetValue(clamp, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			poseHook(hookParts, CFrame.new(target) * facing, CLAW_OPEN + (CLAW_CLOSED - CLAW_OPEN) * eased)
			if clamp < 1 then
				return
			end

			-- 3) Jalón hacia el punto; se suelta solo al llegar.
			if not pulling then
				pulling = true
				humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
				stopPose = startGrapplePose(character, root, function()
					return if newHook.Parent then newHook.WorldPosition - root.Position else nil
				end)
			end
			local offset = target - root.Position
			if offset.Magnitude <= Config.GrappleReleaseDistance then
				release()
				return
			end
			root.AssemblyLinearVelocity = offset.Unit * Config.GrapplePullSpeed
		end)
	end

	-- La herramienta se crea en el cliente para el prototipo; la mochila se vacía sola al reaparecer.
	-- Un click engancha (no hay que mantenerlo); otro click con el gancho puesto lo suelta.
	activeGrappleRelease = release
	tool.Activated:Connect(function()
		if hook then
			release()
		else
			fire()
		end
	end)
	tool.Unequipped:Connect(release)
	tool.Parent = player:WaitForChild("Backpack")

	humanoid.Died:Once(release)
end
local function setupCharacter(character: Model)
	task.spawn(setupDoubleJump, character)
	task.spawn(setupSprint, character)
	task.spawn(setupGrapple, character)
end
return {
	Start = function()
		if player.Character then
			setupCharacter(player.Character)
		end
		player.CharacterAdded:Connect(setupCharacter)
	end,
}