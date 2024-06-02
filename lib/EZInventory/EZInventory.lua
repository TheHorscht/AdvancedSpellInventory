local EZMouse = dofile_once("%PATH%lib/EZMouse/EZMouse.lua")("%PATH%lib/EZMouse/")

local function is_inside_rect(x, y, rect_x, rect_y, width, height)
	return not ((x < rect_x) or (x > rect_x + width) or (y < rect_y) or (y > rect_y + height))
end

local function get_direction( x1, y1, x2, y2 )
	return math.atan2( ( y2 - y1 ), ( x2 - x1 ) )
end

local function get_distance( x1, y1, x2, y2 )
	local result = math.sqrt( ( x2 - x1 ) ^ 2 + ( y2 - y1 ) ^ 2 )
	return result
end

local slot_instances = {}
-- The privates should be read-only from outside
local slot_privates = setmetatable({}, { __mode = "k" })
-- This is indexed by content
local widgets = setmetatable({}, { __mode = "k" })
local extra_info = {}
local widget_extra_info = setmetatable({}, { __mode = "k" })

local Slot__mt = {}
Slot__mt.__index = Slot__mt

local function slot_is_hovered(slot)
  return is_inside_rect(EZMouse.screen_x, EZMouse.screen_y, slot.x, slot.y, slot.width, slot.height)
end

local function fire_event(slot, event_name, event_args)
  for i, listener in ipairs(slot_privates[slot].event_listeners[event_name]) do
    listener(slot, event_args)
  end
end

local EZInventory_GUI = GuiCreate()
local function update()
  if GameGetFrameNum() <= 10 then
    return
  end
  GuiStartFrame(EZInventory_GUI)
  EZMouse.update(EZInventory_GUI)
  local id = 1
  local function new_id()
    id = id + 1
    return id
  end

  content_being_dragged = nil
  for i, slot in ipairs(slot_instances) do
    -- if widgets[slot_privates[slot].content] then
    --   widgets[slot_privates[slot].content]:DebugDraw(EZInventory_GUI)
    -- end
    slot_privates[slot].content_cleared_this_frame = false
    slot.hovered = widgets[slot_privates[slot].content] and widgets[slot_privates[slot].content].hovered or false
    slot.dragging = widgets[slot_privates[slot].content] and widgets[slot_privates[slot].content].dragging or false
    if slot_privates[slot].content and widgets[slot_privates[slot].content].dragging then
      content_being_dragged = slot_privates[slot].content
    end
  end
  -- Do custom PositionTween when letting go of item and it snaps back
  for slot, values in pairs(extra_info) do
    local dir = get_direction(values.target_x, values.target_y, values.x, values.y)
    local dist = get_distance(values.target_x, values.target_y, values.x, values.y)
    values.x = values.x - math.cos(dir) * math.min(dist * 0.5, 60)
    values.y = values.y - math.sin(dir) * math.min(dist * 0.5, 60)
    if dist < 1 then
      values.x = values.target_x
      values.y = values.target_y
      extra_info[slot] = nil
    end
  end
  for i, slot in ipairs(slot_instances) do
    slot:Render(EZInventory_GUI, new_id)
  end
end

function Slot__mt:Destroy()
  if widgets[slot_privates[self].content] then
    widgets[slot_privates[self].content]:Destroy()
    widgets[slot_privates[self].content] = nil
  end
  for i=#slot_instances, 1, -1 do
    if slot_instances[i] == self then
      table.remove(slot_instances, i)
    end
  end
end

function Slot__mt:AddEventListener(event_name, event_listener)
  if not slot_privates[self].event_listeners[event_name] then
    error("Event with name '" .. event_name .. "' doesn't exist.", 2)
  end
  table.insert(slot_privates[self].event_listeners[event_name], event_listener)
  return event_listener
end

function Slot__mt:RemoveEventListener(event_name, event_listener)
  if not slot_privates[self].event_listeners[event_name] then
    error("Event with name '" .. event_name .. "' doesn't exist.", 2)
  end
  local was_removed = false
  for i=#slot_privates[self].event_listeners[event_name], 1, -1 do
    if slot_privates[self].event_listeners[event_name][i] == event_listener then
      table.remove(slot_privates[self].event_listeners[event_name], i)
      was_removed = true
      break
    end
  end
  return was_removed
end

function Slot__mt:Render(gui, new_id)
  if slot_privates[self].content then
    local scale = self.width / 20
    local sprite_w, sprite_h = GuiGetImageDimensions(gui, slot_privates[self].content.sprite)
    local offset_x, offset_y = 2 * scale, 2 * scale --  (difference between sprite_size and slot_size) / 2
    -- Offset content sprite if it's being dragged
    if widgets[slot_privates[self].content].dragging then
      offset_x, offset_y = self.width / 2, self.height / 2
    end
    -- Make content sprite slightly bigger when it's being hovered
    if widgets[slot_privates[self].content].hovered and not widgets[slot_privates[self].content].dragging then
      scale = scale * 1.2
      offset_x = offset_x - 1.5 * scale
      offset_y = offset_y - 1.5 * scale
      if slot_privates[self].content.tooltip_func then
        GuiIdPushString(gui, "EZInventory_tooltip")
        slot_privates[self].content.tooltip_func(gui, self.x, self.y + self.height + 10, self.z - 2000, slot_privates[self].content)
        GuiIdPop(gui)
      end
    end
    local x = widgets[slot_privates[self].content].x
    local y = widgets[slot_privates[self].content].y
    if extra_info[self] then
      x = extra_info[self].x
      y = extra_info[self].y
    end
    -- If it's being dragged, render it on top of all the other contents
    local z = self.z - 1
    if widgets[slot_privates[self].content].dragging then
      z = z - 500
    end
    GuiZSetForNextWidget(gui, z)
    GuiImage(gui, new_id(), x + offset_x, y + offset_y, slot_privates[self].content.sprite, 1, scale, scale)
    if slot_privates[self].content.render_after then
      slot_privates[self].content.render_after(gui, new_id, x + offset_x, y + offset_y, z, scale)
    end
    -- widgets[slot_privates[self].content]:DebugDraw(gui)
  end
  local background_sprite = slot_privates[self].background_sprite
  -- Highlight slot if something is being dragged and the slot being hovered does not contain an item, or it's the same slot the item is being dragged from
  if content_being_dragged and slot_is_hovered(self) and (not slot_privates[self].content or (slot_privates[self].content == content_being_dragged)) then
    background_sprite = slot_privates[self].background_sprite_highlight
  end
  GuiZSetForNextWidget(gui, self.z)
  local scale = self.width / 20
  GuiImage(gui, new_id(), self.x, self.y, background_sprite, 1, scale, scale)
end

function Slot__mt:ClearContent()
  widgets[slot_privates[self].content]:Destroy()
  widgets[slot_privates[self].content] = nil
  slot_privates[self].content = nil
  slot_privates[self].content_cleared_this_frame = true
end

-- Moves content from one slot to another, if the other slot is occupied, swaps contents
function Slot__mt:MoveContent(target_slot)
  -- print(("MoveContent (%s[%s] -> %s[%s])"):format(self.z, slot_privates[self].content, target_slot.z, slot_privates[target_slot].content))
  if not slot_privates[self].content then
    error("Can't move content, source slot is empty.", 2)
  end
  -- First save our content, then clear current slots content,
  -- move that into the other content and if that slot already has content, move that into this one
  local temp_content = slot_privates[self].content
  slot_privates[self].content = nil
  if slot_privates[target_slot].content then
    target_slot:MoveContent(self)
  end
  extra_info[target_slot] = {
    target_x = target_slot.x,
    target_y = target_slot.y,
    x = widgets[temp_content].x + self.width / 2,
    y = widgets[temp_content].y + self.width / 2,
  }
  target_slot:SetContent(temp_content, true)
  fire_event(self, "move_content", { content = temp_content, target = target_slot })
end

function Slot__mt:__index(key)
  if key == "content" then
    return slot_privates[self][key]
  else
    -- local x = rawget(self, key)
    -- print('key (' .. tostring(key) .. ':'.. type(key) .. ')')
    -- print('x (' .. tostring(x) .. ':'.. type(x) .. ')')
    return Slot__mt[key] or rawget(self, key)
  end
end

function Slot__mt:SetContent(content, dont_fire_event)
  -- print(("SetContent %s -> %s"):format(self.z, content))
  if type(content) ~= "table" then
    error("Content cannot be empty, to clear the content use ClearContent instead", 2)
  end
  slot_privates[self].content = content
  local function drag_start_handler(widget, event)
    extra_info[self] = nil
  end
  local function drag_end_handler(widget, event)
    -- Check if we're moving it onto another slot
    local was_moved_to_another_slot = false
    local was_moved_to_self = false
    for i, target_slot in ipairs(slot_instances) do
      if slot_is_hovered(target_slot) then
        if target_slot ~= self then
          self:MoveContent(target_slot)
          was_moved_to_another_slot = true
        else
          was_moved_to_self = true
        end
        break
      end
    end
    -- If it wasn't dropped onto another slot, make it tween back to its original place
    if not was_moved_to_another_slot or was_moved_to_self then
      extra_info[self] = {
        target_x = event.start_x,
        target_y = event.start_y,
        x = widget.x + self.width / 2,
        y = widget.y + self.width / 2,
      }
      widget.x = event.start_x
      widget.y = event.start_y
      if not was_moved_to_self then
        fire_event(self, "drop_content", { content = content })
        if slot_privates[self].content_cleared_this_frame then
          return
        end
      end
    end
  end
  if not widgets[content] then
    widgets[content] = EZMouse.Widget({
      x = self.x,
      y = self.y,
      z = self.z - 1000,
      width = self.width,
      height = self.height,
      draggable = true,
      enabled = true,
      drag_anchor = "center",
      constraints = { left = 0, top = 0, right = 999, bottom = 999 } -- TODO: Fill constraints with screen width and height
    })
  else
    widgets[content].x = self.x
    widgets[content].y = self.y
    widgets[content].z = self.z
  end
  widget_extra_info[content] = widget_extra_info[content] or {}
  if widget_extra_info[content].drag_start_handler then
    widgets[content]:RemoveEventListener("drag_start", widget_extra_info[content].drag_start_handler)
  end
  if widget_extra_info[content].drag_end_handler then
    widgets[content]:RemoveEventListener("drag_end", widget_extra_info[content].drag_end_handler)
  end
  widgets[content]:AddEventListener("drag_start", drag_start_handler)
  widgets[content]:AddEventListener("drag_end", drag_end_handler)
  widget_extra_info[content].drag_start_handler = drag_start_handler
  widget_extra_info[content].drag_end_handler = drag_end_handler
  -- slot_privates[self].event_listeners[event_name]
  if not dont_fire_event then
    fire_event(self, "set_content", { content = content })
  end
end

local function new_slot(props)
  local o = setmetatable({
    x = props.x,
    y = props.y,
    z = props.z or 1,
    data = props.data, -- Should contain static data like slot_number or slot type like "Headgear" or whatever
    width = props.width,
    height = props.height
  }, Slot__mt)
  slot_privates[o] = {
    background_sprite = "data/ui_gfx/inventory/full_inventory_box.png",
    background_sprite_highlight = "data/ui_gfx/inventory/full_inventory_box_highlight.png",
    event_listeners = {
      set_content = {}, -- Gets called once the content has been set
      move_content = {}, -- Gets called on the slot it was moved FROM, once the content has been moved to another slot
      drop_content = {}, -- Gets called when the content is dropped into "the world"
    },
  }

  table.insert(slot_instances, o)
  return o
end

return {
  Slot = new_slot,
  Update = update,
}
