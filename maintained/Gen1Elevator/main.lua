-- Gen1Elevator
--
-- The lift panel, as a panel.
--
-- Reading the button plate in SILPH CO., the ROCKET HIDEOUT or the CELADON
-- DEPT. STORE puts a full-screen white list on the screen with WHICH FLOOR?
-- at the top of it and four floors visible at a time, which is what
-- DisplayElevatorFloorMenu does on the cartridge and what data/scripts/
-- story3.lua faithfully reproduces here.  It is also the one screen in the
-- game where a full screen buys nothing: there are never more than eleven
-- rows, every row is three glyphs wide, and the car you are standing in
-- disappears while you pick.
--
-- So: a small box against the right edge, every floor visible at once, and
-- the lift still on the screen behind it.  Nothing else changes -- the same
-- list picks the same floor, cancels the same way, and hands off to the same
-- ElevatorShake ride.
--
-- ------- the geometry is Menu's, exactly
--
-- Not a private layout that looks a bit like one.  src/ui/Menu.lua is what
-- every boxed choice in this game is drawn by, and its two rules are the ones
-- that make a box look like it belongs here:
--
--   * rows are TWO tiles apart, not one.  A one-tile pitch fits more floors
--     in and reads as a list that has been squashed, because nothing else in
--     the game is spaced that way;
--   * the choices anchor to the BOTTOM interior row and the slack falls as a
--     blank row under the top border (draw_start_menu.asm, and the comment
--     in Menu:draw).
--
-- The first version of this file got both wrong -- one-tile rows and choices
-- from the top -- and carried a FLOOR title on its border besides.
--
-- ------- there is no title on it
--
-- There was, and it earned nothing.  A box of floor numbers that opens when
-- you read a lift's button plate, in a lift, is not ambiguous; the word only
-- ever said what the rows already said, and it cost the box three tiles of
-- width and a rule that had to be knocked out to make room for it.  Without
-- it the panel is as wide as its widest floor and no wider, which is what a
-- panel against the edge of the screen should be.
--
-- ------- what is NOT done here
--
-- The floor you are currently on is not marked.  Gen 2 prints it ("Now on:
-- 3F", Elevator_GetCurrentFloorText) and this could not: the list is handed
-- the floor rows and nothing else, and the map the player came from lives on
-- the overworld controller, which is not reachable from a ListMenu instance.
-- A wrong marker is worse than none, so there is none.

local TITLE = "WHICH FLOOR?"
local PATCH = "__gen1ElevatorListMenu"

local SCREEN_TILES_W, SCREEN_TILES_H = 20, 18

-- One tile of margin off the right edge and off the top.
local MARGIN = 1
local ROW_STEP = 2              -- tiles, the pitch every Gen 1 menu uses

-- Two borders, the cursor's column and one spare at the right, around the
-- widest floor token.
local ROW_CHROME = 4

-- Narrow is the point, but a box under six tiles stops reading as a box.  No
-- Gen 1 lift reaches it -- B1F is the widest token in the game, which is
-- seven -- so this only ever catches a modded lift with one-glyph floors.
local MIN_TW = 6

return function(mod)
  local Font = mod.ui.Font
  local Theme = mod.ui.Theme
  local ListMenu = mod.ui.ListMenu
  local Strings = require("src.core.Strings")

  mod.options:define({
    { key = "enabled", type = "toggle", label = "ELEVATOR PANEL",
      default = true },
  })

  local function enabled()
    local ok, value = pcall(function() return mod.options:get("enabled") end)
    if not ok or value == nil then return true end
    return value == true
  end

  local function isPanel(title)
    if type(title) ~= "string" then return false end
    if title == TITLE then return true end
    local ok, localized = pcall(Strings, TITLE)
    return ok and title == localized
  end

  local function glyphs(text)
    local ok, spans = pcall(Font.split, tostring(text or ""))
    if ok then return #spans end
    return #tostring(text or "")
  end

  -- As wide as the widest floor token and no wider.
  local function widthFor(items)
    local widest = 0
    for _, item in ipairs(items) do
      local n = glyphs(item.label)
      if n > widest then widest = n end
    end
    return math.min(SCREEN_TILES_W, math.max(widest + ROW_CHROME, MIN_TW))
  end

  -- How many floors a box can show and still sit inside the screen with its
  -- margin: the box is `visible * 2 + 2` tiles tall from row MARGIN.
  local function visibleFor(count)
    local room = math.floor((SCREEN_TILES_H - MARGIN - 2) / ROW_STEP)
    return math.max(1, math.min(count, room))
  end

  -- Menu's own box: rows anchor to the bottom interior row, slack falls as a
  -- blank row under the top border.
  local function geometry(items)
    local visible = visibleFor(#items)
    local tw = widthFor(items)
    local th = visible * ROW_STEP + 2
    return SCREEN_TILES_W - tw - MARGIN, MARGIN, tw, th, visible
  end

  local function draw(self)
    local items = self.items or {}
    local tx, ty, tw, th, visible = geometry(items)

    love.graphics.setColor(0, 0, 0, 1)
    Font.drawBox(tx, ty, tw, th)
    love.graphics.setColor(0, 0, 0, 1)

    -- Menu:draw's rowY: count back from the bottom interior row, so a box
    -- with slack in it puts the blank row at the TOP.
    local function rowY(row)
      return (ty + th - 2 - (visible - row) * ROW_STEP) * 8
    end

    for row = 1, visible do
      local i = (self.scroll or 0) + row
      local item = items[i]
      if not item then break end
      local y = rowY(row)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(tostring(item.label or ""), (tx + 2) * 8, y)
      if i == self.index then
        Font.drawCode(Theme.cursor, (tx + 1) * 8, y)
      end
    end

    -- more below, on the bottom border, where Menu puts it
    if (self.scroll or 0) + visible < #items then
      Font.drawCode(Theme.moreArrow, (tx + tw - 2) * 8, (ty + th - 1) * 8)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  local function decorate(list)
    local baseDraw = list.draw
    if type(baseDraw) ~= "function" then return list end
    local baseOpaque = list.isOpaque
    local basePalettes = list.sgbPalettes
    local baseRows = list.rows

    -- Opaque is what made it a screen.  A panel is something you read with
    -- the room still around it, so the lift stays drawn underneath -- and the
    -- map keeps its own palette, which a whole-screen SET_PAL_GENERIC would
    -- have replaced.
    --
    -- `rows` is what ListMenu scrolls against, so it has to agree with what
    -- the box can show: eleven floors (SILPH CO. 1F-11F) is more than fits,
    -- and the more-arrow says so.
    list.isOpaque = false
    list.sgbPalettes = false
    list.rows = visibleFor(#(list.items or {}))
    list.draw = function(self)
      if not enabled() then
        self.isOpaque = baseOpaque
        self.sgbPalettes = basePalettes
        self.rows = baseRows
        return baseDraw(self)
      end
      self.isOpaque = false
      self.sgbPalettes = false
      self.rows = visibleFor(#(self.items or {}))
      return draw(self)
    end
    return list
  end

  if type(ListMenu) ~= "table" or type(ListMenu.new) ~= "function" then
    mod.log:warn("src.ui.ListMenu is not what this build expects; the lift "
      .. "panel keeps its full-screen list")
    return
  end
  if rawget(ListMenu, PATCH) then return end

  local baseNew = ListMenu.new
  ListMenu.new = function(game, title, items, opts)
    local list = baseNew(game, title, items, opts)
    if type(list) ~= "table" or not isPanel(title) then return list end
    local ok, result = pcall(decorate, list)
    -- A panel that will not decorate is still a panel: hand back the
    -- engine's own list rather than nothing at all.
    if not ok then
      mod.log:warn("the lift panel did not decorate (%s); it keeps its "
        .. "full-screen list", tostring(result))
      return list
    end
    return result
  end
  ListMenu[PATCH] = true

  mod.exports.isPanel = isPanel
  mod.exports.widthFor = widthFor
  mod.exports.visibleFor = visibleFor
  mod.exports.geometry = geometry

  mod.log:info("the lift panel is a panel")
end
