dofile_once("data/scripts/lib/utilities.lua")
dofile_once("data/scripts/debug/keycodes.lua")
dofile_once("data/scripts/lib/coroutines.lua")
dofile_once("data/scripts/gun/gun_enums.lua")
dofile_once("data/scripts/debug/keycodes.lua")
dofile_once("mods/AdvancedSpellInventory/lib/EZInventory/init.lua")("mods/AdvancedSpellInventory/lib/EZInventory/")

ModRegisterAudioEventMappings("mods/AdvancedSpellInventory/audio/GUIDs.txt")

local EZWand
local EZInventory = dofile_once("mods/AdvancedSpellInventory/lib/EZInventory/EZInventory.lua")
local EZMouse = dofile("mods/AdvancedSpellInventory/lib/EZInventory/lib/EZMouse/EZMouse.lua")("mods/AdvancedSpellInventory/lib/EZInventory/lib/EZMouse/")

local action_lookup = {
  -- For "bugged" spells
  [""] = {
		sprite = "data/ui_gfx/gun_actions/unidentified.png"
  }
}
local spell_types = {
  { name = "Everything", icon = "mods/AdvancedSpellInventory/files/spell_type_all.png" },
  { type = ACTION_TYPE_PROJECTILE, name = GameTextGetTranslatedOrNot("$inventory_actiontype_projectile"), icon = "data/ui_gfx/inventory/item_bg_projectile.png" },
  { type = ACTION_TYPE_STATIC_PROJECTILE, name = GameTextGetTranslatedOrNot("$inventory_actiontype_staticprojectile"), icon = "data/ui_gfx/inventory/item_bg_static_projectile.png" },
  { type = ACTION_TYPE_MODIFIER, name = GameTextGetTranslatedOrNot("$inventory_actiontype_modifier"), icon = "data/ui_gfx/inventory/item_bg_modifier.png" },
  { type = ACTION_TYPE_DRAW_MANY, name = GameTextGetTranslatedOrNot("$inventory_actiontype_drawmany"), icon = "data/ui_gfx/inventory/item_bg_draw_many.png" },
  { type = ACTION_TYPE_MATERIAL, name = GameTextGetTranslatedOrNot("$inventory_actiontype_material"), icon = "data/ui_gfx/inventory/item_bg_material.png" },
  { type = ACTION_TYPE_OTHER, name = GameTextGetTranslatedOrNot("$inventory_actiontype_other"), icon = "data/ui_gfx/inventory/item_bg_other.png" },
  { type = ACTION_TYPE_UTILITY, name = GameTextGetTranslatedOrNot("$inventory_actiontype_utility"), icon = "data/ui_gfx/inventory/item_bg_utility.png" },
  { type = ACTION_TYPE_PASSIVE, name = GameTextGetTranslatedOrNot("$inventory_actiontype_passive"), icon = "data/ui_gfx/inventory/item_bg_passive.png" },
}

local function is_keybind_down() return false end
local function is_dump_keybind_down() return false end
if ModIsEnabled("mnee") then
	ModLuaFileAppend("mods/mnee/bindings.lua", "mods/AdvancedSpellInventory/files/mnee.lua")
end

local function is_wand(entity)
	local ability_component = EntityGetFirstComponentIncludingDisabled(entity, "AbilityComponent")
	if not ability_component then
		return false
	end
	return ComponentGetValue2(ability_component, "use_gun_script") == true
end

-- Add script to spell refresh
do
  local file_path = "data/entities/particles/image_emitters/spell_refresh_effect.xml"
  local content = ModTextFileGetContent(file_path)
  ModTextFileSetContent(file_path, content:gsub([[</Entity>]], [[
    <LuaComponent
      script_source_file="mods/AdvancedSpellInventory/files/spell_refresh_add.lua"
      execute_every_n_frame="-1"
      execute_on_added="1"
      remove_after_executed="1"
    ></LuaComponent>
</Entity>
  ]]))
end

local sounds_enabled = ModSettingGet("AdvancedSpellInventory.sounds_enabled")
EZInventory.SetSoundsEnabled(sounds_enabled)
local function play_ui_sound(name)
  if not sounds_enabled then
    return
  end
  local cx, cy = GameGetCameraPos()
  GamePlaySound("data/audio/Desktop/ui.bank", "ui/" .. name, cx, cy)
end

local sorting_functions
sorting_functions = {
  alphabetical = function(a, b)
    local name_a = GameTextGetTranslatedOrNot(action_lookup[a.spell.action_id].name)
    local name_b = GameTextGetTranslatedOrNot(action_lookup[b.spell.action_id].name)
    return name_a < name_b
  end,
  uses_remaining = function(a, b)
    -- First sort by uses remaining, and if they're equal alphabetically
    if a.spell.uses_remaining < b.spell.uses_remaining then return true end
    if a.spell.uses_remaining > b.spell.uses_remaining then return false end
    return sorting_functions.alphabetical(a, b)
  end,
  type = function(a, b)
    -- First sort by uses remaining, and if they're equal alphabetically
    local type_a = action_lookup[a.spell.action_id].type
    local type_b = action_lookup[b.spell.action_id].type
    if type_a < type_b then return true end
    if type_a > type_b then return false end
    return sorting_functions.alphabetical(a, b)
  end,
}

local button_pos_x = ModSettingGet("AdvancedSpellInventory.button_pos_x") or 162
local button_pos_y = ModSettingGet("AdvancedSpellInventory.button_pos_y") or 41
local open = false
local origin_x, origin_y =
  tonumber(MagicNumbersGetValue("UI_FULL_INVENTORY_OFFSET_X"))
  + tonumber(MagicNumbersGetValue("UI_BARS_POS_X")),
  tonumber(MagicNumbersGetValue("UI_BARS_POS_Y")) --170, 48
local full_inventory_slots_x, full_inventory_slots_y
local filter_panel_height
local slot_width, slot_height
local search_filter = ""
local filter_by_type
local num_rows = ModSettingGet("AdvancedSpellInventory.num_rows")
local auto_storage = ModSettingGet("AdvancedSpellInventory.auto_storage")
local enable_spell_refresh_in_storage = ModSettingGet("AdvancedSpellInventory.enable_spell_refresh_in_storage")
local opening_inv_closes_spell_inv = ModSettingGet("AdvancedSpellInventory.opening_inv_closes_spell_inv")

function OnPausedChanged(is_paused, is_main_menu)
  if not is_paused then
    button_pos_x = ModSettingGet("AdvancedSpellInventory.button_pos_x") or 162
    button_pos_y = ModSettingGet("AdvancedSpellInventory.button_pos_y") or 41
    sounds_enabled = ModSettingGet("AdvancedSpellInventory.sounds_enabled")
    enable_spell_refresh_in_storage = ModSettingGet("AdvancedSpellInventory.enable_spell_refresh_in_storage")
    opening_inv_closes_spell_inv = ModSettingGet("AdvancedSpellInventory.opening_inv_closes_spell_inv")
    EZInventory.SetSoundsEnabled(sounds_enabled)
    EZInventory.UpdateCustomScreenResolution()
  end
end

local function get_spell_inventory()
  local player = EntityGetWithTag("player_unit")[1]
  if player then
    for i, child in ipairs(EntityGetAllChildren(player) or {}) do
      if EntityGetName(child) == "inventory_full" then
        return child
      end
    end
  end
end

local function is_inventory_open()
	local player = EntityGetWithTag("player_unit")[1]
	if player then
		local inventory_gui_component = EntityGetFirstComponentIncludingDisabled(player, "InventoryGuiComponent")
		if inventory_gui_component then
			return ComponentGetValue2(inventory_gui_component, "mActive")
		end
	end
end

local function get_spells_in_inventory()
  local spells = {}
  local spell_inventory = get_spell_inventory()
  if spell_inventory then
    for i, spell in ipairs(EntityGetAllChildren(spell_inventory) or {}) do
      local action_id
      local item_action_comp = EntityGetFirstComponentIncludingDisabled(spell, "ItemActionComponent")
      if item_action_comp then
        action_id = ComponentGetValue2(item_action_comp, "action_id")
      end
      local inv_x, inv_y, ui_sprite, uses_remaining
      local item_comp = EntityGetFirstComponentIncludingDisabled(spell, "ItemComponent")
      if item_comp then
        inv_x, inv_y = ComponentGetValue2(item_comp, "inventory_slot")
        uses_remaining = ComponentGetValue2(item_comp, "uses_remaining")
        ui_sprite = action_lookup[action_id] and action_lookup[action_id].sprite or ComponentGetValue2(item_comp, "ui_sprite")
      end
      table.insert(spells, {
        entity_id = spell,
        item_comp = item_comp,
        action_id = action_id,
        inv_x = inv_x,
        inv_y = inv_y,
        ui_sprite = ui_sprite,
        uses_remaining = uses_remaining,
      })
    end
    return spells
  else
    return nil
  end
end

local function get_inventory_size()
  local player = EntityGetWithTag("player_unit")[1]
  if player then
    local inventory_2_comp = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
    if inventory_2_comp then
      return
        ComponentGetValue2(inventory_2_comp, "full_inventory_slots_x"),
        ComponentGetValue2(inventory_2_comp, "full_inventory_slots_y")
    end
  end
end

local spell_tooltip_size_cache = setmetatable({}, { __mode = "k" })
local function calculate_spell_tooltip_size(gui, x, y, z, content)
  return spell_tooltip_size_cache[content] or { width = 0, height = 0 }
end

local tooltip_size_cache = setmetatable({}, { __mode = "k" })
local function calculate_other_tooltip_size(gui, x, y, z, content)
  return tooltip_size_cache[content] or { width = 0, height = 0 }
end

local function draw_other_tooltip(gui, x, y, z, content)
  local name = ComponentGetValue2(content.spell.item_comp, "item_name")
  local desc = ComponentGetValue2(content.spell.item_comp, "ui_description")
  local sprite = ComponentGetValue2(content.spell.item_comp, "ui_sprite")
  GuiIdPushString(gui, "tooltip")
  GuiBeginAutoBox(gui)
  GuiLayoutBeginHorizontal(gui, x, y, true)
  GuiLayoutBeginVertical(gui, 0, 0, true)
  GuiZSetForNextWidget(gui, z - 1)
  GuiColorSetForNextWidget(gui, 0.8, 0.8, 0.8, 1)
  GuiText(gui, 0, 0, GameTextGetTranslatedOrNot(name):upper())
  GuiZSetForNextWidget(gui, z - 1)
  GuiColorSetForNextWidget(gui, 0.8, 0.8, 0.8, 1)
  GuiText(gui, 0, 5, GameTextGetTranslatedOrNot(desc))
  GuiLayoutEnd(gui)
  GuiZSetForNextWidget(gui, z - 1)
  GuiImage(gui, 3, 10, 0, sprite, 1, 2, 2)
  GuiLayoutEnd(gui)
  GuiZSetForNextWidget(gui, z)
  GuiEndAutoBoxNinePiece(gui)
  local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
  if not tooltip_size_cache[content] then
    tooltip_size_cache[content] = { width = width - slot_width, height = height }
  end
  GuiIdPop(gui)
end

local function tooltip_func(gui, x, y, z, content)
  local action_id = content.spell.action_id
  GuiAnimateBegin(gui)
  GuiIdPushString(gui, "tooltip_animation")
  GuiAnimateScaleIn(gui, 1, 0.08, false)
  GuiAnimateAlphaFadeIn(gui, 2, 0.15, 0.15, false)
  if action_id and action_id ~= "" then
    local size = calculate_spell_tooltip_size(gui, x, y, z, content)
    if content.spell.entity_id then
      EZWand.RenderSpellTooltip(content.spell.entity_id, x + 2 - size.width / 2, y, gui)
    else
      EZWand.RenderSpellTooltip(action_id, x + 2 - size.width / 2, y, gui, {
        uses_remaining = content.spell.uses_remaining
      })
    end
    local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
    if not spell_tooltip_size_cache[content] then
      spell_tooltip_size_cache[content] = { width = width, height = height }
    end
  elseif not action_id then
    local size = calculate_other_tooltip_size(gui, x, y, z, content)
    draw_other_tooltip(gui, x - size.width / 2, y + 7, z, content)
  else
    GuiBeginAutoBox(gui)
    GuiZSetForNextWidget(gui, z - 1)
    GuiText(gui, x, y, "Bugged spell oh no :(")
    GuiZSetForNextWidget(gui, z)
    GuiEndAutoBoxNinePiece(gui)
  end
  GuiIdPop(gui)
  GuiAnimateEnd(gui)
end

local function does_spell_match_filter(filter, spell)
  local matches = true
  filter = filter:lower()
  if spell.action_id then
    local action_id = spell.action_id
    -- local description = GameTextGetTranslatedOrNot(action_lookup[action_id].description)
    if filter_by_type then
      matches = matches and (action_lookup[action_id].type == filter_by_type)
    end
    if filter ~= "" then
      local name = GameTextGetTranslatedOrNot(action_lookup[action_id].name or ""):lower()
      local id = action_id:lower()
      matches = matches and (name:find(filter) ~= nil) -- or description:find(filter)
    end
    return matches
  end
  return false
end

local function render_after(self, slot, gui, new_id, x, y, z, scale)
  if self.spell.action_id then
    GuiZSetForNextWidget(gui, z - 0.5)
    GuiImage(gui, new_id(), x, y, EZWand.get_spell_bg(self.spell.action_id), 1, 1, 1)
  end
  if self.spell.uses_remaining >= 0 then
    GuiZSetForNextWidget(gui, z - 2)
    GuiColorSetForNextWidget(gui, 0.9, 0.9, 0.9, 1)
    GuiText(gui, x + 2, y + 2, self.spell.uses_remaining, 1, "data/fonts/font_small_numbers.xml", true)
  end
  -- Grey it out if filters are active
  if not does_spell_match_filter(search_filter or "", self.spell) then
    GuiZSetForNextWidget(gui, z - 2.1)
    local scale_x = slot.width / 20
    local scale_y = slot.height / 20
    GuiImage(gui, new_id(), x, y, "mods/AdvancedSpellInventory/files/grey.png", 1, scale_x, scale_y)
  end
end

local function are_spells_same(a, b)
  return a.action_id == b.action_id and a.uses_remaining == b.uses_remaining
end

-- gets called before moving to check whether it can stack with target slot
-- a is source slot, b is target
local function stackable_with(a, b)
  if b.data.is_storage then
    return are_spells_same(a.content.spell, b.content.spell)
  end
  return false
end

local function clone_content(content)
  return {
    sprite = content.sprite,
    spell = {
      entity_id = content.spell.entity_id,
      item_comp = content.spell.item_comp,
      action_id = content.spell.action_id,
      inv_x = content.spell.inv_x,
      inv_y = content.spell.inv_y,
      uses_remaining = content.spell.uses_remaining,
    },
    max_stack_size = content.max_stack_size,
    render_after = content.render_after,
    stackable_with = content.stackable_with,
    tooltip_func = content.tooltip_func,
    clone = content.clone_content
  }
end

local function make_content_from_action_id(action_id, stack_size, uses_remaining)
  local sprite = action_lookup[action_id] and action_lookup[action_id].sprite
  return {
    sprite = sprite,
    stack_size = tonumber(stack_size),
    max_stack_size = 999,
    stackable_with = stackable_with,
    render_after = render_after,
    tooltip_func = tooltip_func,
    clone = clone_content,
    spell = {
      entity_id = nil,
      item_comp = nil,
      action_id = action_id,
      inv_x = 1,
      inv_y = 1,
      uses_remaining = tonumber(uses_remaining),
    },
  }
end

local function make_content_from_entity(entity_id)
  local action_id
  local item_action_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "ItemActionComponent")
  if item_action_comp then
    action_id = ComponentGetValue2(item_action_comp, "action_id")
  end
  local inv_x, inv_y, ui_sprite, uses_remaining
  local item_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "ItemComponent")
  if item_comp then
    inv_x, inv_y = ComponentGetValue2(item_comp, "inventory_slot")
    uses_remaining = ComponentGetValue2(item_comp, "uses_remaining")
    ui_sprite = action_lookup[action_id] and action_lookup[action_id].sprite or ComponentGetValue2(item_comp, "ui_sprite")
  end
  return {
    sprite = ui_sprite,
    stack_size = 1,
    max_stack_size = 999,
    stackable_with = stackable_with,
    render_after = render_after,
    tooltip_func = tooltip_func,
    clone = clone_content,
    spell = {
      entity_id = entity_id,
      item_comp = item_comp,
      action_id = action_id,
      inv_x = inv_x,
      inv_y = inv_y,
      uses_remaining = uses_remaining,
    },
  }
end

local storage_slots
local function get_first_stackable_or_free_storage_slot(current_slot)
  local free_slot
  for i, slot in ipairs(storage_slots or {}) do
    if not free_slot and slot.content == nil then
      free_slot = slot
    end
    if current_slot:CanStackWith(slot) then
      return slot
    end
  end
  return free_slot
end

local slots
local function get_first_free_inventory_slot()
  for i, slot in ipairs(slots or {}) do
    if slot.content == nil then
      return slot
    end
  end
end

local key = "AdvancedSpellInventory_stored_spells"
local function load_stored_spells()
  local serialized = GlobalsGetValue(key, "")
  local stored_spells = string_split(serialized, "|")
  for i, spell in ipairs(stored_spells) do
    if spell ~= "" then
      local values = string_split(spell, ";") -- stack_size;action_id;uses_remaining
      local stack_size, action_id, uses_remaining = unpack(values)
      if storage_slots[i] then
        storage_slots[i]:SetContent(make_content_from_action_id(action_id, stack_size, uses_remaining))
      end
    end
  end
end

local function save_stored_spells()
  local out = {}
  for i, slot in ipairs(storage_slots) do
    local spell = slot.content and slot.content.spell
    if spell then
      local str = ("%d;%s;%d"):format(slot.content.stack_size, spell.action_id, spell.uses_remaining)
      table.insert(out, str)
    else
      table.insert(out, "")
    end
  end
  GlobalsSetValue(key, table.concat(out, "|"))
end

-- Keep the display in sync with what's in the spell inventory
-- Simply recreating all widgets is probably more efficient than doing all kinds of checks to only update the ones that changed
local function update_slots()
  for i, slot in ipairs(slots) do
    slot:ClearContent()
  end
  for i, spell in ipairs(get_spells_in_inventory() or {}) do
    local did_store_spell = false
    if auto_storage and spell.action_id and spell.item_comp and ComponentGetValue2(spell.item_comp, "mFramePickedUp") == GameGetFrameNum() then
      local content = make_content_from_entity(spell.entity_id)
      for i, slot in ipairs(storage_slots or {}) do
        if slot.content == nil then
          slot:SetContent(content)
          did_store_spell = true
        elseif are_spells_same(content.spell, slot.content.spell) then
          slot.content.stack_size = slot.content.stack_size + 1
          did_store_spell = true
        end
        if did_store_spell then
          EntityKill(spell.entity_id)
          break
        end
      end
    end
    if not did_store_spell then
      -- Problem: Sometimes in vanilla, items can have the same inv slot set, so indexing by inv slot is suboptimal...
      local slot = slots[spell.inv_y * full_inventory_slots_x + spell.inv_x + 1]
      slot:SetContent(make_content_from_entity(spell.entity_id))
    else
      save_stored_spells()
    end
  end
end

local function sort_spells_in_storage(func, sort_order)
  local contents = {}
  for i, slot in ipairs(storage_slots) do
    if slot.content then
      table.insert(contents, slot.content)
    end
  end
  -- Merge same spells
  for i=#contents, 1, -1 do
    local content = contents[i]
    for j=i-1, 1, -1 do
      local content2 = contents[j]
      if are_spells_same(content.spell, content2.spell) then
        content2.stack_size = content2.stack_size + content.stack_size
        table.remove(contents, i)
        break
      end
    end
  end
  for i, slot in ipairs(storage_slots) do
    slot:ClearContent()
  end
  table.sort(contents, function(a, b)
    if sort_order == "ascending" then
      return func(a, b)
    elseif sort_order == "descending" then
      return func(b, a)
    end
    error("You misspelled sort_order, stringly typed strikes again")
    return true
  end)
  for i, content in ipairs(contents) do
    storage_slots[i]:SetContent(content)
  end
end

local function has_infinite_spells()
  local world_entity_id = GameGetWorldStateEntity()
  if world_entity_id then
    local worldstate_comp = EntityGetFirstComponentIncludingDisabled(world_entity_id, "WorldStateComponent")
    if worldstate_comp then
      return ComponentGetValue2(worldstate_comp, "perk_infinite_spells")
    end
  end
  return false
end

local function update_spell_uses()
  for i, slot in ipairs(storage_slots) do
    if slot.content then
      if has_infinite_spells() and not action_lookup[slot.content.spell.action_id].never_unlimited then
        slot.content.spell.uses_remaining = -1
      else
        slot.content.spell.uses_remaining = action_lookup[slot.content.spell.action_id].max_uses or -1
      end
    end
  end
end

local infinite_spells_last_frame = false
local function update_storage_if_unlimited_perks()
  local infinite_spells = has_infinite_spells()
  if infinite_spells ~= infinite_spells_last_frame then
    infinite_spells_last_frame = infinite_spells
    update_spell_uses()
  end
end

local previous_spells
local function has_spell_inventory_changed()
  local player = EntityGetWithTag("player_unit")[1]
  if not player then
    return false
  end
  local spells = get_spells_in_inventory()
  local _previous_spells = previous_spells
  previous_spells = spells
  if not spells or not _previous_spells then
    return false
  end
  if #_previous_spells ~= #spells then
    return true
  end
  for i=1, #spells do
    if spells[i].entity_id ~= _previous_spells[i].entity_id then
      return true
    end
    if spells[i].action_id ~= _previous_spells[i].action_id then
      return true
    end
    if spells[i].uses_remaining ~= _previous_spells[i].uses_remaining then
      return true
    end
    if spells[i].inv_x ~= _previous_spells[i].inv_x then
      return true
    end
    if spells[i].inv_y ~= _previous_spells[i].inv_y then
      return true
    end
  end
end

-- Gets called when dropping content into the world, not onto other slots
local function drop_content_handler(self, ev)
  local player = EntityGetWithTag("player_unit")[1]
  if player then
    play_ui_sound("item_remove")
    if self.data.is_storage then
      local mx, my = DEBUG_GetMouseWorld()
      SetRandomSeed(GameGetFrameNum() + mx, my)
      for i=1, self.content.stack_size do
        local px, py = EntityGetFirstHitboxCenter(player)
        local entity_id = CreateItemActionEntity(self.content.spell.action_id, px, py)
        local vel_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "VelocityComponent")
        if vel_comp then
          local dx, dy = mx - px, my - py
          local dist = math.sqrt(dx * dx + dy * dy)
          dist = math.min(dist, 100)
          dist = dist + Random(5, 10)
          local dir = math.atan2(dy, dx)
          dir = dir + Randomf(math.rad(-20), math.rad(20))
          local vx, vy = math.cos(dir) * dist, math.sin(dir) * dist
          ComponentSetValue2(vel_comp, "mVelocity", vx, vy)
          EntitySetComponentsWithTagEnabled(entity_id, "enabled_in_world", true)
          EntitySetComponentsWithTagEnabled(entity_id, "enabled_in_inventory", false)
          EntitySetComponentsWithTagEnabled(entity_id, "item_unidentified", false)
        end
        local item_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "ItemComponent")
        if item_comp then
          ComponentSetValue2(item_comp, "uses_remaining", self.content.spell.uses_remaining)
        end
        if ModIsEnabled("quant.ew") then
          CrossCall("ew_thrown", entity_id)
        end
      end
    else
      local entity_id = self.content.spell.entity_id
      local vel_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "VelocityComponent")
      if vel_comp then
        local px, py = EntityGetFirstHitboxCenter(player)
        local mx, my = DEBUG_GetMouseWorld()
        local dx, dy = mx - px, my - py
        local dist = math.sqrt(dx * dx + dy * dy)
        dist = math.min(dist, 100)
        local dir = math.atan2(dy, dx)
        local vx, vy = math.cos(dir) * dist, math.sin(dir) * dist
        ComponentSetValue2(vel_comp, "mVelocity", vx, vy)
        EntityRemoveFromParent(entity_id)
        EntityApplyTransform(entity_id, px, py)
        EntitySetComponentsWithTagEnabled(entity_id, "enabled_in_world", true)
        EntitySetComponentsWithTagEnabled(entity_id, "enabled_in_inventory", false)
        EntitySetComponentsWithTagEnabled(entity_id, "item_unidentified", false)
      end
      local item_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "ItemComponent")
      if item_comp then
        ComponentSetValue2(item_comp, "uses_remaining", self.content.spell.uses_remaining)
      end
      if ModIsEnabled("quant.ew") then
        CrossCall("ew_thrown", entity_id)
      end
    end
  end
  self:ClearContent()
  save_stored_spells()
end

function string_split(input, sep)
  local result = {}
  for v in string.gmatch(input..sep, '([^'.. sep ..']*)' .. sep) do
    table.insert(result, v)
  end
  return result
end

function OnPlayerSpawned(player)
  frame_player_spawned = GameGetFrameNum()
  if ModIsEnabled("mnee") then
    function is_keybind_down()
      return get_binding_pressed("AdvSpellInv", "toggle")
    end
    function is_dump_keybind_down()
      return get_binding_pressed("AdvSpellInv", "dump")
    end
  end
end

local function button(gui, new_id, text, active)
  local w, h = GuiGetTextDimensions(gui, text)
  GuiText(gui, 2, 0, "")
  local _, _, _, tx, ty = GuiGetPreviousWidgetInfo(gui)
  tx = tx - 1
  GuiImageNinePiece(gui, new_id(), tx - 2, ty, w + 7, h + 2, 0, "data/debug/whitebox.png")
  local clicked, _, hovered = GuiGetPreviousWidgetInfo(gui)
  -- GuiGetPreviousWidgetInfo does not return right click for GuiImageNinePiece, so get it manually
  local right_clicked = hovered and InputIsMouseButtonJustDown(Mouse_right)
  GuiZSetForNextWidget(gui, 20 - 1)
  GuiImageNinePiece(gui, new_id(), tx + 3, ty + 2, w - 1, h - 4, 1, "mods/AdvancedSpellInventory/files/button_9piece" .. (active and "_active" or "") .. ".png")
  if hovered then
    GuiColorSetForNextWidget(gui, 0.95, 0.95, 0.7, 1)
  end
  GuiText(gui, 0, 0, text)
  GuiText(gui, 1, 0, "")
  return clicked, right_clicked
end

local function render_filter_panel(gui, new_id, origin_x, origin_y)
  local total_height = 0
  -- Sort buttons
  GuiLayoutBeginHorizontal(gui, origin_x, origin_y, true)
  GuiText(gui, 0, 0, " Sort by: ")
  local o = {
    ["A-Z"] = sorting_functions.alphabetical,
    ["Uses"] = sorting_functions.uses_remaining,
    ["Type"] = sorting_functions.type,
  }
  for name, func in pairs(o) do
    local clicked, right_clicked = button(gui, new_id, name, false)
    if clicked or right_clicked then
      sort_spells_in_storage(func, clicked and "ascending" or "descending")
    end
  end
  local v = ""
  if input_focused then
    GuiAnimateBegin(gui)
    GuiAnimateAlphaFadeIn(gui, new_id(), 0, 0, true)
    GuiBeginAutoBox(gui)
    GuiOptionsAddForNextWidget(gui, GUI_OPTION.Layout_NoLayouting)
    GuiZSetForNextWidget(gui, -99999999999)
    GuiBeginScrollContainer(gui, new_id(), EZMouse.screen_x, EZMouse.screen_y, 10, 10, false, 0, 0)
    GuiEndAutoBoxNinePiece(gui)
    GuiAnimateEnd(gui)

    v = GuiTextInput(gui, new_id(), 0, 0, "", 0, 8)

    GuiEndScrollContainer(gui)
  end
  -- Input field with logic to disable inputs and have backspace-holding delete functionality
  if input_focused then
    GuiColorSetForNextWidget(gui, 0.9, 0.9, 0, 1)
  end
  GuiText(gui, 1, 0, " Filter:")
  local new_search_filter = GuiTextInput(gui, new_id(), 0, 0, search_filter or "", 54, 8)
  local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
  if InputIsMouseButtonJustDown(Mouse_right) and hovered then
    new_search_filter = ""
    search_filter = ""
  end
  if #new_search_filter < 8 then
    new_search_filter = new_search_filter .. v
  end
  if InputIsKeyJustDown(Key_BACKSPACE) then
    input_backspace_down_frame = GameGetFrameNum()
    new_search_filter = new_search_filter:gsub(".?$", "")
  elseif input_focused and InputIsKeyDown(Key_BACKSPACE) and input_backspace_down_frame + 15 < GameGetFrameNum() and GameGetFrameNum() % 5 == 0 then
    new_search_filter = new_search_filter:gsub(".?$", "")
  end
  if new_search_filter ~= search_filter then
    search_filter_changed = true
  end
  if input_focused then
    search_filter = new_search_filter
  end
  if InputIsMouseButtonJustDown(Mouse_left) then
    input_focused = hovered
  elseif InputIsKeyJustDown(Key_RETURN) then
    input_focused = false
  end
  input_hovered = hovered
  GuiLayoutEnd(gui)
  -- Second row, filter by spell type
  local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
  total_height = total_height + height + 2
  GuiLayoutBeginHorizontal(gui, origin_x - 1, origin_y + height + 2, true)
  local text = "Filter spells by type:"
  local text_width, text_height = GuiGetTextDimensions(gui, text)
  GuiText(gui, 4, (slot_height - text_height) / 2, text)
  for i, spell_type in ipairs(spell_types) do
    local scale = slot_width / 20
    GuiImage(gui, new_id(), 0, 0, spell_type.icon, 1, scale, scale)
    local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
    if spell_type.type == filter_by_type then
      GuiOptionsAddForNextWidget(gui, GUI_OPTION.Layout_NoLayouting)
      GuiColorSetForNextWidget(gui, 0, 1, 0, 1)
      local checkbox_w, checkbox_h = GuiGetImageDimensions(gui, "data/debug/sui_checkbox_overlay.png", scale)
      GuiImage(gui, new_id(), x - (checkbox_w - slot_width) / 2, y - (checkbox_h - slot_height) / 2, "data/debug/sui_checkbox_overlay.png", 1, scale, scale)
    end
    if clicked then
      filter_by_type = spell_type.type
    end
    GuiTooltip(gui, spell_type.name, "")
  end
  GuiLayoutEnd(gui)
  local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
  total_height = total_height + height
  return total_height
end

function OnWorldPostUpdate()
  if opening_inv_closes_spell_inv and GameIsInventoryOpen() then
    open = false
  end

  local id = 1
  local function new_id()
    id = id + 1
    return id
  end

  gui = gui or GuiCreate()
  GuiStartFrame(gui)

  EZMouse.update(gui)

  if not slot_width then
    slot_width, slot_height = GuiGetImageDimensions(gui, "data/ui_gfx/inventory/full_inventory_box.png", 1)
  end

  -- Run this 1 frame after player has spawned
  if frame_player_spawned == GameGetFrameNum() - 1 then
    dofile_once("mods/mnee/lib.lua")
    -- Do this here so mods have enough time to do their gun_actions.lua mod appends
    dofile_once("data/scripts/gun/gun_actions.lua")
    EZWand = dofile_once("mods/AdvancedSpellInventory/lib/EZWand/EZWand.lua")
    for i, action in ipairs(actions) do
      action_lookup[action.id] = action
    end

    -- Render the middle panel part once to calculate its size, jank yea yea
    filter_panel_height = render_filter_panel(gui, new_id, 0, -100000)

    if not slots then
      slots = {}
      full_inventory_slots_x, full_inventory_slots_y = get_inventory_size()
      for y=1, full_inventory_slots_y do
        for x=1, full_inventory_slots_x do
          local idx = x + (y-1) * full_inventory_slots_x
          slots[idx] = EZInventory.Slot({
            x = origin_x + (x-1) * slot_width,
            y = origin_y + (y-1) * slot_height,
            data = {
              slot_x = x,
              slot_y = y,
              move_check = function(self, target_slot)
                return self.content.spell.action_id ~= nil or not target_slot.data.is_storage
              end,
              -- Needs to return the max stack size this slot can hold of the provided content
              get_max_stack_size = function(self, content)
                return 1
              end
            },
            width = slot_width,
            height = slot_height,
          })
          slots[idx]:AddEventListener("shift_click", function(self, ev)
            if self.content then
              local free_slot = get_first_stackable_or_free_storage_slot(self)
              if free_slot then
                self:MoveContent(free_slot)
              end
            end
          end)
          slots[idx]:AddEventListener("drop_content", drop_content_handler)
          slots[idx]:AddEventListener("move_content", function(self, ev)
            if ev.target.data.is_storage then
              EntityKill(ev.content.spell.entity_id)
              ev.content.spell.entity_id = nil
              ev.content.spell.item_comp = nil
              save_stored_spells()
            else
              ComponentSetValue2(ev.content.spell.item_comp, "inventory_slot", ev.target.data.slot_x - 1, ev.target.data.slot_y - 1)
            end
          end)
        end
      end
      update_slots()

      storage_slots = {}
      for y=1, num_rows do
        for x=1, full_inventory_slots_x do
          local storage_slot = EZInventory.Slot({
            x = origin_x + (x-1) * slot_width,
            y = origin_y + (y-1) * slot_height + (full_inventory_slots_y * slot_height) + filter_panel_height + 4,
            data = {
              is_storage = true,
              slot_x = x,
              slot_y = y,
              x = x,
              y = y,
              move_check = function(self, target_slot)
                if not target_slot.data.is_storage and target_slot.content and self.content.stack_size > 1 then
                  return false
                end
                return true
              end,
              get_max_stack_size = function(self, content)
                return math.huge
              end
            },
            width = slot_width,
            height = slot_height,
          })
          storage_slot:AddEventListener("shift_click", function(self, ev)
            if self.content then
              local free_slot = get_first_free_inventory_slot()
              if free_slot then
                storage_slot:MoveContent(free_slot)
              end
            end
          end)
          storage_slot:AddEventListener("drop_content", drop_content_handler)
          storage_slot:AddEventListener("move_content", function(self, ev)
            if not ev.target.data.is_storage then
              local action_entity = CreateItemActionEntity(ev.content.spell.action_id)
              local item_comp = EntityGetFirstComponentIncludingDisabled(action_entity, "ItemComponent")
              if item_comp then
                ComponentSetValue2(item_comp, "inventory_slot", ev.target.data.slot_x - 1, ev.target.data.slot_y - 1)
                ComponentSetValue2(item_comp, "uses_remaining", ev.content.spell.uses_remaining)
              end
              local spell_inventory = get_spell_inventory()
              EntityAddChild(spell_inventory, action_entity)
            end
            save_stored_spells()
          end)
          storage_slots[(y-1) * full_inventory_slots_x + x] = storage_slot
        end
      end
    end
    load_stored_spells()
  end

  update_storage_if_unlimited_perks()
  if has_spell_inventory_changed() then
    update_slots()
  end

  -- Refresh spells in spell storage if spell refresh is picked up
  if enable_spell_refresh_in_storage and GlobalsGetValue("AdvancedSpellInventory_spells_refreshed", "0") == "1" then
    GlobalsSetValue("AdvancedSpellInventory_spells_refreshed", "0")
    update_spell_uses()
  end

  -- Allow speed clicking
  GuiOptionsAdd(gui, GUI_OPTION.HandleDoubleClickAsClick)
  GuiOptionsAdd(gui, GUI_OPTION.ClickCancelsDoubleClick)

  if GameGetIsGamepadConnected() then
		GuiOptionsAdd(gui, GUI_OPTION.NonInteractive)
	end
	GuiOptionsAdd(gui, GUI_OPTION.NoPositionTween)

  local player = EntityGetWithTag("player_unit")[1]
	local inventory_open = is_inventory_open()
  local inventory_bags_open = GlobalsGetValue("InventoryBags_is_open", "0") ~= "0"
	if player then
    local button_clicked = false
    if not inventory_open and not inventory_bags_open then
      local image = InputIsKeyDown(Key_LSHIFT) and "dump_button.png" or "gui_button.png"
      button_clicked = GuiImageButton(gui, 99999, button_pos_x, button_pos_y, "", "mods/AdvancedSpellInventory/files/" .. image)
      local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
      if hovered and InputIsMouseButtonDown(Mouse_right) then
        dragging_button = true
      end
      if InputIsKeyDown(Key_LSHIFT) then
        GuiTooltip(gui, "Take a dump", "Dump all spells of currently active wand to spell storage")
      end
    end
    -- Toggle it open/closed
    if is_keybind_down() or (not InputIsKeyDown(Key_LSHIFT) and button_clicked) then
      open = not open
      GlobalsSetValue("AdvancedSpellInventory_is_open", tostring(open and 1 or 0))
      play_ui_sound("inventory_" .. (open and "open" or "close"))
    elseif is_dump_keybind_down() or (InputIsKeyDown(Key_LSHIFT) and button_clicked) then
        local inventory_2_comp = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
        if inventory_2_comp then
          local active_wand_entity_id = ComponentGetValue2(inventory_2_comp, "mActiveItem")
          if is_wand(active_wand_entity_id) then
            for i, action_entity_id in ipairs(EntityGetAllChildren(active_wand_entity_id) or {}) do
              for i, slot in ipairs(storage_slots or {}) do
                local did_store_spell = false
                -- This is the worst mod I've ever written what the fuck
                local content = make_content_from_entity(action_entity_id)
                content.spell.entity_id = nil
                content.spell.item_comp = nil
                if slot.content == nil then
                  slot:SetContent(content)
                  did_store_spell = true
                elseif are_spells_same(content.spell, slot.content.spell) then
                  slot.content.stack_size = slot.content.stack_size + 1
                  did_store_spell = true
                end
                if did_store_spell then
                  -- Apparently required according to some of my older comments, because EntityKill takes one frame to take effect
                  EntityRemoveFromParent(action_entity_id)
                  EntityKill(action_entity_id)
                  break
                end
              end
            end
            ComponentSetValue2(inventory_2_comp, "mForceRefresh", true)
            ComponentSetValue2(inventory_2_comp, "mActualActiveItem", 0)
            if sounds_enabled then
              GamePlaySound("mods/AdvancedSpellInventory/audio/AdvancedSpellInventory.bank", "dump", 0, 0)
            end
            save_stored_spells()
          end
        end
    end
  end

  if InputIsMouseButtonJustUp(Mouse_right) then
    dragging_button = false
    ModSettingSet("AdvancedSpellInventory.button_pos_x", button_pos_x)
    ModSettingSet("AdvancedSpellInventory.button_pos_y", button_pos_y)
  end
  if dragging_button then
    button_pos_x, button_pos_y = EZMouse.screen_x - 10, EZMouse.screen_y - 10
  end

  for i, slot in ipairs(slots or {}) do
    if slot.hovered and InputIsMouseButtonJustDown(Mouse_right) then
      drop_content_handler(slot)
      slot:ClearContent()
    end
  end
  for i, slot in ipairs(storage_slots or {}) do
    if slot.hovered and InputIsMouseButtonJustDown(Mouse_right) then
      drop_content_handler(slot)
      slot:ClearContent()
    end
  end

  local visible = open and not inventory_open and (player ~= nil)
  local dragging_enabled = not InputIsKeyDown(Key_LSHIFT)
  EZInventory.Update(gui, visible, dragging_enabled)
	if visible then
    local title_text = GameTextGetTranslatedOrNot("$hud_title_actionstorage")
    local text_w, text_h = GuiGetTextDimensions(gui, title_text)
    GuiZSetForNextWidget(gui, 20)
    GuiText(gui, origin_x, origin_y - 2 - text_h, title_text)
    GuiZSetForNextWidget(gui, 21)
    GuiColorSetForNextWidget(gui, 0, 0, 0, 1)
    -- Title "Spells"
    GuiText(gui, origin_x, origin_y - 2 - text_h + 1, title_text)
    local panel_width = full_inventory_slots_x * slot_width - 2
    local panel_height = full_inventory_slots_y * slot_height + num_rows * slot_height + filter_panel_height + 2
    -- Container with border
    GuiZSetForNextWidget(gui, 20)
    GuiImageNinePiece(gui, new_id(), origin_x + 1, origin_y + 1, panel_width, panel_height, 1, "mods/AdvancedSpellInventory/files/container_9piece.png", "mods/AdvancedSpellInventory/files/container_9piece.png")
    local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
    -- Block mouse clicks if panel is hovered
    if hovered then
      local mx, my = EZMouse.screen_x, EZMouse.screen_y
      GuiZSetForNextWidget(gui, 0)
      GuiImage(gui, new_id(), mx - 100, my - 100, "data/debug/whitebox.png", 0.0001, 10, 10)
    end
    render_filter_panel(gui, new_id, origin_x + 2, origin_y + (full_inventory_slots_y * slot_height) + 4)
	end

  -- Disable controls if input field is hovered
  if player then
    local controls_enabled = not visible or not input_focused
    if controls_enabled ~= controls_enabled_last_frame then
      local controls_comp = EntityGetFirstComponentIncludingDisabled(player, "ControlsComponent")
      if controls_comp then
        EntityRemoveComponent(player, controls_comp)
        controls_comp = EntityAddComponent2(player, "ControlsComponent")
        ComponentSetValue2(controls_comp, "enabled", controls_enabled)
      end
      local inventory_2_comp = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
      if inventory_2_comp then
        EntitySetComponentIsEnabled(player, inventory_2_comp, controls_enabled)
      end
    end
    controls_enabled_last_frame = controls_enabled
  end
end
