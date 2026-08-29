-- Gen1ModernBag for Gen1Recomp
-- Splits the vanilla BagMenu into pockets while delegating every item action
-- to the original menu, preserving engine and inter-mod item behavior.

local PATCH_KEY = "__gen1_modern_bag_dispatch_v1"
local BAG_PATCH_KEY = "__gen1_modern_bag_unlimited_inventory_v1"
local INPUT_PATCH_KEY = "__gen1_modern_bag_move_info_input_v1"
local INFO_ACTION = "gen1_modern_bag_move_info"
local SEARCH_QUERY_LIMIT = 12

local QUICK_SEARCH_SCREEN_ID = "ModernBagNicknameSearch"
local MOVE_INFO_SCREEN_ID = "ModernBagMoveInfo"

local POCKETS = {
  { id = "favorites", label = "FAVORITES", virtual = true },
  { id = "medicine", label = "MEDICINE" },
  { id = "balls", label = "BALLS" },
  { id = "machines", label = "TM/HM" },
  { id = "battle", label = "BATTLE" },
  { id = "key", label = "KEY ITEMS" },
  { id = "other", label = "OTHER" },
  -- A search fills this one and puts you on it; it is not in the ring until
  -- then, and it is gone the next time the Bag opens.
  { id = "results", label = "RESULTS", virtual = true, transient = true },
}

local OPENING_POCKET_VALUES = {
  favorites = true, medicine = true, balls = true, machines = true,
  battle = true, key = true, other = true, last = true,
}

local SCROLL_SPEEDS = {
  off = { enabled = false, delay = 16, rate = 4 },
  normal = { enabled = true, delay = 16, rate = 4 },
  fast = { enabled = true, delay = 10, rate = 2 },
  very_fast = { enabled = true, delay = 6, rate = 1 },
}

local function optionValue(mod, key, default)
  if mod and mod.options and type(mod.options.get) == "function" then
    local ok, value = pcall(mod.options.get, mod.options, key)
    if ok and value ~= nil then return value end
  end
  return default
end

local function pocketIndexById(id)
  for i, pocket in ipairs(POCKETS) do
    if pocket.id == id then return i end
  end
  return 2
end

local function openingPocketIndex(mod)
  local wanted = tostring(optionValue(mod, "opening_pocket", "medicine") or "medicine")
  if not OPENING_POCKET_VALUES[wanted] then wanted = "medicine" end
  if wanted == "last" then
    local saved = mod and mod.save and mod.save:get("last_pocket", "medicine") or "medicine"
    if not OPENING_POCKET_VALUES[saved] or saved == "last" then saved = "medicine" end
    wanted = saved
  end
  return pocketIndexById(wanted)
end

local function scrollConfig(mod)
  local speed = tostring(optionValue(mod, "hold_scroll_speed", "off") or "off")
  return SCROLL_SPEEDS[speed] or SCROLL_SPEEDS.off
end

-- Pocket header.
--
-- The Bag is a ListMenu the engine opens with itemBox = true, and that path
-- draws the LIST_MENU_BOX, its rows, the quantities and the cursor -- and
-- nothing else. `self.title` is only ever drawn by ListMenu:draw's plain
-- full-screen branch (src/ui/ListMenu.lua), which the Bag returns before
-- reaching, so a title assigned to the Bag list never reaches the screen.
-- The name has to be drawn here; refreshPocket still keeps list.title in
-- step for Gen1 Modern UI and anything else that reads it.
--
-- It goes on the box's own top border, which is where Gen 1 titles a window:
-- the border line runs up to the label and continues after it.
--
-- LIST_MENU_BOX is tiles 4,2 - 19,12, and the fourteen columns between its
-- corners are the label's. Nothing else is on that border: up to 1.3.1 the
-- Left/Right arrows took the outermost column at each end, which left a
-- nine-letter pocket name only one column of rule to sit in.
--
-- ------- and the same window one tile wider, for the icons
--
-- An item icon is sixteen pixels, which is two tiles, and the engine's window
-- has one to spare: the cursor takes the column at x = 40 and a name from
-- x = 48 has thirteen columns to the right margin for the twelve glyphs a Gen
-- 1 item name can be. Putting a picture in that one spare column would have
-- cost every twelve-glyph name its last letter -- SUPER POTION, FULL RESTORE,
-- THUNDERSTONE, HELIX FOSSIL, BIKE VOUCHER, HYPER POTION and OAK's PARCEL are
-- the seven, which is most of a starting Bag -- and a name cut short is a
-- worse row than a name with no picture beside it.
--
-- So the window grows a tile at the left instead. It still starts inside the
-- screen and the map still shows around it: this is the same pop-up over the
-- overworld it has always been, two tiles in from the edge rather than four.
-- Nothing else moves. The name column, the quantity column, the more-arrow
-- and both borders are where they were, so the pocket name and the money
-- still sit exactly where a player's eye already goes for them.
local LAYOUTS = {
  -- the engine's own, drawn by the engine's own drawItemBox
  plain = {
    tx = 4, ty = 2, tw = 16, th = 11,
    cursorX = 40, iconX = nil, nameX = 48,
  },
  -- two tiles wider at the left: cursor 24, icon 32-47, the rule down the
  -- middle of the tile after it, and the name from 56 -- which is twelve
  -- glyphs to the right margin at 152, so no name is trimmed.
  --
  -- Two rather than one. The first buys the icon its column; the second buys
  -- the gap between the icon and the word, and the rule down the middle of
  -- that gap. Without it a picture sits flush against the first letter of the
  -- name and reads as part of it.
  --
  -- The window still starts inside the screen and the map still shows around
  -- it. Every column that was here before this feature -- the name, the
  -- quantity, the more-arrow, the pocket name and the money -- is still
  -- exactly where it was; what has moved is only what was added.
  icons = {
    tx = 2, ty = 2, tw = 18, th = 11,
    cursorX = 24, iconX = 32, nameX = 56, iconY = -4, ruleX = 51,
  },
}

-- iconY, and why it is not zero.
--
-- A row is sixteen pixels and so is an icon, so an icon drawn at the row's
-- own y fills it exactly -- and looks wrong. The row holds two lines: the
-- item's name on the top eight pixels and its count underneath. A Gen 1
-- glyph inks rows 0 to 6 of its cell, so the name's ink is centred on y + 3
-- while the icon's is centred on y + 7.5, and the word reads as floating
-- above its own picture.
--
-- What a reader pairs is the name and the icon, not the whole cell and the
-- icon, so the icon is centred on the name: four pixels up puts the two
-- centres within half a pixel of each other. Icons stay sixteen apart, so the
-- column shifts as a whole and no two of them come any closer together; the
-- top one lands on y = 28, four clear of the window's own interior.
local HEADER_Y = LAYOUTS.plain.ty * 8

-- Which of the two a Bag is drawing in. The icons are a setting and the
-- setting is live, so this is asked every frame rather than fixed when the
-- Bag opened -- and it answers `plain` whenever there are no icons to draw,
-- which is a build whose assets did not survive being installed.
local function layoutFor(state)
  if type(state) ~= "table" or state.icons == nil then return LAYOUTS.plain end
  if optionValue(state.mod, "item_icons", true) == false then
    return LAYOUTS.plain
  end
  return LAYOUTS.icons
end

local function layoutOf(list)
  return layoutFor(type(list) == "table" and list.modernBag or nil)
end

-- How many glyphs a name has between where it starts and the frame: the
-- window's last interior column less the name column, in 8px cells. Thirteen
-- in the engine's window, twelve in the one with icons in it.
local function nameGlyphs(box)
  return math.floor(((box.tx + box.tw - 1) * 8 - box.nameX) / 8)
end

-- Knock the border line out from under a label.
--
-- Glyphs are drawn as a mask -- Font.draw paints them in whatever colour is
-- set, which is how black text lands on the box's white fill -- so a label
-- drawn straight onto a border would have the line running through the
-- letters. Painting the cells white first leaves the line either side of the
-- label and nothing behind it.
--
-- Knock out exactly the width of the text and the line ends flush against the
-- first glyph and restarts flush against the last, which reads as the frame
-- touching the letters. src/ui/Menu.lua's own title does this. A tile of
-- clearance at each end is what buys the gap; the label itself does not move.
local BORDER_LABEL_PAD = 8

-- The frame carries a one-pixel white margin around the whole window, outside
-- its rule, and on a top border that margin is the border tile's first pixel
-- row. Gen 1 glyphs ink rows 0 to 6 of their cell and leave the last blank, so
-- a label drawn at the tile's own y puts ink on that margin: a top-border
-- label is drawn one pixel lower, which lands it between the margin and the
-- rule. A bottom border needs no such shift -- its margin is the tile's last
-- pixel row, which is the row the glyphs already leave empty.
local WINDOW_EDGE = 1

local function clearBorderRun(x, y, width)
  if width <= 0 then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", x, y, width, 8)
end

-- The padded run, clamped so it can never rub out a corner glyph: those are
-- the columns at tx and tx + tw - 1, and the run lives between them.
local function clearLabelRun(x, y, width, tx, tw)
  local left = math.max((tx + 1) * 8, x - BORDER_LABEL_PAD)
  local right = math.min((tx + tw - 1) * 8, x + width + BORDER_LABEL_PAD)
  clearBorderRun(left, y, right - left)
end

-- Centre a label between a box's corner columns, on the 8px column grid the
-- rest of the box sits on.
local function borderLabelX(Font, text, tx, tw)
  local slack = math.max(0, (tw - 2) * 8 - Font.width(text))
  return (tx + 1) * 8 + math.floor(slack / 16) * 8
end

-- Label a box on its top border row: knock the line out, then draw a pixel
-- lower, clear of the frame's outer margin. The knock-out stays on the tile,
-- so it still takes the whole rule out from under the label.
local function drawBorderLabel(Font, text, tx, ty, tw)
  local x = borderLabelX(Font, text, tx, tw)
  clearLabelRun(x, ty * 8, Font.width(text), tx, tw)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(text, x, ty * 8 + WINDOW_EDGE)
  return x
end

-- Trim to a pixel budget rather than a character count: a font mod can ship
-- variable-width glyphs, and Font.width is what measures them.
--
-- Trim by glyphs, not by bytes. A label can carry a multi-byte character --
-- POKé, the ¥ -- or a Gen 1 control code, and half of one of those is not a
-- character. Font.split is the engine's own glyph split, the same one Menu
-- measures its title with; it is used when it round-trips, so a build without
-- it still trims the old way rather than breaking.
local function labelGlyphs(Font, label)
  if type(Font.split) ~= "function" then return nil end
  local ok, glyphs = pcall(Font.split, label)
  if not ok or type(glyphs) ~= "table" then return nil end
  local joined = table.concat(glyphs)
  if joined ~= label then return nil end
  return glyphs
end

local function fitLabel(Font, label, budget)
  if Font.width(label) <= budget then return label end
  local glyphs = labelGlyphs(Font, label)
  if glyphs then
    while #glyphs > 0 and Font.width(table.concat(glyphs)) > budget do
      table.remove(glyphs)
    end
    return table.concat(glyphs)
  end
  while #label > 0 and Font.width(label) > budget do
    label = label:sub(1, #label - 1)
  end
  return label
end

-- The pocket name is a border label like any other window's title now, so it
-- is drawn by the same code: centred between the corners, a tile of clearance
-- at each end, the rule running up to it and on after it.
local function drawPocketHeader(list)
  local state = list.modernBag
  local pocket = state and POCKETS[state.pocket]
  if not pocket then return end
  local Font = require("src.render.Font")
  local box = layoutOf(list)
  -- Corners, and a tile of clearance inside each.
  local label = fitLabel(Font, pocket.label, (box.tw - 4) * 8)
  drawBorderLabel(Font, label, box.tx, box.ty, box.tw)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Money.
--
-- On the item window's bottom border, right-aligned, the same way the pocket
-- name sits on the top one. 1.2.0 gave it a little window of its own hanging
-- under that corner; on the border there is no second frame at all, and the
-- amount lands exactly where the bottom-right of the item window is.
--
-- LIST_MENU_BOX ends on tile row 12, so that border is the row at y = 96, and
-- The amount stops one column short of the corner, at x = 144, so the tile
-- between it and the corner glyph is its clearance -- the same tile the rule
-- gives it at the other end.
-- Both windows end on the same tile row and the same right-hand corner, so
-- the amount does not move between them; only the wall it can never be pushed
-- past on the way left does.
local MONEY_Y = (LAYOUTS.plain.ty + LAYOUTS.plain.th - 1) * 8

local function moneyRightX(box) return (box.tx + box.tw - 2) * 8 end
local function moneyLeftLimit(box) return (box.tx + 1) * 8 + BORDER_LABEL_PAD end

local function moneyText(game)
  local amount = math.floor(tonumber(game and game.save and game.save.money) or 0)
  return ("¥%d"):format(math.max(0, amount))
end

local function drawBagMoney(list)
  local text = moneyText(list.game)
  if type(text) ~= "string" or text == "" then return end
  local Font = require("src.render.Font")
  local box = layoutOf(list)
  local rightX, leftLimit = moneyRightX(box), moneyLeftLimit(box)
  -- Never past its own clearance at the other end, however wide the glyphs are.
  local x = math.max(leftLimit, rightX - Font.width(text))
  clearBorderRun(x - BORDER_LABEL_PAD,
    MONEY_Y, (rightX - x) + BORDER_LABEL_PAD * 2)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(text, x, MONEY_Y)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Pop-up menus.
--
-- These are src/ui/Menu.lua, the engine's own framed menu widget: it draws the
-- frame, the title on the top border and the more-arrow on the bottom one, and
-- it owns the cursor, the scrolling and the input. A mod hands it a list of
-- { label, onSelect } and a corner to put it in.
--
-- Up to 1.3.0 these were ListMenus with their `draw` replaced by a frame this
-- mod painted itself, because ListMenu's full-screen branch fills all 160x144
-- white and paints no frame at all. Menu is the widget that was wanted all
-- along.
local SCREEN_TILES_W = 20
local SCREEN_TILES_H = 18

-- A window over the whole screen, for the two screens that have more to say
-- than a corner will hold. Its interior is the eighteen columns from x = 8 and
-- the sixteen rows from y = 8.
local WINDOW_BOX = { tx = 0, ty = 0, tw = SCREEN_TILES_W, th = SCREEN_TILES_H }
local WINDOW_LEFT_X = 8
local WINDOW_TOP_Y = 8
local WINDOW_BOTTOM_Y = 128
local WINDOW_INNER_W = 144

-- RESULTS only exists while a search is loaded into it. Everything else is
-- always in the ring.
local function pocketVisible(state, pocket)
  if not pocket then return false end
  if pocket.transient then return state ~= nil and state.results ~= nil end
  return true
end

local function rememberPocket(state)
  if not state or not state.mod or not state.mod.save then return end
  local pocket = POCKETS[state.pocket]
  -- A transient pocket is not somewhere to reopen the Bag on: it is empty by
  -- the time the Bag opens again, so LAST USED keeps the pocket before it.
  if pocket and not pocket.transient then
    state.mod.save:set("last_pocket", pocket.id)
  end
end

local MEDICINE = {
  POTION = true, SUPER_POTION = true, HYPER_POTION = true,
  MAX_POTION = true, FULL_RESTORE = true,
  ANTIDOTE = true, BURN_HEAL = true, ICE_HEAL = true,
  AWAKENING = true, PARLYZ_HEAL = true, FULL_HEAL = true,
  REVIVE = true, MAX_REVIVE = true,
  FRESH_WATER = true, SODA_POP = true, LEMONADE = true,
  ETHER = true, MAX_ETHER = true, ELIXER = true, MAX_ELIXER = true,
  HP_UP = true, PROTEIN = true, IRON = true, CARBOS = true,
  CALCIUM = true, RARE_CANDY = true, PP_UP = true,
}

local BATTLE_ITEMS = {
  X_ATTACK = true, X_DEFEND = true, X_SPEED = true, X_SPECIAL = true,
  X_ACCURACY = true, DIRE_HIT = true, GUARD_SPEC = true,
  POKE_DOLL = true,
}

local BALL_IDS = {
  MASTER_BALL = true, ULTRA_BALL = true, GREAT_BALL = true,
  POKE_BALL = true, SAFARI_BALL = true,
}

local STONES = {
  FIRE_STONE = true, WATER_STONE = true, THUNDER_STONE = true,
  LEAF_STONE = true, MOON_STONE = true,
}

local function upper(value)
  return tostring(value or ""):upper()
end

local function pocketFor(id, def)
  def = def or {}
  if def.machine then return "machines" end
  if def.ball or BALL_IDS[id] then return "balls" end
  if BATTLE_ITEMS[id] then return "battle" end
  if MEDICINE[id] then return "medicine" end

  -- Friendly inference for modded records. Explicit engine fields win; the
  -- name/effect fallback only catches conventional custom medicines.
  local effect = upper(def.effect)
  if not STONES[id] and (
       effect:find("HEAL", 1, true)
    or effect:find("REVIVE", 1, true)
    or effect:find("MEDIC", 1, true)
    or effect:find("VITAMIN", 1, true)
    or effect:find("ETHER", 1, true)
    or effect:find("ELIX", 1, true)
    or effect:find("CANDY", 1, true)
    or effect:find("PP_UP", 1, true)) then
    return "medicine"
  end

  if def.keyItem or def.tossable == false then return "key" end
  return "other"
end

local function countOf(save, id)
  local value = save and save.inventory and save.inventory[id]
  value = math.floor(tonumber(value) or 0)
  return math.max(0, value)
end

local function positionOf(order, id)
  for i, value in ipairs(order or {}) do
    if value == id then return i end
  end
  return nil
end

local function cleanSavedOrder(value)
  local out, seen = {}, {}
  if type(value) ~= "table" then return out end
  for _, id in ipairs(value) do
    if type(id) == "string" and id ~= "" and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  return out
end

local function orderIndex(order)
  local out = {}
  for i, id in ipairs(order or {}) do out[id] = i end
  return out
end

-- Opening a Menu.
--
-- The title is not handed to Menu. Menu draws its own at the border tile's own
-- y and knocks out exactly its width, which puts ink on the frame's outer
-- white margin and ends the rule flush against the first and last letter. It
-- is drawn here instead, through the same drawBorderLabel every other window
-- title in this mod goes through: a pixel lower, with a tile of clearance
-- knocked out at each end. Only `draw` is wrapped, so the frame, the rows, the
-- cursor and the more-arrow all stay Menu's.
--
-- Menu grows tw to the widest label + 3 and never accounts for the title, so
-- the width still has to be asked for: the title plus its two clearance tiles
-- has to fit between the corners, which is tw - 4.
local MENU_LABEL_MARGIN = 3
local MENU_TITLE_MARGIN = 4

-- Four rows of options, opened clear of the pocket header on the item
-- window's top border. Menu works its own height out from the rows.
local ITEM_TOOLS_TY = 5
local SORT_PICKER_TY = 6

local function menuTiles(Font, text)
  return math.ceil(Font.width(text) / 8)
end

local function menuWidth(Font, title, items)
  local widest = 0
  for _, item in ipairs(items) do
    local tiles = menuTiles(Font, tostring(item.label or ""))
    if tiles > widest then widest = tiles end
  end
  local forTitle = title and (menuTiles(Font, title) + MENU_TITLE_MARGIN) or 0
  return math.min(SCREEN_TILES_W,
    math.max(widest + MENU_LABEL_MARGIN, forTitle))
end

-- Labels are held to the width that was asked for: Menu sizes itself from the
-- widest one, so a long label would otherwise grow the menu off the screen.
local function fitMenuLabels(Font, items, tw)
  local budget = (tw - MENU_LABEL_MARGIN) * 8
  for _, item in ipairs(items) do
    item.label = fitLabel(Font, tostring(item.label or ""), budget)
  end
end

-- A title is optional: a menu whose rows say what it is does not need one.
local function labelMenuBorder(menu, title, tx, ty, tw)
  local baseDraw = menu.draw
  if type(baseDraw) ~= "function" then return menu end
  function menu:draw(...)
    local result = baseDraw(self, ...)
    local Font = require("src.render.Font")
    drawBorderLabel(Font, fitLabel(Font, title, (tw - 4) * 8), tx, ty, tw)
    love.graphics.setColor(1, 1, 1, 1)
    return result
  end
  return menu
end

local function openMenu(game, title, items, opts)
  opts = opts or {}
  local Font = require("src.render.Font")
  local Menu = require("src.ui.Menu")
  local tw = opts.tw or menuWidth(Font, title, items)
  local tx = SCREEN_TILES_W - tw   -- against the right edge, as Gen 1 does
  local ty = opts.ty or 0
  fitMenuLabels(Font, items, tw)
  local menu = Menu.new(game, items, {
    tx = tx,
    ty = ty,
    tw = tw,
    maxVisible = opts.maxVisible,
    onCancel = opts.onCancel,
  })
  if title and title ~= "" then
    labelMenuBorder(menu, title, tx, ty, tw)
  end
  game.stack:push(menu)
  return menu
end

-- How a pocket is ordered.
--
-- Each pocket keeps its own mode and stays in it: choosing one is a setting
-- for that tab, not a one-off rearrangement. ALPHA and QUANTITY are worked out
-- from the items every time the rows are built, so they hold as the Bag
-- changes; CUSTOM is the order you arranged by hand, which is what MOVE ITEM
-- edits and what the Bag stores.
--
-- The machine orders are offered only on a pocket holding a machine, since
-- number and base power mean nothing to a shelf of potions.
local SORT_MODES = {
  { id = "ALPHA", label = "A-Z" },
  { id = "QUANTITY", label = "QUANTITY" },
  { id = "CUSTOM", label = "CUSTOM" },
  { id = "NUMBER", label = "TM/HM NUMBER", machinesOnly = true },
  { id = "POWER_DESC", label = "POWER HIGH", machinesOnly = true },
  { id = "POWER_ASC", label = "POWER LOW", machinesOnly = true },
}
local DEFAULT_SORT = "ALPHA"

local SORT_LABELS, SORT_VALUES = {}, {}
for _, mode in ipairs(SORT_MODES) do
  SORT_LABELS[mode.id] = mode.label
  SORT_VALUES[mode.id] = true
end

-- CUSTOM is an order, not a rule: there is nothing to arrange on a page that
-- is rebuilt from a query every time.
local function sortModeAvailable(mode, pocket, machines)
  if mode.machinesOnly and not machines then return false end
  if mode.id == "CUSTOM" and pocket and pocket.transient then return false end
  return true
end

-- One mode per pocket, keyed by pocket id and saved, so a tab stays in the
-- order you put it in across sessions.
local function cleanSavedSorts(value)
  local out = {}
  if type(value) ~= "table" then return out end
  for id, mode in pairs(value) do
    if type(id) == "string" and SORT_VALUES[upper(mode)] then
      out[id] = upper(mode)
    end
  end
  return out
end

local function loadPreferenceState(mod)
  local favorites = cleanSavedOrder(mod.save:get("favorite_items", {}))
  local pinned = cleanSavedOrder(mod.save:get("pinned_items", {}))
  return {
    mod = mod,
    favoriteOrder = favorites,
    favoriteSet = orderIndex(favorites),
    pinnedOrder = pinned,
    pinnedSet = orderIndex(pinned),
    pocketSort = cleanSavedSorts(mod.save:get("pocket_sort", {})),
  }
end

local function pocketSortMode(state, pocketId)
  local saved = state and state.pocketSort
  return (saved and saved[pocketId]) or DEFAULT_SORT
end

local function setPocketSort(state, pocketId, mode)
  if not SORT_VALUES[mode] then return end
  state.pocketSort = state.pocketSort or {}
  state.pocketSort[pocketId] = mode
  if state.mod then state.mod.save:set("pocket_sort", state.pocketSort) end
end

local function persistPreferences(state)
  if not state or not state.mod then return end
  state.mod.save:set("favorite_items", cleanSavedOrder(state.favoriteOrder))
  state.mod.save:set("pinned_items", cleanSavedOrder(state.pinnedOrder))
end

local function rebuildPreferenceIndexes(state)
  state.favoriteOrder = cleanSavedOrder(state.favoriteOrder)
  state.pinnedOrder = cleanSavedOrder(state.pinnedOrder)
  state.favoriteSet = orderIndex(state.favoriteOrder)
  state.pinnedSet = orderIndex(state.pinnedOrder)
end

local function toggleOrderedItem(order, id)
  local index = positionOf(order, id)
  if index then
    table.remove(order, index)
    return false
  end
  order[#order + 1] = id
  return true
end

local function pocketIndexFor(id, def)
  local wanted = pocketFor(id, def)
  for i, pocket in ipairs(POCKETS) do
    if pocket.id == wanted then return i end
  end
  return #POCKETS
end

local function normalizedSearch(value)
  local text = upper(value)
  text = text:gsub("é", "E"):gsub("É", "E")
  return text:gsub("[^A-Z0-9]", "")
end


-- Generation I determines physical/special damage from the move type.
-- Non-damaging moves are exposed as STATUS so filters never hide them in an
-- arbitrary damage class.
local PHYSICAL_TYPES = {
  NORMAL = true, FIGHTING = true, FLYING = true, POISON = true,
  GROUND = true, ROCK = true, BUG = true, GHOST = true,
}

local function moveDamageClass(move)
  move = move or {}
  local power = math.floor(tonumber(move.power) or 0)
  if power <= 0 then return "STATUS" end
  return PHYSICAL_TYPES[upper(move.type)] and "PHYSICAL" or "SPECIAL"
end

local function displayType(game, typeId)
  local types = game and game.data and game.data.types
  local def = types and types[typeId]
  return upper((def and def.name) or typeId or "UNKNOWN")
end

local function machineCode(id, def)
  local machine = def and def.machine or {}
  local kind = upper(machine.kind)
  if kind ~= "TM" and kind ~= "HM" then kind = upper(tostring(id):match("^(%a%a)")) end
  local number = tonumber(machine.number)
  if not number then number = tonumber(tostring(def and def.name or id):match("(%d+)")) end
  if not number then number = tonumber(tostring(id):match("(%d+)$")) end
  number = number or 999
  return kind .. (number < 100 and ("%02d"):format(number) or tostring(number)), kind, number
end

local function readableEffect(effect)
  local label = upper(effect or "NO ADDITIONAL EFFECT")
  label = label:gsub("_EFFECT$", ""):gsub("_", " ")
  return label
end

local function machineInfo(game, id, def)
  def = def or (game and game.data and game.data.items and game.data.items[id]) or {}
  if not def.machine then return nil end
  local moveId = def.machine.move
  local move = game and game.data and game.data.moves and game.data.moves[moveId] or {}
  local code, kind, number = machineCode(id, def)
  local moveName = (move and move.name) or moveId or id
  local typeId = move and move.type or "UNKNOWN"
  local power = math.floor(tonumber(move and move.power) or 0)
  local accuracy = tonumber(move and move.accuracy)
  local pp = math.floor(tonumber(move and move.pp) or 0)
  local damageClass = moveDamageClass(move)
  local nameKey = normalizedSearch(moveName)
  local kindRank = kind == "HM" and 0 or 1
  return {
    id = id,
    item = def,
    move = move,
    moveId = moveId,
    code = code,
    kind = kind,
    number = number,
    numberKey = kindRank * 1000 + number,
    name = moveName,
    nameKey = nameKey,
    type = typeId,
    typeLabel = displayType(game, typeId),
    damageClass = damageClass,
    power = power,
    accuracy = accuracy,
    pp = pp,
    effect = readableEffect(move and move.effect),
    -- Type and damage class are in here so FIRE and SPECIAL are things the
    -- search box can find, rather than filters behind a menu of their own.
    searchKey = normalizedSearch(table.concat({
      code, moveName, tostring(moveId or ""), tostring(id),
      displayType(game, typeId), damageClass,
    }, " ")),
  }
end

-- Drawable width of a machine row. The 20-tile item window also spends
-- columns on the selection cursor and the window border, so the usable run
-- is ~13 glyphs, not 15 -- and one fewer again in the window with icons in
-- it, where the name starts a tile further in. The marker variant reserves
-- four of those for "P"/"F"/"PF", which is upstream's own offset between the
-- two. Lower MACHINE_LABEL_TRIM if your display still clips.
local MACHINE_LABEL_TRIM = 0
local MACHINE_LABEL_MARKER_ROOM = 4

local function compactMachineLabel(info, markers, box)
  local maxChars = nameGlyphs(box or LAYOUTS.plain) - MACHINE_LABEL_TRIM
  if markers ~= "" then maxChars = maxChars - MACHINE_LABEL_MARKER_ROOM end
  local label = info.code .. " " .. info.name
  if #label > maxChars then label = label:sub(1, maxChars - 1) .. "." end
  return label
end

local function machineSortLess(a, b, mode)
  local ma, mb = a.modernMachine, b.modernMachine
  if not ma or not mb then return tostring(a.value) < tostring(b.value) end
  if mode == "NAME" then
    if ma.nameKey ~= mb.nameKey then return ma.nameKey < mb.nameKey end
  elseif mode == "POWER_DESC" then
    if ma.power ~= mb.power then return ma.power > mb.power end
    if ma.nameKey ~= mb.nameKey then return ma.nameKey < mb.nameKey end
  elseif mode == "POWER_ASC" then
    if ma.power ~= mb.power then return ma.power < mb.power end
    if ma.nameKey ~= mb.nameKey then return ma.nameKey < mb.nameKey end
  else
    if ma.numberKey ~= mb.numberKey then return ma.numberKey < mb.numberKey end
  end
  return ma.numberKey < mb.numberKey
end

-- One row ordering, used by the pocket re-sort and by the results page.
-- NAME goes by displayed name; the machine modes group the machines first, in
-- that order, and leave everything else after them by name -- a POTION has no
-- machine number and no base power.
-- A machine's name is its move's; its own is "TM24".
local function rowNameKey(row)
  local info = row.modernMachine
  return (info and info.nameKey) or row.modernSort or ""
end

local function rowSortLess(a, b, mode)
  if mode == "ALPHA" then
    local ak, bk = rowNameKey(a), rowNameKey(b)
    if ak ~= bk then return ak < bk end
  elseif mode == "QUANTITY" then
    local ac, bc = a.modernCount or 0, b.modernCount or 0
    if ac ~= bc then return ac > bc end
  elseif mode == "CUSTOM" then
    local ai = a.modernFavoriteRank or a.modernSourceIndex or 0
    local bi = b.modernFavoriteRank or b.modernSourceIndex or 0
    if ai ~= bi then return ai < bi end
  else
    -- A machine order: the machines first, then everything else by name.
    local am, bm = a.modernMachine ~= nil, b.modernMachine ~= nil
    if am ~= bm then return am end
    if am and bm then return machineSortLess(a, b, mode) end
  end
  -- Ties break on the item, so the order is total whatever the mode.
  return (a.modernSort or "") < (b.modernSort or "")
end

local function orderRowsBy(rows, mode)
  table.sort(rows, function(a, b) return rowSortLess(a, b, mode) end)
end



local function inventorySignature(game)
  local Bag = require("src.inventory.Bag")
  local ids = {}
  for id, count in pairs(game.save.inventory or {}) do
    local amount = math.floor(tonumber(count) or 0)
    local badge = type(Bag.isBadge) == "function"
                  and Bag.isBadge(id)
                  or tostring(id):find("BADGE", 1, true) ~= nil
    if amount > 0 and not badge then ids[#ids + 1] = tostring(id) end
  end
  table.sort(ids)
  return table.concat(ids, "\0")
end

local function automaticSortKey(id, def)
  def = def or {}
  local label = normalizedSearch(def.name or id)
  if def.machine then
    local kind = upper(def.machine.kind)
    local kindRank = kind == "HM" and "0" or "1"
    local number = tonumber(tostring(id):match("(%d+)$")) or 999
    return kindRank .. ("%03d"):format(number) .. label
  end
  return label .. "\0" .. tostring(id)
end

-- Keeping the order honest, without rearranging it.
--
-- Up to 1.8.0 the whole Bag was re-sorted alphabetically every time it opened,
-- which quietly undid every manual move and every one-shot SORT the moment the
-- Bag was closed -- so SORT looked like it did nothing that lasted. The order
-- is the player's now: this only drops what they no longer carry, and anything
-- newly acquired is appended, which puts it at the bottom of its own pocket
-- because a pocket is drawn in the order's own order.
local function pruneBagOrder(game)
  local Bag = require("src.inventory.Bag")
  local order = Bag.order(game.save)
  local kept, seen = {}, {}
  for _, id in ipairs(order) do
    if not seen[id] and countOf(game.save, id) > 0 then
      seen[id] = true
      kept[#kept + 1] = id
    end
  end
  local changed = #kept ~= #order
  for i = 1, #kept do
    if order[i] ~= kept[i] then changed = true end
    order[i] = kept[i]
  end
  for i = #order, #kept + 1, -1 do order[i] = nil end
  return changed
end

local function autoSortBag(game, preferences)
  local Bag = require("src.inventory.Bag")
  local order = Bag.order(game.save)
  local sortable = {}
  local pinned = preferences and preferences.pinnedSet or {}
  for originalIndex, id in ipairs(order) do
    if countOf(game.save, id) > 0 then
      local def = game.data.items[id]
      sortable[#sortable + 1] = {
        id = id,
        pocket = pocketIndexFor(id, def),
        pin = pinned[id],
        key = automaticSortKey(id, def),
        original = originalIndex,
      }
    end
  end
  table.sort(sortable, function(a, b)
    if a.pocket ~= b.pocket then return a.pocket < b.pocket end
    if (a.pin ~= nil) ~= (b.pin ~= nil) then return a.pin ~= nil end
    if a.pin and b.pin and a.pin ~= b.pin then return a.pin < b.pin end
    if a.key ~= b.key then return a.key < b.key end
    return a.original < b.original
  end)
  local changed = #sortable ~= #order
  for i, row in ipairs(sortable) do
    if order[i] ~= row.id then changed = true end
    order[i] = row.id
  end
  for i = #order, #sortable + 1, -1 do order[i] = nil end
  return changed
end

local function itemRows(game, pocketId, state)
  local Bag = require("src.inventory.Bag")
  local order = Bag.order(game.save)
  local rows = {}
  local favoriteSet = state and state.favoriteSet or {}
  local pinnedSet = state and state.pinnedSet or {}
  for globalIndex, id in ipairs(order) do
    local count = countOf(game.save, id)
    if count > 0 then
      local def = game.data.items[id]
      local actualPocket = pocketFor(id, def)
      local included = pocketId == "favorites"
        and favoriteSet[id] ~= nil
        or actualPocket == pocketId
      if included then
        local favorite = favoriteSet[id] ~= nil
        local pinned = pinnedSet[id] ~= nil
        local markers = (pinned and "P" or "") .. (favorite and "F" or "")
        local info = actualPocket == "machines" and machineInfo(game, id, def) or nil
        local label = (def and def.name) or id
        if pocketId == "machines" and info then
          label = compactMachineLabel(info, markers, layoutFor(state))
        end
        rows[#rows + 1] = {
          label = label,
          right = (markers ~= "" and (markers .. " ") or "") .. "x" .. tostring(count),
          value = id,
          -- The displayed name, not the row label: a machine's row reads
          -- "TM24 SELFDES.", and sorting by that is code order, not name.
          modernSort = normalizedSearch((def and def.name) or id) .. "\0" .. tostring(id),
          modernCount = count,
          modernGlobalIndex = globalIndex,
          modernPocket = pocketIndexFor(id, def),
          modernPinned = pinned,
          modernFavorite = favorite,
          modernPinRank = pinnedSet[id],
          modernFavoriteRank = favoriteSet[id],
          modernSourceIndex = globalIndex,
          modernMachine = info,
        }
      end
    end
  end
  -- The pocket's own mode, worked out from the items every time, so it holds
  -- as the Bag changes rather than being a rearrangement that decays.
  local mode = pocketSortMode(state, pocketId)
  table.sort(rows, function(a, b)
    -- Pinned rows lead their pocket whatever the mode says.
    if a.modernPinned ~= b.modernPinned then return a.modernPinned end
    if a.modernPinned and b.modernPinned
       and a.modernPinRank ~= b.modernPinRank then
      return a.modernPinRank < b.modernPinRank
    end
    return rowSortLess(a, b, mode)
  end)
  return rows
end

local function selectedId(list)
  local item = list.items and list.items[list.index or 1]
  return item and item.value or nil
end

local function cursorBucket(state, pocketId)
  state.cursors[pocketId] = state.cursors[pocketId] or { index = 1, scroll = 0 }
  return state.cursors[pocketId]
end

local function saveCursor(list)
  local state = list.modernBag
  local pocket = POCKETS[state.pocket]
  if not pocket then return end
  local cursor = cursorBucket(state, pocket.id)
  cursor.index = list.index or 1
  cursor.scroll = list.scroll or 0
  cursor.selected = selectedId(list)
end

local function restoreCursor(list, rows, preserveId)
  local state = list.modernBag
  local pocket = POCKETS[state.pocket]
  local cursor = cursorBucket(state, pocket.id)
  local wanted = preserveId or cursor.selected
  local index
  if wanted then
    for i, row in ipairs(rows) do
      if row.value == wanted then index = i break end
    end
  end
  list.index = index or math.max(1, math.min(cursor.index or 1, #rows))
  if #rows == 0 then list.index = 1 end
  list.scroll = math.max(0, cursor.scroll or 0)
  local maxScroll = math.max(0, #rows - (list.rows or 7))
  if list.scroll > maxScroll then list.scroll = maxScroll end
  if list.index - list.scroll < 1 then list.scroll = list.index - 1 end
  if list.index - list.scroll > (list.rows or 7) then
    list.scroll = list.index - (list.rows or 7)
  end
end

local function refreshPocket(list, preserveId)
  local state = list.modernBag
  local pocket = POCKETS[state.pocket]
  -- The results page is rebuilt from the search that filled it rather than
  -- from a snapshot, so its counts follow the Bag as items are used up.
  local rows = pocket.transient
    and state.results and state.results.build(list.game, state)
    or itemRows(list.game, pocket.id, state)
  list.items = rows
  -- Not drawn by the engine for an item-box list (see the pocket header
  -- above), but Gen1 Modern UI and the compatibility contract read it.
  list.title = pocket.label
  -- START opens the item tools on every pocket; SELECT opens that pocket's
  -- search -- the same one on every pocket now. The labels are published for
  -- Gen1 Modern UI, which puts a touch button on each of them; nothing is
  -- spelled out on the Bag itself any more.
  state.startActionLabel = "TOOLS"
  state.selectActionLabel = "SEARCH"
  -- Published for Gen1 Modern UI: the order this tab is in.
  state.pocketSortLabel = SORT_LABELS[pocketSortMode(state, pocket.id)]
  -- The amount is drawn on the window's bottom border, off the save, and the
  -- list's own footer is left empty on purpose.  `ListMenu:drawItemBox` opens
  -- the standard full-width text box under the window for any list that has
  -- one -- `if self.messageBox or self.footer` -- so a Bag that parked the
  -- money there got the amount twice: once on the border and once inside a
  -- box the Bag has not had since 1.2.0.  Nothing else reads it.
  list.footer = nil
  restoreCursor(list, rows, preserveId)

  if state.swapId then
    list.hollowIndex = nil
    for i, row in ipairs(rows) do
      if row.value == state.swapId then list.hollowIndex = i break end
    end
    if not list.hollowIndex then state.swapId = nil end
  else
    list.hollowIndex = nil
  end
end

local function switchPocket(list, delta)
  saveCursor(list)
  local state = list.modernBag
  state.swapId = nil
  list.hollowIndex = nil
  local index = state.pocket
  for _ = 1, #POCKETS do
    index = ((index - 1 + delta) % #POCKETS) + 1
    if pocketVisible(state, POCKETS[index]) then break end
  end
  state.pocket = index
  rememberPocket(state)
  refreshPocket(list)
end

-- Load a search into the results page and put the Bag on it.
local function showResults(list, results)
  local state = list.modernBag
  if not state then return end
  saveCursor(list)
  state.swapId = nil
  list.hollowIndex = nil
  state.results = results
  -- A fresh search starts at the top rather than where the last one was left.
  state.cursors.results = { index = 1, scroll = 0 }
  state.pocket = pocketIndexById("results")
  refreshPocket(list)
end

-- Sorting.
--
-- Two different things wear the name, because they order two different lists.
--
-- The item tools re-sort the open pocket once and then leave it alone: they
-- rewrite the order the pocket is drawn from, and MOVE ITEM adjusts what they
-- produced. A saved sort would have to win over every manual move to stay
-- true, which is the opposite of what MOVE ITEM is for -- and up to 1.6.0 it
-- did exactly that on the TM/HM pocket, which was drawn in the saved order and
-- so could not be arranged by hand at all.
--
-- The search keyboard's SORT is a saved preference, because the results page
-- is built fresh from the query every time and has no order to keep.
-- Rewrites the open pocket's slice of the order it is drawn from, leaving
-- every other pocket's items exactly where they were: only the positions this
-- pocket already occupies are written back, in the wanted order.
-- Freezing what is on screen into the order the pocket is stored in, so a
-- hand-arranged order starts from the one you were just looking at rather than
-- from whatever the Bag happened to hold underneath.
--
-- Only the slots this pocket already occupies are written back, in ascending
-- order, so every other pocket keeps its own. The slot list comes out unsorted
-- as soon as a pocket is drawn differently from how it is stored, which pinned
-- rows and every non-CUSTOM mode do.
local function freezeOrder(list)
  local state = list.modernBag
  local pocket = state and POCKETS[state.pocket]
  local rows = list.items or {}
  if not pocket or pocket.transient or #rows < 2 then return false end

  local order
  if pocket.id == "favorites" then
    order = state.favoriteOrder
  else
    order = require("src.inventory.Bag").order(list.game.save)
  end

  local slots, ids = {}, {}
  for _, row in ipairs(rows) do
    local at = positionOf(order, row.value)
    if at then
      slots[#slots + 1] = at
      ids[#ids + 1] = row.value
    end
  end
  if #slots < 2 then return false end
  table.sort(slots)
  for i, slot in ipairs(slots) do order[slot] = ids[i] end

  if pocket.id == "favorites" then
    rebuildPreferenceIndexes(state)
    persistPreferences(state)
  end
  return true
end

-- Choosing an order is a setting for that tab, kept until it is changed again.
local function applyPocketSort(list, mode)
  local state = list.modernBag
  local pocket = state and POCKETS[state.pocket]
  if not pocket or not SORT_VALUES[mode] then return false end
  -- Arranging by hand starts from what is on screen.
  if mode == "CUSTOM" and pocketSortMode(state, pocket.id) ~= "CUSTOM" then
    freezeOrder(list)
  end
  setPocketSort(state, pocket.id, mode)
  pcall(function() require("src.core.Sound").play(list.game.data, "Swap") end)
  refreshPocket(list, selectedId(list))
  return true
end

local function sortMenuRows(bagList)
  local state = bagList.modernBag
  local pocket = state and POCKETS[state.pocket]
  local machines = false
  for _, row in ipairs(bagList.items or {}) do
    if row.modernMachine then machines = true break end
  end
  local rows = {}
  for _, mode in ipairs(SORT_MODES) do
    if sortModeAvailable(mode, pocket, machines) then
      rows[#rows + 1] = {
        label = mode.label,
        onSelect = function() applyPocketSort(bagList, mode.id) end,
      }
    end
  end
  return rows
end

local function openPocketSortMenu(bagList)
  if not (bagList and bagList.modernBag) then return end
  openMenu(bagList.game, "SORT", sortMenuRows(bagList), { ty = SORT_PICKER_TY })
end

-- Moving an item.
--
-- Picking one up carries it: Up and Down walk it through the pocket a row at a
-- time and the list reorders under it as it goes, so the move is what you see
-- rather than something that happens when you finally commit. A places it, B
-- puts it back where it started.
--
-- Up to 1.5.0 this was a two-ended swap -- pick one item, move the cursor,
-- press START on a second, and the two traded places with nothing on screen
-- between. START also opened the item tools, so the key that started a move
-- was the key that ended it.
local function carriedRow(list)
  local id = list.modernBag and list.modernBag.swapId
  if not id then return nil end
  for i, row in ipairs(list.items or {}) do
    if row.value == id then return i end
  end
  return nil
end

local function beginMove(item, list)
  local state = list.modernBag
  if not item or not state then return end
  -- Arranging by hand is what CUSTOM is: in any other mode the pocket would be
  -- re-ordered out from under the move on the next redraw. Switching here
  -- freezes what is on screen, so the arrangement starts from what you see.
  local pocket = POCKETS[state.pocket]
  if pocket and not pocket.transient
     and pocketSortMode(state, pocket.id) ~= "CUSTOM" then
    freezeOrder(list)
    setPocketSort(state, pocket.id, "CUSTOM")
    refreshPocket(list, item.value)
  end
  state.swapId = item.value
  list.hollowIndex = list.index
  -- Where it came from, so B can put it back.
  state.swapRow = carriedRow(list)
end

local function endMove(list, sound)
  local state = list.modernBag
  state.swapId = nil
  state.swapRow = nil
  list.hollowIndex = nil
  if sound then
    pcall(function() require("src.core.Sound").play(list.game.data, sound) end)
  end
  refreshPocket(list, selectedId(list))
end

-- One row, by trading places with the neighbour it is passing. Repeated, that
-- is an insertion: everything the carried item walks past shifts up one.
local function carryStep(list, delta)
  local state = list.modernBag
  local rows = list.items or {}
  local from = carriedRow(list)
  if not from then return false end
  local to = from + delta
  if to < 1 or to > #rows then return false end

  local pocket = POCKETS[state.pocket]
  local order
  if pocket and pocket.id == "favorites" then
    order = state.favoriteOrder
  else
    local Bag = require("src.inventory.Bag")
    order = Bag.order(list.game.save)
  end
  local a = positionOf(order, state.swapId)
  local b = positionOf(order, rows[to].value)
  if not a or not b then return false end
  local function trade()
    order[a], order[b] = order[b], order[a]
    if pocket and pocket.id == "favorites" then
      rebuildPreferenceIndexes(state)
      persistPreferences(state)
    end
    refreshPocket(list, state.swapId)
  end

  trade()
  -- The row it ended on is only where it was asked to go if the pocket's own
  -- order decides it: the TM/HM pocket sorts by SORT and the results page by
  -- the search, and pinned items sort above unpinned ones. Where the step did
  -- not land, put the order back rather than leave it quietly rearranged
  -- underneath a list that will never show it.
  if carriedRow(list) == from then
    trade()
    return false
  end
  return true
end

local function cancelMove(list)
  local state = list.modernBag
  local origin = state.swapRow
  local rows = #(list.items or {})
  -- Walk it back to where it was picked up, bounded so a pocket that will not
  -- reorder cannot spin here.
  for _ = 1, rows do
    local at = carriedRow(list)
    if not at or not origin or at == origin then break end
    if not carryStep(list, origin < at and -1 or 1) then break end
  end
  endMove(list)
end

-- The item being carried takes the hollow cursor, which is the whole of the
-- "you are holding this" state. 1.5.0 set list.hollowIndex for it, which the
-- engine's item-box path does not read, so nothing ever looked picked up.
--
-- LIST_MENU_BOX draws the first item name at y = 32, two rows to an item; the
-- cursor's column is the layout's, because the icons move it one tile left.
local ITEM_ROW_TOP_Y = 32
local ITEM_ROW_H = 16
-- home/list_menu.asm:479-490 -- the 'x' at column 14, the count right-aligned
-- after it -- and the terminator's more-arrow at 144,88.
local ITEM_QTY_X, ITEM_QTY_END = 112, 136
local ITEM_MORE_X, ITEM_MORE_Y = 144, 88

local function drawCarriedCursor(list)
  local row = carriedRow(list)
  if not row then return end
  local visible = row - (list.scroll or 0)
  if visible < 1 or visible > (list.rows or 4) then return end
  local Font = require("src.render.Font")
  local Theme = require("src.ui.Theme")
  local cursorX = layoutOf(list).cursorX
  local y = ITEM_ROW_TOP_Y + (visible - 1) * ITEM_ROW_H
  -- The solid cursor is already drawn on this row; white it out, or the
  -- hollow one lands on top of it and neither reads.
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", cursorX, y, 8, 8)
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawCode(Theme.cursorHollow or Theme.cursor, cursorX, y)
  love.graphics.setColor(1, 1, 1, 1)
end

-- The standard bottom text box, which the item-box path draws under the
-- window whenever there is a footer or a message to put in it. Last two lines
-- of what it is given, like the GB's own scrolled box -- `src/ui/ListMenu.lua`
-- keeps this as a local, so redrawing the window means carrying a copy of it.
local function drawListMessageBox(list, Font)
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  if not list.footer then return end
  local ok, TextBox = pcall(require, "src.render.TextBox")
  if not ok or type(TextBox) ~= "table"
      or type(TextBox.paginate) ~= "function" then
    return
  end
  local flat = {}
  for _, page in ipairs(TextBox.paginate(list.footer)) do
    for _, line in ipairs(page) do flat[#flat + 1] = line end
  end
  local y = 112
  for i = math.max(1, #flat - 1), #flat do
    Font.draw(flat[i], 8, y)
    y = y + 16
  end
end

-- ------- the item window, when it is the one with icons in it
--
-- Drawn here rather than by the engine, and only in the icons layout. With
-- the icons off this is not called at all and `ListMenu:drawItemBox` draws
-- the Bag exactly as it always has -- which is the point of it being a
-- setting, and the reason the switch cannot cost anybody a frame of the
-- window they had.
--
-- Everything below is `src/ui/ListMenu.lua`'s own item-box draw with the four
-- x-positions taken from the layout instead of from its constants: the same
-- box, the same four rows sixteen apart, the same 'x' at column 14 with the
-- count right-aligned after it, the same more-arrow on the terminator, the
-- same bottom text box. Nothing about WHAT is drawn changes, only where two
-- of the columns are -- so a row that reads oddly here reads oddly with the
-- icons off too, and is the engine's to fix rather than this file's.
--
-- The one addition is the trim. The engine prints an item name unclipped
-- because at x = 48 nothing in the game is long enough to reach the frame;
-- from x = 56 a thirteen-glyph name from a mod would print over the border,
-- so it is cut to the column budget the same way every other label in this
-- file is.
local function drawItemWindow(list, icons)
  local Font = require("src.render.Font")
  local Theme = require("src.ui.Theme")
  local Strings = require("src.core.Strings")
  local box = layoutOf(list)
  local rows = list.rows or 4
  local budget = (box.tx + box.tw - 1) * 8 - box.nameX

  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(box.tx, box.ty, box.tw, box.th)
  love.graphics.setColor(0, 0, 0, 1)
  if #list.items == 0 then
    Font.draw(Strings("Nothing here."), box.nameX, ITEM_ROW_TOP_Y)
  end

  local shown, sawCancel = 0, false
  for row = 1, rows do
    local i = (list.scroll or 0) + row
    local item = list.items[i]
    if not item then break end
    shown = shown + 1
    if item.cancel then sawCancel = true end
    local y = ITEM_ROW_TOP_Y + (row - 1) * ITEM_ROW_H
    if box.iconX and icons then
      icons.drawFor(list.game, item.value, box.iconX, y + (box.iconY or 0))
    end
    -- The column rule, on every row including CANCEL: it divides two columns
    -- rather than decorating an item, and one with gaps in it where a row
    -- happens to have no picture reads as damage. A row's full height, so
    -- consecutive rows join into one line and the line stops where the list
    -- does.
    if box.ruleX then
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", box.ruleX, y, 1, ITEM_ROW_H)
    end
    Font.draw(fitLabel(Font, tostring(item.label or ""), budget), box.nameX, y)
    if item.sub then
      Font.draw(item.sub, ITEM_QTY_X, y + 8)
    elseif item.right then
      local count = item.right:sub(2)
      Font.draw(item.right:sub(1, 1), ITEM_QTY_X, y + 8)
      Font.draw(count, ITEM_QTY_END - Font.width(count), y + 8)
    end
    if i == list.index then
      Font.drawCode(list.hollowIndex == i
                    and Theme.cursorHollow or Theme.cursor, box.cursorX, y)
    end
    if list.swapIndex == i and i ~= list.index then
      Font.drawCode(Theme.cursorHollow, box.cursorX, y)
    end
  end

  -- the terminator prints CANCEL and returns before the '▼'
  if shown == rows and not sawCancel then
    Font.drawCode(Theme.moreArrow, ITEM_MORE_X, ITEM_MORE_Y)
  end
  if list.messageBox or list.footer then drawListMessageBox(list, Font) end
  love.graphics.setColor(1, 1, 1, 1)
end

-- SORT orders the whole result list. NAME goes by displayed name; the machine
-- modes group the machines first, in that order, and leave everything else
-- after them by name -- a POTION has no machine number and no base power.
local function sortSearchRows(rows, state)
  -- The results page is a pocket like any other as far as its order goes.
  orderRowsBy(rows, pocketSortMode(state, "results"))
end

local function searchRows(game, query, state)
  local Bag = require("src.inventory.Bag")
  local wanted = normalizedSearch(query)
  local rows = {}
  local favoriteSet = state and state.favoriteSet or {}
  local pinnedSet = state and state.pinnedSet or {}
  for _, id in ipairs(Bag.order(game.save)) do
    local count = countOf(game.save, id)
    if count > 0 then
      local def = game.data.items[id]
      local name = (def and def.name) or id
      local markers = (pinnedSet[id] and "P" or "")
        .. (favoriteSet[id] and "F" or "")
      local info = def and def.machine and machineInfo(game, id, def) or nil
      local label = name
      local haystack = normalizedSearch(name .. " " .. id)
      if info then
        -- A machine answers to its code, its move, and that move's type and
        -- damage class; and it is listed by its move, not by "TM24".
        haystack = haystack .. info.searchKey
        label = compactMachineLabel(info, markers, layoutFor(state))
      end
      if wanted == "" or haystack:find(wanted, 1, true) then
        rows[#rows + 1] = {
          label = label,
          right = (markers ~= "" and (markers .. " ") or "") .. "x" .. tostring(count),
          value = id,
          modernPocket = pocketIndexFor(id, def),
          modernMachine = info,
          modernCount = count,
          modernSort = normalizedSearch(name) .. "\0" .. tostring(id),
        }
      end
    end
  end
  sortSearchRows(rows, state)
  return rows
end

local SEARCH_GRID = {
  { "A", "B", "C", "D", "E", "F", "G", "H", "I" },
  { "J", "K", "L", "M", "N", "O", "P", "Q", "R" },
  { "S", "T", "U", "V", "W", "X", "Y", "Z", "0" },
  { "1", "2", "3", "4", "5", "6", "7", "8", "9" },
  { "DEL", "CLR", "GO", "EXIT" },
}

-- Rows one to four are one glyph per key. The last is words, and is measured
-- and centred instead of laid out on the letters' pitch.
local KEYBOARD_GLYPH_ROWS = 4

-- The search keyboard.
--
-- 1.1.1 drew this as a bare white page. There was no frame; the three header
-- lines sat on a 12px pitch the 8px font does not land on; and the last row --
-- DEL, CLR, GO and EXIT, which are words rather than single glyphs -- was laid
-- out on the same 16px pitch as the letters, so the four keys were drawn on
-- top of one another and read as "DECLBOEXIT".
--
-- The screen is now one framed window with everything on the 8px grid. Its
-- title sits on the window's top border, the letters keep a cell per key with
-- the cursor in the column to the left of the glyph, and the action row is
-- measured and centred so no two words can share a column whatever the font.
local KEYBOARD_LEFT_X = WINDOW_LEFT_X
local KEYBOARD_INNER_W = WINDOW_INNER_W
local KEYBOARD_CELL_W = 16     -- cursor column + glyph column
-- A row below the window's first interior row, so the query is not crowded up
-- against the title on the border above it.
local KEYBOARD_HEADER_Y = WINDOW_TOP_Y + 8
local KEYBOARD_GRID_TOP = 40
local KEYBOARD_ROW_H = 16
-- The one word row, low enough to sit clear of the grid. What is left over
-- falls either side of it: a row above FIND, two between FIND and the letters,
-- two between the letters and this, and two below.
local KEYBOARD_WORD_ROW_Y = { 112 }

local function drawKeyboardGrid(screen, Font, Theme)
  for r = 1, KEYBOARD_GLYPH_ROWS do
    local y = KEYBOARD_GRID_TOP + (r - 1) * KEYBOARD_ROW_H
    for c, key in ipairs(SEARCH_GRID[r]) do
      local x = KEYBOARD_LEFT_X + (c - 1) * KEYBOARD_CELL_W
      if r == screen.row and c == screen.col then Font.drawCode(Theme.cursor, x, y) end
      Font.draw(key, x + 8, y)
    end
  end

  -- The word rows are measured: laid out on the letters' 16px pitch, DEL and
  -- CLR and GO and EXIT would be drawn on top of one another.
  for r = KEYBOARD_GLYPH_ROWS + 1, #SEARCH_GRID do
    local keys = SEARCH_GRID[r]
    local y = KEYBOARD_WORD_ROW_Y[r - KEYBOARD_GLYPH_ROWS]
    if y then
      local run = 0
      for _, key in ipairs(keys) do run = run + 8 + Font.width(key) end
      -- Centre the measured run on the 8px column grid the rest of the box uses.
      local x = KEYBOARD_LEFT_X
        + math.max(0, math.floor((KEYBOARD_INNER_W - run) / 16)) * 8
      for c, key in ipairs(keys) do
        if r == screen.row and c == screen.col then Font.drawCode(Theme.cursor, x, y) end
        Font.draw(key, x + 8, y)
        x = x + 8 + Font.width(key)
      end
    end
  end
end

local function drawSearchKeyboard(screen, headerLines)
  local Font = require("src.render.Font")
  local Theme = require("src.ui.Theme")
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(WINDOW_BOX.tx, WINDOW_BOX.ty, WINDOW_BOX.tw, WINDOW_BOX.th)
  drawBorderLabel(Font, tostring(screen.title or ""),
    WINDOW_BOX.tx, WINDOW_BOX.ty, WINDOW_BOX.tw)
  love.graphics.setColor(0, 0, 0, 1)
  local y = KEYBOARD_HEADER_Y
  for _, line in ipairs(headerLines) do
    Font.draw(line, KEYBOARD_LEFT_X, y)
    y = y + 8
  end
  drawKeyboardGrid(screen, Font, Theme)
  love.graphics.setColor(1, 1, 1, 1)
end

local QuickSearch = {}
QuickSearch.__index = QuickSearch
QuickSearch.isOpaque = true

local function syncSearchQuery(state)
  state.query = table.concat(state.glyphs or {})
  return state.query
end

function QuickSearch.new(game, bagList)
  return setmetatable({
    screenId = QUICK_SEARCH_SCREEN_ID,
    game = game,
    bagList = bagList,
    title = "QUICK SEARCH",
    query = "",
    glyphs = {},
    maxLen = SEARCH_QUERY_LIMIT,
    row = 1,
    col = 1,
    lower = false,
    modernBagSearchKeyboard = true,
    modernBagSearchActionLabel = "SEARCH",
    modernBagSearchHint = "A TYPE   B DELETE/EXIT   SELECT CLEAR   START SEARCH",
  }, QuickSearch)
end

function QuickSearch:grid()
  return SEARCH_GRID
end

function QuickSearch:close()
  if self.game.stack:top() == self then self.game.stack:pop() end
end

local function searchSound(game, name)
  pcall(function() require("src.core.Sound").play(game.data, name) end)
end

-- GO does not open a page of its own. The matches are loaded into the Bag's
-- results page and the Bag is put on it, so they are read where every other
-- item is read -- in the item window, with the pocket header, the counts and
-- the markers -- instead of on an undecorated full-screen list.
function QuickSearch:openResults()
  syncSearchQuery(self)
  local bag = self.bagList
  local query = self.query
  self:close()
  if not bag or not bag.modernBag then return end
  showResults(bag, {
    query = query,
    build = function(game, state) return searchRows(game, query, state) end,
  })
end

function QuickSearch:activateCurrentKey()
  local row = SEARCH_GRID[self.row]
  local key = row and row[self.col]
  if not key then return false end
  if key == "DEL" then
    table.remove(self.glyphs)
  elseif key == "CLR" then
    self.glyphs = {}
  elseif key == "GO" then
    self:openResults()
    return true
  elseif key == "EXIT" then
    self:close()
    return true
  elseif #self.glyphs < SEARCH_QUERY_LIMIT then
    self.glyphs[#self.glyphs + 1] = key
  end
  syncSearchQuery(self)
  return true
end

function QuickSearch:update(dt)
  local input = self.game.input
  local row = SEARCH_GRID[self.row]
  if input:wasPressed("left") then
    self.col = ((self.col - 2) % #row) + 1
  elseif input:wasPressed("right") then
    self.col = (self.col % #row) + 1
  elseif input:wasPressed("up") then
    self.row = ((self.row - 2) % #SEARCH_GRID) + 1
    self.col = math.min(self.col, #SEARCH_GRID[self.row])
  elseif input:wasPressed("down") then
    self.row = (self.row % #SEARCH_GRID) + 1
    self.col = math.min(self.col, #SEARCH_GRID[self.row])
  elseif input:wasPressed("select") then
    self.glyphs = {}
    syncSearchQuery(self)
    searchSound(self.game, "Swap")
  elseif input:wasPressed("start") then
    searchSound(self.game, "Press_AB")
    self:openResults()
  elseif input:wasPressed("b") then
    searchSound(self.game, "Press_AB")
    if #self.glyphs > 0 then
      table.remove(self.glyphs)
      syncSearchQuery(self)
    else
      self:close()
    end
  elseif input:wasPressed("a") then
    searchSound(self.game, "Press_AB")
    self:activateCurrentKey()
  end
end

-- The sort applies to the results and is the Bag's own saved preference, so
-- the picker writes it straight through and re-sorts the open pocket.
function QuickSearch:draw()
  drawSearchKeyboard(self, {
    -- "FIND: " plus the twelve glyphs the query is capped at is eighteen.
    "FIND: " .. (self.query == "" and "ALL" or self.query),
  })
end

local function openQuickSearch(list)
  local state = list.modernBag
  state.swapId = nil
  list.hollowIndex = nil
  list.game.stack:push(QuickSearch.new(list.game, list))
end


local function wrapWords(text, width, maxLines)
  local lines, current = {}, ""
  for word in tostring(text or ""):gmatch("%S+") do
    local candidate = current == "" and word or (current .. " " .. word)
    if #candidate > width and current ~= "" then
      lines[#lines + 1] = current
      current = word
      if maxLines and #lines >= maxLines then break end
    else
      current = candidate
    end
  end
  if current ~= "" and (not maxLines or #lines < maxLines) then lines[#lines + 1] = current end
  if #lines == 0 then lines[1] = "--" end
  return lines
end

local MoveInfoScreen = {}
MoveInfoScreen.__index = MoveInfoScreen
MoveInfoScreen.isOpaque = true

function MoveInfoScreen.new(game, id)
  return setmetatable({
    screenId = MOVE_INFO_SCREEN_ID,
    game = game,
    id = id,
    info = machineInfo(game, id),
  }, MoveInfoScreen)
end

function MoveInfoScreen:update(dt)
  local input = self.game.input
  if input:wasPressed(INFO_ACTION) or input:wasPressed("b")
     or input:wasPressed("a") or input:wasPressed("start") then
    self.game.stack:pop()
  end
end

-- Move Information.
--
-- The last of the mod's screens to be drawn as a bare white page: no frame,
-- and eleven lines on a 14px pitch the 8px font does not land on, so every row
-- but one sat between the rows the rest of the game draws on. A machine with
-- no move data also escaped through an early return that never put the draw
-- colour back, leaving black set for whatever drew next.
--
-- It is the same screen-filling window the search keyboard uses, titled on
-- its top border, with the sixteen interior rows spent on the machine and its
-- move, the five stats, the effect over four wrapped lines and the way out --
-- each block separated by a blank row.
local INFO_MOVE_Y = WINDOW_TOP_Y              --   8
local INFO_STATS_Y = WINDOW_TOP_Y + 16        --  24
local INFO_EFFECT_LABEL_Y = WINDOW_TOP_Y + 64 --  72
local INFO_EFFECT_Y = WINDOW_TOP_Y + 72       --  80
local INFO_EFFECT_LINES = 4
local INFO_EFFECT_COLS = 18
local INFO_BACK_HINT = "Y/I OR A/B BACK"

function MoveInfoScreen:draw()
  local Font = require("src.render.Font")
  local info = self.info
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(WINDOW_BOX.tx, WINDOW_BOX.ty, WINDOW_BOX.tw, WINDOW_BOX.th)
  drawBorderLabel(Font, "MOVE INFORMATION",
    WINDOW_BOX.tx, WINDOW_BOX.ty, WINDOW_BOX.tw)
  love.graphics.setColor(0, 0, 0, 1)

  if info then
    -- Four for the code, two for the gap, twelve for the longest Gen 1 move
    -- name: eighteen, which is the interior exactly.
    Font.draw(info.code .. "  " .. info.name, WINDOW_LEFT_X, INFO_MOVE_Y)
    local stats = {
      "TYPE: " .. info.typeLabel,
      "CLASS: " .. info.damageClass,
      "POWER: " .. (info.power > 0 and tostring(info.power) or "--"),
      "ACCURACY: " .. (info.accuracy and (tostring(info.accuracy) .. "%") or "--"),
      "PP: " .. tostring(info.pp),
    }
    for i, line in ipairs(stats) do
      Font.draw(line, WINDOW_LEFT_X, INFO_STATS_Y + (i - 1) * 8)
    end
    Font.draw("EFFECT:", WINDOW_LEFT_X, INFO_EFFECT_LABEL_Y)
    local lines = wrapWords(info.effect, INFO_EFFECT_COLS, INFO_EFFECT_LINES)
    for i = 1, math.min(#lines, INFO_EFFECT_LINES) do
      Font.draw(lines[i], WINDOW_LEFT_X, INFO_EFFECT_Y + (i - 1) * 8)
    end
  else
    Font.draw("NO MOVE DATA", WINDOW_LEFT_X, INFO_MOVE_Y)
  end

  Font.draw(INFO_BACK_HINT, WINDOW_LEFT_X, WINDOW_BOTTOM_Y)
  love.graphics.setColor(1, 1, 1, 1)
end

local function openMoveInfo(game, id)
  if not id then return end
  game.stack:push(MoveInfoScreen.new(game, id))
end

local function machineFilters(state)
  if type(state.machineFilters) ~= "table" then
    state.machineFilters = { query = "", type = "ANY", damageClass = "ANY" }
  end
  return state.machineFilters
end

local function machineFilteredRows(game, state)
  local filters = machineFilters(state)
  local wanted = normalizedSearch(filters.query)
  local rows = {}
  for _, row in ipairs(itemRows(game, "machines", state)) do
    local info = row.modernMachine
    if info and (wanted == "" or info.searchKey:find(wanted, 1, true))
       and (filters.type == "ANY" or info.typeLabel == filters.type)
       and (filters.damageClass == "ANY" or info.damageClass == filters.damageClass) then
      rows[#rows + 1] = row
    end
  end
  return rows
end

local function openItemTools(item, list)
  if not item or not list or not list.modernBag then return end
  local state = list.modernBag
  local id = item.value
  local favorite = state.favoriteSet[id] ~= nil
  local pinned = state.pinnedSet[id] ~= nil

  local function swapSound()
    pcall(function() require("src.core.Sound").play(list.game.data, "Swap") end)
  end

  -- No title: rows that name themselves do not need one.
  --
  -- Menu closes itself around onSelect unless the row asks to stay open, so
  -- none of these close it by hand. Nothing here depends on which side of
  -- onSelect that happens.
  openMenu(list.game, nil, {
    -- Ordering first: it is about the whole pocket rather than this item.
    { label = "SORT", onSelect = function() openPocketSortMenu(list) end },
    {
      label = favorite and "REMOVE FAVORITE" or "ADD FAVORITE",
      onSelect = function()
        toggleOrderedItem(state.favoriteOrder, id)
        rebuildPreferenceIndexes(state)
        persistPreferences(state)
        swapSound()
        refreshPocket(list, id)
      end,
    },
    {
      label = pinned and "UNPIN ITEM" or "PIN TO TOP",
      onSelect = function()
        toggleOrderedItem(state.pinnedOrder, id)
        rebuildPreferenceIndexes(state)
        persistPreferences(state)
        swapSound()
        refreshPocket(list, id)
      end,
    },
    { label = "MOVE ITEM", onSelect = function() beginMove(item, list) end },
    { label = "CANCEL" },
  }, { ty = ITEM_TOOLS_TY })
end

-- START opens the tools for the item under the cursor. It cannot land a move
-- any more: a carry is confirmed with A, and START is swallowed while one is
-- in progress so the tools cannot open on top of it.
local function openBagTools(list)
  local item = list.items and list.items[list.index or 1]
  if item then openItemTools(item, list) end
end

local function decorateBag(game, opts, list, mod, icons)
  if type(list) ~= "table" or list.modernBag then return list end

  local baseUpdate = list.update
  local baseDraw = list.draw
  if type(baseUpdate) ~= "function" or type(baseDraw) ~= "function" then
    return list
  end

  local preferences = loadPreferenceState(mod)
  local initialPocket = openingPocketIndex(mod)
  local repeatConfig = scrollConfig(mod)
  -- Nothing is filed on open. Every pocket starts in A-Z and is drawn that way
  -- from the items themselves, so the stored order is only ever the CUSTOM one
  -- -- and opening the Bag cannot undo an arrangement it never touches.
  pruneBagOrder(game)
  list.modernBag = {
    pocket = initialPocket,
    cursors = {},
    swapId = nil,
    battle = opts and opts.battle or nil,
    inventorySignature = inventorySignature(game),
    mod = mod,
    favoriteOrder = preferences.favoriteOrder,
    favoriteSet = preferences.favoriteSet,
    pinnedOrder = preferences.pinnedOrder,
    pinnedSet = preferences.pinnedSet,
    pocketSort = preferences.pocketSort,
    machineFilters = { query = "", type = "ANY", damageClass = "ANY" },
    searchAvailable = true,
    -- The item icons, or nil when there are none to draw. Loaded once per
    -- install (see loadIcons) and carried on the state so the drawing code
    -- reaches them through the list it is already given.
    icons = icons,
    startActionLabel = "TOOLS",
    selectActionLabel = "SEARCH",
  }
  list.pageJump = false

  -- Gen1Recomp ListMenu has native hold-to-scroll support. Enabling it here
  -- keeps remapped keyboards/controllers and future input backends working
  -- through the engine's own input state instead of polling device keys.
  list.keyRepeat = repeatConfig.enabled
  list.repeatDelay = repeatConfig.delay
  list.repeatRate = repeatConfig.rate
  list.holdDir = nil
  list.holdFrames = 0

  function list:update(dt)
    local state = self.modernBag
    local signature = inventorySignature(self.game)
    if state and signature ~= state.inventorySignature then
      pruneBagOrder(self.game)
      state.inventorySignature = inventorySignature(self.game)
    end

    local current = selectedId(self)
    refreshPocket(self, current)
    local input = self.game.input
    local pocket = POCKETS[state.pocket]

    -- Carrying an item takes the D-pad and A over: Up and Down walk it, A puts
    -- it down, B puts it back. START is swallowed so the tools cannot open on
    -- top of a move. Left/Right still change pocket, and that drops the carry.
    if state.swapId then
      if input:wasPressed("up") then
        carryStep(self, -1)
        return
      elseif input:wasPressed("down") then
        carryStep(self, 1)
        return
      elseif input:wasPressed("a") then
        endMove(self, "Swap")
        return
      elseif input:wasPressed("b") then
        cancelMove(self)
        return
      elseif input:wasPressed("start") then
        return
      end
    end

    if input:wasPressed(INFO_ACTION) then
      -- Machine data, not the pocket, is what decides this: a TM reached
      -- through FAVORITES or the results page answers Y/I the same way it
      -- does in TM/HM.
      local id = selectedId(self)
      if id and machineInfo(self.game, id) then
        openMoveInfo(self.game, id)
        return
      end
    end
    if input:wasPressed("select") then
      -- The same search on every pocket. A machine answers to its move, its
      -- type and its damage class, so TM/HM needs no search of its own.
      openQuickSearch(self)
      return
    elseif input:wasPressed("start") then
      openBagTools(self)
      return
    elseif input:wasPressed("left") then
      switchPocket(self, -1)
      return
    elseif input:wasPressed("right") then
      switchPocket(self, 1)
      return
    end
    baseUpdate(self, dt)
    if self.modernBag then saveCursor(self) end
  end

  function list:draw()
    -- The wider window is drawn here; the engine's own is drawn by the engine.
    -- Which one it is is asked every frame, so ITEM ICONS switches the Bag on
    -- the next frame rather than on the next boot -- and an item-box list this
    -- mod never decorated (a build that draws its own) is left to whatever
    -- draws it.
    if self.itemBox and layoutOf(self).iconX then
      drawItemWindow(self, self.modernBag.icons)
    else
      baseDraw(self)
    end
    -- Only the item-box path leaves the title and footer rows unpainted. If a
    -- build ever draws them itself, leave it alone rather than doubling up.
    if self.itemBox then
      drawPocketHeader(self)
      drawBagMoney(self)
      if self.modernBag and self.modernBag.swapId then drawCarriedCursor(self) end
    end
  end

  refreshPocket(list)
  return list
end

local function pressInfoAction(input, source)
  if type(input.sourcePress) == "function" then
    input:sourcePress(INFO_ACTION, source)
  elseif type(input.pressQueue) == "table" then
    input.pressQueue[#input.pressQueue + 1] = INFO_ACTION
  end
end

local function releaseInfoAction(input, source)
  if type(input.sourceRelease) == "function" then
    input:sourceRelease(INFO_ACTION, source)
  elseif type(input.state) == "table" then
    input.state[INFO_ACTION] = false
  end
end

local function installMoveInfoBindings(input)
  if type(input) ~= "table" then return false end
  local patch = rawget(_G, INPUT_PATCH_KEY)
  if not patch then
    patch = {
      baseKeyPressed = input.keypressed,
      baseKeyReleased = input.keyreleased,
      basePadPressed = input.gamepadpressed,
      basePadReleased = input.gamepadreleased,
    }
    rawset(_G, INPUT_PATCH_KEY, patch)

    if type(input.keypressed) == "function" then
      input.keypressed = function(self, key, ...)
        local result = patch.baseKeyPressed(self, key, ...)
        if key == "i" then pressInfoAction(self, "modern-bag-key:i") end
        return result
      end
    end
    if type(input.keyreleased) == "function" then
      input.keyreleased = function(self, key, ...)
        local result = patch.baseKeyReleased(self, key, ...)
        if key == "i" then releaseInfoAction(self, "modern-bag-key:i") end
        return result
      end
    end
    if type(input.gamepadpressed) == "function" then
      input.gamepadpressed = function(self, joystick, button, ...)
        local result = patch.basePadPressed(self, joystick, button, ...)
        if button == "y" then pressInfoAction(self, "modern-bag-pad:y") end
        return result
      end
    end
    if type(input.gamepadreleased) == "function" then
      input.gamepadreleased = function(self, joystick, button, ...)
        local result = patch.basePadReleased(self, joystick, button, ...)
        if button == "y" then releaseInfoAction(self, "modern-bag-pad:y") end
        return result
      end
    end
  end
  return true
end

local function installUnlimitedInventory(Bag, game, mod)
  if type(Bag) ~= "table" then return false end

  -- Compatibility with older engine builds that exposed a writable constant.
  Bag.CAPACITY = math.huge

  -- Current builds read the distinct-slot capacity from Data.constants.
  game.data.constants = game.data.constants or {}
  game.data.constants.bagSize = 2147483647

  local patch = rawget(_G, BAG_PATCH_KEY)
  if not patch then
    patch = {
      baseAdd = Bag.add,
      baseCapacity = Bag.capacity,
    }
    rawset(_G, BAG_PATCH_KEY, patch)

    if type(Bag.capacity) == "function" then
      Bag.capacity = function()
        return math.huge
      end
    end

    if type(Bag.add) == "function" then
      Bag.add = function(save, id, qty, data)
        local handler = patch.add
        if handler then return handler(save, id, qty, data) end
        return patch.baseAdd(save, id, qty, data)
      end
    end
  end

  patch.add = function(save, id, qty, data)
    if type(save) ~= "table" or type(save.inventory) ~= "table"
       or type(id) ~= "string" or id == "" then
      return patch.baseAdd(save, id, qty, data)
    end

    local amount = qty == nil and 1 or tonumber(qty)
    if not amount or amount <= 0 then
      return patch.baseAdd(save, id, qty, data)
    end
    amount = math.floor(amount)

    local inventory = save.inventory
    local isNew = inventory[id] == nil
    inventory[id] = (tonumber(inventory[id]) or 0) + amount

    local badge = type(Bag.isBadge) == "function"
                  and Bag.isBadge(id)
                  or id:find("BADGE", 1, true) ~= nil
    if isNew and not badge then
      table.insert(Bag.order(save), id)
    end
    return true
  end

  return true
end

local function modernMoveInfoModel(state)
  local info = state.info
  if not info then
    return {
      title = "MOVE INFORMATION",
      rows = { { label = "NO MOVE DATA", enabled = false } },
      index = 1,
      scroll = 0,
      footer = { "A/B BACK" },
    }
  end
  return {
    title = "MOVE INFORMATION",
    rows = {
      { label = info.code .. "  " .. info.name, header = true, enabled = false },
      { label = "TYPE", value = info.typeLabel, enabled = false },
      { label = "CLASS", value = info.damageClass, enabled = false },
      { label = "POWER", value = info.power > 0 and tostring(info.power) or "--",
        enabled = false },
      { label = "ACCURACY", value = info.accuracy
          and (tostring(info.accuracy) .. "%") or "--", enabled = false },
      { label = "PP", value = tostring(info.pp), enabled = false },
      { label = "EFFECT", header = true, enabled = false },
      { label = info.effect or "--", enabled = false },
    },
    index = 1,
    scroll = 0,
    footer = { "Y/I OR A/B BACK" },
  }
end

local modernUiContract = {
  apiVersion = 1,
  screens = {
    gen1_modern_bag_move_info = {
      match = function(state)
        return type(state) == "table" and state.screenId == MOVE_INFO_SCREEN_ID
          and state.game ~= nil
      end,
      canSuppressNative = true,
      model = function(_, state) return modernMoveInfoModel(state) end,
      actions = {
        select = function(_, state)
          state.game.stack:pop()
          return true
        end,
        start = function(_, state)
          state.game.stack:pop()
          return true
        end,
        back = function(_, state)
          state.game.stack:pop()
          return true
        end,
      },
    },
  },
}

-- ------- the icon set
--
-- A file this mod ships, compiled in this mod's own sandbox. `mod:read` plus
-- `load` is the documented way to reach one: a mod's directory is not on
-- package.path, and require() would only find it by accident of where the mod
-- happens to be installed.
--
-- Nil is an ordinary answer -- an older host with no `mod:read`, or an
-- install that dropped assets/ -- and the Bag draws the window it always drew.
local function loadIcons(mod)
  if type(mod.read) ~= "function" then return nil end
  local ok, source = pcall(mod.read, mod, "icons.lua")
  if not ok or not source then return nil end
  local chunk = load(source, "@" .. tostring(mod.path) .. "/icons.lua")
  if not chunk then return nil end
  local built, icons = pcall(chunk)
  if not built or type(icons) ~= "function" then return nil end
  local made, value = pcall(icons, mod)
  if not made or type(value) ~= "table" then return nil end
  return value
end

return function(mod)
  if mod.options and type(mod.options.define) == "function" then
    mod.options:define({
      {
        key = "opening_pocket",
        type = "choice",
        -- Set in the game's own voice, which is capitals: every other row in
        -- this mod's own pocket table above, and every row every other mod in
        -- the set puts in the manager, is written that way.  These were the
        -- one screen in the suite that was not, which reads as a different
        -- mod's settings sitting in the middle of the list.  The pocket names
        -- here are the pocket names from POCKETS, to the character, so the row
        -- says the same word as the tab it selects.
        label = "OPENING POCKET",
        default = "medicine",
        choices = {
          { "FAVORITES", "favorites" },
          { "MEDICINE", "medicine" },
          { "BALLS", "balls" },
          { "TM/HM", "machines" },
          { "BATTLE", "battle" },
          { "KEY ITEMS", "key" },
          { "OTHER", "other" },
          { "LAST USED", "last" },
        },
      },
      {
        key = "hold_scroll_speed",
        type = "choice",
        label = "HOLD SCROLL",
        -- OFF, so a press is a row and nothing repeats on its own.  Any
        -- hold-to-scroll setting has a threshold, and the threshold is the
        -- problem: a press either crosses it or does not, so the same press
        -- is one step or a run of them depending on how long a finger rests,
        -- which reads as the list moving by itself rather than as a speed.
        -- NORMAL, FAST and VERY FAST are all still here for anyone who wants
        -- a hold to scroll; none of them is what an unconfigured Bag does.
        default = "off",
        choices = {
          { "OFF", "off" },
          { "NORMAL", "normal" },
          { "FAST", "fast" },
          { "VERY FAST", "very_fast" },
        },
      },
      {
        key = "item_icons",
        type = "toggle",
        label = "ITEM ICONS",
        -- A picture of every item in the column between the cursor and the
        -- name. It is a switch because it is the one setting here that moves
        -- the window: the icons need a column the engine's own does not have,
        -- so the Bag grows a tile at the left to hold one (see LAYOUTS). Off
        -- is the window every release up to 1.9.4 drew, to the pixel.
        default = true,
      },
    })
  end
  local modernUiExports
  local modernUiRegistered = false
  local function ensureModernUiAdapter()
    if type(mod.find) ~= "function" then return false end
    local okFind, handle = pcall(mod.find, "gen1_modern_ui")
    if not okFind or type(handle) ~= "table" or type(handle.exports) ~= "table" then
      modernUiExports, modernUiRegistered = nil, false
      return false
    end
    local ex = handle.exports
    if tonumber(ex.compatibilityApiVersion or 1) ~= 1
        or type(ex.registerAdapter) ~= "function" then
      modernUiExports, modernUiRegistered = ex, false
      return false
    end
    if modernUiRegistered and modernUiExports == ex then return true end
    local ok, registered, reason = pcall(ex.registerAdapter, {
      owner = "gen1_modern_bag",
      version = "1.6.0",
      contract = modernUiContract,
    })
    if ok and registered ~= false then
      modernUiExports, modernUiRegistered = ex, true
      return true
    end
    modernUiExports, modernUiRegistered = ex, false
    if mod.log then
      mod.log:warn("Gen1 Modern UI adapter unavailable: %s",
        tostring(ok and reason or registered))
    end
    return false
  end

  mod.exports.gen1ModernUi = modernUiContract
  mod.exports.ensureModernUiAdapter = ensureModernUiAdapter
  mod.exports.openingPocketIndex = function()
    return openingPocketIndex(mod)
  end
  mod.exports.scrollConfig = function()
    local cfg = scrollConfig(mod)
    return { enabled = cfg.enabled, delay = cfg.delay, rate = cfg.rate }
  end

  -- Loaded once, at install, and carried onto every Bag this mod decorates.
  -- The images themselves are still loaded lazily, the first time a row asks
  -- for one; what is built here is only the thing that knows how to find them.
  local icons = loadIcons(mod)
  if not icons then
    mod.log:info("Gen1ModernBag found no item icons; the Bag draws its rows without them")
  end

  mod.events:on("game.ready", function(event)
    local game = event and event.game
    if not game then
      mod.log:warn("Gen1ModernBag could not install: game.ready had no game object; restart with the mod enabled")
      return
    end

    ensureModernUiAdapter()

    if not installMoveInfoBindings(game.input) then
      mod.log:warn("Gen1ModernBag could not bind Y / I for move information")
    end

    -- Remove both vanilla inventory limits: the number of distinct item ids
    -- and the 99-unit cap for each individual stack. Item effects and removal
    -- still run through the engine's normal inventory functions.
    local bagOk, Bag = pcall(require, "src.inventory.Bag")
    if not bagOk or not installUnlimitedInventory(Bag, game, mod) then
      mod.log:warn("Gen1ModernBag could not remove inventory limits; src.inventory.Bag was unavailable")
    end

    local ok, BagMenu = pcall(require, "src.ui.BagMenu")
    if not ok or type(BagMenu) ~= "table" or type(BagMenu.new) ~= "function" then
      mod.log:warn("Gen1ModernBag could not find src.ui.BagMenu; check game compatibility and restart")
      return
    end

    local dispatch = rawget(_G, PATCH_KEY)
    if not dispatch then
      dispatch = { baseNew = BagMenu.new }
      rawset(_G, PATCH_KEY, dispatch)
      BagMenu.new = function(currentGame, opts)
        local list = dispatch.baseNew(currentGame, opts)
        local decorator = dispatch.decorate
        if decorator then return decorator(currentGame, opts, list) end
        return list
      end
    end
    dispatch.decorate = function(currentGame, opts, list)
      return decorateBag(currentGame, opts, list, mod, icons)
    end
    mod.log:info("Gen1ModernBag installed with " .. tostring(#POCKETS)
      .. " pockets, configurable opening pocket, hold scrolling, favorites, pinned items, TM/HM filters, move data, power sorting and unlimited inventory")
  end)

  -- Published like every other capability here: a sibling with a place for an
  -- item's picture -- a held-item row, a shop, a PC list -- can draw one
  -- without carrying a copy of the set. Nil for an item that has no icon,
  -- which every caller has to handle anyway.
  mod.exports.itemIcon = function(game, id)
    if not icons then return nil end
    return icons.of(game, id)
  end
  mod.exports.drawItemIcon = function(game, id, x, y)
    if not icons then return nil end
    return icons.drawFor(game, id, x, y)
  end

  mod.exports.pocketFor = pocketFor
  mod.exports.autoSort = function(game)
    return autoSortBag(game, loadPreferenceState(mod))
  end
  mod.exports.search = function(game, query)
    return searchRows(game, query, loadPreferenceState(mod))
  end
  mod.exports.machineInfo = function(game, id)
    return machineInfo(game, id)
  end
  mod.exports.machineRows = function(game, filters, sortMode)
    local state = loadPreferenceState(mod)
    if sortMode then setPocketSort(state, "machines", upper(sortMode)) end
    state.machineFilters = filters or { query = "", type = "ANY", damageClass = "ANY" }
    return machineFilteredRows(game, state)
  end
  mod.exports.moveDamageClass = moveDamageClass
  mod.exports.isFavorite = function(id)
    return loadPreferenceState(mod).favoriteSet[id] ~= nil
  end
  mod.exports.isPinned = function(id)
    return loadPreferenceState(mod).pinnedSet[id] ~= nil
  end

  -- The pockets an item can live in. The results page is not one of them:
  -- nothing is filed there, a search puts things there for one Bag session.
  mod.exports.pockets = function()
    local out = {}
    for _, pocket in ipairs(POCKETS) do
      if not pocket.transient then
        out[#out + 1] = { id = pocket.id, label = pocket.label }
      end
    end
    return out
  end

  -- Register immediately when load order permits it; game.ready retries after
  -- the full mod set is active, and Gen1 Modern UI can also discover this
  -- public export on reload/enable changes.
  ensureModernUiAdapter()
end
