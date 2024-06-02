dofile_once("data/scripts/lib/utilities.lua")
local EZWand = dofile_once("mods/AdvancedSpellInventory/lib/EZWand/EZWand.lua")
dofile_once("mods/AdvancedSpellInventory/lib/EZInventory/init.lua")("mods/AdvancedSpellInventory/lib/EZInventory/")
local EZInventory = dofile_once("mods/AdvancedSpellInventory/lib/EZInventory/EZInventory.lua")

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

local button_pos_x = 5
local button_pos_y = 100
local open = false
local button_locked = true

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
        ui_sprite = ("data/ui_gfx/gun_actions/%s.png"):format(action_id:lower()) -- "light_bullet.png" --ComponentGetValue2(item_comp, "ui_sprite")
      end
      table.insert(spells, { entity_id = spell, item_comp = item_comp, action_id = action_id, inv_x = inv_x, inv_y = inv_y, ui_sprite = ui_sprite, uses_remaining = uses_remaining })
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

local slots
local function update_slots()
  for i, slot in ipairs(slots) do
    slot:ClearContent()
  end
  for i, spell in ipairs(get_spells_in_inventory() or {}) do
    local slot = slots[spell.inv_x + 1]
    slot:SetContent({
      sprite = spell.ui_sprite,
      spell = spell,
      render_after = function(gui, new_id, x, y, z, scale)
        GuiZSetForNextWidget(gui, z - 0.5)
        GuiImage(gui, new_id(), x - 2, y - 2, EZWand.get_spell_bg(spell.action_id), 1, 1, 1)
        if spell.uses_remaining >= 0 then
          GuiZSetForNextWidget(gui, z - 2)
          GuiColorSetForNextWidget(gui, 0.8, 0.8, 0.8, 1)
          GuiText(gui, x, y, spell.uses_remaining, 1, "data/fonts/font_small_numbers.xml", true)
        end
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

local origin_x, origin_y =
  tonumber(MagicNumbersGetValue("UI_FULL_INVENTORY_OFFSET_X"))
  + tonumber(MagicNumbersGetValue("UI_BARS_POS_X")),
  tonumber(MagicNumbersGetValue("UI_BARS_POS_Y")) --170, 48 
local full_inventory_slots_x, full_inventory_slots_y
local slot_width, slot_height = 20, 20
local slot_margin = 1
local slot_width_total, slot_height_total = (slot_width + slot_margin * 2), (slot_height + slot_margin * 2)
function OnPlayerSpawned(player)
  GamePickUpInventoryItem(player, CreateItemActionEntity("LIGHT_BULLET", 0, 0), false)
  GamePickUpInventoryItem(player, CreateItemActionEntity("LIGHT_BULLET", 0, 0), false)
  GamePickUpInventoryItem(player, CreateItemActionEntity("LIGHT_BULLET", 0, 0), false)
  GamePickUpInventoryItem(player, CreateItemActionEntity("BOMB", 0, 0), false)
  GamePickUpInventoryItem(player, CreateItemActionEntity("BOMB", 0, 0), false)
  GamePickUpInventoryItem(player, CreateItemActionEntity("BOMB", 0, 0), false)
  if not slots then
    slots = {}
    full_inventory_slots_x, full_inventory_slots_y = get_inventory_size()
    for x=1, full_inventory_slots_x do
      slots[x] = EZInventory.Slot({
        x = origin_x + (x-1) * 20,
        y = origin_y,
        data = { slot_number = x },
        width = 20,
        height = 20,
      })
      slots[x]:AddEventListener("move_content", function(self, ev)
        if ev.target.data.is_storage then
          EntityKill(ev.content.spell.entity_id)
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
          y = origin_y + (y-1) * 20 + 60,
          data = { is_storage = true, slot_number = y * full_inventory_slots_x + x, x = x, y = y },
          width = 20,
          height = 20,
        })
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
end

function OnWorldPostUpdate()
  if has_spell_inventory_changed() then
    GamePrint("SPELLS CHANGED")
    update_slots()
  end
  local frame_num = GameGetFrameNum()
  local id = 1
  local function new_id()
    id = id + 1
    return id
  end

  gui = gui or GuiCreate()
  GuiStartFrame(gui)

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
	if not inventory_open and (GuiImageButton(gui, new_id(), button_pos_x, button_pos_y, "", "mods/AdvancedSpellInventory/files/gui_button.png")
		or ModIsEnabled("mnee") and get_binding_pressed("AdvSpellInv", "toggle")) then
		open = not open
		GlobalsSetValue("AdvancedSpellInventory_is_open", tostring(open and 1 or 0))
	end

	if open and not inventory_open then
    local title_text = GameTextGetTranslatedOrNot("$hud_title_actionstorage")
    local text_w, text_h = GuiGetTextDimensions(gui, title_text)
    GuiZSetForNextWidget(gui, 20)
    GuiText(gui, origin_x, origin_y - 2 - text_h, title_text)
    GuiZSetForNextWidget(gui, 21)
    GuiColorSetForNextWidget(gui, 0, 0, 0, 1)
    GuiText(gui, origin_x, origin_y - 2 - text_h + 1, title_text)
    local panel_width = full_inventory_slots_x * slot_width - 2
    local panel_height = full_inventory_slots_y * slot_height + 5 * slot_height - 2
    GuiZSetForNextWidget(gui, 20)
    GuiImageNinePiece(gui, new_id(), origin_x + 1, origin_y + 1, panel_width, panel_height, 1, "mods/AdvancedSpellInventory/files/container_9piece.png", "mods/AdvancedSpellInventory/files/container_9piece.png")
    local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)

    -- Block mouse clicks if panel is hovered
    if hovered then
      local mx, my = get_mouse_gui_pos(gui)
      GuiZSetForNextWidget(gui, 0)
      GuiImage(gui, new_id(), mx - 100, my - 100, "data/debug/whitebox.png", 0.0001, 10, 10)
    end

    -- GuiOptionsAdd(gui, GUI_OPTION.DrawNoHoverAnimation)

    EZInventory.Update(gui)

    for i, slot in ipairs(slots) do
      if slot.hovered and not slot.dragging and slot.content then
        EZWand.RenderSpellTooltip(slot.content.spell.action_id, slot.x + 2, slot.y + slot_height, gui)
      end
    end

    for i, slot in ipairs(storage_slots) do
      if slot.hovered and not slot.dragging and slot.content then
        EZWand.RenderSpellTooltip(slot.content.spell.action_id, slot.x + 2, slot.y + slot_height, gui)
      end
    end

    -- GuiAnimateBegin(gui)
    -- GuiIdPushString(gui, "tooltip_animation")
    -- GuiAnimateScaleIn(gui, 1, 0.08, false)
    -- GuiAnimateAlphaFadeIn(gui, 2, 0.15, 0.15, false)
    -- EZWand.RenderSpellTooltip(spell.action_id, x + 2, y + slot_height, gui)
    -- GuiIdPop(gui)
    -- GuiAnimateEnd(gui)
	end
end
