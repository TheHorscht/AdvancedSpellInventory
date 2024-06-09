dofile_once("data/scripts/lib/utilities.lua")
dofile_once("data/scripts/debug/keycodes.lua")
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
local origin_x, origin_y =
  tonumber(MagicNumbersGetValue("UI_FULL_INVENTORY_OFFSET_X"))
  + tonumber(MagicNumbersGetValue("UI_BARS_POS_X")),
  tonumber(MagicNumbersGetValue("UI_BARS_POS_Y")) --170, 48 
local full_inventory_slots_x, full_inventory_slots_y
local slot_width, slot_height = 20, 20
local slot_margin = 1
local slot_width_total, slot_height_total = (slot_width + slot_margin * 2), (slot_height + slot_margin * 2)

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
    stackable_with = content.stackable_with
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
  for i, slot in ipairs(slots) do
    slot:ClearContent()
  end
  for i, spell in ipairs(get_spells_in_inventory() or {}) do
    local slot = slots[spell.inv_x + 1]
    slot:SetContent({
      sprite = spell.ui_sprite,
      spell = spell,
      stack_size = 1,
      max_stack_size = 200,
      stackable_with = function(a, b)
        return a.spell.action_id == b.spell.action_id
      end,
      render_after = function(self, gui, new_id, x, y, z, scale)
        GuiZSetForNextWidget(gui, z - 0.5)
        GuiImage(gui, new_id(), x - 2, y - 2, EZWand.get_spell_bg(self.content.spell.action_id), 1, 1, 1)
        if self.content.spell.uses_remaining >= 0 then
          GuiZSetForNextWidget(gui, z - 2)
          GuiColorSetForNextWidget(gui, 0.8, 0.8, 0.8, 1)
          GuiText(gui, x, y, self.content.spell.uses_remaining, 1, "data/fonts/font_small_numbers.xml", true)
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

function OnPlayerSpawned(player)
  GamePickUpInventoryItem(player, CreateItemActionEntity("LIGHT_BULLET", 0, 0), false)
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
      -- slots[x]:AddEventListener("set_content", function(self, ev)
      --   GamePrint("Setting Content!")
      -- end)
      slots[x]:AddEventListener("move_content", function(self, ev)
        print("MOVEEEEEEEEEE CONTENTTTTTTTTTT") -- cehck if this trigger when stacking
        if ev.target.data.is_storage then
          -- self.content contains the targets content IF it had one and was swapped here
          EntityKill(ev.content.spell.entity_id)
        else
          ComponentSetValue2(ev.content.spell.item_comp, "inventory_slot", ev.target.data.slot_number - 1, ev.content.spell.inv_y)
        end
        -- if ev.target.data.is_storage then
        --   -- self.content contains the targets content IF it had one and was swapped here
        --   -- Merge stacks if same spell
        --   if ev.content and self.content and (ev.content.spell.action_id == self.content.spell.action_id) then
        --     ev.content.spell.stack_size = ev.content.spell.stack_size + self.content.spell.stack_size
        --     self:ClearContent()
        --   end
        --   print('ev.content.spell.entity_id (' .. tostring(ev.content.spell.entity_id) .. ':'.. type(ev.content.spell.entity_id) .. ')')
        --   EntityKill(ev.content.spell.entity_id)
        -- else
        --   ComponentSetValue2(ev.content.spell.item_comp, "inventory_slot", ev.target.data.slot_number - 1, ev.content.spell.inv_y)
        -- end
      end)
    end
    update_slots()

    storage_slots = {}
    for y=1, 3 do
      for x=1, full_inventory_slots_x do
        local slot = EZInventory.Slot({
          x = origin_x + (x-1) * 20,
          y = origin_y + (y-1) * 20 + 60,
          data = { is_storage = true, slot_number = y * full_inventory_slots_x + x, x = x, y = y,
            callback = function(self, target_slot)
              if target_slot.data.is_storage then
                return true
              else
                -- local content_copy = copy_content(self.content)
                -- content_copy.stack_size = 1
                -- self.content.stack_size = self.content.stack_size - 1
                -- if self.content.stack_size <= 0 then
                --   self:ClearContent()
                -- end
                -- target_slot:SetContent(content_copy)
                if self.content.stack_size == 1 then
                  self:MoveContent(target_slot, true)
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
              -- return target_slot.data.is_storage
            end
          },
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
          -- if not ev.target.data.is_storage then
          --   if ev.target.content.stack_size > 1 then
          --     -- Move it back and split
          --     ev.target:MoveContent(self)
          --     self:SplitContent(ev.target, 1, function(content)
          --       return {
          --         sprite = content.sprite,
          --         spell = content.spell,
          --         max_stack_size = content.max_stack_size,
          --         stackable_with = content.stackable_with,
          --         render_after = content.render_after
          --       }
          --     end)
          --   end
          -- end
          -- if not ev.target.data.is_storage then
          --   local action_entity = CreateItemActionEntity(ev.content.spell.action_id)
          --   local item_comp = EntityGetFirstComponentIncludingDisabled(action_entity, "ItemComponent")
          --   if item_comp then
          --     ev.content.spell.entity_id = action_entity
          --     ev.content.spell.item_comp = item_comp
          --     ComponentSetValue2(item_comp, "inventory_slot", ev.target.data.slot_number - 1, ev.content.spell.inv_y)
          --     ComponentSetValue2(item_comp, "uses_remaining", ev.content.spell.uses_remaining)
          --   end
          --   local spell_inventory = get_spell_inventory()
          --   EntityAddChild(spell_inventory, action_entity)
          --   if ev.content.spell.stack_size > 1 then
          --     ev.content.spell.stack_size = ev.content.spell.stack_size - 1
          --     local copy = copy_content(ev.content)
          --     self:SetContent(copy)
          --   end
          -- else
          --   -- Merge stacks if same spell
          --   if ev.content and self.content and (ev.content.spell.action_id == self.content.spell.action_id) then
          --     ev.content.spell.stack_size = ev.content.spell.stack_size + self.content.spell.stack_size
          --     self:ClearContent()
          --   end
          -- end
        end)
        storage_slots[(y-1) * full_inventory_slots_x + x] = slot
      end
    end
  end

  local ent = EntityCreateNew()
  EntityAddComponent2(ent, "LifetimeComponent", {
    lifetime = 600
  })
  EntityAddComponent2(ent, "UIIconComponent", {
    icon_sprite_file="data/debug/circle_16.png",
    name="Heatstrokey",
    description="You don't feel so goody...",
    display_above_head=true,
    display_in_hud=true,
    is_perk=false
  })
  EntityAddChild(player, ent)
end

local function set_slots_enabled(enabled)
  for i, slot in ipairs(slots) do
    slot.enabled = enabled
  end
  for i, slot in ipairs(storage_slots) do
    slot.enabled = enabled
  end
end

local EZMouse = dofile("mods/AdvancedSpellInventory/lib/EZInventory/lib/EZMouse/EZMouse.lua")("mods/AdvancedSpellInventory/lib/EZInventory/lib/EZMouse/")
function OnWorldPostUpdate()
  if has_spell_inventory_changed() then
    GamePrint("SPELLS CHANGED")
    update_slots()
  end
  -- if InputIsKeyJustDown(Key_LSHIFT) then
  --   set_slots_enabled(false)
  -- elseif InputIsKeyJustUp(Key_LSHIFT) then
  --   set_slots_enabled(true)
  -- end

  local frame_num = GameGetFrameNum()
  local id = 1
  local function new_id()
    id = id + 1
    return id
  end

  gui = gui or GuiCreate()
  GuiStartFrame(gui)

  -- if not EZMouse then
  --   EZMouse = dofile_once("mods/AdvancedSpellInventory/lib/EZInventory/lib/EZMouse/EZMouse.lua")("mods/AdvancedSpellInventory/lib/EZInventory/lib/EZMouse/")
  -- end
  if not widget then
    widget = EZMouse.Widget({
      x = 20,
      y = 150,
      z = 1,
      width = 50,
      height = 50,
      draggable = true,
      enabled = true,
      resizable = true,
      resize_granularity = 2,
      -- resize_symmetrical = true,
      drag_anchor = "center",
      constraints = { left = 0, top = 0, right = 999, bottom = 999 } -- TODO: Fill constraints with screen width and height
    })
    widget:AddEventListener("drag_end", function (self, ev)
      self.x = ev.start_x
      self.y = ev.start_y
    end)
    -- widget2 = EZMouse.Widget({
    --   x = 50,
    --   y = 120,
    --   z = 1,
    --   width = 50,
    --   height = 50,
    --   draggable = true,
    --   enabled = true,
    --   resizable = true,
    --   resize_granularity = 2,
    --   -- resize_symmetrical = true,
    --   drag_anchor = "center",
    --   constraints = { left = 0, top = 0, right = 999, bottom = 999 } -- TODO: Fill constraints with screen width and height
    -- })
  end
  widget:DebugDraw(gui)
  -- widget2:DebugDraw(gui)
  EZMouse.update(gui)
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
    -- for i, slot in ipairs(slots) do
    --   slot.draggable = open
    -- end
    -- for i, slot in ipairs(storage_slots) do
    --   slot.draggable = open
    -- end
    if not open then
      -- GuiDestroy(gui)
      -- gui = GuiCreate()
    end
		GlobalsSetValue("AdvancedSpellInventory_is_open", tostring(open and 1 or 0))
	end

  local visible = open and not inventory_open
  local dragging_enabled = not InputIsKeyDown(Key_LSHIFT)
  EZInventory.Update(gui, visible, dragging_enabled)
	if visible then
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

    for i, slot in ipairs(slots) do
      if slot.hovered and not slot.dragging and slot.content then
        -- EZWand.RenderSpellTooltip(slot.content.spell.action_id, slot.x + 2, slot.y + slot_height, gui)
        if InputIsKeyDown(Key_LSHIFT) and InputIsMouseButtonJustDown(Mouse_left) then
          local free_slot = get_first_free_or_stackable_storage_slot(slot)
          if free_slot then
            slot:MoveContent(free_slot)
          end
        end
      end
    end

    for i, slot in ipairs(storage_slots) do
      if slot.hovered and not slot.dragging and slot.content then
        -- EZWand.RenderSpellTooltip(slot.content.spell.action_id, slot.x + 2, slot.y + slot_height, gui)
        if InputIsKeyDown(Key_LSHIFT) and InputIsMouseButtonJustDown(Mouse_left) then
          local free_slot = get_first_free_inventory_slot()
          if free_slot then
            slot:MoveContent(free_slot)
            -- if (slot.content.stack_size or 1) == 1 then
            --   slot:MoveContent(free_slot)
            -- else
            --   slot:SplitContent(free_slot, 1, function(content)
            --     return {
            --       sprite = content.sprite,
            --       spell = content.spell,
            --       max_stack_size = content.max_stack_size,
            --       stackable_with = content.stackable_with,
            --       render_after = content.render_after
            --     }
            --   end)
            -- end
          end
        end
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
