-- Mural de exhibición: 5 estands en cada cueva-base (sobre las marcas "MuralSlot" que pone Bases.luau) donde el dueño
-- exhibe sus minerales más valiosos. Cada estand es una vitrina: zócalo, columna, caja de vidrio con luz suave, el
-- mineral girando adentro (modelo de assets/models/Minerals, lo anima el cliente) y una placa con nombre, cantidad y
-- valor. El del centro es más grande: el trofeo con el mineral más valioso.
--  · Por defecto se llenan solos con los tipos que el dueño tiene guardados, del más valioso al menos (centro,
--    luego a los lados).
--  · Poner un mineral: con un mineral de la mochila en la mano, el aviso del estand lo coloca ahí (lo que llevas de
--    ese tipo pasa al almacén de la base, a salvo) y ese estand lo muestra (atributo Mural_<estand>). Sin nada en la
--    mano, el aviso cambia el estand al siguiente tipo guardado.
--  · Exhibir no gasta nada: el mineral sigue en el almacén y se puede vender (NUCLEO_FRACTURA.md: Mural).
--  · Los visitantes ven el mural de cualquier base.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Minerals = require(ReplicatedStorage.Shared.Config.Minerals)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Bases = require(script.Parent.Bases)
local Inventory = require(script.Parent.Inventory)
local SignKit = require(script.Parent.SignKit)

local DARK = Color3.fromRGB(40, 42, 48)
local STEEL = Color3.fromRGB(96, 100, 108)
local GLASS = Color3.fromRGB(190, 215, 235)
local HAZARD = Color3.fromRGB(230, 180, 40)

local notify: RemoteEvent
local RANK_ORDER = { 3, 2, 4, 1, 5 } -- en qué estand va el 1º, 2º... más valioso (el centro primero)
local TROPHY = 3 -- el estand del centro, más grande

-- tipos del más valioso al menos
local TYPES = {}
for key in Minerals do table.insert(TYPES, key) end
table.sort(TYPES, function(a, b) return (Minerals[a].Value or 0) > (Minerals[b].Value or 0) end)
local NAMES = { Comun = "Común", Epico = "Épico" }
local function displayName(key: string): string
	return Minerals[key].Name or NAMES[key] or key
end

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanTouch = name, true, false
	p.Size, p.CFrame, p.Color, p.Material = size, cframe, color, material
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function deco(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = part(parent, name, size, cframe, color, material)
	p.CanCollide, p.CanQuery, p.CastShadow = false, false, false
	return p
end

type Stand = {
	slot: number,
	frame: CFrame, -- piso del estand; -Z (LookVector) hacia el centro de la base
	scale: number,
	model: Model,
	showcase: CFrame, -- dónde va el mineral (centro de la vitrina)
	plaque: TextLabel, -- nombre del mineral
	plaqueSub: TextLabel, -- cantidad y valor
	glow: PointLight,
	prompt: ProximityPrompt, -- solo el dueño lo ve (client/Features/Mural)
	exhibit: Instance?,
	shown: string?, -- clave del mineral que muestra ahora (y su cantidad), para no rehacerlo si no cambió
}

-- Vitrina vacía (el mineral se pone aparte). `s` escala todo el estand.
local function buildStand(parent: Instance, slot: number, frame: CFrame, color: Color3): Stand
	local s = if slot == TROPHY then 1.35 else 1
	local model = Instance.new("Model")
	model.Name = `MuralStand{slot}`
	model.Parent = parent
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x * s, y * s, z * s)
	end
	part(model, "Plinth", Vector3.new(4, 0.8, 4) * s, at(0, 0.4, 0), DARK, Enum.Material.DiamondPlate)
	deco(model, "PlinthTrim", Vector3.new(4.1, 0.15, 4.1) * s, at(0, 0.82, 0), color, Enum.Material.Neon)
	part(model, "Column", Vector3.new(2.8, 2.6, 2.8) * s, at(0, 2.1, 0), STEEL, Enum.Material.Metal)
	part(model, "Table", Vector3.new(3.4, 0.3, 3.4) * s, at(0, 3.55, 0), DARK, Enum.Material.Metal)
	local glass = part(model, "Glass", Vector3.new(3.1, 3.4, 3.1) * s, at(0, 5.4, 0), GLASS, Enum.Material.Glass)
	glass.Transparency, glass.CastShadow = 0.82, false
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do -- aristas de la vitrina
		deco(model, "GlassEdge", Vector3.new(0.18, 3.4, 0.18) * s, at(c[1] * 1.55, 5.4, c[2] * 1.55), STEEL, Enum.Material.Metal)
	end
	part(model, "Cap", Vector3.new(3.5, 0.45, 3.5) * s, at(0, 7.3, 0), DARK, Enum.Material.Metal)
	local lamp = deco(model, "CapLight", Vector3.new(2.2, 0.08, 2.2) * s, at(0, 7.05, 0), Color3.new(1, 1, 1), Enum.Material.Neon)
	local glow = Instance.new("PointLight")
	glow.Range, glow.Brightness, glow.Shadows = 9 * s, 0, false -- se enciende con el color del mineral
	glow.Parent = lamp
	-- placa al frente, mirando hacia el centro de la base
	local plaque = SignKit.Build(model, "Plaque", at(0, 2.1, -1.66), 3.3 * s, 1.75 * s, {
		title = "VACÍO", sub = " ", accent = color, depth = 0.22, subRatio = 0.36, bolts = false,
	})
	if slot == TROPHY then -- letrero del trofeo, sobre la vitrina
		SignKit.Build(model, "TrophySign", at(0, 8.35, -1.25), 3.8 * s, 1 * s, { title = "MÁS VALIOSO", accent = HAZARD, depth = 0.18, bolts = false, glow = true })
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText, prompt.ObjectText = "Exhibir mineral", "Estand" -- el cliente lo ajusta según lo que tengas en la mano
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = plaque.plate
	CollectionService:AddTag(prompt, "MuralPrompt") -- el cliente lo muestra solo al dueño (atributo Owner del estand)
	return {
		slot = slot, frame = frame, scale = s, model = model, showcase = at(0, 5.3, 0),
		plaque = plaque.title, plaqueSub = plaque.sub, glow = glow, prompt = prompt, exhibit = nil, shown = nil,
	}
end

-- Copia del modelo del mineral (o un cristal si no hay modelo), del tamaño de la vitrina, sin colisión ni disparos.
local function exhibitModel(key: string, size: number): Instance
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Minerals")
	local template = folder and folder:FindFirstChild(`Mineral_{key}`)
	local model: Model
	if template and template:IsA("Model") then
		model = template:Clone()
		local extents = model:GetExtentsSize()
		local biggest = math.max(extents.X, extents.Y, extents.Z)
		if biggest > 0 then model:ScaleTo(model:GetScale() * size / biggest) end
	else
		model = Instance.new("Model")
		local crystal = Instance.new("Part")
		crystal.Size = Vector3.new(size * 0.45, size, size * 0.45)
		crystal.Material, crystal.Color = Enum.Material.Neon, Minerals[key].Color
		crystal.Parent = model
		model.PrimaryPart = crystal
	end
	model.Name = "Exhibit"
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
		end
	end
	model:SetAttribute("Rarity", nil) -- no es un mineral del mundo (no se dispara ni se recoge)
	model:SetAttribute("MineralModel", nil)
	return model
end

-- Pone (o quita) el mineral de un estand.
local function show(stand: Stand, key: string?, count: number)
	local signature = if key then `{key}:{count}` else "vacío"
	if stand.shown == signature then return end
	local sameMineral = key ~= nil and stand.shown ~= nil and string.match(stand.shown, "^(.-):") == key
	stand.shown = signature
	if not sameMineral then
		if stand.exhibit then stand.exhibit:Destroy() end
		stand.exhibit = nil
		if key then
			local model = exhibitModel(key, 2 * stand.scale)
			model:PivotTo(stand.showcase)
			model:SetAttribute("Base", stand.showcase) -- el cliente lo hace girar alrededor de aquí
			CollectionService:AddTag(model, "MuralExhibit")
			model.Parent = stand.model
			stand.exhibit = model
		end
		stand.glow.Color = if key then Minerals[key].Color else Color3.new(1, 1, 1)
		stand.glow.Brightness = if key then 1.2 else 0
	end
	if key then
		local value = count * (Minerals[key].Value or 0)
		stand.plaque.Text = string.upper(displayName(key))
		stand.plaque.TextColor3 = Minerals[key].Color:Lerp(Color3.new(1, 1, 1), 0.35)
		stand.plaqueSub.Text = `x{count}   ·   valor {value}`
	else
		stand.plaque.Text = "VACÍO"
		stand.plaque.TextColor3 = Color3.fromRGB(130, 130, 136)
		stand.plaqueSub.Text = "sin mineral"
	end
end

-- Qué muestra cada estand: lo que eligió el dueño y, en los demás, sus tipos guardados del más valioso al menos.
local function plan(owner: Player?, slots: number): { [number]: string? }
	local result = {}
	if not owner then return result end
	local function stored(key: string): number return owner:GetAttribute("Stored_" .. key) or 0 end
	local used = {}
	for slot = 1, slots do
		local chosen = owner:GetAttribute(`Mural_{slot}`)
		if typeof(chosen) == "string" and Minerals[chosen] and stored(chosen) > 0 and not used[chosen] then
			result[slot], used[chosen] = chosen, true
		end
	end
	local rank = 1
	for _, key in TYPES do
		if stored(key) > 0 and not used[key] then
			while rank <= #RANK_ORDER and (RANK_ORDER[rank] > slots or result[RANK_ORDER[rank]] ~= nil) do rank += 1 end
			if rank > #RANK_ORDER then break end
			result[RANK_ORDER[rank]], used[key] = key, true
		end
	end
	return result
end

return {
	Start = function()
		while workspace:GetAttribute("BasesReady") ~= true do
			task.wait(0.5)
		end
		local folder = workspace:WaitForChild("Bases")
		notify = Remotes.get("Progress_Notify") -- avisos en pantalla (los muestra client/Features/Progression)
		local murals: { [any]: { Stand } } = {}
		for _, base in Bases.All() do
			local baseModel = folder:FindFirstChild(`Base{base.index}`)
			local stands = {}
			if baseModel then
				for _, anchor in baseModel:GetChildren() do
					if anchor.Name == "MuralSlot" and anchor:IsA("BasePart") then
						local stand = buildStand(baseModel, anchor:GetAttribute("Slot"), anchor.CFrame * CFrame.new(0, -0.1, 0), base.color)
						table.insert(stands, stand)
						stand.prompt.Triggered:Connect(function(player)
							if base.owner ~= player then return end
							-- con un mineral de la mochila en la mano: se coloca en este estand (pasa al almacén)
							local held = player.Character and player.Character:FindFirstChildOfClass("Tool")
							local item = held and held:GetAttribute("Item")
							if typeof(item) == "string" and Minerals[item] then
								local n = Inventory.Count(player, item)
								if n > 0 then
									Inventory.Add(player, item, -n)
									Bases.Deposit(player, { [item] = n }, false)
								end
								for slot = 1, #stands do -- si estaba elegido en otro estand, pasa a este
									if player:GetAttribute(`Mural_{slot}`) == item then player:SetAttribute(`Mural_{slot}`, nil) end
								end
								player:SetAttribute(`Mural_{stand.slot}`, item)
								notify:FireClient(player, `{displayName(item)} en exhibición (x{n} guardados en tu base).`, "ok")
								return
							end
							-- sin nada en la mano: el siguiente tipo guardado (de más a menos valioso)
							local have = {}
							for _, key in TYPES do
								if (player:GetAttribute("Stored_" .. key) or 0) > 0 then table.insert(have, key) end
							end
							if #have == 0 then
								notify:FireClient(player, "No tienes minerales para exhibir: toma uno de tu mochila en la mano y vuelve a intentarlo.", "error")
								return
							end
							local current = if stand.shown then string.match(stand.shown, "^(.-):") else nil
							local index = table.find(have, current or "") or 0
							player:SetAttribute(`Mural_{stand.slot}`, have[index % #have + 1])
						end)
					end
				end
			end
			table.sort(stands, function(a, b) return a.slot < b.slot end)
			murals[base] = stands
		end
		-- se repinta cada segundo (8 bases x 5 estands: barato); solo cambia lo que cambió
		while true do
			for base, stands in murals do
				local ok, err = pcall(function()
					local owner = base.owner
					local shown = plan(owner, #stands)
					for _, stand in stands do
						local key = shown[stand.slot]
						show(stand, key, if key and owner then owner:GetAttribute("Stored_" .. key) or 0 else 0)
						local ownerId = if owner then owner.UserId else 0
						if stand.model:GetAttribute("Owner") ~= ownerId then stand.model:SetAttribute("Owner", ownerId) end
					end
				end)
				if not ok then warn(`[Mural] base {base.index}: {err}`) end
			end
			task.wait(1)
		end
	end,
}
