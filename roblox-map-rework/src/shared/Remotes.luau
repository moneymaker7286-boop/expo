--!strict
--[[
	Remote plumbing. The server creates the folder and every event inside it;
	the client only ever waits. That ordering means a client can never create
	a remote the server does not know about.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "StageReworkRemotes"

local Remotes = {}

local function container(): Instance
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME, 30) or ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Remotes.Event(name: string): RemoteEvent
	local folder = container()

	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
		return event
	end

	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
