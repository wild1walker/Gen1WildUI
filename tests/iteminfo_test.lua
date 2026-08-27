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
    ListMenu = { new = function() return {} end },
  }
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
end

-- --------------------------------------------------------- the lift panel

do
  local mod = fakeMod({ enabled = true })
  local ListMenu = mod.ui.ListMenu
  local baseNew = ListMenu.new
  chunkOf(ELEVATOR .. "main.lua")(mod)
  ok(ListMenu.new ~= baseNew, "the panel wraps ListMenu.new")

  local isPanel, widthFor = mod.exports.isPanel, mod.exports.widthFor
  ok(isPanel("WHICH FLOOR?"), "the lift's list is recognised")
  ok(not isPanel("BUY"), "and nothing else is")
  ok(not isPanel(nil), "a list with no title is not a crash")

  -- Eight tiles is the floor: the word on the border needs six between the
  -- corners, and no Gen 1 floor token is wide enough to beat it.
  eq(widthFor({ { label = "1F" }, { label = "B1F" } }), 8,
     "a normal lift is as wide as its border label")
  eq(widthFor({ { label = "MEZZANINE" } }), 13,
     "a modded lift with long names is as wide as it needs to be")
  eq(widthFor({}), 8, "a lift with no floors still draws a box")
end

print(("iteminfo: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
