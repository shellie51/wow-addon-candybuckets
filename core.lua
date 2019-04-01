if select(4, GetBuildInfo()) < 80000 then return end -- BfA required

local addonName, ns = ...
local DEBUG = false

--
-- Session
--

ns.FACTION = 0
ns.QUESTS = {}
ns.PROVIDERS = {}

ns.COMPLETED_QUESTS = setmetatable({}, {
	__index = function(self, questID)
		local isCompleted = IsQuestFlaggedCompleted(questID)
		if isCompleted then
			rawset(self, questID, isCompleted)
		end
		return isCompleted
	end
})

--
-- Map
--

ns.PARENT_MAP = {}
do
	local parentMapIDs = {
		12, -- Kalimdor
		13, -- Eastern Kingdoms
		101, -- Outland
		113, -- Northrend
		203, -- Vashj'ir
		224, -- Stranglethorn Vale
		424, -- Pandaria
		572, -- Draenor
		619, -- Broken Isles
		875, -- Zandalar
		876, -- Kul Tiras
		948, -- The Maelstrom
		-- 947, -- Azeroth (hogs CPU but is kind of neat, though not complete as we only check the direct children of these maps...)
	}

	for i = 1, #parentMapIDs do
		local uiMapID = parentMapIDs[i]
		local children = C_Map.GetMapChildrenInfo(uiMapID, nil, true) -- Enum.UIMapType.Zone

		for _, child in pairs(children) do
			if not ns.PARENT_MAP[uiMapID] then
				ns.PARENT_MAP[uiMapID] = {}
			end

			ns.PARENT_MAP[uiMapID][child.mapID] = true
		end
	end
end

--
-- Waypoint
--

-- ns:GetWaypointAddon()
-- ns:AutoWaypoint(poi, wholeModule, silent)
do
	local waypointAddons = {}

	-- TomTom (v80001-1.0.2)
	table.insert(waypointAddons, {
		name = "TomTom",
		func = function(self, poi, wholeModule)
			if wholeModule then
				self:funcAll(poi.quest.module)
				TomTom:SetClosestWaypoint()
			else
				local uiMapID = poi:GetMap():GetMapID()
				local x, y = poi:GetPosition()
				local mapInfo = C_Map.GetMapInfo(uiMapID)
				TomTom:AddWaypoint(uiMapID, x, y, {
					title = string.format("%s (%s, %d)", poi.name, mapInfo.name or "Map " .. uiMapID, poi.quest.quest),
					minimap = true,
					crazy = true,
				})
			end
			return true
		end,
		funcAll = function(self, module)
			for i = 1, #module.quests do
				local quest = module.quests[i]
				for uiMapID, coords in pairs(quest) do
					if type(uiMapID) == "number" and type(coords) == "table" then
						local name = module.title[quest.extra or 1]
						local mapInfo = C_Map.GetMapInfo(uiMapID)
						TomTom:AddWaypoint(uiMapID, coords[1]/100, coords[2]/100, {
							title = string.format("%s (%s, %d)", name, mapInfo.name or "Map " .. uiMapID, quest.quest),
							minimap = true,
							crazy = true,
						})
					end
				end
			end
		end,
	})

	local supportedAddons = ""
	local supportedAddonsWarned = false
	for i = 1, #waypointAddons do
		supportedAddons = supportedAddons .. waypointAddons[i].name .. " "
	end

	function ns:GetWaypointAddon()
		for i = 1, #waypointAddons do
			local waypoint = waypointAddons[i]
			if IsAddOnLoaded(waypoint.name) then
				return waypoint
			end
		end
	end

	function ns:AutoWaypoint(poi, wholeModule, silent)
		local waypoint = ns:GetWaypointAddon()
		if not waypoint then
			if not silent then
				if not supportedAddonsWarned and supportedAddons ~= "" then
					supportedAddonsWarned = true
					DEFAULT_CHAT_FRAME:AddMessage("You need to install one of these supported waypoint addons: " .. supportedAddons, 1, 1, 0)
				end
			end
			return false
		end
		local status, err = pcall(function() return waypoint:func(poi, wholeModule) end)
		if not status or err then
			if not silent then
				DEFAULT_CHAT_FRAME:AddMessage("Unable to set waypoint using " .. waypoint.name .. ": " .. err, 1, 1, 0)
			end
			return false
		end
		return true
	end
end

--
-- Mixin
--

CandyBucketsDataProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function CandyBucketsDataProviderMixin:OnShow()
end

function CandyBucketsDataProviderMixin:OnHide()
end

function CandyBucketsDataProviderMixin:OnEvent(event, ...)
	-- self:RefreshAllData()
end

function CandyBucketsDataProviderMixin:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate("CandyBucketsPinTemplate")
end

function CandyBucketsDataProviderMixin:RefreshAllData(fromOnShow)
	self:RemoveAllData()

	local uiMapID = self:GetMap():GetMapID()
	local childUiMapIDs = ns.PARENT_MAP[uiMapID]

	for i = 1, #ns.QUESTS do
		local quest = ns.QUESTS[i]
		local poi, poi2

		if not childUiMapIDs then
			poi = quest[uiMapID]

		else
			for childUiMapID, _ in pairs(childUiMapIDs) do
				poi = quest[childUiMapID]

				if poi then
					local translateKey = uiMapID .. "," .. childUiMapID

					if poi[translateKey] ~= nil then
						poi = poi[translateKey]

					else
						local continentID, worldPos = C_Map.GetWorldPosFromMapPos(childUiMapID, CreateVector2D(poi[1]/100, poi[2]/100))
						poi, poi2 = nil, poi

						if continentID and worldPos then
							local _, mapPos = C_Map.GetMapPosFromWorldPos(continentID, worldPos, uiMapID)

							if mapPos then
								poi = mapPos
								poi2[translateKey] = mapPos
							end
						end

						if not poi then
							poi2[translateKey] = false
						end
					end

					break
				end
			end
		end

		if poi then
			self:GetMap():AcquirePin("CandyBucketsPinTemplate", quest, poi)
		end
	end

	if uiMapID == 947 then
		-- TODO: Azeroth map overlay of sorts with statistics per continent?
	end
end

--
-- Pin
--

CandyBucketsPinMixin = CreateFromMixins(MapCanvasPinMixin)

function CandyBucketsPinMixin:OnLoad()
	self:SetScalingLimits(1, 1.0, 1.2)
	self.HighlightTexture:Hide()
	self.hasTooltip = true
	self:EnableMouse(self.hasTooltip)
	self.Texture:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	self.Texture:ClearAllPoints()
	self.Texture:SetAllPoints()
end

function CandyBucketsPinMixin:OnAcquired(quest, poi)
	self.quest = quest
	self:UseFrameLevelType("PIN_FRAME_LEVEL_GOSSIP", self:GetMap():GetNumActivePinsByTemplate("CandyBucketsPinTemplate"))
	self:SetSize(12, 12)
	self.Texture:SetTexture(quest.module.texture[quest.extra or 1])
	self.name = quest.module.title[quest.extra or 1]
	if poi.GetXY then
		self:SetPosition(poi:GetXY())
	else
		self:SetPosition(poi[1]/100, poi[2]/100)
	end
	--[=[ -- TODO: show the local zone, not the zoomed out one
	local uiMapID = self:GetMap():GetMapID()
	if uiMapID then
		local x, y = self:GetPosition()
		local mapInfo = C_Map.GetMapInfo(uiMapID)
		if x and y and mapInfo and mapInfo.name then
			self.description = string.format("%s (%.2f, %.2f)", mapInfo.name, x, y)
		end
	end
	--]=]
end

function CandyBucketsPinMixin:OnReleased()
	self.quest, self.name, self.description = nil
end

function CandyBucketsPinMixin:OnMouseEnter()
	if not self.hasTooltip then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	self.UpdateTooltip = self.OnMouseEnter
	GameTooltip_SetTitle(GameTooltip, self.name)
	if self.description and self.description ~= "" then
		GameTooltip_AddNormalLine(GameTooltip, self.description, true)
	end
	GameTooltip_AddNormalLine(GameTooltip, "Quest ID: " .. self.quest.quest, false)
	if ns:GetWaypointAddon() then
		GameTooltip_AddNormalLine(GameTooltip, "<Click to show waypoint.>", false)
	end
	GameTooltip:Show()
end

function CandyBucketsPinMixin:OnMouseLeave()
	if not self.hasTooltip then return end
	GameTooltip:Hide()
end

function CandyBucketsPinMixin:OnClick(button)
	if button ~= "LeftButton" then return end
	ns:AutoWaypoint(self, IsModifierKeyDown())
end

--
-- Modules
--

ns.modules = ns.modules or {}

local MODULE_FROM_TEXTURE = {
	[235461] = "hallow",
	[235462] = "hallow",
	[235460] = "hallow",
	[235470] = "lunar",
	[235471] = "lunar",
	[235469] = "lunar",
	[235473] = "midsummer",
	[235474] = "midsummer",
	[235472] = "midsummer",
}

--
-- Addon
--

local addon = CreateFrame("Frame")
addon:SetScript("OnEvent", function(addon, event, ...) addon[event](addon, event, ...) end)
addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")

local InjectDataProvider do
	local function WorldMapMixin_OnLoad(self)
		local dataProvider = CreateFromMixins(CandyBucketsDataProviderMixin)
		ns.PROVIDERS[dataProvider] = true
		self:AddDataProvider(dataProvider)
	end

	function InjectDataProvider()
		hooksecurefunc(WorldMapMixin, "OnLoad", WorldMapMixin_OnLoad)
		WorldMapMixin_OnLoad(WorldMapFrame)
	end
end

function addon:RefreshAllWorldMaps(onlyShownMaps, fromOnShow)
	for dataProvider, _ in pairs(ns.PROVIDERS) do
		if not onlyShownMaps or dataProvider:GetMap():IsShown() then
			dataProvider:RefreshAllData(fromOnShow)
		end
	end
end

function addon:RemoveQuestPois(questID)
	local removed = 0

	for i = #ns.QUESTS, 1, -1 do
		local quest = ns.QUESTS[i]

		if quest.quest == questID then
			removed = removed + 1
			table.remove(ns.QUESTS, i)
		end
	end

	return removed > 0
end

function addon:CanLoadModule(name)
	return type(ns.modules[name]) == "table" and ns.modules[name].loaded ~= true
end

function addon:CanUnloadModule(name)
	return type(ns.modules[name]) == "table" and ns.modules[name].loaded == true
end

function addon:LoadModule(name)
	local module = ns.modules[name]
	module.loaded = true

	local i = #ns.QUESTS
	for j = 1, #module.quests do
		local quest = module.quests[j]

		if (not quest.side or quest.side == 3 or quest.side == ns.FACTION) and not ns.COMPLETED_QUESTS[quest.quest] then
			quest.module = module
			i = i + 1
			ns.QUESTS[i] = quest
		end
	end

	addon:RefreshAllWorldMaps(true)
end

function addon:UnloadModule(name)
	local module = ns.modules[name]
	module.loaded = false

	for i = #ns.QUESTS, 1, -1 do
		local quest = ns.QUESTS[i]

		if quest.module.event == name then
			table.remove(ns.QUESTS, i)
		end
	end

	addon:RefreshAllWorldMaps(true)
end

function addon:CheckCalendar()
	local curHour, curMinute = GetGameTime()
	local curDate = C_Calendar.GetDate()
	local calDate = C_Calendar.GetMonthInfo()
	local month, day, year = calDate.month, curDate.monthDay, calDate.year
	local curMonth, curYear = curDate.month, curDate.year
	local monthOffset = -12 * (curYear - year) + month - curMonth
	local numEvents = C_Calendar.GetNumDayEvents(monthOffset, day)
	local loadedEvents, numLoaded, numLoadedRightNow = {}, 0, 0

	if monthOffset ~= 0 then
		return -- we only care about the current events, so we need the view to be on the current month (otherwise we unload the ongoing events if we change the month manually...)
	end

	for i = 1, numEvents do
		local event = C_Calendar.GetDayEvent(monthOffset, day, i)

		if event and event.calendarType == "HOLIDAY" then
			local ongoing = event.sequenceType == "ONGOING" -- or event.sequenceType == "INFO"
			local moduleName = MODULE_FROM_TEXTURE[event.iconTexture]

			if event.sequenceType == "START" then
				ongoing = curHour >= event.startTime.hour and (curHour > event.startTime.hour or curMinute >= event.startTime.minute)
			elseif event.sequenceType == "END" then
				ongoing = curHour <= event.endTime.hour and (curHour < event.endTime.hour or curMinute <= event.endTime.minute)
			end

			if ongoing and addon:CanLoadModule(moduleName) then
				DEFAULT_CHAT_FRAME:AddMessage("|cffFFFFFF" .. addonName .. "|r has loaded the module for |cffFFFFFF" .. event.title .. "|r!", 1, 1, 0)
				addon:LoadModule(moduleName)
				numLoadedRightNow = numLoadedRightNow + 1
			elseif not ongoing and addon:CanUnloadModule(moduleName) then
				DEFAULT_CHAT_FRAME:AddMessage("|cffFFFFFF" .. addonName .. "|r has unloaded the module for |cffFFFFFF" .. event.title .. "|r because the event has ended.", 1, 1, 0)
				addon:UnloadModule(moduleName)
			end

			if moduleName and ongoing then
				loadedEvents[moduleName] = true
			end
		end
	end

	if DEBUG then
		for name, module in pairs(ns.modules) do
			if addon:CanLoadModule(name) then
				DEFAULT_CHAT_FRAME:AddMessage("|cffFFFFFF" .. addonName .. "|r has loaded the module for |cffFFFFFF[DEBUG] " .. name .. "|r!", 1, 1, 0)
				addon:LoadModule(name)
				numLoadedRightNow = numLoadedRightNow + 1
			end
			loadedEvents[name] = true
		end
	end

	for name, module in pairs(ns.modules) do
		if addon:CanUnloadModule(name) and not loadedEvents[name] then
			DEFAULT_CHAT_FRAME:AddMessage("|cffFFFFFF" .. addonName .. "|r couldn't find |cffFFFFFF" .. name .. "|r in the calendar so we consider the event expired.", 1, 1, 0)
			addon:UnloadModule(name)
		end
	end

	for name, module in pairs(ns.modules) do
		if addon:CanUnloadModule(name) then
			numLoaded = numLoaded + 1
		end
	end

	if numLoaded > 0 then
		addon:RegisterEvent("QUEST_TURNED_IN")
	else
		addon:UnregisterEvent("QUEST_TURNED_IN")
	end

	if numLoadedRightNow > 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cffFFFFFF" .. addonName .. "|r has |cffFFFFFF" .. #ns.QUESTS .. "|r locations for you to visit.", 1, 1, 0)
	end
end

function addon:QueryCalendar(check)
	addon:RegisterEvent("CALENDAR_UPDATE_EVENT")
	addon:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
	addon:RegisterEvent("GUILD_ROSTER_UPDATE")
	addon:RegisterEvent("PLAYER_GUILD_UPDATE")

	if type(CalendarFrame) ~= "table" or not CalendarFrame:IsShown() then
		local curDate = C_Calendar.GetDate()
		C_Calendar.SetAbsMonth(curDate.month, curDate.year)
	end

	if check then
		addon:CheckCalendar()
	end
end

--
-- Events
--

function addon:ADDON_LOADED(event, name)
	if name == addonName then
		addon:UnregisterEvent(event)
		InjectDataProvider()
	end
end

function addon:PLAYER_LOGIN(event)
	addon:UnregisterEvent(event)

	local faction = UnitFactionGroup("player")
	if faction == "Alliance" then
		ns.FACTION = 1
	elseif faction == "Horde" then
		ns.FACTION = 2
	else
		ns.FACTION = 3
	end

	GetQuestsCompleted(ns.COMPLETED_QUESTS)
	addon:QueryCalendar(true)
end

function addon:CALENDAR_UPDATE_EVENT()
	addon:CheckCalendar()
end

function addon:CALENDAR_UPDATE_EVENT_LIST()
	addon:CheckCalendar()
end

function addon:GUILD_ROSTER_UPDATE()
	addon:CheckCalendar()
end

function addon:PLAYER_GUILD_UPDATE()
	addon:CheckCalendar()
end

function addon:QUEST_TURNED_IN(event, questID)
	ns.COMPLETED_QUESTS[questID] = true

	if addon:RemoveQuestPois(questID) then
		addon:RefreshAllWorldMaps(true)
	end
end
