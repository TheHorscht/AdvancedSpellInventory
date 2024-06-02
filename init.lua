dofile_once("data/scripts/lib/utilities.lua")
local EZWand = dofile_once("mods/AdvancedSpellInventory/lib/EZWand/EZWand.lua")
dofile_once("mods/AdvancedSpellInventory/lib/EZInventory/init.lua")("mods/AdvancedSpellInventory/lib/EZInventory/")
local EZInventory = dofile_once("mods/AdvancedSpellInventory/lib/EZInventory/EZInventory.lua")

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
  local player = EntityGetWithTag("player_unit")[1]
  if player then
    for i, child in ipairs(EntityGetAllChildren(player) or {}) do
      if EntityGetName(child) == "inventory_full" then
        for i, spell in ipairs(EntityGetAllChildren(child) or {}) do
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
          table.insert(spells, { action_id = action_id, inv_x = inv_x, inv_y = inv_y, ui_sprite = ui_sprite, uses_remaining = uses_remaining })
        end
        break
      end
    end
    -- if inventory_2_comp and item_comp then
    --   local x, y = ComponentGetValue2(item_comp, "inventory_slot")
    --   ComponentSetValue2(item_comp, "inventory_slot", (x + 1) % 5, y)
    -- end
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
  for i, spell in ipairs(get_spells_in_inventory() or {}) do
    slots[spell.inv_x + 1]:SetContent({
      sprite = spell.ui_sprite,
      spell = spell
    })
  end
end

local origin_x, origin_y = 170, 48
local full_inventory_slots_x, full_inventory_slots_y
local slot_width, slot_height = 20, 20
local slot_margin = 1
local slot_width_total, slot_height_total = (slot_width + slot_margin * 2), (slot_height + slot_margin * 2)
function OnPlayerSpawned(player)
  GamePickUpInventoryItem(player, CreateItemActionEntity("LIGHT_BULLET", 0, 0), false)
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
      slots[x]:AddEventListener("move_content", function(content, target)

      end)
    end
    update_slots()
  end
end

function OnWorldPostUpdate()
  local frame_num = GameGetFrameNum()
  local id = 1
  local function new_id()
    id = id + 1
    return id
  end

  gui = gui or GuiCreate()
  GuiStartFrame(gui)

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
		-- local spacer = 4
		-- local held_wands = get_held_wands()
		-- local stored_wands = get_stored_wands(active_wand_tab)
		-- local held_items = get_held_items()
		-- local stored_items = get_stored_items(active_item_tab)
		-- local rows_wands = math.max(4, math.ceil((#stored_wands + 1) / 4))
		-- local rows_items = math.max(4, math.ceil((#stored_items + 1) / 4))
		-- local box_width = slot_width_total * 4
		-- local box_height_wands = slot_height_total * (rows_wands+1) + spacer
		-- local box_height_items = slot_height_total * (rows_items+1) + spacer
		-- Render wand bag
    GuiZSetForNextWidget(gui, 20)
    GuiImageNinePiece(gui, new_id(), origin_x, origin_y, full_inventory_slots_x * slot_width, 200, 1, "mods/AdvancedSpellInventory/files/container_9piece.png", "mods/AdvancedSpellInventory/files/container_9piece.png")
    local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)

    -- Block mouse clicks if panel is hovered
    if hovered then
      local mx, my = get_mouse_gui_pos(gui)
      GuiZSetForNextWidget(gui, 0)
      GuiImage(gui, new_id(), mx - 100, my - 100, "data/debug/whitebox.png", 0.0001, 10, 10)
    end

    GuiOptionsAdd(gui, GUI_OPTION.DrawNoHoverAnimation)

    EZInventory.Update(gui)

    -- for i, slot in ipairs(slots) do
    --   GuiZSetForNextWidget(gui, 15)
    --   GuiImage(gui, new_id(), slot.x, slot.y, "data/ui_gfx/inventory/quick_inventory_box.png", 1, 1, 1)
    -- end




    -- if full_inventory_slots_x then
    --   for y=1, full_inventory_slots_y do
    --     for x=1, full_inventory_slots_x do
    --       GuiZSetForNextWidget(gui, 15)
    --       GuiImage(gui, new_id(), origin_x + slot_width * (x-1), origin_y + slot_height * (y-1), "data/ui_gfx/inventory/quick_inventory_box.png", 1, 1, 1)
    --     end
    --   end
    -- end

    for i, slot in ipairs(slots) do
      if slot.hovered and not slot.dragging and slot.content then
        -- print('slot.content (' .. tostring(slot.content) .. ':'.. type(slot.content) .. ')')
        -- print('slot.content.spell (' .. tostring(slot.content.spell) .. ':'.. type(slot.content.spell) .. ')')
        -- print('slot.content.spell.action_id (' .. tostring(slot.content.spell.action_id) .. ':'.. type(slot.content.spell.action_id) .. ')')
        EZWand.RenderSpellTooltip(slot.content.spell.action_id, slot.x + 2, slot.y + slot_height, gui)
      end
    end

    -- for i, spell in ipairs(get_spells_in_inventory() or {}) do
      -- GuiZSetForNextWidget(gui, 14.5)
      -- GuiImage(gui, new_id(), origin_x + slot_width * (i-1), origin_y, EZWand.get_spell_bg(spell.action_id), 1, 1, 1)
      -- if spell.uses_remaining >= 0 then
      --   GuiZSetForNextWidget(gui, 13.9)
      --   GuiText(gui, origin_x + slot_width * (i-1) + 2, origin_y + 2, spell.uses_remaining, 1, "data/fonts/font_small_numbers.xml", true)
      -- end
      -- GuiZSetForNextWidget(gui, 14)
      -- if GuiImageButton(gui, new_id(), origin_x + slot_width * (i-1) + 2, origin_y + 2, "", spell.ui_sprite) then
      --   GamePrint("boob")
      -- end
      -- local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
      -- Show tooltip on hover
      -- if hovered then
        -- GuiAnimateBegin(gui)
        -- GuiIdPushString(gui, "tooltip_animation")
        -- GuiAnimateScaleIn(gui, 1, 0.08, false)
        -- GuiAnimateAlphaFadeIn(gui, 2, 0.15, 0.15, false)
        -- EZWand.RenderSpellTooltip(spell.action_id, x + 2, y + slot_height, gui)
        -- GuiIdPop(gui)
        -- GuiAnimateEnd(gui)
      -- end
    -- end

    -- GuiImage(gui, new_id(), origin_x - 4, origin_y - 4 + offset_y, "mods/AdvancedSpellInventory/files/invisible_80x10.png", 1, 1, 1)

    -- local taken_slots = {}
    -- Render the held wands and save the taken positions so we can render the empty slots after this
    -- for i, wand in ipairs(held_wands) do
    -- 	if wand then
    -- 		taken_slots[wand.inventory_slot] = true
    -- 		local left_clicked, right_clicked = GuiImageButton(gui, new_id(), origin_x + slot_margin + wand.inventory_slot * slot_width_total, origin_y + slot_margin, "", "data/ui_gfx/inventory/inventory_box.png")
    -- 		if left_clicked and wand_bag_has_space() then
    -- 			async(function()
    -- 				put_wand_in_storage(wand.entity_id, active_wand_tab)
    -- 			end)
    -- 		elseif right_clicked then
    -- 			async(function()
    -- 				take_out_wand_and_place_it_next_to_player(wand.entity_id)
    -- 			end)
    -- 		end
    -- 		local _, _, hovered, x, y, width, height = GuiGetPreviousWidgetInfo(gui)
    -- 		local w, h = GuiGetImageDimensions(gui, wand.image_file, 1) -- scale
    -- 		local scale = hovered and 1.2 or 1
    -- 		if hovered then
    -- 			tooltip_wand = EZWand.Deserialize(EZWand(wand.entity_id):Serialize()) --wand.entity_id
    -- 		end
    -- 		GuiZSetForNextWidget(gui, -9)
    -- 		if wand.active then
    -- 			GuiImage(gui, new_id(), x + (width / 2 - (16 * scale) / 2), y + (height / 2 - (16 * scale) / 2), "mods/InventoryBags/files/highlight_box.png", 1, scale, scale)
    -- 		end
    -- 		GuiZSetForNextWidget(gui, -10)
    -- 		GuiImage(gui, new_id(), x + (width / 2 - (w * scale) / 2), y + (height / 2 - (h * scale) / 2), wand.image_file, 1, scale, scale, 0, GUI_RECT_ANIMATION_PLAYBACK.Loop)
    -- 	end
    -- end
    -- for i=0, (4-1) do
    -- 	if not taken_slots[i] then
    -- 		GuiImage(gui, new_id(), origin_x + slot_margin + i * slot_width_total, origin_y + slot_margin, "data/ui_gfx/inventory/inventory_box.png", 1, 1, 1)
    -- 	end
    -- end
    -- for iy=0, (rows_wands-1) do
    -- 	for ix=0, (4-1) do
    -- 		local idx = (iy*4 + ix) + 1
    -- 		local wand = stored_wands[(iy*4 + ix) + 1]
    -- 		if wand then
    -- 			local left_clicked, right_clicked = GuiImageButton(gui, new_id(), origin_x + slot_margin + ix * slot_width_total, origin_y + spacer + slot_margin + slot_height_total + iy * slot_height_total, "", "data/ui_gfx/inventory/inventory_box.png")
    -- 			if left_clicked then
    -- 				async(function()
    -- 					retrieve_or_swap_wand(wand, active_wand_tab)
    -- 				end)
    -- 			elseif right_clicked then
    -- 				async(function()
    -- 					take_out_wand_and_place_it_next_to_player(wand)
    -- 				end)
    -- 			end
    -- 			local _, _, hovered, x, y, width, height = GuiGetPreviousWidgetInfo(gui)
    -- 			local w, h = GuiGetImageDimensions(gui, wand.sprite_image_file, 1) -- scale
    -- 			local scale = hovered and 1.2 or 1
    -- 			if hovered then
    -- 				tooltip_wand = wand
    -- 			end
    -- 			GuiZSetForNextWidget(gui, -10)
    -- 			GuiImage(gui, new_id(), x + (width / 2 - (w * scale) / 2), y + (height / 2 - (h *scale) / 2), wand.sprite_image_file, 1, scale, scale, 0, GUI_RECT_ANIMATION_PLAYBACK.Loop)
    -- 		else
    -- 			if idx > bags_wand_capacity then
    -- 				GuiColorSetForNextWidget(gui, 0.8, 0.8, 0.8, 1)
    -- 			end
    -- 			GuiImage(gui, new_id(), origin_x + slot_margin + ix * slot_width_total, origin_y + spacer + slot_margin + slot_height_total + iy * slot_height_total, "data/ui_gfx/inventory/inventory_box.png", 1, 1, 1)
    -- 		end
    -- 	end
    -- end
	end


  -- if GuiButton(gui, new_id(), 0, 200, "Inventorymove") then
  --   local player = EntityGetWithTag("player_unit")[1]
  --   if player then
  --     local inventory_2_comp = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
  --     if not item_comp then
  --       for i, child in ipairs(EntityGetAllChildren(player) or {}) do
  --         if EntityGetName(child) == "inventory_full" then
  --           item_comp = EntityGetFirstComponentIncludingDisabled(EntityGetAllChildren(child)[1], "ItemComponent")
  --           break
  --         end
  --       end
  --     end
  --     if inventory_2_comp and item_comp then
  --       local x, y = ComponentGetValue2(item_comp, "inventory_slot")
  --       ComponentSetValue2(item_comp, "inventory_slot", (x + 1) % 5, y)
  --     end
  --   end
  -- end
end
