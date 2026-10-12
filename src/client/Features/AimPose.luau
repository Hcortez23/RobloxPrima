-- Apuntar con el arma: mientras se sostiene un arma (el Rifle, un Tool con atributo Weapon o con atributo Crosshair,
-- como el gancho), el brazo derecho y un poco la cintura se inclinan hacia donde mira la cámara, así el arma sube y baja
-- con la vista en 1ª y 3ª persona. Solo en el cliente (es visual); no actúa durante el mortal ni el gancho, que
-- tienen su propia pose (Movement).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WeaponConfig = require(ReplicatedStorage.Shared.Config.Weapon)

local player = Players.LocalPlayer

local SMOOTH = 18 -- qué tan rápido sigue a la cámara
local WAIST_SHARE = 0.3 -- parte de la inclinación que hace la cintura (el resto, el hombro)
local MAX_PITCH = math.rad(80)

type Joint = { target: Instance, property: string, rest: CFrame }

-- Articulación por nombre (R15 o R6), sea Motor6D (se mueve su C0) o AnimationConstraint (su Attachment0).
local function findJoint(character: Model, names: { string }): Joint?
	for _, name in names do
		local joint = character:FindFirstChild(name, true)
		local target, property
		if joint and joint:IsA("Motor6D") then
			target, property = joint, "C0"
		elseif joint and joint:IsA("AnimationConstraint") and joint.Attachment0 then
			target, property = joint.Attachment0, "CFrame"
		end
		if target then
			-- la pose de reposo queda guardada en la articulación para que Movement (mortal, gancho) parta de ella
			-- y no de la inclinación de apuntar
			local rest = target:GetAttribute("RestCFrame") or (target :: any)[property]
			target:SetAttribute("RestCFrame", rest)
			return { target = target, property = property, rest = rest }
		end
	end
	return nil
end

local function holdingWeapon(character: Model): boolean
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and (child.Name == WeaponConfig.ToolName or child:GetAttribute("Weapon") or child:GetAttribute("Crosshair")) then
			return true
		end
	end
	return false
end

-- Gira un CFrame sobre su propio punto (la articulación) alrededor del eje X de la pieza padre.
local function rotateInPlace(original: CFrame, angle: number): CFrame
	return CFrame.new(original.Position) * CFrame.Angles(angle, 0, 0) * original.Rotation
end

local function setup(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	character:WaitForChild("HumanoidRootPart")
	task.wait() -- deja que se armen las articulaciones del avatar
	local shoulder = findJoint(character, { "RightShoulder", "Right Shoulder" })
	local waist = findJoint(character, { "Waist" }) -- solo R15
	if not shoulder then
		return
	end

	local pitch = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not character.Parent or humanoid.Health <= 0 then
			connection:Disconnect()
			return
		end
		-- el mortal y el gancho mueven estas articulaciones con su propia pose
		if character:GetAttribute("Flipping") or character:GetAttribute("Grappling") then
			return
		end
		local goal = 0
		if holdingWeapon(character) then
			local look = workspace.CurrentCamera.CFrame.LookVector
			goal = math.clamp(math.asin(math.clamp(look.Y, -1, 1)), -MAX_PITCH, MAX_PITCH)
		end
		pitch += (goal - pitch) * math.min(dt * SMOOTH, 1)

		local shoulderTarget: any = shoulder.target
		shoulderTarget[shoulder.property] = rotateInPlace(shoulder.rest, pitch * (1 - WAIST_SHARE))
		if waist then
			local waistTarget: any = waist.target
			waistTarget[waist.property] = rotateInPlace(waist.rest, pitch * WAIST_SHARE)
		end
	end)
end

return {
	Start = function()
		if player.Character then
			task.spawn(setup, player.Character)
		end
		player.CharacterAdded:Connect(setup)
	end,
}
