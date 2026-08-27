-- Headless coverage of ITEM INFO and ELEVATOR PANEL.
--
-- The engine is not here, so nothing about how these screens LOOK can be
-- tested.  What can be, and is where they would actually go wrong, is
-- everything decided before a pixel is drawn:
--
--   * that no description can overflow the box it goes in.  This is the one
--     that matters: the text box shows the last two lines of what it is
--     given, so a description that wraps to three loses its first line
--     silently.  Eighteen glyphs and two lines, every entry, counted the way
--     the font counts them and not the way `#` does -- POKéMON is seven
--     glyphs across eight bytes;
--   * that a machine's line is built from its move and stays inside the same
--     budget for the longest move name in the game;
--   * that the ABOUT row lands where it is meant to, and that adding it
--     cannot push a box off the bottom of the screen;
--   * that only the five lists this mod claims are recognised as its own;
--   * that the lift panel recognises its own list and sizes itself to the
--     floors it was given.
--
-- Run:  luajit tests/iteminfo_test.lua

package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0
local function ok(condition, description)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("  FAIL  ", description, "\n")
  end
end
local function eq(actual, expected, description)
  local same = actual == expected
  if not same then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(same, description)
end

-- ---------------------------------------------------------------- harness

local MODULE = "modules/Gen1ItemInfo/"
local ELEVATOR = "modules/Gen1Elevator/"

local function readFile(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end

local function chunkOf(path)
  local source = assert(readFile(path), path .. " is missing")
  return assert(load(source, "@" .. path))()
end

-- Glyphs, not bytes.  The charmap's é, ♂ and ♀ are one cell each and several
-- bytes each, and a budget counted in bytes rejects sentences that fit and
-- accepts sentences that do not.  UTF-8 continuation bytes are 0x80-0xBF, so
-- counting the bytes that are NOT continuations counts characters.
local function glyphs(text)
  local n = 0
  for i = 1, #text do
    local byte = text:byte(i)
    if byte < 0x80 or byte > 0xBF then n = n + 1 end
  end
  return n
end

-- Stand-ins for the engine modules these files reach for.  None of them is
-- exercised here beyond being callable: the drawing is the part that needs a
-- running game, and the part this suite does not claim to cover.
local function strings(text, ...)
  if select("#", ...) > 0 then return (text:format(...)) end
  return text
end
package.preload["src.core.Strings"] = function() return strings end

local function fakeUI()
  return {
    Font = {
      width = function(text) return glyphs(tostring(text)) * 8 end,
      split = function(text)
        local spans = {}
        for i = 1, #text do
          local byte = text:byte(i)
          if byte < 0x80 or byte > 0xBF then
            spans[#spans + 1] = { from = i, to = i }
          else
            spans[#spans].to = i
          end
        end
        return spans
      end,
      spansFitting = function(spans, budget)
        return math.min(#spans, math.floor(budget / 8))
      end,
      draw = function() end,
      drawBox = function() end,
      drawCode = function() end,
    },
    Menu = { new = function(game, items, opts) return { game = game, items = items,
      ty = opts and opts.ty or 0, th = opts and opts.th or (#items * 2 + 2) } end },
    Theme = { cursor = 0xED, cursorHollow = 0xEC, moreArrow = 0xEE },
    TextBox = {
      new = function(game, text) return { game = game, text = text } end,
      paginate = function(text) return { { text } } end,
    },
    ListMenu = {
      new = function(game, title, items, opts)
        return {
          game = game, title = title, items = items or {},
          kind = (opts and opts.kind) or title,
          index = 1, scroll = 0, rows = 7, isOpaque = true,
          draw = function() end, update = function() end,
        }
      end,
    },
  }
end

-- Enough of love.graphics for a box and some glyphs.  The drawing is the part
-- that needs a running game; what a test can watch is WHAT was drawn and
-- WHERE, which is exactly where the panel's geometry went wrong twice.
local drawn

local function watchDraws(ui)
  drawn = { boxes = {}, text = {}, codes = {}, rects = {}, images = {} }
  love = {
    graphics = {
      setColor = function() end,
      rectangle = function(_, x, y, w, h)
        drawn.rects[#drawn.rects + 1] = { x = x, y = y, w = w, h = h }
      end,
      -- The icons are real files under the module's own assets/, so the stub
      -- opens them rather than pretending: a mapping that names an icon this
      -- mod does not ship is exactly the mistake worth catching, and it can
      -- only be caught against the folder itself.
      newImage = function(path)
        local handle = io.open(path, "rb")
        if not handle then error("no image at " .. tostring(path), 0) end
        handle:close()
        return { path = path, setFilter = function() end }
      end,
      draw = function(image, x, y)
        drawn.images[#drawn.images + 1] =
          { path = image and image.path, x = x, y = y }
      end,
    },
  }
  ui.Font.drawBox = function(tx, ty, tw, th)
    drawn.boxes[#drawn.boxes + 1] = { tx = tx, ty = ty, tw = tw, th = th }
  end
  ui.Font.draw = function(text, x, y)
    drawn.text[#drawn.text + 1] = { text = text, x = x, y = y }
  end
  ui.Font.drawCode = function(code, x, y)
    drawn.codes[#drawn.codes + 1] = { code = code, x = x, y = y }
  end
  return drawn
end

local function fakeMod(options)
  local logged = {}
  return {
    id = "gen1_wild_ui",
    path = ".",
    exports = {},
    ui = fakeUI(),
    log = {
      info = function(_, ...) logged[#logged + 1] = { "info", ... } end,
      warn = function(_, ...) logged[#logged + 1] = { "warn", ... } end,
      error = function(_, ...) logged[#logged + 1] = { "error", ... } end,
    },
    options = {
      define = function() end,
      get = function(_, key) return (options or {})[key] end,
    },
    events = { on = function(_, name, fn) end },
    hooks = { wrap = function(self, name, fn) self[name] = fn end },
    logged = logged,
  }
end

-- ------------------------------------------------- the descriptions fit

do
  local descriptions = chunkOf(MODULE .. "descriptions.lua")
  local count, widest = 0, 0

  for id, text in pairs(descriptions) do
    count = count + 1
    ok(type(text) == "string", id .. " is a string")

    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    ok(#lines == 2, id .. " is exactly two lines (got " .. #lines .. ")")

    for i, line in ipairs(lines) do
      local n = glyphs(line)
      if n > widest then widest = n end
      ok(n <= 18, ("%s line %d is %d glyphs, over the box's 18"):format(id, i, n))
      ok(n > 0, ("%s line %d is not empty"):format(id, i))
    end

    ok(not text:find("\f"), id .. " has no page break in it")
  end

  ok(count >= 80, "every item in the game is described (got " .. count .. ")")
  ok(widest == 18, "at least one line uses the whole box (widest " .. widest .. ")")

  -- The ids that are deliberately absent, so a well-meaning addition here
  -- has to argue with a test rather than slip in.  FLOOR_* are lift buttons
  -- rather than items and nothing ever carries one; ITEM_2C and ITEM_32 are
  -- the ROM table's two unused slots.
  eq(descriptions.FLOOR_3F, nil, "lift buttons are not described")
  eq(descriptions.ITEM_2C, nil, "unused item ids are not described")
  eq(descriptions.TM_MEGA_PUNCH, nil, "machines are described from their move")

  -- Gen151's LINK CABLE, sold on the Celadon 4F shelf beside the four
  -- stones.  It is not vanilla and it is described anyway, because a row
  -- whose every neighbour explains itself and it does not looks broken.
  ok(descriptions.LINK_CABLE ~= nil, "Gen151's LINK CABLE is described")
end

-- --------------------------------------------------- a machine's two lines

do
  local main = assert(readFile(MODULE .. "main.lua"))
  -- machineLine is a local in main.lua and main.lua returns the installer,
  -- so running it in place would need more of the engine than this suite
  -- stubs.  The function is lifted out of the source instead, which also
  -- keeps the test honest about where it lives.
  local body = main:match("(local function machineLine.-\nend)")
  ok(body ~= nil, "machineLine is where the test expects to find it")
  local machineLine = assert(load(body .. "\nreturn machineLine"))()

  eq(machineLine("TM_MEGA_PUNCH", "MEGA PUNCH"),
     "MEGA PUNCH.\nA TM. Used once.", "a TM says what it teaches and its cost")
  eq(machineLine("HM_SURF", "SURF"),
     "SURF.\nAn HM. Reusable.", "an HM says it can be used again")

  -- The longest name in the game plus the longest name a mod could plausibly
  -- ship: both have to stay inside the box, which is the whole reason the
  -- verb is not on this line.
  for _, name in ipairs({ "SELFDESTRUCT", "THUNDERBOLT", "DOUBLE-EDGE",
                          "MEGA DRAIN", "PSYCHIC" }) do
    for _, id in ipairs({ "TM_X", "HM_X" }) do
      local text = machineLine(id, name)
      local lines = {}
      for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
      eq(#lines, 2, name .. " on " .. id .. " is two lines")
      for i, line in ipairs(lines) do
        ok(glyphs(line) <= 18,
          ("%s on %s line %d is %d glyphs"):format(name, id, i, glyphs(line)))
      end
    end
  end
end

-- ------------------------------------------------------------- ABOUT

do
  local factory = chunkOf(MODULE .. "about.lua")
  local mod = fakeMod()
  local described = { POTION = "Restores 20 HP to\none POKéMON." }
  local about = factory(mod, function(_, id) return described[id] end,
                        function() return true end)

  eq(about.LABEL, "ABOUT", "the row is called ABOUT")

  -- ---- where the row goes

  eq(about.insertAt({ { label = "USE" }, { label = "TOSS" } }), 3,
     "with no CANCEL the row goes last")
  eq(about.insertAt({ { label = "SORT" }, { label = "CANCEL" } }), 2,
     "with a CANCEL the row goes above it")
  ok(about.insertAt({ { label = "USE" }, { label = "TOSS" } }) ~= 1,
     "the row is never first -- the cursor opens on row one")

  -- ---- which item it is about

  local function stack(states)
    return { states = states, top = function(self)
      return self.states[#self.states]
    end }
  end

  local bag = { kind = "bag", index = 2,
    items = { { value = "POTION" }, { value = "ANTIDOTE" }, { cancel = true } } }
  eq(about.bagItem({ stack = stack({ bag }) }), "ANTIDOTE",
     "the row is about the item under the bag's cursor")

  bag.index = 3
  eq(about.bagItem({ stack = stack({ bag }) }), nil,
     "the CANCEL row is not an item")

  eq(about.bagItem({ stack = stack({ { kind = "pc_item_toss", items = {} } }) }),
     nil, "a list that is not the bag gets no row")
  eq(about.bagItem({}), nil, "no stack at all is not a crash")

  -- ---- a box that grows cannot fall off the screen

  eq(about.keepOnScreen({ ty = 10, th = 7 }).ty, 10,
     "a box with room is left where it was")
  eq(about.keepOnScreen({ ty = 5, th = 14 }).ty, 4,
     "a box that would run past row 17 moves up by what it grew")
  eq(about.keepOnScreen({ ty = 0, th = 20 }).ty, 0,
     "a box taller than the screen still starts on row 0")
  ok(about.keepOnScreen({}) ~= nil, "a menu with no geometry is not a crash")

  -- ---- installing

  local Menu = mod.ui.Menu
  local baseNew = Menu.new
  ok(about.install(), "it installs")
  ok(Menu.new ~= baseNew, "Menu.new is wrapped")
  ok(about.install(), "installing twice is safe")

  local rows = { { label = "USE" }, { label = "TOSS" } }
  local opts = { tx = 13, ty = 10, tw = 7, th = 5 }
  Menu.new({ stack = stack({ { kind = "bag", index = 1,
    items = { { value = "POTION" } } } }) }, rows, opts)
  eq(#rows, 3, "an item with a description gets an ABOUT row")
  eq(rows[3].label, "ABOUT", "and it is the last row")
  eq(opts.th, 7, "the box that named its own height is grown by one row")

  local plain = { { label = "USE" }, { label = "TOSS" } }
  Menu.new({ stack = stack({ { kind = "bag", index = 1,
    items = { { value = "NUGGET" } } } }) }, plain, { ty = 10, th = 5 })
  eq(#plain, 2, "an item with no description gets no row")

  local elsewhere = { { label = "BUY" }, { label = "SELL" } }
  Menu.new({ stack = stack({ { kind = "overworld" } }) }, elsewhere, {})
  eq(#elsewhere, 2, "a menu that is not over the bag is untouched")

  -- ---- a submenu of a menu that already offered ABOUT does not offer it again
  --
  -- Menu pops itself before running a row, so a picker opened from a row is
  -- built with the bag list back on top and looks exactly like the first
  -- menu.  This is Gen1ModernBag's SORT row, reproduced.

  local game = { stack = stack({ { kind = "bag", index = 1,
    items = { { value = "POTION" } } } }) }
  local submenu
  local tools = {
    { label = "SORT", onSelect = function()
        submenu = { { label = "A-Z" }, { label = "QUANTITY" } }
        Menu.new(game, submenu, { ty = 6 })
      end },
    { label = "MOVE ITEM" },
    { label = "CANCEL" },
  }
  Menu.new(game, tools, { ty = 5 })
  eq(#tools, 4, "the tools menu gets an ABOUT row")
  eq(tools[3].label, "ABOUT", "above CANCEL")

  tools[1].onSelect()
  eq(#submenu, 2, "and the picker it opens does not get one")
  ok(not about.nested(), "the flag is down again once the row has run")

  -- a row that raises still puts the flag down
  local raiser = { { label = "USE", onSelect = function() error("boom", 0) end },
                   { label = "TOSS" } }
  Menu.new(game, raiser, { ty = 10, th = 5 })
  eq(#raiser, 3, "the box gets its row")
  local ran = pcall(raiser[1].onSelect)
  ok(not ran, "a row that raises still raises")
  ok(not about.nested(), "and the flag does not stay up")

  Menu.new = baseNew
end

-- ------------------------------------------------------- the mart and the PC

do
  local factory = chunkOf(MODULE .. "screens.lua")
  local mod = fakeMod()
  local on = true
  local screens = factory(mod, chunkOf(MODULE .. "chrome.lua")(mod),
                          function() return "a description" end,
                          function() return on end)

  -- Five lists and no more: everything else in the game -- the bag, the box,
  -- the dex, the move learner, a mod's own list -- has to fall straight
  -- through untouched.
  local claimed = {}
  for kind in pairs(screens.KINDS) do claimed[#claimed + 1] = kind end
  table.sort(claimed)
  eq(table.concat(claimed, ","),
     "BUY,SELL,pc_item_deposit,pc_item_toss,pc_item_withdraw",
     "exactly the mart's two lists and the PC's three")

  eq(screens.headerRight({ kind = "bag" }), nil,
     "a list this mod does not claim has no header number")

  local game = {
    save = { money = 19436, pcItems = { POTION = 1, HP_UP = 3 } },
    data = { field = { pcItemCap = 50 } },
  }
  eq(screens.headerRight({ kind = "BUY", game = game }), "¥19436",
     "a mart header carries the money")
  eq(screens.headerRight({ kind = "SELL", game = game }), "¥19436",
     "and so does a sell header")
  -- WITHDRAW ITEM reaches the column a right-aligned number would start in,
  -- so no PC header carries one -- see the note over KINDS.
  eq(screens.headerRight({ kind = "pc_item_deposit", game = game }), nil,
     "a PC header carries its title and nothing else")
  eq(screens.headerRight({ kind = "pc_item_withdraw", game = game }), nil,
     "on every one of the three, not two of them")

  ok(screens.switchedOn({ kind = "BUY" }), "a claimed list is switched on")
  ok(not screens.switchedOn({ kind = "bag" }), "an unclaimed list is not")
  on = false
  ok(not screens.switchedOn({ kind = "BUY" }),
     "and the option turns a claimed list off")
  on = true

  -- ---- decorating

  local drew, updated = 0, 0
  local list = {
    kind = "BUY", title = "BUY", index = 1, scroll = 0, footer = "Take your time.",
    items = { { value = "POTION", label = "POTION", right = "¥300" },
              { value = "ANTIDOTE", label = "ANTIDOTE", right = "¥100" } },
    game = game,
    draw = function() drew = drew + 1 end,
    update = function() updated = updated + 1 end,
  }
  local decorated = screens.decorate(list)
  eq(decorated, list, "the engine's own list is handed back, decorated")
  eq(list.rows, 4, "four rows, the same four the vanilla list shows")

  list:update(0)
  eq(updated, 1, "the engine's update still runs")
  eq(list.footer, "a description",
     "and the idle line is replaced by the description")

  list.footer = "Here you are! Thank you!"
  list:update(0)
  eq(list.footer, "Here you are! Thank you!",
     "a clerk who is still talking is not interrupted")

  list.index = 2
  list:update(0)
  eq(list.footer, "a description", "moving the cursor asks about the new row")

  on = false
  list:draw()
  eq(drew, 1, "switched off, the engine draws its own screen")
  on = true

  -- ---- the PC menu underneath the item PC
  --
  -- The item PC's menu is pushed over the Pokemon Center's own, which keeps
  -- drawing and prints its extra rows out from under the shorter box on top.

  local covered, PC_MENU = screens.coveredByPlayerPC, screens.PC_MENU
  local pcMenu = { tx = 0, ty = 0, tw = 16, th = 12 }
  local itemPc = { tx = 0, ty = 0, tw = 16, th = 10, [PC_MENU] = true }
  local overworld = { isOpaque = true }
  local box = { tx = 0, ty = 12, tw = 20, th = 6 }

  local states = { overworld, pcMenu, itemPc }
  for _, st in ipairs(states) do st.game = { stack = { states = states } } end
  box.game = states[1].game

  ok(covered(pcMenu), "the PC menu under the item PC is hidden")
  ok(not covered(itemPc), "the item PC itself is not")
  ok(not covered(overworld),
     "and the overworld is opaque, so it is never the thing hidden")
  ok(not covered(box), "a state that is not on the stack is left alone")

  -- a text box over the item PC does not un-hide what is under it
  states[#states + 1] = { tx = 0, ty = 12, game = states[1].game }
  ok(covered(pcMenu), "still hidden with a text box on top of the item PC")

  -- the bedroom PC: opened with no PC menu under it at all
  local direct = { [PC_MENU] = true }
  local alone = { overworld, direct }
  overworld.game = { stack = { states = alone } }
  direct.game = overworld.game
  ok(not covered(overworld), "the bedroom PC still shows the room behind it")

  ok(not covered(nil), "no state is not a crash")
  ok(not covered({}), "a state with no game is not a crash")
end

-- --------------------------------------------------------- the lift panel

do
  local mod = fakeMod({ enabled = true })
  local ListMenu = mod.ui.ListMenu
  local baseNew = ListMenu.new
  chunkOf(ELEVATOR .. "main.lua")(mod)
  ok(ListMenu.new ~= baseNew, "the panel wraps ListMenu.new")

  local isPanel = mod.exports.isPanel
  local widthFor, visibleFor = mod.exports.widthFor, mod.exports.visibleFor
  local geometry = mod.exports.geometry

  ok(isPanel("WHICH FLOOR?"), "the lift's list is recognised")
  ok(not isPanel("BUY"), "and nothing else is")
  ok(not isPanel(nil), "a list with no title is not a crash")

  -- ---- as wide as its widest floor and no wider
  --
  -- There is no title on the box any more, so nothing but the floors decides
  -- the width: two borders, the cursor's column and one spare.

  eq(widthFor({ { label = "1F" }, { label = "B1F" } }), 7,
     "a lift is as wide as its widest floor token")
  eq(widthFor({ { label = "1F" }, { label = "5F" } }), 6,
     "CELADON's two-glyph floors make the narrowest box")
  eq(widthFor({ { label = "MEZZANINE" } }), 13,
     "a modded lift with long names is as wide as it needs to be")
  eq(widthFor({}), 6, "a lift with no floors still draws a box")

  for _, items in ipairs({
    { { label = "1F" } },
    { { label = "1F" }, { label = "2F" }, { label = "3F" } },
    { { label = "B4F" } },
  }) do
    local tw = widthFor(items)
    local widest = 0
    for _, item in ipairs(items) do
      if #item.label > widest then widest = #item.label end
    end
    -- border, cursor, the token, a spare column, border
    ok(tw >= widest + 4, "the widest floor fits with its cursor beside it")
  end

  -- ---- every floor visible where there is room, scrolling where there is not

  eq(visibleFor(5), 5, "CELADON's five floors are all on screen")
  eq(visibleFor(4), 4, "the ROCKET HIDEOUT's four are too")
  eq(visibleFor(11), 7, "SILPH CO.'s eleven scroll")
  eq(visibleFor(0), 1, "a lift with no floors still has a row's worth of box")

  -- ---- and the box stays on the screen

  local function floors(n)
    local items = {}
    for i = 1, n do items[i] = { label = i .. "F" } end
    return items
  end

  for _, n in ipairs({ 1, 3, 4, 5, 7, 11, 20 }) do
    local tx, ty, tw, th, visible = geometry(floors(n))
    ok(tx >= 0 and tx + tw <= 20,
       ("%d floors: the box is inside the screen across"):format(n))
    ok(ty >= 0 and ty + th <= 18,
       ("%d floors: the box is inside the screen down (ty %d, th %d)")
         :format(n, ty, th))
    eq(th, visible * 2 + 2, n .. " floors: two tiles a row, plus the borders")
    ok(visible <= n, n .. " floors: no more rows than there are floors")
    -- Menu's own anchoring: the last choice on the last interior row, the
    -- slack as a blank row under the top border
    local lastY = (ty + th - 2) * 8
    local firstY = (ty + th - 2 - (visible - 1) * 2) * 8
    eq(lastY, (ty + th - 2) * 8, n .. " floors: the last row is the last row")
    ok(firstY >= (ty + 2) * 8,
       n .. " floors: a blank row sits under the top border")
    ok(lastY + 8 <= (ty + th - 1) * 8,
       n .. " floors: no row is drawn on the bottom border")
  end

  -- The regression this rewrite is for: one-tile rows.
  local _, _, _, th5 = geometry(floors(5))
  eq(th5, 12, "five floors is twelve tiles, not seven")

  -- ---- and what actually reaches the screen
  --
  -- CELADON's five floors, drawn.  This is the guard for the header coming
  -- back and for the row pitch collapsing again: both were things the code
  -- believed it was doing right, and only a draw disagrees.

  watchDraws(mod.ui)
  local panel = ListMenu.new({}, "WHICH FLOOR?", floors(5), {})
  panel.index = 4
  panel:draw()

  eq(#drawn.boxes, 1, "one box, and only one")
  eq(drawn.boxes[1].tw, 6, "six tiles wide -- no title to make room for")
  eq(drawn.boxes[1].th, 12, "twelve tall")
  eq(drawn.boxes[1].tx, 13, "against the right edge, one tile of margin off")

  eq(#drawn.text, 5, "five floors printed, and nothing else")
  for _, printed in ipairs(drawn.text) do
    ok(printed.text ~= "FLOOR",
       "the header is gone (found " .. tostring(printed.text) .. ")")
  end
  eq(drawn.text[1].text, "1F", "the first floor first")
  eq(drawn.text[5].text, "5F", "the last floor last")

  for i = 2, #drawn.text do
    eq(drawn.text[i].y - drawn.text[i - 1].y, 16,
       "row " .. i .. " is sixteen pixels below the one above it")
  end
  eq(drawn.text[1].y, (1 + 12 - 2 - 4 * 2) * 8,
     "the first row leaves a blank row under the top border")
  ok(drawn.text[5].y + 8 <= (1 + 12 - 1) * 8,
     "and the last row is clear of the bottom border")

  eq(#drawn.codes, 1, "one cursor")
  eq(drawn.codes[1].y, drawn.text[4].y, "on the row it is pointing at")
  eq(drawn.codes[1].x, drawn.text[1].x - 8, "one column left of the labels")
end

-- ------------------------------------------------------------ the icons

do
  local mod = fakeMod()
  -- The icons resolve against the module's own folder, which is where the
  -- PNGs actually are; `.` is where this suite runs from.
  mod.path = "modules/Gen1ItemInfo"
  watchDraws(mod.ui)

  local icons = chunkOf(MODULE .. "icons.lua")(mod)
  eq(icons.W, 16, "an icon is sixteen wide")
  eq(icons.H, 16, "and sixteen tall, which is the height of a list row")

  local game = {
    data = {
      items = {
        POTION = { name = "POTION" },
        SURFBOARD = { name = "SURFBOARD" },
        TM_FLAMETHROWER = { name = "TM35",
          machine = { kind = "TM", number = 35, move = "FLAMETHROWER" } },
        HM_SURF = { name = "HM03",
          machine = { kind = "HM", number = 3, move = "SURF" } },
        TM_NOSUCHMOVE = { name = "TM99",
          machine = { kind = "TM", number = 99, move = "NOSUCHMOVE" } },
        LINK_CABLE = { name = "LINK CABLE" },
      },
      moves = {
        FLAMETHROWER = { name = "FLAMETHROWER", type = "FIRE" },
        SURF = { name = "SURF", type = "WATER" },
      },
    },
  }

  local function pathOf(id)
    local image = icons.of(game, id)
    return image and image.path
  end

  eq(pathOf("POTION"), "modules/Gen1ItemInfo/assets/items/potion.png",
     "an item resolves to the file named for its id")

  -- A machine takes the disc of the type of the move it teaches, off the move
  -- and never off a table here: TM35 is FLAMETHROWER is FIRE.
  eq(pathOf("TM_FLAMETHROWER"), "modules/Gen1ItemInfo/assets/items/tm_fire.png",
     "TM35 takes the FIRE disc")
  eq(pathOf("HM_SURF"), "modules/Gen1ItemInfo/assets/items/hm_water.png",
     "HM03 takes the WATER disc, and an HM is never a TM")
  eq(pathOf("TM_NOSUCHMOVE"), "modules/Gen1ItemInfo/assets/items/tm.png",
     "a machine whose move has no type falls back to the plain disc")

  -- Gen151's cable, which the pack has no icon for: the ESCAPE ROPE recolored,
  -- because a coiled rope is the shape a cable has.
  ok(pathOf("LINK_CABLE"), "the LINK CABLE has an icon of its own")

  -- The one drawn placeholder: nothing anywhere has ever drawn Gen 1's
  -- SURFBOARD, so make_item_icons.py draws a board-shaped one in the set's
  -- own idiom rather than borrowing an icon that means something else.
  eq(pathOf("SURFBOARD"), "modules/Gen1ItemInfo/assets/items/surfboard.png",
     "the SURFBOARD has its placeholder")

  -- No icon is an ordinary answer, not an error: a badge is never in a list
  -- this mod draws, and an item a mod added is not in this folder.
  eq(pathOf("BOULDERBADGE"), nil, "an item with no icon resolves to nothing")
  eq(pathOf("SOMEMOD_WIDGET"), nil, "and so does an item this set never saw")
  eq(icons.of(game, nil), nil, "a nil id is not a crash")

  -- An item that names its own wins, and a path that is not there falls back
  -- rather than leaving the row blank.
  game.data.items.POTION.icon = "modules/Gen1ItemInfo/assets/items/nugget.png"
  eq(pathOf("POTION"), "modules/Gen1ItemInfo/assets/items/nugget.png",
     "an item's own icon wins over the shipped one")
  game.data.items.POTION.icon = "modules/Gen1ItemInfo/assets/items/nothing.png"
  eq(pathOf("POTION"), "modules/Gen1ItemInfo/assets/items/potion.png",
     "and a missing override falls back")
  game.data.items.POTION.icon = nil

  -- ---- the row an icon is drawn on

  local C = chunkOf(MODULE .. "chrome.lua")(mod)
  local on = true
  local screens = chunkOf(MODULE .. "screens.lua")(
    mod, C, function() return "a description" end,
    function(feature) return on or feature ~= "icons" end, icons)

  local list = {
    kind = "BUY", title = "BUY", index = 1, scroll = 0, game = game,
    items = { { value = "POTION", label = "POTION", right = "¥300" },
              { value = "TM_FLAMETHROWER", label = "TM35", right = "¥2000" } },
    draw = function() end, update = function() end,
  }
  screens.decorate(list)

  drawn.images, drawn.text, drawn.codes, drawn.rects = {}, {}, {}, {}
  list:draw()

  eq(#drawn.images, 2, "one icon per row")
  for i, image in ipairs(drawn.images) do
    eq(image.x, C.ICON_X, "icon " .. i .. " is in the icon column")
    eq(image.y, C.rowY(i) + C.ICON_DY, "icon " .. i .. " is on its own row")
  end
  -- Centred on the NAME, not on the row: a row is two lines and the name is
  -- the top one, so an icon filling all sixteen pixels sits four below the
  -- word it belongs to.  A glyph inks rows 0-6 of its cell, so the name's ink
  -- is centred on y+3 and a shifted icon's on y+3.5.
  eq(C.ICON_DY, -4, "the icon is raised to meet its name")
  for i = 1, C.ROWS do
    local nameCentre = C.rowY(i) + 3
    local iconCentre = C.rowY(i) + C.ICON_DY + icons.H / 2
    ok(math.abs(iconCentre - nameCentre) <= 1,
       "row " .. i .. " has its icon and its name on the same centre line")
  end
  -- Neither end may leave the body: the top row's icon has to clear the
  -- header box and the bottom row's the text box.
  ok(C.rowY(1) + C.ICON_DY >= C.BODY_TOP,
     "the top row's icon stays clear of the header box")
  ok(C.rowY(C.ROWS) + C.ICON_DY + icons.H - 1 <= C.BODY_BOTTOM,
     "the bottom row's icon stays clear of the text box")

  -- ---- the rule between the two columns

  -- One pixel wide and a row tall, so consecutive rows join into one line,
  -- down the middle of the tile between the icon and the name.
  ok(C.ICON_RULE_X >= C.ICON_X + icons.W,
     "the rule is clear of the icon")
  ok(C.ICON_RULE_X < C.ICON_LABEL_X, "and clear of the name")
  local rules = {}
  for _, rect in ipairs(drawn.rects) do
    if rect.w == 1 and rect.x == C.ICON_RULE_X then rules[#rules + 1] = rect end
  end
  eq(#rules, 2, "one rule per row")
  for i, rect in ipairs(rules) do
    eq(rect.y, C.rowY(i), "rule " .. i .. " starts on its row")
    eq(rect.h, C.ROW_STEP,
       "rule " .. i .. " is a whole row tall, so rows join up")
  end
  ok(C.rowY(C.ROWS) + C.ROW_STEP - 1 <= C.BODY_BOTTOM,
     "the bottom rule stays clear of the text box")
  -- And the icon column has to clear the cursor on one side and the label on
  -- the other.
  ok(C.ICON_X >= C.CURSOR_X + 8, "the icon clears the cursor")
  ok(C.ICON_LABEL_X >= C.ICON_X + icons.W, "and the label clears the icon")

  local labels, prices = {}, {}
  for _, printed in ipairs(drawn.text) do
    if printed.text == "POTION" or printed.text == "TM35" then
      labels[#labels + 1] = printed
    elseif printed.text:find("¥") and printed.y >= C.BODY_TOP then
      -- the header's money is a ¥ too, and it is not on a row
      prices[#prices + 1] = printed
    end
  end
  eq(#labels, 2, "both names are printed")
  for _, label in ipairs(labels) do
    eq(label.x, C.ICON_LABEL_X, "a name starts after the icon")
  end
  -- The price drops to the row's second line, which is what buys the name the
  -- whole width: SUPER POTION is twelve glyphs and a price is five more.
  eq(#prices, 2, "both prices are printed")
  for i, price in ipairs(prices) do
    eq(price.y, C.rowY(i) + C.RIGHT_SUB_Y, "a price is on the row's second line")
    ok(price.x + 8 * 4 <= C.RIGHT, "and right-aligned inside the margin")
  end
  -- Twelve glyphs is the longest a Gen 1 item name gets, and it has to fit
  -- from the label column to the right margin without being cut.
  eq(C.fit("HYPER POTION", C.RIGHT - C.ICON_LABEL_X), "HYPER POTION",
     "the longest item name fits beside an icon")

  -- ---- and the switch puts the old row straight back

  on = false
  drawn.images, drawn.text, drawn.rects = {}, {}, {}
  list:draw()
  eq(#drawn.images, 0, "ITEM ICONS off draws no icons")
  for _, rect in ipairs(drawn.rects) do
    ok(not (rect.w == 1 and rect.x == C.ICON_RULE_X),
       "ITEM ICONS off still drew the column rule")
  end
  for _, printed in ipairs(drawn.text) do
    if printed.text == "POTION" then
      eq(printed.x, C.LABEL_X, "and the name goes back to the old column")
    end
    if printed.text == "¥300" then
      eq(printed.y, C.rowY(1), "with the price back on the name's own line")
    end
  end
  on = true
end

print(("iteminfo: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
