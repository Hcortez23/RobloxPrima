-- Progresión por capas (Config/Progression): cada jugador tiene sus capas desbloqueadas, aunque el terreno (y los
-- túneles que excavan otros) sea el mismo para todos.
--  · Atributos del jugador: Progress_Unlocked (última capa desbloqueada, empieza en 1) y Hub_<capa> = true cuando
--    descubrió ese hub (el de la capa 1, la cueva del foso, siempre). Pressure (0..1) para el aviso del cliente.
--  · Permiso de descenso (Progression.BuyPermit, lo llama el terminal de LayerHubs): se paga con el valor de lo guardado
--    en la base (primero lo más barato) y pide un arma con DigPower suficiente para la capa siguiente.
--  · Excavation pregunta Progression.CanDigDepth: nadie excava más abajo de su última capa desbloqueada.
--  · Presión: en una capa sin permiso, aviso y daño creciente hasta que suba (o muera y reaparezca en su base).
--  · Elevador (Progression.OpenElevator, lo llama la cabina de LayerHubs): menú en el cliente con los hubs; solo lleva
--    a hubs descubiertos de capas desbloqueadas.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Progression)
local WorldConfig = require(ReplicatedStorage.Shared.Config.World)
local ExcavationConfig = require(ReplicatedStorage.Shared.Config.Excavation)
local Minerals = require(ReplicatedStorage.Shared.Config.Minerals)
local HubLayout = require(ReplicatedStorage.Shared.HubLayout)
local BiomeMap = require(ReplicatedStorage.Shared.BiomeMap)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local World = require(script.Parent.World)

local LAYERS = WorldConfig.Layers
local notifyRemote: RemoteEvent
local elevatorRemote: RemoteEvent

-- tipos de mineral del más barato al más caro (así se paga el permiso)
local TYPES = {}
for key in Minerals do table.insert(TYPES, key) end
table.sort(TYPES, function(a, b) return (Minerals[a].Value or 0) < (Minerals[b].Value or 0) end)

local Progression = {}

local function notify(player: Player, text: string, kind: string?)
	if notifyRemote then notifyRemote:FireClient(player, text, kind or "info") end
end

function Progression.Unlocked(player: Player): number
	return player:GetAttribute("Progress_Unlocked") or 1
end

-- ¿Puede excavar hasta esa profundidad? (hasta el fondo de su última capa desbloqueada)
function Progression.CanDigDepth(player: Player, depth: number): boolean
	return depth <= LAYERS[Progression.Unlocked(player)].MaxDepth
end

-- DigPower que hace falta para excavar la capa `i` (que un disparo abra al menos MinRadius)
function Progression.RequiredDigPower(i: number): number
	return math.ceil(LAYERS[i].Hardness * ExcavationConfig.MinRadius / ExcavationConfig.BaseRadius)
end

-- El mejor DigPower entre las armas que lleva (mochila y en la mano)
function Progression.BestDigPower(player: Player): number
	local best = ExcavationConfig.DefaultDigPower
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, tool in container:GetChildren() do
				if tool:IsA("Tool") then
					best = math.max(best, tool:GetAttribute("DigPower") or ExcavationConfig.DefaultDigPower)
				end
			end
		end
	end
	return best
end

-- valor total guardado en la base
local function storedValue(player: Player): number
	local total = 0
	for _, key in TYPES do
		total += (player:GetAttribute("Stored_" .. key) or 0) * (Minerals[key].Value or 0)
	end
	return total
end

-- cobra `cost` del almacén de la base, empezando por lo más barato (del último tipo, lo justo para cubrirlo)
local function pay(player: Player, cost: number)
	local remaining = cost
	for _, key in TYPES do
		if remaining <= 0 then break end
		local value = Minerals[key].Value or 0
		local have = player:GetAttribute("Stored_" .. key) or 0
		if value > 0 and have > 0 then
			local take = math.min(have, math.ceil(remaining / value))
			player:SetAttribute("Stored_" .. key, have - take)
			remaining -= take * value
		end
	end
end

-- Compra el permiso para la capa `target` (debe ser la siguiente a la última desbloqueada).
function Progression.BuyPermit(player: Player, target: number)
	local unlocked = Progression.Unlocked(player)
	if target <= unlocked then
		notify(player, `Ya tienes permiso para la CAPA {target}.`)
		return
	end
	if target ~= unlocked + 1 or not LAYERS[target] then
		notify(player, `Primero necesitas el permiso para la CAPA {unlocked + 1}.`, "error")
		return
	end
	local need = Progression.RequiredDigPower(target)
	if Progression.BestDigPower(player) < need then
		notify(player, `Tu arma no puede con la roca de la CAPA {target}: necesitas poder de excavación {need}.`, "error")
		return
	end
	local cost = Config.PermitCost[target] or 0
	if storedValue(player) < cost then
		notify(player, `Te falta valor en tu base: el permiso cuesta {cost} (tienes {storedValue(player)}).`, "error")
		return
	end
	pay(player, cost)
	player:SetAttribute("Progress_Unlocked", target)
	notify(player, `Permiso concedido: ya puedes bajar a la CAPA {target} · {LAYERS[target].Name}.`, "ok")
end

-- lista para el menú del elevador: { capa, nombre, estado = "ok" | "locked" | "unknown" }
local function elevatorList(player: Player)
	local list = {}
	local unlocked = Progression.Unlocked(player)
	for i, hub in HubLayout.All do
		local state = "ok"
		if i > unlocked then
			state = "locked"
		elseif not player:GetAttribute(`Hub_{i}`) or not World.Hubs[i] then
			state = "unknown"
		end
		table.insert(list, { layer = i, name = if hub.main then "Cueva del foso" else LAYERS[i].Name, state = state })
	end
	return list
end

-- ¿Está junto a la cabina de algún hub? Devuelve ese hub.
local function cabinNear(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	for _, hub in HubLayout.All do
		if (root.Position - hub.elevator.Position).Magnitude <= Config.ElevatorRange then return hub end
	end
	return nil
end

function Progression.OpenElevator(player: Player)
	local hub = cabinNear(player)
	if hub then elevatorRemote:FireClient(player, "open", elevatorList(player), hub.layer) end
end

local traveling: { [Player]: boolean } = {}
local function travel(player: Player, target: number)
	local from = cabinNear(player)
	local hub = HubLayout.Get(target)
	if traveling[player] or not from or not hub or from.layer == target then return end
	for _, entry in elevatorList(player) do
		if entry.layer == target and entry.state ~= "ok" then return end
	end
	traveling[player] = true
	elevatorRemote:FireClient(player, "travel", target, if hub.main then "Cueva del foso" else LAYERS[target].Name)
	local arrival = hub.elevator * CFrame.new(0, 3, -9) -- frente a la puerta de la cabina, mirando hacia fuera
	pcall(function() player:RequestStreamAroundAsync(arrival.Position) end)
	task.wait(0.9) -- la pantalla ya está en negro
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(arrival)
	end
	traveling[player] = nil
end

local function setup(player: Player)
	if player:GetAttribute("Progress_Unlocked") == nil then player:SetAttribute("Progress_Unlocked", 1) end
	player:SetAttribute("Hub_1", true)
	player:SetAttribute("Pressure", 0)
end

Progression.Start = function()
	notifyRemote = Remotes.get("Progress_Notify")
	elevatorRemote = Remotes.get("Elevator")
	elevatorRemote.OnServerEvent:Connect(function(player, action, target)
		if action == "go" and typeof(target) == "number" then travel(player, target) end
	end)
	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do setup(p) end
	Players.PlayerRemoving:Connect(function(p) traveling[p] = nil end)

	-- presión y descubrimiento de hubs
	local pressureTime: { [Player]: number } = {}
	local last = os.clock()
	while true do
		task.wait(0.25)
		local now = os.clock()
		local dt = now - last
		last = now
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				local pos = root.Position
				local layer = if pos.Y > BiomeMap.CommonZoneY then 1 else BiomeMap.Layer(-pos.Y)
				local unlocked = Progression.Unlocked(player)
				-- descubrir el hub en el que está
				local hub = HubLayout.At(pos)
				if hub and hub.layer <= unlocked and World.Hubs[hub.layer] and not player:GetAttribute(`Hub_{hub.layer}`) then
					player:SetAttribute(`Hub_{hub.layer}`, true)
					notify(player, `HUB descubierto · CAPA {hub.layer} · {LAYERS[hub.layer].Name}. El elevador ya te trae aquí.`, "ok")
				end
				-- presión en capas sin permiso
				if layer > unlocked then
					local t = (pressureTime[player] or 0) + dt
					pressureTime[player] = t
					player:SetAttribute("Pressure", math.clamp(t / Config.Pressure.Grace, 0, 1))
					player:SetAttribute("PressureLayer", layer)
					local over = t - Config.Pressure.Grace
					if over > 0 then
						local rate = Config.Pressure.Damage + Config.Pressure.Ramp * over
						humanoid:TakeDamage(humanoid.MaxHealth * rate * dt)
					end
				elseif pressureTime[player] then
					pressureTime[player] = nil
					player:SetAttribute("Pressure", 0)
				end
			elseif pressureTime[player] then
				pressureTime[player] = nil
				player:SetAttribute("Pressure", 0)
			end
		end
		for p in pressureTime do
			if p.Parent ~= Players then pressureTime[p] = nil end
		end
	end
end

return Progression
