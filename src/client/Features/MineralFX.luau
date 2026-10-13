-- Efectos llamativos en los minerales cercanos (tag "Mineral") según su rareza, ver Config/MineralFX:
-- luz que late, contorno brillante, destellos, partículas que suben, cometas en órbita, rayos de luz girando,
-- un destello fuerte en estrella cada pocos segundos, y giro + flotación en los modelos de assets/models/Minerals. Todo es visual y solo en el cliente:
-- el servidor (Minerals.luau) sigue usando la posición original para disparos y explosiones.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.MineralFX)
local Minerals = require(ReplicatedStorage.Shared.Config.Minerals)

-- Destello: estrella de UI en un BillboardGui, luz que se dispara y ráfaga de chispas.
type Flash = { gui: BillboardGui, bars: { Frame }, light: PointLight, sparks: ParticleEmitter, glare: ParticleEmitter }

type Active = {
	mineral: PVInstance,
	settings: { [string]: any },
	base: CFrame, -- pivote original, alrededor del cual gira y flota
	radius: number,
	phase: number, -- desfase para que no floten todos al mismo ritmo
	comets: { { a: Attachment, b: Attachment, tilt: CFrame, speed: number, offset: number } },
	rays: { Attachment },
	effects: { Instance },
	flash: Flash,
	nextFlash: number,
}

local active: { [Instance]: Active } = {}

local function sizeOf(mineral: PVInstance): Vector3
	return if mineral:IsA("Model") then mineral:GetExtentsSize() else (mineral :: BasePart).Size
end

local function particle(parent: Instance, color: Color3, rate: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rate = rate
	emitter.Shape = Enum.ParticleEmitterShape.Sphere
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.Parent = parent
	return emitter
end

-- Degradado de arcoíris empezando en `startHue` (0-1); se cambia en cada destello para que varíen los colores.
local function rainbow(startHue: number): ColorSequence
	local keypoints = {}
	for k = 0, 6 do
		table.insert(keypoints, ColorSequenceKeypoint.new(k / 6, Color3.fromHSV((startHue + k / 6) % 1, 0.75, 1)))
	end
	return ColorSequence.new(keypoints)
end

-- Barra de luz de la estrella del destello: delgada, centrada y con las puntas desvanecidas.
local function glintBar(parent: Instance, rotation: number, thickness: number, color: Color3): Frame
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.5)
	bar.Size = UDim2.fromScale(0, thickness)
	bar.Rotation = rotation
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar:SetAttribute("Thickness", thickness)
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = bar
	bar.Parent = parent
	return bar
end

local function makeFlash(volume: BasePart, color: Color3, radius: number, sizeFactor: number): Flash
	local span = radius * 2 * sizeFactor
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(span, span) -- en studs: escala con la distancia como un objeto del mundo
	gui.LightInfluence = 0
	gui.Brightness = 3
	gui.Adornee = volume
	gui.Enabled = false
	gui.Parent = volume
	local white = Color3.new(1, 1, 1)
	local tint = color:Lerp(white, 0.5)
	local bars = {
		glintBar(gui, 0, 0.05, white),
		glintBar(gui, 90, 0.05, white),
		glintBar(gui, 45, 0.025, tint),
		glintBar(gui, -45, 0.025, tint),
	}
	-- núcleo redondo de la estrella
	local core = Instance.new("Frame")
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromScale(0, 0)
	core.BackgroundColor3 = white
	core.BorderSizePixel = 0
	core:SetAttribute("Core", true)
	Instance.new("UICorner", core).CornerRadius = UDim.new(0.5, 0)
	local coreGradient = Instance.new("UIGradient")
	coreGradient.Color = ColorSequence.new(white, tint)
	coreGradient.Parent = core
	core.Parent = gui
	table.insert(bars, core)
	if Config.FlashRainbow then
		-- fondos en blanco: el UIGradient pone los colores encima
		for _, bar in bars do
			bar.BackgroundColor3 = white
		end
	end

	local light = Instance.new("PointLight")
	light.Color = tint
	light.Brightness = 0
	light.Range = radius * 6
	light.Shadows = false
	light.Parent = volume

	local sparks = particle(volume, color, 0)
	sparks.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	sparks.Lifetime = NumberRange.new(0.4, 0.8)
	sparks.Speed = NumberRange.new(radius * 3, radius * 6)
	sparks.Drag = 4
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, math.clamp(radius * 0.12, 0.2, 0.8)),
		NumberSequenceKeypoint.new(1, 0),
	})

	-- resplandor grande y breve detrás de la estrella
	local glare = particle(volume, color, 0)
	glare.Shape = Enum.ParticleEmitterShape.Box
	glare.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	glare.Lifetime = NumberRange.new(0.3)
	glare.Speed = NumberRange.new(0)
	glare.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, radius * sizeFactor * 0.6),
		NumberSequenceKeypoint.new(1, radius * sizeFactor * 1.2),
	})
	glare.Transparency = NumberSequence.new(0.2, 1)

	return { gui = gui, bars = bars, light = light, sparks = sparks, glare = glare }
end

local function playFlash(entry: Active)
	local flash = entry.flash
	-- aparece en un punto al azar de la superficie, no siempre en el centro
	local offset = Random.new():NextUnitVector() * entry.radius * 0.5
	flash.gui.StudsOffsetWorldSpace = offset
	flash.gui.Enabled = true

	-- arcoíris con un tono de inicio distinto cada vez; cada brazo de la estrella va desfasado
	local hue = math.random()
	if Config.FlashRainbow then
		for i, bar in flash.bars do
			bar:FindFirstChildOfClass("UIGradient").Color = rainbow(hue + i * 0.17)
		end
		flash.light.Color = Color3.fromHSV(hue, 0.6, 1)
		flash.glare.Color = ColorSequence.new(Color3.fromHSV(hue, 0.7, 1), Color3.fromHSV((hue + 0.4) % 1, 0.7, 1))
	end

	local grow = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fade = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, bar in flash.bars do
		bar.BackgroundTransparency = 0
		if bar:GetAttribute("Core") then
			bar.Size = UDim2.fromScale(0, 0)
			TweenService:Create(bar, grow, { Size = UDim2.fromScale(0.14, 0.14) }):Play()
		else
			local thickness = bar:GetAttribute("Thickness")
			local length = if thickness >= 0.05 then 1 else 0.6
			bar.Size = UDim2.fromScale(0, thickness)
			TweenService:Create(bar, grow, { Size = UDim2.fromScale(length, thickness) }):Play()
		end
		task.delay(0.1, function()
			TweenService:Create(bar, fade, { BackgroundTransparency = 1 }):Play()
		end)
	end
	task.delay(0.6, function()
		flash.gui.Enabled = false
	end)

	flash.light.Brightness = entry.settings.Light * 3 + 4
	TweenService:Create(flash.light, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	flash.glare:Emit(1)
	if Config.FlashSparks then
		flash.sparks:Emit(math.floor(8 + entry.radius * 3))
	end
end

local function setup(mineral: Instance)
	if active[mineral] or not mineral:IsA("PVInstance") or mineral:IsA("Workspace") then
		return
	end
	-- Las plantillas de ReplicatedStorage no se animan; solo los minerales del mapa.
	if not mineral:IsDescendantOf(workspace) then
		return
	end
	local rarity = mineral:GetAttribute("Rarity")
	local settings = Config[rarity]
	if not settings then
		return
	end
	local color = if Minerals[rarity] then Minerals[rarity].Color else Color3.new(1, 1, 1)
	local size = sizeOf(mineral :: PVInstance)
	local radius = size.Magnitude / 2
	local base = (mineral :: PVInstance):GetPivot()
	local effects = {}

	-- Volumen invisible del tamaño del mineral: de su superficie salen las partículas y en él van las luces.
	local volume = Instance.new("Part")
	volume.Name = "MineralFX"
	volume.Shape = Enum.PartType.Ball
	volume.Size = Vector3.one * math.max(size.X, size.Y, size.Z) * 0.8
	volume.CFrame = base
	volume.Transparency = 1
	volume.Anchored = true
	volume.CanCollide = false
	volume.CanQuery = false
	volume.CanTouch = false
	volume.CastShadow = false
	volume.Parent = mineral
	table.insert(effects, volume)

	local pulse = TweenInfo.new(Config.PulseTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

	if settings.Light > 0 then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = settings.LightRange
		light.Brightness = settings.Light * 0.4
		light.Shadows = false
		light.Parent = volume
		TweenService:Create(light, pulse, { Brightness = settings.Light }):Play()
	end

	if settings.Highlight then
		local highlight = Instance.new("Highlight")
		highlight.Name = "MineralFX"
		highlight.FillColor = color
		highlight.OutlineColor = color:Lerp(Color3.new(1, 1, 1), 0.4)
		highlight.FillTransparency = 0.85
		highlight.OutlineTransparency = 0.5
		highlight.Adornee = mineral
		highlight.Parent = mineral
		table.insert(effects, highlight)
		TweenService:Create(highlight, pulse, { FillTransparency = 0.6, OutlineTransparency = 0 }):Play()
	end

	-- Destellos tipo estrella que aparecen y desaparecen sobre la superficie.
	if settings.Twinkles > 0 then
		local twinkles = particle(volume, color, settings.Twinkles)
		twinkles.Lifetime = NumberRange.new(0.4, 0.9)
		twinkles.Speed = NumberRange.new(0)
		twinkles.Rotation = NumberRange.new(0, 360)
		twinkles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, math.clamp(radius * 0.18, 0.4, 1.2)),
			NumberSequenceKeypoint.new(1, 0),
		})
	end

	-- Partículas de energía que suben despacio y se desvanecen.
	if settings.Motes > 0 then
		local motes = particle(volume, color, settings.Motes)
		motes.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		motes.Lifetime = NumberRange.new(1.2, 2)
		motes.Speed = NumberRange.new(0.5, 1.5)
		motes.Acceleration = Vector3.new(0, 2, 0)
		motes.Drag = 0.5
		motes.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 0),
		})
		motes.Transparency = NumberSequence.new(0.1, 1)
	end

	-- Cometas: dos Attachments que orbitan y una estela (Trail) entre ellos.
	local comets = {}
	for i = 1, settings.Comets do
		local a = Instance.new("Attachment")
		a.Parent = volume
		local b = Instance.new("Attachment")
		b.Parent = volume
		local trail = Instance.new("Trail")
		trail.Attachment0 = a
		trail.Attachment1 = b
		trail.Lifetime = 0.45
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.FaceCamera = true
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		trail.Transparency = NumberSequence.new(0, 1)
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Parent = volume
		table.insert(comets, {
			a = a,
			b = b,
			tilt = CFrame.Angles(math.rad(25 + i * 35), math.rad(i * 70), 0),
			speed = 2.2 + i * 0.4,
			offset = i * math.pi * 2 / settings.Comets,
		})
	end

	-- Rayos: haces de luz del centro hacia afuera que se van desvaneciendo y giran lentamente.
	local rays = {}
	if settings.Rays > 0 then
		local center = Instance.new("Attachment")
		center.Parent = volume
		for _ = 1, settings.Rays do
			local tip = Instance.new("Attachment")
			tip.Parent = volume
			local beam = Instance.new("Beam")
			beam.Attachment0 = center
			beam.Attachment1 = tip
			beam.Width0 = radius * 0.5
			beam.Width1 = radius * 0.05
			beam.FaceCamera = true
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.5), color)
			beam.Transparency = NumberSequence.new(0.55, 1)
			beam.Parent = volume
			table.insert(rays, tip)
		end
	end

	active[mineral] = {
		mineral = mineral :: PVInstance,
		settings = settings,
		base = base,
		radius = radius,
		phase = math.random() * math.pi * 2,
		comets = comets,
		rays = rays,
		effects = effects,
		flash = makeFlash(volume, color, radius, settings.FlashSize),
		nextFlash = os.clock() + math.random() * settings.FlashEvery,
	}
end

local function cleanup(mineral: Instance)
	local entry = active[mineral]
	if not entry then
		return
	end
	active[mineral] = nil
	if mineral.Parent and mineral:GetAttribute("MineralModel") then
		entry.mineral:PivotTo(entry.base) -- deja el modelo quieto en su lugar original
	end
	for _, effect in entry.effects do
		effect:Destroy()
	end
end

return {
	Start = function()
		-- Solo los minerales cerca de la cámara llevan efectos y tienen su luz encendida: con cientos de minerales en el
		-- mundo, tenerlos todos activos costaría mucho. Se revisa cada medio segundo.
		local function refresh()
			local camPos = workspace.CurrentCamera.CFrame.Position
			for _, mineral in CollectionService:GetTagged("Mineral") do
				if mineral:IsA("PVInstance") and mineral:IsDescendantOf(workspace) then
					local dist = ((mineral :: PVInstance):GetPivot().Position - camPos).Magnitude
					local light = mineral:FindFirstChildOfClass("PointLight") -- la luz propia del mineral (la pone el servidor)
					if light then
						light.Enabled = dist <= Config.LightRadius
					end
					if dist <= Config.ActiveRadius and not active[mineral] then
						setup(mineral)
					elseif dist > Config.ActiveRadius + 20 and active[mineral] then
						cleanup(mineral)
					end
				end
			end
		end
		CollectionService:GetInstanceRemovedSignal("Mineral"):Connect(cleanup)
		task.spawn(function()
			while true do
				refresh()
				task.wait(0.5)
			end
		end)

		RunService.RenderStepped:Connect(function()
			local t = os.clock()
			for mineral, entry in active do
				if not mineral.Parent then
					cleanup(mineral)
					continue
				end
				local settings = entry.settings

				if t >= entry.nextFlash then
					entry.nextFlash = t + settings.FlashEvery * (0.7 + math.random() * 0.6)
					playFlash(entry)
				end

				-- Giro y flotación solo en los modelos generados (no en modelos del Marketplace ni placeholders).
				local pivot = entry.base
				if mineral:GetAttribute("MineralModel") and (settings.Spin > 0 or settings.Bob > 0) then
					pivot = entry.base
						* CFrame.new(0, math.sin(t * 1.6 + entry.phase) * settings.Bob, 0)
						* CFrame.Angles(0, math.rad(t * settings.Spin), 0)
					entry.mineral:PivotTo(pivot)
				end

				local orbit = entry.radius * 1.15
				for _, comet in entry.comets do
					local angle = t * comet.speed + comet.offset
					local point = comet.tilt * Vector3.new(math.cos(angle) * orbit, 0, math.sin(angle) * orbit)
					local up = comet.tilt.UpVector * 0.15 * entry.radius
					comet.a.WorldPosition = entry.base.Position + point + up
					comet.b.WorldPosition = entry.base.Position + point - up
				end

				local reach = entry.radius * 2.2
				for i, tip in entry.rays do
					local angle = t * 0.35 + i * math.pi * 2 / #entry.rays
					local lift = math.sin(t * 0.8 + i) * 0.5
					tip.WorldPosition = entry.base.Position + Vector3.new(math.cos(angle), lift, math.sin(angle)).Unit * reach
				end
			end
		end)
	end,
}
