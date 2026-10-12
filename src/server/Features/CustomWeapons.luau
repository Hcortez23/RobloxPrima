-- Convierte modelos puestos en el mapa (ej. del Marketplace) en armas equipables, según Config.Weapon.CustomWeapons.
-- Al iniciar: copia el efecto de disparo (ShotEffect) a ReplicatedStorage.WeaponEffects (el aura
-- del arma se rehace pegada a sus piezas), arma un Tool con las piezas soldadas a una empuñadura, calcula hacia dónde apunta y dónde está la boca (Muzzle), y lo pone en StarterPack.
-- Weapon (servidor y cliente) dispara con cualquier Tool con atributo Weapon, usando su Damage y su ShotEffect.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")

local Config = require(ReplicatedStorage.Shared.Config.Weapon)
local EffectCopy = require(ReplicatedStorage.Shared.EffectCopy)

local function effectsFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild("WeaponEffects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "WeaponEffects"
		folder.Parent = ReplicatedStorage
	end
	return folder :: Folder
end

-- Caja que envuelve todas las piezas, medida en el espacio de la empuñadura.
local function boundsInHandleSpace(handle: BasePart, parts: { BasePart }): (Vector3, Vector3)
	local min, max = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in parts do
		local half = part.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = handle.CFrame:PointToObjectSpace(part.CFrame:PointToWorldSpace(half * Vector3.new(sx, sy, sz)))
					min, max = min:Min(corner), max:Max(corner)
				end
			end
		end
	end
	return min, max
end

-- Skin: pinta las piezas por tamaño (Body / Trim / Glow), quita texturas que la taparían, agrupa las piezas en un
-- Model para poder ponerle un contorno (Highlight) y agrega una luz del color de la skin.
local function applySkin(tool: Tool, handle: BasePart, gunParts: { BasePart }, skin)
	-- sin Body la skin no repinta (sirve para armas que ya traen su textura)
	if skin.Body then
		local visible = {}
		for _, part in gunParts do
			if part.Transparency < 1 then
				table.insert(visible, part)
			end
		end
		table.sort(visible, function(a, b)
			return a.Size.X * a.Size.Y * a.Size.Z > b.Size.X * b.Size.Y * b.Size.Z
		end)
		local meshes, unions, textured = 0, 0, 0
		for i, part in visible do
			local look = if i <= math.ceil(#visible * 0.45) then skin.Body
				elseif i <= math.ceil(#visible * 0.8) then skin.Trim
				else skin.Glow
			part.Color = look.Color
			part.Material = look.Material
			part.Reflectance = 0
			if part:IsA("UnionOperation") then
				unions += 1
				part.UsePartColor = true -- sin esto la unión conserva sus colores originales
			elseif part:IsA("MeshPart") then
				meshes += 1
				if part.TextureID ~= "" then
					-- la textura original taparía el color; si Roblox no deja quitarla, se avisa abajo
					if not pcall(function() part.TextureID = "" end) then
						textured += 1
					end
				end
			end
			for _, child in part:GetDescendants() do
				if child:IsA("SurfaceAppearance") or child:IsA("Decal") then -- Decal incluye Texture
					child:Destroy()
				end
			end
		end
		print(`[CustomWeapons] skin aplicada a "{tool.Name}": {#visible} piezas ({meshes} MeshPart, {unions} uniones)`)
		if textured > 0 then
			warn(`[CustomWeapons] {textured} MeshPart(s) de "{tool.Name}" conservan su textura y no toman el color de la skin`)
		end
	end

	if skin.Outline then
		-- Highlight necesita un Model o una pieza: el resto del arma va a un Model y la empuñadura lleva el suyo.
		local body = Instance.new("Model")
		body.Name = "Body"
		for _, part in gunParts do
			if part ~= handle then
				part.Parent = body
			end
		end
		body.Parent = tool
		for _, adornee in { body, handle } do
			local outline = Instance.new("Highlight")
			outline.Name = "SkinOutline"
			outline.FillTransparency = 1
			outline.OutlineColor = skin.Outline
			outline.OutlineTransparency = 0
			outline.DepthMode = Enum.HighlightDepthMode.Occluded
			outline.Adornee = adornee
			outline.Parent = adornee
		end
	end

	if skin.Light then
		local light = Instance.new("PointLight")
		light.Name = "SkinLight"
		light.Color = skin.Light
		light.Range = 8
		light.Brightness = 1.5
		light.Shadows = false
		light.Parent = handle
	end
end

local function build(entry): Tool?
	-- primero la ruta exacta; si se movió, por su nombre en cualquier parte del Workspace
	local current: Instance? = workspace
	for _, name in entry.Path do
		current = current and current:FindFirstChild(name)
	end
	local source = current or workspace:FindFirstChild(entry.Path[#entry.Path], true)
	if not source then
		warn(`[CustomWeapons] no se encontró {table.concat(entry.Path, ".")} en Workspace`)
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = entry.ToolName
	tool.CanBeDropped = false
	tool:SetAttribute("Weapon", true)
	tool:SetAttribute("Crosshair", true)
	tool:SetAttribute("Damage", entry.Damage)

	-- Una copia del aura va a ReplicatedStorage.WeaponEffects para que los clientes la pongan en cada disparo;
	-- el aura del arma se rehace más abajo pegada al arma. Por seguridad no se conservan scripts del Marketplace.
	local effect: Instance? = nil
	local auraPivot, auraSize = CFrame.identity, Vector3.one
	if entry.ShotEffect then
		effect = source:FindFirstChild(entry.ShotEffect)
		if effect then
			for _, descendant in effect:GetDescendants() do
				if descendant:IsA("LuaSourceContainer") then
					descendant:Destroy()
				end
			end
			-- dónde estaba y cuánto medía el aura, medido mientras sigue en el mapa
			auraPivot, auraSize = EffectCopy.pivot(effect), EffectCopy.extents(effect)
			local shot = effect:Clone()
			EffectCopy.boostVisibility(shot, Config.ShotAuraBoost) -- intensidad del aura en los disparos
			shot.Name = entry.ToolName
			if entry.TrailColor then
				shot:SetAttribute("TrailColor", entry.TrailColor) -- el cliente la usa para el rastro de bala
			end
			shot.Parent = effectsFolder()
			tool:SetAttribute("ShotEffect", entry.ToolName)
		else
			warn(`[CustomWeapons] "{source.Name}" no tiene "{entry.ShotEffect}"; los disparos usarán el trazador normal`)
		end
	end

	-- Pasa el contenido del modelo al Tool.
	if source:IsA("BasePart") then
		source.Parent = tool
	else
		for _, child in source:GetChildren() do
			child.Parent = tool
		end
		source:Destroy()
	end

	-- solo las piezas del arma (sin las del aura): empuñadura, soldaduras y hacia dónde apunta
	local gunParts = {}
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") then
			if not (effect and descendant:IsDescendantOf(effect)) then
				table.insert(gunParts, descendant)
			end
		end
	end
	if #gunParts == 0 then
		warn(`[CustomWeapons] "{entry.ToolName}" no tiene piezas`)
		return nil
	end

	-- Empuñadura: la pieza llamada Handle o, si no hay, la más grande del arma. Debe ser hija directa del Tool.
	local handle = tool:FindFirstChild("Handle", true)
	if not (handle and handle:IsA("BasePart")) then
		local bestVolume = 0
		for _, part in gunParts do
			local volume = part.Size.X * part.Size.Y * part.Size.Z
			if volume > bestVolume then
				handle, bestVolume = part, volume
			end
		end
	end
	handle = handle :: BasePart
	handle.Name = "Handle"
	handle.Parent = tool

	local min, max = boundsInHandleSpace(handle, gunParts)
	local size, center = max - min, (min + max) / 2

	-- Hacia dónde apunta: el eje más largo del arma. Se toma su lado negativo como frente (convención de Roblox:
	-- -Z es "adelante"); si el arma sale al revés, poner FlipFront = true en el config.
	local axis = if size.X >= size.Y and size.X >= size.Z then Vector3.xAxis elseif size.Y >= size.Z then Vector3.yAxis else Vector3.zAxis
	local length = size:Dot(axis)
	local front = if entry.FlipFront then axis else -axis

	-- Aura del arma: se rehace dentro de la empuñadura, encajada en el tamaño y la forma del arma, con las
	-- partículas fijas a la pieza y lentas para que no se esparzan fuera del arma. Luego se borra la original.
	if effect then
		-- AuraBack: studs que se corre el aura hacia atrás (hacia la culata) desde el centro del arma
		local auraCenter = center - front * (entry.AuraBack or 0)
		local gunPivot = handle.CFrame * CFrame.new(auraCenter)
		local scale = size.Magnitude / math.max(auraSize.Magnitude, 0.01) * Config.WeaponAuraScale
		EffectCopy.copy(effect, handle, scale, auraPivot, gunPivot)
		for _, copied in handle:GetDescendants() do
			if copied:IsA("ParticleEmitter") and copied.Name == EffectCopy.NAME then
				copied.LockedToPart = true
				copied.Speed = NumberRange.new(copied.Speed.Min * 0.3, copied.Speed.Max * 0.3)
				copied.Acceleration = Vector3.zero
				copied.Drag = math.max(copied.Drag, 3)
			end
		end
		if entry.AuraBack then
			-- lo que emitía desde toda la superficie del arma pasa a salir del punto de atrás
			local anchor = Instance.new("Attachment")
			anchor.Name = EffectCopy.NAME
			anchor.Position = auraCenter
			anchor.Parent = handle
			for _, copied in handle:GetChildren() do
				if copied.Name == EffectCopy.NAME and (copied:IsA("ParticleEmitter") or copied:IsA("Light") or copied:IsA("Fire") or copied:IsA("Smoke") or copied:IsA("Sparkles")) then
					copied.Parent = anchor
				end
			end
		end
		EffectCopy.boostVisibility(handle, Config.WeaponAuraBoost) -- intensidad del aura del arma
		effect:Destroy()
	end

	for _, part in gunParts do
		part.CanCollide = false
		part.CanTouch = false
		part.Massless = true
		if part ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = handle
		end
	end
	for _, part in gunParts do
		part.Anchored = false
	end

	if entry.Skin then
		local skin = Config.Skins[entry.Skin]
		if skin then
			applySkin(tool, handle, gunParts, skin)
		else
			warn(`[CustomWeapons] no existe la skin "{entry.Skin}" en Config.Weapon.Skins`)
		end
	end

	local up = if math.abs(front.Y) > 0.9 then Vector3.zAxis else Vector3.yAxis

	-- Boca del cañón: un Attachment llamado Muzzle si el modelo lo trae; si no, la punta del frente, subida MuzzleUp studs
	-- (el cañón suele ir arriba del centro del arma).
	local muzzle = tool:FindFirstChild("Muzzle", true)
	if not (muzzle and muzzle:IsA("Attachment")) then
		muzzle = Instance.new("Attachment")
		muzzle.Name = "Muzzle"
		muzzle.Position = center + front * (length / 2) + up * (entry.MuzzleUp or 0)
		muzzle.Parent = handle
	end

	-- Dónde la sostiene la mano: GripAlong es la fracción del largo desde el centro (negativo = hacia atrás; agarrarla
	-- más adelante acerca el arma a la cámara) y GripDrop baja el punto de agarre en studs (sube el arma en pantalla).
	local gripPoint = center + front * (length * (entry.GripAlong or -0.25)) - up * (entry.GripDrop or 0)
	tool.Grip = CFrame.lookAt(gripPoint, gripPoint + front, up)

	return tool
end

return {
	Start = function()
		for _, entry in Config.CustomWeapons do
			task.spawn(function()
				local tool = build(entry)
				if not tool then
					return
				end
				tool.Parent = StarterPack -- se entrega en cada respawn
				for _, player in Players:GetPlayers() do
					local backpack = player:FindFirstChild("Backpack")
					if backpack then
						tool:Clone().Parent = backpack
					end
				end
			end)
		end
	end,
}
