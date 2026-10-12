-- Servidor crea el RemoteEvent al pedirlo; cliente espera a que exista.
-- Uso: Remotes.get("Fracture_Hit")
local RS = game:GetService("ReplicatedStorage")
local isServer = game:GetService("RunService"):IsServer()

local folder = RS:FindFirstChild("Remotes")
if not folder and isServer then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = RS
end
folder = folder or RS:WaitForChild("Remotes")

return {
	get = function(name: string): RemoteEvent
		local ev = folder:FindFirstChild(name)
		if ev then return ev end
		if isServer then
			ev = Instance.new("RemoteEvent")
			ev.Name = name
			ev.Parent = folder
			return ev
		end
		return folder:WaitForChild(name)
	end,
}
