dofile_once("data/scripts/lib/utilities.lua")
dofile_once("data/scripts/debug/keycodes.lua")
local EZWand = dofile_once("mods/AdvancedSpellInventory/lib/EZWand/EZWand.lua")
dofile_once("mods/AdvancedSpellInventory/lib/EZInventory/init.lua")("mods/AdvancedSpellInventory/lib/EZInventory/")
local EZInventory = dofile_once("mods/AdvancedSpellInventory/lib/EZInventory/EZInventory.lua")
local EZMouse = dofile("mods/AdvancedSpellInventory/lib/EZInventory/lib/EZMouse/EZMouse.lua")("mods/AdvancedSpellInventory/lib/EZInventory/lib/EZMouse/")

dofile_once("data/scripts/gun/gun_enums.lua")
dofile_once("data/scripts/gun/gun_actions.lua")

local action_lookup = {}
for i, action in ipairs(actions) do
  action_lookup[action.id] = action
end

-- Print contents of `tbl`, with indentation.
-- `indent` sets the initial level of indentation.
function tprint (tbl, indent)
  if not indent then indent = 0 end
  for k, v in pairs(tbl) do
    formatting = string.rep("  ", indent) .. k .. ": "
    if type(v) == "table" then
      print(formatting)
      tprint(v, indent+1)
    elseif type(v) == 'boolean' then
      print(formatting .. tostring(v))
    else
      print(formatting .. v)
    end
  end
end

if ModIsEnabled("mnee") then
	ModLuaFileAppend("mods/mnee/bindings.lua", "mods/AdvancedSpellInventory/mnee.lua")
	dofile_once("mods/mnee/lib.lua")
end

local sort_order = "ascending"
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
}

local button_pos_x = 162
local button_pos_y = 44
local open = false
local button_locked = true
local origin_x, origin_y =
  tonumber(MagicNumbersGetValue("UI_FULL_INVENTORY_OFFSET_X"))
  + tonumber(MagicNumbersGetValue("UI_BARS_POS_X")),
  tonumber(MagicNumbersGetValue("UI_BARS_POS_Y")) --170, 48 
local full_inventory_slots_x, full_inventory_slots_y
local slot_width, slot_height = 20, 20
local slot_margin = 1
local slot_width_total, slot_height_total = (slot_width + slot_margin * 2), (slot_height + slot_margin * 2)
local sorting_function = sorting_functions.alphabetical

local function get_mouse_gui_pos(gui)
  -- These seem to always be 1280, 720 no matter the actual screen size/resolution
  local mouse_screen_x, mouse_screen_y = InputGetMousePosOnScreen() -- or ControlsComponent:mMousePositionRaw
  local mx_p, my_p = mouse_screen_x / 1280, mouse_screen_y / 720
  local gui_width, gui_height = GuiGetScreenDimensions(gui)
  return mx_p * gui_width, my_p * gui_height
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
  -- collectgarbage("collect")
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
    -- print("calculating size!!!!", width, height)
    tooltip_size_cache[content] = { width = width - 20, height = height }
    -- local count = 0
    -- for k, v in pairs(tooltip_size_cache) do
    --   count = count + 1
    --   print(tostring(k))
    -- end
    -- print("Count: ", count)
  end
  GuiIdPop(gui)
end

local function copy_content(content)
  return {
    sprite = content.sprite,
    spell = {
      entity_id = content.spell.entity_id,
      item_comp = content.spell.item_comp,
      action_id = content.spell.action_id,
      inv_x = content.spell.inv_x,
      inv_y = content.spell.inv_y,
      ui_sprite = content.spell.ui_sprite,
      uses_remaining = content.spell.uses_remaining,
    },
    max_stack_size = content.max_stack_size,
    render_after = content.render_after,
    stackable_with = content.stackable_with,
    tooltip_func = content.tooltip_func
  }
end

local storage_slots
local function get_first_free_or_stackable_storage_slot(current_slot)
  for i, slot in ipairs(storage_slots or {}) do
    if slot.content == nil or current_slot:CanStackWith(slot) then
      return slot
    end
  end
end

local slots
local function get_first_free_inventory_slot()
  for i, slot in ipairs(slots or {}) do
    if slot.content == nil then
      return slot
    end
  end
end

-- Keep the display in sync with what's in the spell inventory
-- Simply recreating all widgets is probably more efficient than doing all kinds of checks to only update the ones that changed
local function update_slots()
  -- print("updating slots!")
  for i, slot in ipairs(slots) do
    slot:ClearContent()
  end
  for i, spell in ipairs(get_spells_in_inventory() or {}) do
    -- Problem: Sometimes in vanilla, items can have the same inv slot set, so indexing by inv slot is suboptimal...
    local slot = slots[spell.inv_x + 1]
    slot:SetContent({
      sprite = spell.ui_sprite,
      spell = spell,
      stack_size = 1,
      max_stack_size = 200,
      -- gets called before moving, a is source slot, b is target
      stackable_with = function(a, b)
        if b.data.is_storage then
          return a.content.spell.action_id == b.content.spell.action_id
            and a.content.spell.uses_remaining == b.content.spell.uses_remaining
        end
        return false
      end,
      render_after = function(self, slot, gui, new_id, x, y, z, scale)
        if self.spell.action_id then
          GuiZSetForNextWidget(gui, z - 0.5)
          GuiImage(gui, new_id(), x - 2, y - 2, EZWand.get_spell_bg(self.spell.action_id), 1, 1, 1)
        end
        if self.spell.uses_remaining >= 0 then
          GuiZSetForNextWidget(gui, z - 2)
          GuiColorSetForNextWidget(gui, 0.8, 0.8, 0.8, 1)
          GuiText(gui, x, y, self.spell.uses_remaining, 1, "data/fonts/font_small_numbers.xml", true)
        end
      end,
      tooltip_func = function(gui, x, y, z, content)
        local action_id = content.spell.action_id
        GuiAnimateBegin(gui)
        GuiIdPushString(gui, "tooltip_animation")
        GuiAnimateScaleIn(gui, 1, 0.08, false)
        GuiAnimateAlphaFadeIn(gui, 2, 0.15, 0.15, false)
        if action_id then
          local size = calculate_spell_tooltip_size(gui, x, y, z, content)
          EZWand.RenderSpellTooltip(action_id, x + 2 - size.width / 2, y, gui)
          local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
          if not spell_tooltip_size_cache[content] then
            spell_tooltip_size_cache[content] = { width = width, height = height }
          end
        else
          local size = calculate_other_tooltip_size(gui, x, y, z, content)
          draw_other_tooltip(gui, x - size.width / 2, y + 7, z, content)
        end
        GuiIdPop(gui)
        GuiAnimateEnd(gui)
      end
    })
  end
end

local previous_spells
local function has_spell_inventory_changed()
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
    end
  end
  self:ClearContent()
end

local key = "AdvancedSpellInventory_stored_spells"
local function load_stored_spells()
  local serialized = GlobalsGetValue(key, "")

end

local function save_stored_spells()
  GlobalsSetValue(key, "")
end

function OnPlayerSpawned(player)
  -- GamePickUpInventoryItem(player, CreateItemActionEntity("LIGHT_BULLET", 0, 0), false)
  -- GamePickUpInventoryItem(player, CreateItemActionEntity("LIGHT_BULLET", 0, 0), false)
  -- GamePickUpInventoryItem(player, CreateItemActionEntity("LIGHT_BULLET", 0, 0), false)
  -- GamePickUpInventoryItem(player, CreateItemActionEntity("LIGHT_BULLET", 0, 0), false)
  -- GamePickUpInventoryItem(player, CreateItemActionEntity("BOMB", 0, 0), false)
  GamePickUpInventoryItem(player, CreateItemActionEntity("BOMB", 0, 0), false)
  GamePickUpInventoryItem(player, CreateItemActionEntity("DISC_BULLET", 0, 0), false)
  GamePickUpInventoryItem(player, CreateItemActionEntity("POLLEN", 0, 0), false)
  GamePickUpInventoryItem(player, CreateItemActionEntity("GRENADE", 0, 0), false)
  GamePickUpInventoryItem(player, CreateItemActionEntity("GLUE_SHOT", 0, 0), false)
  GamePickUpInventoryItem(player, CreateItemActionEntity("SUMMON_ROCK", 0, 0), false)
  -- GamePickUpInventoryItem(player, CreateItemActionEntity("BOMB", 0, 0), false)
  GamePickUpInventoryItem(player, EntityLoad("data/entities/animals/boss_centipede/sampo.xml"), false)
  if not slots then
    slots = {}
    full_inventory_slots_x, full_inventory_slots_y = get_inventory_size()
    for x=1, full_inventory_slots_x do
      slots[x] = EZInventory.Slot({
        x = origin_x + (x-1) * 20,
        y = origin_y,
        data = {
          slot_number = x,
          move_check = function(self, target_slot)
            -- print("move check slot")
            if self.content.spell.action_id then
              -- Only support storing spells currently
              return not target_slot.content or self:CanStackWith(target_slot) or target_slot.content.stack_size == 1
            else
              return not target_slot.data.is_storage --false
            end
          end
        },
        width = 20,
        height = 20,
      })
      slots[x]:AddEventListener("shift_click", function(self, ev)
        if self.content then
          local free_slot = get_first_free_or_stackable_storage_slot(self)
          if free_slot then
            self:MoveContent(free_slot)
          end
        end
      end)
      slots[x]:AddEventListener("drop_content", drop_content_handler)
      slots[x]:AddEventListener("move_content", function(self, ev)
        if ev.target.data.is_storage then
          EntityKill(ev.content.spell.entity_id)
          ev.content.spell.entity_id = nil
          ev.content.spell.item_comp = nil
          save_stored_spells()
        else
          ComponentSetValue2(ev.content.spell.item_comp, "inventory_slot", ev.target.data.slot_number - 1, ev.content.spell.inv_y)
        end
      end)
    end
    update_slots()

    storage_slots = {}
    for y=1, 3 do
      for x=1, full_inventory_slots_x do
        local slot = EZInventory.Slot({
          x = origin_x + (x-1) * 20,
          y = origin_y + (y-1) * 20 + 40,
          data = {
            is_storage = true,
            slot_number = y * full_inventory_slots_x + x,
            x = x,
            y = y,
            move_check = function(self, target_slot)
              -- print("move check storage slot")
              if target_slot.data.is_storage then
                return true
              else
                if self.content and self.content.stack_size == 1 then
                  return true
                elseif target_slot.content then
                  return false
                else
                  self:SplitContent(target_slot, 1, copy_content)
                  local action_entity = CreateItemActionEntity(target_slot.content.spell.action_id)
                  local item_comp = EntityGetFirstComponentIncludingDisabled(action_entity, "ItemComponent")
                  if item_comp then
                    target_slot.content.spell.entity_id = action_entity
                    target_slot.content.spell.item_comp = item_comp
                    ComponentSetValue2(item_comp, "inventory_slot", target_slot.data.slot_number - 1, target_slot.content.spell.inv_y)
                    ComponentSetValue2(item_comp, "uses_remaining", target_slot.content.spell.uses_remaining)
                  end
                  local spell_inventory = get_spell_inventory()
                  EntityAddChild(spell_inventory, action_entity)
                end
                return false
              end
            end
          },
          width = 20,
          height = 20,
        })
        slot:AddEventListener("shift_click", function(self, ev)
          if self.content then
            local free_slot = get_first_free_inventory_slot()
            if free_slot then
              slot:MoveContent(free_slot)
            end
          end
        end)
        slot:AddEventListener("drop_content", drop_content_handler)
        slot:AddEventListener("move_content", function(self, ev)
          if not ev.target.data.is_storage then
            local action_entity = CreateItemActionEntity(ev.content.spell.action_id)
            local item_comp = EntityGetFirstComponentIncludingDisabled(action_entity, "ItemComponent")
            if item_comp then
              ev.content.spell.entity_id = action_entity
              ev.content.spell.item_comp = item_comp
              ComponentSetValue2(item_comp, "inventory_slot", ev.target.data.slot_number - 1, ev.content.spell.inv_y)
              ComponentSetValue2(item_comp, "uses_remaining", ev.content.spell.uses_remaining)
            end
            local spell_inventory = get_spell_inventory()
            EntityAddChild(spell_inventory, action_entity)
          end
        end)
        storage_slots[(y-1) * full_inventory_slots_x + x] = slot
      end
    end
  end

  for i, slot in ipairs(slots) do
    if slot.content then
      local free_slot = get_first_free_or_stackable_storage_slot(slot)
      if free_slot then
        slot:MoveContent(free_slot)
      end
    end
  end
end

function OnWorldPostUpdate()
  if has_spell_inventory_changed() then
    -- GamePrint("SPELLS CHANGED")
    update_slots()
  end

  local id = 1
  local function new_id()
    id = id + 1
    return id
  end

  gui = gui or GuiCreate()
  GuiStartFrame(gui)

  if GuiButton(gui, new_id(), 0, 180, "Clear") then
    for i, slot in ipairs(slots) do
      slot:ClearContent()
    end
  end

  -- Allow speed clicking
  GuiOptionsAdd(gui, GUI_OPTION.HandleDoubleClickAsClick)
  GuiOptionsAdd(gui, GUI_OPTION.ClickCancelsDoubleClick)

  if GameGetIsGamepadConnected() then
		GuiOptionsAdd(gui, GUI_OPTION.NonInteractive)
	end
	GuiOptionsAdd(gui, GUI_OPTION.NoPositionTween)

	local inventory_open = is_inventory_open()
	-- If button dragging is enabled in the settings and the inventory is not open, make it draggable
	if not inventory_open and not button_locked then
		GuiOptionsAddForNextWidget(gui, GUI_OPTION.IsExtraDraggable)
		GuiOptionsAddForNextWidget(gui, GUI_OPTION.DrawNoHoverAnimation)
		GuiImageButton(gui, 5318008, button_pos_x, button_pos_y, "", "mods/AdvancedSpellInventory/files/gui_button_invisible.png")
		local _, _, hovered, x, y, draw_width, draw_height, draw_x, draw_y = GuiGetPreviousWidgetInfo(gui)
		if draw_x ~= 0 and draw_y ~= 0 and draw_x ~= button_pos_x and draw_y ~= button_pos_y then
			button_pos_x = draw_x - draw_width / 2
			button_pos_y = draw_y - draw_height / 2
		end
	end
	-- Toggle it open/closed
	if not inventory_open and (GuiImageButton(gui, 99999, button_pos_x, button_pos_y, "", "mods/AdvancedSpellInventory/files/gui_button.png")
		or ModIsEnabled("mnee") and get_binding_pressed("AdvSpellInv", "toggle")) then
		open = not open
		GlobalsSetValue("AdvancedSpellInventory_is_open", tostring(open and 1 or 0))
	end

  local player = EntityGetWithTag("player_unit")[1]
  local visible = open and not inventory_open and player
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
    local panel_height = full_inventory_slots_y * slot_height + 4 * slot_height - 2
    -- Container with border
    GuiZSetForNextWidget(gui, 20)
    GuiImageNinePiece(gui, new_id(), origin_x + 1, origin_y + 1, panel_width, panel_height, 1, "mods/AdvancedSpellInventory/files/container_9piece.png", "mods/AdvancedSpellInventory/files/container_9piece.png")
    local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
    -- Block mouse clicks if panel is hovered
    if hovered then
      local mx, my = get_mouse_gui_pos(gui)
      GuiZSetForNextWidget(gui, 0)
      GuiImage(gui, new_id(), mx - 100, my - 100, "data/debug/whitebox.png", 0.0001, 10, 10)
    end
    -- Sort buttons
    local function button(text, active)
      local w, h = GuiGetTextDimensions(gui, text)
      GuiText(gui, 2, 0, "")
      local _, _, _, tx, ty = GuiGetPreviousWidgetInfo(gui)
      GuiImageNinePiece(gui, new_id(), tx - 2, ty, w + 7, h + 2, 0, "data/debug/whitebox.png")
      local clicked, _, hovered = GuiGetPreviousWidgetInfo(gui)
      GuiZSetForNextWidget(gui, 20 - 1)
      GuiImageNinePiece(gui, new_id(), tx, ty, w + 5, h, 1, "data/ui_gfx/decorations/9piece0" .. (not active and "_gray" or "") .. ".png")
      if hovered then
        GuiColorSetForNextWidget(gui, 0.95, 0.95, 0.7, 1)
      end
      GuiText(gui, 1, 0, text)
      GuiText(gui, 4, 0, "")
      return clicked
    end
    GuiLayoutBeginHorizontal(gui, origin_x + 1, origin_y + 24, true)
    -- GuiLayoutBeginHorizontal(gui, origin_x + 4, origin_y + 24, true)
    if button("Sort") then
      local contents = {}
      for i, slot in ipairs(storage_slots) do
        if slot.content then
          table.insert(contents, slot.content)
        end
      end
      for i, slot in ipairs(storage_slots) do
        slot:ClearContent()
      end
      table.sort(contents, function(a, b)
        if sort_order == "ascending" then
          return sorting_function(a, b)
        elseif sort_order == "descending" then
          return sorting_function(b, a)
        end
        error("You misspelled sort_order, stringly typed strikes again")
        return true
      end)
      for i, content in ipairs(contents) do
        storage_slots[i]:SetContent(content)
      end
    end
    if sort_order == "ascending" then
      GuiColorSetForNextWidget(gui, 0, 0.7, 0, 1)
    end
    if GuiImageButton(gui, new_id(), 0, -1, "", "mods/AdvancedSpellInventory/files/arrow_up.png") then
      sort_order = "ascending"
    end
    if sort_order == "descending" then
      GuiColorSetForNextWidget(gui, 0, 0.7, 0, 1)
    end
    if GuiImageButton(gui, new_id(), -9, 7, "", "mods/AdvancedSpellInventory/files/arrow_down.png") then
      sort_order = "descending"
    end
    GuiText(gui, 2, 0, "Sort by:")
    if button("A-Z", sorting_function == sorting_functions.alphabetical) then
      sorting_function = sorting_functions.alphabetical
    end
    if button("Uses remaining", sorting_function == sorting_functions.uses_remaining) then
      sorting_function = sorting_functions.uses_remaining
    end
    GuiLayoutEnd(gui)
	end
end
