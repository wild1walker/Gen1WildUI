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
-- ------- how the list is recognised
--
-- By its title, which is all there is.  The panel's list is built inside
-- story3.lua's `elevator` closure with a literal title and no `kind`, so
-- ListMenu falls back to the title and this arrives as "WHICH FLOOR?".  There
-- is no screen id to override and no hook that reaches it.
--
-- The comparison is against the literal AND against Strings() of it, because
-- a localized game prints a translated title from a script that still passes
-- the English literal -- matching only one of the two would miss on one side
-- or the other depending on which end the translation happens.
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

-- The box: one tile of margin off the right edge and one off the top, wide
-- enough for the widest floor token plus the cursor column, and never
-- narrower than the label on its border needs.
local MARGIN = 1
local LABEL = "FLOOR"
local MIN_TW = 8
local ROW_STEP = 8              -- one tile per floor, not two

-- A top border carries a one-pixel white margin above its rule, and Gen 1
-- glyphs ink rows 0-6 of their cell, so a label drawn at the tile's own y
-- puts ink on that margin.  One pixel lower lands it between the two.
local WINDOW_EDGE = 1
local LABEL_PAD = 8

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

  -- Wide enough for the widest floor token, and for the word on the border.
  local function widthFor(items)
    local widest = 0
    for _, item in ipairs(items) do
      local ok, spans = pcall(Font.split, tostring(item.label or ""))
      local n = ok and #spans or #tostring(item.label or "")
      if n > widest then widest = n end
    end
    -- cursor column, the label, a column of right padding, two borders
    return math.max(MIN_TW, widest + 4)
  end

  -- Knock the border line out from under the label: glyphs are drawn as a
  -- mask, so a label printed straight onto a border has the rule running
  -- through the letters.  Painting the run white first leaves the line either
  -- side of the word and nothing behind it -- which is how Menu titles its
  -- own box (src/ui/Menu.lua) and how the bag titles its pocket.
  local function borderLabel(text, tx, ty, tw)
    local width = Font.width(text)
    local slack = math.max(0, (tw - 2) * 8 - width)
    local x = (tx + 1) * 8 + math.floor(slack / 16) * 8
    local left = math.max((tx + 1) * 8, x - LABEL_PAD)
    local right = math.min((tx + tw - 1) * 8, x + width + LABEL_PAD)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", left, ty * 8, right - left, 8)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(text, x, ty * 8 + WINDOW_EDGE)
  end

  local function draw(self)
    local items = self.items or {}
    local visible = math.min(#items, self.rows or #items)
    local tw = widthFor(items)
    local th = visible + 2
    local tx = SCREEN_TILES_W - tw - MARGIN
    local ty = math.max(0, math.min(MARGIN, SCREEN_TILES_H - th))

    love.graphics.setColor(0, 0, 0, 1)
    Font.drawBox(tx, ty, tw, th)
    love.graphics.setColor(0, 0, 0, 1)
    borderLabel(LABEL, tx, ty, tw)

    for row = 1, visible do
      local i = (self.scroll or 0) + row
      local item = items[i]
      if not item then break end
      local y = (ty + row) * ROW_STEP
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(tostring(item.label or ""), (tx + 2) * 8, y)
      if i == self.index then
        Font.drawCode(Theme.cursor, (tx + 1) * 8, y)
      end
    end

    -- more below, on the border the way every other scrolling box marks it
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

    -- Every floor at once: eleven is the most this game ever offers (SILPH
    -- CO. 1F-11F), and eleven rows plus two borders is thirteen tiles, which
    -- fits under a screen of eighteen with the margin still on it.  The cap
    -- is the guard for a modded lift with more floors than that, and the
    -- more-arrow above says so when it bites.
    local roomFor = SCREEN_TILES_H - MARGIN - 2

    -- Opaque is what made it a screen.  A panel is something you read with
    -- the room still around it, so the lift stays drawn underneath -- and the
    -- map keeps its own palette, which a whole-screen SET_PAL_GENERIC would
    -- have replaced.
    list.isOpaque = false
    list.sgbPalettes = false
    list.rows = math.min(#(list.items or {}), roomFor)
    list.draw = function(self)
      if not enabled() then
        self.isOpaque = baseOpaque
        self.sgbPalettes = basePalettes
        self.rows = baseRows
        return baseDraw(self)
      end
      self.isOpaque = false
      self.sgbPalettes = false
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

  mod.log:info("the lift panel is a panel")
end
