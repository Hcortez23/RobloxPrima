-- Efectos de la excavación (la lógica está en server/Features/Excavation.luau):
--  · "dig": trozos de roca que saltan del hueco y una nube de polvo.
--  · "hard": chispas cuando la roca es demasiado dura para el arma (hace falta una mejor) o la zona está protegida.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Excavation)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- pieza invisible y anclada para soltar partículas en un punto
local function emitterAt(pos: Vector3, lifetime: number): BasePart
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency, p.Size, p.Position = 1, Vector3.one * 0.2, pos
	p.Parent = workspace
	Debris:AddItem(p, lifetime)
	return p
end

local function dig(pos: Vector3, radius: number, normal: Vector3, color: Color3)
	local rng = Random.new()
	for _ = 1, Config.DebrisCount do
		local rock = Instance.new("Part")
		rock.Size = Vector3.new(rng:NextNumber(0.3, 0.9), rng:NextNumber(0.3, 0.9), rng:NextNumber(0.3, 0.9)) * math.clamp(radius / 2, 0.6, 2)
		rock.CFrame = CFrame.new(pos + normal * 0.5) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
		rock.Color, rock.Material = color, Enum.Material.Slate
		rock.CanCollide, rock.CanQuery, rock.CanTouch, rock.CastShadow = false, false, false, false
		rock.AssemblyLinearVelocity = (normal + rng:NextUnitVector() * 0.8).Unit * rng:NextNumber(14, 26)
		rock.Parent = workspace
		Debris:AddItem(rock, 1.2)
	end
	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(color)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, radius * 0.5), NumberSequenceKeypoint.new(1, radius * 1.4) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime, dust.Speed, dust.Drag = NumberRange.new(0.6, 1.1), NumberRange.new(2, 6), 3
	dust.SpreadAngle, dust.Rate = Vector2.new(180, 180), 0
	dust.Parent = emitterAt(pos, 1.5)
	dust:Emit(10)
end

local function hard(pos: Vector3, normal: Vector3)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 120, 40))
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime, sparks.Speed, sparks.Drag = NumberRange.new(0.2, 0.4), NumberRange.new(10, 20), 2
	sparks.SpreadAngle, sparks.LightEmission, sparks.Rate = Vector2.new(50, 50), 1, 0
	sparks.EmissionDirection = Enum.NormalId.Top
	local holder = emitterAt(pos + normal * 0.2, 1)
	holder.CFrame = CFrame.lookAt(holder.Position, holder.Position + normal) * CFrame.Angles(-math.pi / 2, 0, 0) -- Top = normal
	sparks.Parent = holder
	sparks:Emit(14)
end

return {
	Start = function()
		Remotes.get("Excavation_Dig").OnClientEvent:Connect(function(kind: string, pos: Vector3, a, b, c)
			if kind == "dig" then
				dig(pos, a, b, c)
			elseif kind == "hard" then
				hard(pos, a)
			end
		end)
	end,
}
