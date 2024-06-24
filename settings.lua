dofile("data/scripts/lib/mod_settings.lua")

local mod_id = "AdvancedSpellInventory"
mod_settings_version = 1

local function int_slider(mod_id, gui, in_main_menu, im_id, setting)
	local setting_id = mod_setting_get_id(mod_id, setting)
	local value = tonumber(ModSettingGetNextValue(setting_id)) or 0
	GuiLayoutBeginHorizontal(gui, 0, 0, false, 0, 2)
	GuiText(gui, 0, 0, setting.ui_name)
	value = GuiSlider(gui, im_id, 0, 1, "", value, setting.value_min, setting.value_max, setting.value_default, 1, " ", 50)
	GuiText(gui, 4, 0, ("%d"):format(value))
	GuiLayoutEnd(gui)
	value = math.floor(value + 0.5)
	ModSettingSetNextValue(setting_id, value, false)
end

local custom_gui

mod_settings =
{
	{
		id = "sounds_enabled",
		ui_name = "Enable sounds",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "num_rows",
		ui_name = "Amount of rows",
		ui_description = "How many extra spell inventory rows there should be.",
		value_default = 3,
		value_min = 1,
		value_max = 14,
		ui_fn = int_slider,
		scope = MOD_SETTING_SCOPE_NEW_GAME,
	},
	{
		id = "auto_storage",
		ui_name = "Pick up spells directly to storage",
		ui_description = "If you pick up spells, they will go directly\ninto the storage instead of regular spell inventory.",
		value_default = false,
		scope = MOD_SETTING_SCOPE_RUNTIME_RESTART,
	},
	{
		not_setting = true,
		ui_fn = function(mod_id, gui, in_main_menu, im_id, setting)
			if GuiButton(gui, im_id, 0, 0, "[ Reset button position ]") then
				ModSettingSet("AdvancedSpellInventory.button_pos_x", 162)
				ModSettingSet("AdvancedSpellInventory.button_pos_y", 41)
			end
		end
	},
	{
		category_id = "custom_resolution",
		foldable = true,
		_folded = true,
		ui_name = "Custom Resolution",
		ui_description = "If you modified your config.xml with a custom\ninternal render resolution, set the same here\nso that the mouse coordinate detection works correctly.",
		settings = {
			{
				not_setting = true,
				ui_fn = function(mod_id, gui, in_main_menu, im_id, setting)
					local custom_screen_resolution_x = ModSettingGetNextValue("EZMouse.custom_screen_resolution_x")
					local custom_screen_resolution_y = ModSettingGetNextValue("EZMouse.custom_screen_resolution_y")
					GuiIdPush(gui, im_id)
					GuiLayoutBeginHorizontal(gui, 0, 0)
					GuiText(gui, 0, 0, "Width: ")
					local new_x = GuiTextInput(gui, 2, 0, 0, tostring(custom_screen_resolution_x or ""), 50, 6, "0123456789")
					if tonumber(new_x) ~= custom_screen_resolution_x then
						if tonumber(new_x) == nil then
							ModSettingRemove("EZMouse.custom_screen_resolution_x")
						else
							ModSettingSetNextValue("EZMouse.custom_screen_resolution_x", tonumber(new_x) or 1280, false)
							ModSettingSet("EZMouse.custom_screen_resolution_x", tonumber(new_x) or 1280)
						end
					end
					GuiText(gui, 0, 0, "Height: ")
					local new_y = GuiTextInput(gui, 3, 0, 0, tostring(custom_screen_resolution_y or ""), 50, 6, "0123456789")
					if tonumber(new_y) ~= custom_screen_resolution_y then
						if tonumber(new_y) == nil then
							ModSettingRemove("EZMouse.custom_screen_resolution_y")
						else
							ModSettingSetNextValue("EZMouse.custom_screen_resolution_y", tonumber(new_y) or 720, false)
							ModSettingSet("EZMouse.custom_screen_resolution_y", tonumber(new_y) or 720)
						end
					end
					GuiLayoutEnd(gui)
					GuiIdPop(gui)
				end
			},
			{
				not_setting = true,
				ui_fn = function(mod_id, gui, in_main_menu, im_id, setting)
					GuiIdPush(gui, im_id)
					local clicked, right_clicked = GuiButton(gui, 0, 0, 0, "[ Auto-config custom resolution ]")
					GuiTooltip(gui, "Right click to reset", "")
					if clicked then
						config_resolution = true
						custom_gui = GuiCreate()
					elseif right_clicked then
						ModSettingRemove("EZMouse.custom_screen_resolution_x")
						ModSettingRemove("EZMouse.custom_screen_resolution_y")
					end
					if config_resolution then
						GuiStartFrame(custom_gui)
						local mx, my = InputGetMousePosOnScreen()
						GuiZSetForNextWidget(custom_gui, -99999999)
						local screen_width, screen_height = GuiGetScreenDimensions(custom_gui)
						local text = "Move your mouse to the very BOTTOM RIGHT CORNER of your screen and CLICK"
						local text_width, text_height = GuiGetTextDimensions(custom_gui, text)
						GuiText(custom_gui, (screen_width - text_width) / 2, (screen_height - text_height) / 2, text)
						GuiZSetForNextWidget(custom_gui, -9999999)
						GuiColorSetForNextWidget(custom_gui, 0, 0, 0, 1)
						GuiImage(custom_gui, 1, 0, 0, "data/debug/whitebox.png", 0.8, 1000, 1000)
						local clicked2, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(custom_gui)
						local rx, ry = 0, 0
						if not clicked and clicked2 then
							rx, ry = math.ceil(mx), math.ceil(my)
							config_resolution = false
							ModSettingSetNextValue("EZMouse.custom_screen_resolution_x", rx, false)
							ModSettingSetNextValue("EZMouse.custom_screen_resolution_y", ry, false)
							ModSettingSet("EZMouse.custom_screen_resolution_x", rx)
							ModSettingSet("EZMouse.custom_screen_resolution_y", ry)
							GuiDestroy(custom_gui)
							custom_gui = nil
						end
					end
					GuiIdPop(gui)
				end
			},
		}
	},
}

function ModSettingsUpdate(init_scope)
	local old_version = mod_settings_get_version(mod_id)
	mod_settings_update(mod_id, mod_settings, init_scope)
end

function ModSettingsGuiCount()
	return mod_settings_gui_count(mod_id, mod_settings)
end

function ModSettingsGui(gui, in_main_menu)
	mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)
end
