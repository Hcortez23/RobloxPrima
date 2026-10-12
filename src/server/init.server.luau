local Features = script:WaitForChild("Features")

for _, module in Features:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, feature = pcall(require, module)
		if not ok then
			warn(`[{module.Name}] fallo al cargar: {feature}`)
		elseif type(feature) == "table" and feature.Start then
			task.spawn(feature.Start)
		end
	end
end
