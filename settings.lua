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

mod_settings =
{
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
		ui_name = "SHID",
		not_setting = true,
		ui_fn = function(mod_id, gui, in_main_menu, im_id, setting)
			if GuiButton(gui, im_id, 0, 0, "[ Reset button position ]") then
				ModSettingSet("AdvancedSpellInventory.button_pos_x", 162)
				ModSettingSet("AdvancedSpellInventory.button_pos_y", 41)
			end
		end
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
