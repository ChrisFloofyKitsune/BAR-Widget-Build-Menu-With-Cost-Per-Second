--- Patches gui_gridmenu.lua to add in cost per second and build time info (based on selected BP)
local function my_get_info()
	return {
		name = "Grid Menu with Costs/Second",
		desc = "A dynamically patched version of the Grid Menu that adds in cost per second and build time info",
		author = "Floris, grid by badosu and resopmok. Cost/second by engolianth and zenfur. Maintained by ChrisFloofyKitsune.",
		date = "June 2024",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = false,
		handler = true,
	}
end

-------------------------------------------------------------------------------
--- Original Widget Loading
-------------------------------------------------------------------------------

local orig_text = VFS.LoadFile("LuaUI/Widgets/gui_gridmenu.lua")

local locals_to_make_accessors_for = {
	"activeCmd",
	"font2",
	"priceFontSize",
	"units",
	"drawCell",
	"showPrice",
	"cellPadding",
	"cellInnerSize",
	"isPregame",
	"startDefID",
	"formatPrice",
	"activeBuilder",
	"refreshCommands",
}

for _, var_name in pairs(locals_to_make_accessors_for) do
	orig_text = orig_text .. '\nfunction get_' .. var_name .. '() return ' .. var_name .. ' end\n'
	orig_text = orig_text .. '\nfunction set_' .. var_name .. '(value) ' .. var_name .. ' = value end\n'
end

orig = loadstring(orig_text)
setfenv(orig, widget)
orig()

function widget:GetInfo()
	return my_get_info()
end

-------------------------------------------------------------------------------
--- Cached Values
-------------------------------------------------------------------------------
local spGetSelectedUnitsSorted = Spring.GetSelectedUnitsSorted
local math_floor = math.floor
local math_round = math.round

-------------------------------------------------------------------------------
--- Configuration
-------------------------------------------------------------------------------

local config_cost_per_second = {
	alwaysReturn = true,
	autoSelectFirst = true,
	useLabBuildMode = true,
	showDetailedPrice = true,
	showInfoUnderCursor = true,
}

local OPTION_COST_PER_SECOND_SPECS = {
	{
		configVariable = "alwaysReturn",
		name = Spring.I18N('ui.settings.option.gridmenu_alwaysreturn'),
		description = Spring.I18N('ui.settings.option.gridmenu_alwaysreturn_descr'),
		type = "bool",
		widgetApiFunction = 'setAlwaysReturn',
	},
	{
		configVariable = "autoSelectFirst",
		name = Spring.I18N('ui.settings.option.gridmenu_autoselectfirst'),
		description = Spring.I18N('ui.settings.option.gridmenu_autoselectfirst_descr'),
		type = "bool",
		widgetApiFunction = 'setAutoSelectFirst',
	},
	{
		configVariable = "useLabBuildMode",
		name = Spring.I18N('ui.settings.option.gridmenu_labbuildmode'),
		description = Spring.I18N('ui.settings.option.gridmenu_labbuildmode_descr'),
		type = "bool",
		widgetApiFunction = 'setUseLabBuildMode',
	},
	{
		configVariable = "showDetailedPrice",
		name = "Show detailed price",
		description = "Show detailed price in grid menu with cost per seconds and time to finish",
		type = "bool",
	},
	{
		configVariable = "showInfoUnderCursor",
		name = "Show context details under cursor",
		description = "Show context details of selected building next to cursor",
		type = "bool",
	},
}

local function getOptionId(optionSpec)
	return "grid__menu__" .. optionSpec.configVariable
end

local function getWidgetName()
	return "Grid Menu with Costs/Second"
end

local function getOptionValue(optionSpec)
	if optionSpec.type == "slider" then
		return config_cost_per_second[optionSpec.configVariable]
	elseif optionSpec.type == "bool" then
		return config_cost_per_second[optionSpec.configVariable]
	elseif optionSpec.type == "select" then
		-- we have text, we need index
		for i, v in pairs(optionSpec.options) do
			if config_cost_per_second[optionSpec.configVariable] == v then
				return i
			end
		end
	end
end

local function setOptionValue(optionSpec, value)
	if optionSpec.type == "slider" then
		config_cost_per_second[optionSpec.configVariable] = value
	elseif optionSpec.type == "bool" then
		config_cost_per_second[optionSpec.configVariable] = value
	elseif optionSpec.type == "select" then
		-- we have index, we need text
		config_cost_per_second[optionSpec.configVariable] = optionSpec.options[value]
	end

	--Spring.Echo("Setting " .. optionSpec.configVariable .. " to " .. tostring(config_cost_per_second[optionSpec.configVariable]))
	--Spring.Echo("Calling " .. tostring(optionSpec.widgetApiFunction))
	--Spring.Echo("Function Exists: " .. tostring(WG['gridmenu'] ~= nil and WG['gridmenu'][optionSpec.widgetApiFunction] ~= nil))
	if optionSpec.widgetApiFunction and WG['gridmenu'] ~= nil and WG['gridmenu'][optionSpec.widgetApiFunction] ~= nil then
		--Spring.Echo("Calling " .. optionSpec.widgetApiFunction)
		WG['gridmenu'][optionSpec.widgetApiFunction](config_cost_per_second[optionSpec.configVariable])
	end
end

local function createOnChange(optionSpec)
	return function(i, value, force)
		setOptionValue(optionSpec, value)
	end
end

local function addOptionFromSpec(optionSpec)
	local option = table.copy(optionSpec)

	option.configVariable = nil
	option.enabled = nil
	option.id = getOptionId(optionSpec)
	option.widgetname = getWidgetName()
	option.value = getOptionValue(optionSpec)
	option.onchange = createOnChange(optionSpec)

	if WG['options'] ~= nil then
		WG['options'].addOption(option)
	end
end

-------------------------------------------------------------------------------
--- INTERFACE VALUES
-------------------------------------------------------------------------------

local selectedBuildPower = 100

-------------------------------------------------------------------------------
--- Unit prep
-------------------------------------------------------------------------------

local units = get_units()
units.unitBuildTime = {}
units.unitBuildSpeed = {}
units.soloBuilder = {}

for unitDefID, unitDef in pairs(UnitDefs) do
	units.unitBuildTime[unitDefID] = unitDef.buildTime
	if unitDef.isBuilder then
		if unitDef.canAssist ~= false then
			units.unitBuildSpeed[unitDefID] = unitDef.buildSpeed or 0
		elseif unitDef.buildOptions and #unitDef.buildOptions > 0 then
			units.unitBuildSpeed[unitDefID] = unitDef.buildSpeed or 0
			units.soloBuilder[unitDefID] = true
		end
	end
end
-------------------------------------------------------------------------------
--- Helper Functions
-------------------------------------------------------------------------------

local formatPrice = get_formatPrice()

local function formatBuildTime(buildTime)
	if buildTime < 1 then
		return ("%.2f s"):format(buildTime)
	end

	if buildTime < 10 then
		return ("%.1f s"):format(buildTime)
	end

	if buildTime < 60 then
		return ("%d s"):format(buildTime)
	end

	local seconds = buildTime % 60
	local minutes = math_floor((buildTime % 3600) / 60)
	if buildTime < 3600 then
		return ("%d m %02d s"):format(minutes, seconds)
	end

	local hours = math_floor(buildTime / 3600)
	return ("%d h %02d m %02d s"):format(hours, minutes, seconds)
end

local function drawDetailedCostLabels(label_x, label_y, uid, fontSize, disabled)
	local _, err = pcall(function()
		if not font2 then
			font2 = get_font2()
		end

		if disabled == nil then
			disabled = false
		end

		if uid == nil then
			return
		end

		local metalCost = units.unitMetalCost[uid]
		local energyCost = units.unitEnergyCost[uid]
		local buildTime = units.unitBuildTime[uid]

		if metalCost == nil or energyCost == nil or buildTime == nil or buildTime <= 0 then
			return
		end

		local metalColor = disabled and "\255\125\125\125" or "\255\245\245\245"
		local energyColor = disabled and "\255\135\135\135" or "\255\255\255\000"
		local timeColor = disabled and "\255\100\100\100" or "\255\185\240\185"

		local buildPower = selectedBuildPower or 100
		local metalPerSecond = formatPrice(math_round(metalCost / buildTime * buildPower)) .. '/s'
		local energyPerSecond = formatPrice(math_round(energyCost / buildTime * buildPower)) .. '/s'
		local timeEstimate = formatBuildTime(buildTime / buildPower)

		local font2 = get_font2()

		font2:Print(metalColor .. metalPerSecond, label_x, label_y - (fontSize), fontSize, "ro")
		font2:Print(energyColor .. energyPerSecond, label_x, label_y - (fontSize * 2), fontSize, "ro")
		font2:Print(timeColor .. timeEstimate, label_x, label_y - (fontSize * 3), fontSize, "ro")
	end)

	if err then
		Spring.Echo("Error in drawDetailedCostLabels")
		Spring.Echo(err)
	end
end

local function drawCursorInfo()
	if not config_cost_per_second.showInfoUnderCursor then
		return
	end
	
	local x, y, _, _, _ = Spring.GetMouseState()
	local activeCmd = nil
	if get_isPregame() then
		local prebuildId = WG["pregame-build"] and WG['pregame-build'].getPreGameDefID and WG['pregame-build'].getPreGameDefID()
		activeCmd = prebuildId and -prebuildId or nil
	else
		activeCmd = get_activeCmd()
	end

	if activeCmd ~= nil then
		drawDetailedCostLabels(x + 10, y, -activeCmd, 2 * get_priceFontSize())
	end
end

local function calculateSelectedBuildPower()
	local active_builder = get_activeBuilder()
	if active_builder and units.soloBuilder[active_builder] == true then
		selectedBuildPower = units.unitBuildSpeed[active_builder]
	else
		local build_power = 0
		for unitDefID, unitIds in pairs(spGetSelectedUnitsSorted() or {}) do
			local build_speed = units.unitBuildSpeed[unitDefID] or 0
			if build_speed > 0 and units.soloBuilder[unitDefID] ~= true then
				build_power = build_power + (build_speed * #unitIds)
			end
		end

		selectedBuildPower = build_power or 100
	end
end

---------------------------------------------------------------------------------
--- Widget Callins Patching
---------------------------------------------------------------------------------
local orig_get_config_data = widget.GetConfigData
function widget:GetConfigData()
	local result = orig_get_config_data(widget)
	for _, option in pairs(OPTION_COST_PER_SECOND_SPECS) do
		result[option.configVariable] = getOptionValue(option)
	end
	return result
end

local orig_set_config_data = widget.SetConfigData
function widget:SetConfigData(data)
	local orig_data = widgetHandler.configData["Grid menu"]
	orig_set_config_data(widget, table.merge(orig_data, data))
	for _, option in pairs(OPTION_COST_PER_SECOND_SPECS) do
		local configVariable = option.configVariable
		if data[configVariable] ~= nil then
			--Spring.Echo("Setting " .. configVariable .. " to " .. tostring(data[configVariable]))
			setOptionValue(option, data[configVariable])
		end
	end
end

local orig_widget_initialize = widget.Initialize
function widget:Initialize()
	local exclusive_widgets = {
		"Grid menu", "Build Menu", -- default widgets
		"Build menu v2", "Grid menu v2", -- old versions of this widgets
		"Build Menu with Costs/Second", -- alternate version of this widget
	}

	for _, widgetName in pairs(exclusive_widgets) do
		if widgetHandler:IsWidgetKnown(widgetName) then
			widgetHandler:DisableWidget(widgetName)
		end
	end

	for _, optionSpec in pairs(OPTION_COST_PER_SECOND_SPECS) do
		addOptionFromSpec(optionSpec)
	end

	orig_widget_initialize(widget)

	if get_isPregame() then
		selectedBuildPower = units.unitBuildSpeed[get_startDefID()] or 300
	end
end

local orig_widget_shutdown = widget.Shutdown
function widget:Shutdown()
	orig_widget_shutdown(widget)

	if WG['options'] ~= nil then
		for _, option in pairs(OPTION_COST_PER_SECOND_SPECS) do
			WG['options'].removeOption(getOptionId(option))
		end
	end
end

local orig_widget_update = widget.Update
function widget:Update(dt)
	orig_widget_update(widget, dt)
	if get_isPregame() then
		selectedBuildPower = units.unitBuildSpeed[get_startDefID()] or 300
	end
end

local orig_widget_selection_changed = widget.SelectionChanged
function widget:SelectionChanged(selectedUnits)
	orig_widget_selection_changed(widget, selectedUnits)
	calculateSelectedBuildPower()
end

local orig_widget_draw_screen = widget.DrawScreen
function widget:DrawScreen()
	orig_widget_draw_screen(widget)
	drawCursorInfo()
end

-------------------------------------------------------------------------------
--- Local Function Patching
-------------------------------------------------------------------------------

local orig_refresh_commands = get_refreshCommands()
local function refreshCommands()
	orig_refresh_commands()
	calculateSelectedBuildPower()
end
set_refreshCommands(refreshCommands)

local orig_draw_cell = get_drawCell()
local function drawCell(rect)
	orig_draw_cell(rect)

	if not config_cost_per_second.showDetailedPrice then
		return
	end

	local priceFontSize = get_priceFontSize()
	local hotkeyFontSize = priceFontSize * 1.2
	local cellPadding = get_cellPadding()
	local cellInnerSize = get_cellInnerSize()

	if get_showPrice() or rect.opts.hovered then
		drawDetailedCostLabels(
			rect.xEnd - cellPadding - (cellInnerSize * 0.048),
			rect.yEnd - hotkeyFontSize - cellPadding,
			rect.opts.uDefID,
			priceFontSize * 0.8,
			rect.opts.disabled
		)
	end
end
set_drawCell(drawCell)
