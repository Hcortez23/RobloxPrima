-- Aura elegante para cualquier Model o BasePart con el tag "Aura" (se pone en Studio: Properties -> Tags)
-- o cuyo nombre esté en Config.Aura.WorkspaceTargets.
-- Además copia efectos de modelos de VFX (ej. del Marketplace, ver shared/EffectCopy) a otros objetos según
-- Config.Aura.CopyEffects y a todos los minerales de una rareza según Config.Aura.RarityEffects.
-- (Config.Aura.TransferEffects lo hace el servidor: server/Features/AuraTransfer.)
-- Contorno brillante que "respira", luz suave y destellos finos que flotan desde la superficie.
-- Color opcional con el atributo AuraColor (Color3) en el objeto; si no, usa el de Config/Aura.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.Aura)
local EffectCopy = require(ReplicatedStorage.Shared.EffectCopy)

local TAG = "Aura"
local NAME = EffectCopy.NAME -- nombre de todo lo que crea el aura, para poder quitarlo

local largestPart = EffectCopy.largestPart
local findInWorkspace = EffectCopy.findInWorkspace
local findEffectSource = EffectCopy.findSource
local copyEffects = EffectCopy.copy

local function removeAura(target: Instance)
	for _, child in target:GetDescendants() do
		if child.Name == NAME then
			child:Destroy()
		end
	end
end
local function addAura(target: Instance)
	if not (target:IsA("Model") or target:IsA("BasePart")) then
		return
	end
	removeAura(target)
	local color = target:GetAttribute("AuraColor")
	if typeof(color) ~= "Color3" then
		color = Config.Color
	end
	local pulse = TweenInfo.new(Config.PulseTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

	-- Contorno y relleno tenue que respiran.
	local highlight = Instance.new("Highlight")
	highlight.Name = NAME
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.92
	highlight.OutlineTransparency = 0.6
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = target
	highlight.Parent = target
	TweenService:Create(highlight, pulse, { FillTransparency = 0.8, OutlineTransparency = 0.15 }):Play()

	local part = largestPart(target)
	if not part then
		return
	end
	local radius = part.Size.Magnitude / 2

	local glow = Instance.new("PointLight")
	glow.Name = NAME
	glow.Color = color
	glow.Shadows = false
	glow.Range = radius + 4
	glow.Brightness = 0.6
	glow.Parent = part
	TweenService:Create(glow, pulse, { Brightness = 1.6, Range = radius + 7 }):Play()

	-- Destellos: la cantidad crece con el tamaño de la pieza, sin pasar de un tope para que siga siendo sutil.
	local motes = Instance.new("ParticleEmitter")
	motes.Name = NAME
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	motes.Rate = math.clamp(radius * 3, 4, Config.MaxParticles)
	motes.Lifetime = NumberRange.new(1.4, 2.4)
	motes.Speed = NumberRange.new(0.3, 0.8)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.SpreadAngle = Vector2.new(30, 30)
	motes.Acceleration = Vector3.new(0, 0.6, 0)
	motes.Drag = 1
	motes.Rotation = NumberRange.new(0, 360)
	motes.RotSpeed = NumberRange.new(-30, 30)
	local moteSize = math.clamp(radius * 0.06, 0.12, 0.4)
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, moteSize),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	motes.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Parent = part
end

return {
	Start = function()
		CollectionService:GetInstanceAddedSignal(TAG):Connect(addAura)
		CollectionService:GetInstanceRemovedSignal(TAG):Connect(removeAura)
		for _, target in CollectionService:GetTagged(TAG) do
			task.spawn(addAura, target)
		end
		-- Objetos puestos a mano en Workspace (ej. modelos del Marketplace), buscados por nombre.
		for _, name in Config.WorkspaceTargets do
			task.spawn(function()
				local target = workspace:WaitForChild(name, 10)
				if target then
					addAura(target)
				else
					warn(`[Aura] no se encontró "{name}" en Workspace`)
				end
			end)
		end
		-- Efectos por rareza: todos los minerales del mapa de esa rareza reciben los efectos del modelo indicado.
		for rarity, path in Config.RarityEffects do
			task.spawn(function()
				local source = findEffectSource(path)
				if not source then
					warn(`[Aura] no se encontró {table.concat(path, ".")} para los minerales {rarity}`)
					return
				end
				local function apply(mineral: Instance)
					if mineral:GetAttribute("Rarity") == rarity and mineral:IsDescendantOf(workspace) then
						copyEffects(source, mineral)
					end
				end
				CollectionService:GetInstanceAddedSignal("Mineral"):Connect(apply)
				for _, mineral in CollectionService:GetTagged("Mineral") do
					apply(mineral)
				end
			end)
		end

		-- Efectos copiados de un modelo de VFX a otro objeto, solo en este cliente (ver Config.Aura.CopyEffects).
		for _, entry in Config.CopyEffects do
			task.spawn(function()
				local source = findEffectSource(entry.From)
				local target = findInWorkspace(entry.To)
				if source and target then
					copyEffects(source, target)
				else
					warn(`[Aura] no se encontró {table.concat(if source then entry.To else entry.From, ".")} en Workspace`)
				end
			end)
		end
	end,
}
