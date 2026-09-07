-- Gold's party list in the set's own frame (modules/Gen1Party/gen2panel.lua).
--
-- The engine is not here and neither is a display, so nothing about how the
-- page LOOKS can be tested.  What can be, and is the whole contract, is WHICH
-- CALLS the panel makes and WHERE: this replaces a screen the player cannot
-- get out of if it goes wrong, on coordinates that were arrived at on paper.
--
-- Three things the assertions are really about:
--
--   * the block MOVED and the columns did NOT.  Every second-line column is
--     the ASM's own -- status 5, level 8, bar 11 -- and the only reason to
--     touch them would be a right margin this page has no room for.  A test
--     that pins them is what stops a later edit from buying that margin by
--     eye.
--   * CANCEL is drawn, always, and is cursored when the engine says it is the
--     selection.  It has no row of its own here, so if this stops drawing it
--     the way out of the screen becomes invisible.
--   * a panel that raises hands the engine's own back, once, and stops
--     trying.
--
-- Run:  luajit tests/partypanel2_test.lua

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

local function chunkOf(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

-- ---------------------------------------------------------------- harness

_G.love = _G.love or {}
_G.love.graphics = {
  setColor = function() end,
  rectangle = function(mode, x, y, w, h)
    _G.__rects[#_G.__rects + 1] = { mode = mode, x = x, y = y, w = w, h = h }
  end,
}
_G.__rects = {}

local calls
local function record(what, t)
  t.what = what
  calls[#calls + 1] = t
  return t
end

local Chrome = {
  DEFAULT_BOX_PALETTE = {
    { 255, 255, 255 }, { 255, 255, 255 }, { 255, 255, 255 }, { 0, 0, 0 },
  },
  clear = function() record("clear", {}) end,
  box = function(tx, ty, tw, th)
    record("box", { tx = tx, ty = ty, tw = tw, th = th })
  end,
  textbox = function(tx, ty, iw, ih)
    record("textbox", { tx = tx, ty = ty, iw = iw, ih = ih })
  end,
  print = function(text, tx, ty)
    record("print", { text = text, tx = tx, ty = ty })
  end,
  printRight = function(text, txEnd, ty)
    record("printRight", { text = text, txEnd = txEnd, ty = ty })
  end,
  cursor = function(tx, ty, hollow)
    record("cursor", { tx = tx, ty = ty, hollow = hollow or false })
  end,
}
package.loaded["src.ui.gen2.Chrome"] = Chrome

-- Font, cut to what the panel asks it: a width, a glyph split for the
-- truncation, and the battle-extra page toggle.
local battleExtra = false
package.loaded["src.render.Font"] = {
  width = function(text) return #tostring(text) * 8 end,
  split = function(text)
    local spans = {}
    for i = 1, #text do spans[i] = { to = i } end
    return spans
  end,
  useBattleExtra = function(on)
    local was = battleExtra
    battleExtra = on
    record("font", { battleExtra = on })
    return was
  end,
}

package.loaded["src.core.Strings"] = setmetatable({
  source = function(text) return text end,
}, { __call = function(_, text) return text end })

-- The engine's PartyMenu, reduced to the class-level pieces the panel reads.
local PartyMenu = {
  PROMPTS = {
    choose = "Choose a POKéMON.",
    useItem = "Use on which <PK><MN>?",
    moveTo = "Move to where?",
    none = "You have no <PK><MN>!",
  },
  rowFor = function(mon, hp)
    if mon.isEgg then return { name = "EGG" } end
    return {
      name = mon.nickname or mon.species,
      hp = ("%3d/%3d"):format(hp or mon.hp or 0, mon.maxHp or 0),
      status = mon.status and "SLP" or nil,
      level = "<LV>" .. tostring(mon.level or 5),
    }
  end,
}
-- every instance method the install gate insists on
for _, name in ipairs({ "isCancel", "iconX", "iconBob", "drawIcon",
                        "shownHpFor", "drawHpBar", "tmhmAble",
                        "itemResultClimbing", "drawSubmenu", "drawPanel" }) do
  PartyMenu[name] = function() end
end
package.loaded["src.ui.gen2.PartyMenu"] = PartyMenu

local logged
local function fakeMod(options)
  local mod = { log = {} }
  logged = {}
  for _, level in ipairs({ "info", "warn", "error", "debug" }) do
    mod.log[level] = function(_, format, ...)
      logged[#logged + 1] = select("#", ...) > 0
        and format:format(...) or format
    end
  end
  mod.options = {
    get = function(_, key)
      local value = (options or {})[key]
      if value == nil then return true end
      return value
    end,
  }
  return mod
end

local Panel = chunkOf("modules/Gen1Party/gen2panel.lua")

-- A party screen, as the engine would hand one to drawPanel.
local function screen(opts)
  opts = opts or {}
  local party = opts.party or {}
  local self = {
    party = party,
    index = opts.index or 1,
    switchFrom = opts.switchFrom,
    softboiledFrom = opts.softboiledFrom,
    tmhm = opts.tmhm,
    itemResult = opts.itemResult,
    submenu = opts.submenu,
    prompt = opts.prompt or PartyMenu.PROMPTS.choose,
    promptIsBuiltin = opts.promptIsBuiltin ~= false,
    game = { data = { gen2Statuses = {} } },
    icons = {},
  }
  self.isCancel = function(s) return (opts.cancel == true) end
  self.iconX = function(s, i) return i == s.index and 8 or 0 end
  self.iconBob = function() return 0 end
  self.drawIcon = function(_s, mon, px, py)
    record("icon", { mon = mon, px = px, py = py })
  end
  self.shownHpFor = function(_s, _i, mon) return mon.hp end
  self.drawHpBar = function(_s, mon, tx, ty)
    record("bar", { tx = tx, ty = ty })
  end
  self.tmhmAble = function() return opts.able end
  self.itemResultClimbing = function() return opts.climbing == true end
  self.drawSubmenu = function() record("submenu", {}) end
  return self
end

local function mons(n)
  local out = {}
  for i = 1, n do
    out[i] = { species = "TOTODILE", nickname = "TOTODILE", hp = 20,
               maxHp = 45, level = 15, status = "sleep" }
  end
  return out
end

local function draw(panel, self)
  calls = {}
  _G.__rects = {}
  panel.drawPanel(self)
  return calls
end

local function firstOf(what)
  for _, c in ipairs(calls) do if c.what == what then return c end end
end

local function allOf(what)
  local out = {}
  for _, c in ipairs(calls) do if c.what == what then out[#out + 1] = c end end
  return out
end

local function printAt(tx, ty)
  for _, c in ipairs(calls) do
    if c.what == "print" and c.tx == tx and c.ty == ty then return c end
  end
end

-- ------------------------------------------------------------- the frame

do
  io.write("the frame\n")
  local panel = Panel(fakeMod())
  draw(panel, screen({ party = mons(6) }))

  ok(firstOf("clear") ~= nil, "the page is cleared first")

  local boxes = allOf("box")
  eq(#boxes, 2, "two boxes: a header and a footer")
  eq(boxes[1].ty, 0, "the header sits on row 0")
  eq(boxes[1].th, 3, "three rows of it")
  eq(boxes[1].tw, 20, "full width")
  eq(boxes[2].ty, 15, "the footer starts on row 15")
  eq(boxes[2].th, 3, "and is three rows, which is what leaves the body twelve")

  -- 3 header + 12 body + 3 footer is the whole screen, which is the arithmetic
  -- the layout stands on.
  eq(boxes[1].th + 12 + boxes[2].th, 18,
     "header, six two-row mons and footer are exactly the eighteen rows there "
     .. "are -- which is why CANCEL has no row of its own")

  ok(printAt(1, 1) ~= nil, "the title is on the header's interior row")
  eq(printAt(1, 1).text, "PARTY", "and says which screen this is")
end

-- ------------------------------------------------------------- the rows

do
  io.write("the rows moved, the columns did not\n")
  local panel = Panel(fakeMod())
  draw(panel, screen({ party = mons(6), index = 1 }))

  -- Six mons at two rows each, starting under the header.
  local icons = allOf("icon")
  eq(#icons, 6, "six icons")
  eq(icons[1].py, 24, "the first sits on the body's first pixel row")
  eq(icons[6].py, 24 + 5 * 16, "and the sixth on the last")
  eq(icons[6].py + 16, 120, "the body ends where the footer box begins")

  eq(icons[1].px, 8, "the icon is FIXED at 8 rather than sliding on select")
  eq(icons[2].px, 8, "on every row, so the rule has somewhere to be")

  -- The name is the one first-line column that moves, and only for the rule.
  ok(printAt(4, 3) ~= nil, "the first name is at column 4, right of the rule")
  ok(printAt(4, 5) ~= nil, "the second is two rows below it")

  -- Everything on the second line is the ASM's own coordinate.
  ok(printAt(13, 3) ~= nil, "HP digits stay at column 13")
  ok(printAt(5, 4) ~= nil, "the status stays at column 5")
  ok(printAt(8, 4) ~= nil, "the level stays at column 8")
  local bars = allOf("bar")
  eq(#bars, 6, "a bar per mon")
  eq(bars[1].tx, 11, "the bar stays at column 11")
  eq(bars[1].ty, 4, "on the row under the name")

  -- and the rule itself
  eq(#_G.__rects, 6, "one hairline per row")
  eq(_G.__rects[1].x, 26, "at x 26, the dex list's own column")
  eq(_G.__rects[1].y, 24, "from the top of the row")
  eq(_G.__rects[1].h, 16, "for its whole height")
  eq(_G.__rects[1].w, 1, "one pixel wide")
end

do
  io.write("RULED ICONS off\n")
  local panel = Panel(fakeMod({ ruled_icons = false }))
  draw(panel, screen({ party = mons(2), index = 1 }))

  eq(#_G.__rects, 0, "no hairline")
  ok(printAt(3, 3) ~= nil, "the name goes back to the full-width column")
  local icons = allOf("icon")
  eq(icons[1].px, 8, "and the engine's slide comes back on the selected row")
  eq(icons[2].px, 0, "with the others at 0, where the cart puts them")
end

do
  io.write("a long name\n")
  local panel = Panel(fakeMod())
  local party = mons(1)
  party[1].nickname = "CHARMANDER"
  draw(panel, screen({ party = party }))
  eq(printAt(4, 3).text, "CHARMANDE",
     "ten glyphs come back nine: the air is bought with the tenth")

  local wide = Panel(fakeMod({ ruled_icons = false }))
  draw(wide, screen({ party = party }))
  eq(printAt(3, 3).text, "CHARMANDER", "and off, all ten fit again")
end

-- ------------------------------------------------------------- the cursor

do
  io.write("the cursor and CANCEL\n")
  local panel = Panel(fakeMod())

  draw(panel, screen({ party = mons(3), index = 2 }))
  local cursors = allOf("cursor")
  eq(#cursors, 1, "one cursor")
  eq(cursors[1].tx, 0, "at column 0")
  eq(cursors[1].ty, 5, "on the selected mon's name row")

  local right = firstOf("printRight")
  ok(right ~= nil, "CANCEL is right-aligned in the header")
  eq(right.text, "CANCEL", "by name")
  eq(right.txEnd, 19, "ending at the right margin")
  eq(right.ty, 1, "on the header's interior row")

  -- The held row while a switch is open.
  draw(panel, screen({ party = mons(3), index = 1, switchFrom = 3 }))
  local held
  for _, c in ipairs(allOf("cursor")) do if c.hollow then held = c end end
  ok(held ~= nil, "the held row keeps its hollow arrow")
  eq(held.ty, 7, "on the third mon's row")
end

do
  local panel = Panel(fakeMod())
  -- The engine's isCancel is `index == #party + 1`, so the index is past the
  -- last mon and no body row matches it.
  draw(panel, screen({ party = mons(6), index = 7, cancel = true }))
  local cursors = allOf("cursor")
  eq(#cursors, 1, "when CANCEL is the selection it is the only cursor")
  eq(cursors[1].ty, 1, "and it is in the HEADER, not on a body row")
  -- one tile left of a six-glyph word ending at 19
  eq(cursors[1].tx, 12, "one tile left of the word")

  eq(panel.cancelCursorTx(8 * 8), 10,
     "a longer translation moves the cursor with it")
end

-- ------------------------------------------------------------ the footer

do
  io.write("the footer\n")
  local panel = Panel(fakeMod())

  draw(panel, screen({ party = mons(2) }))
  local prompt = printAt(1, 16)
  ok(prompt ~= nil, "the prompt is on the footer's interior row")
  eq(prompt.text, "Choose a POKéMON.", "and is the engine's own sentence")

  draw(panel, screen({ party = mons(2), switchFrom = 1 }))
  eq(printAt(1, 16).text, "Move to where?", "a switch says where to")

  draw(panel, screen({ party = {} }))
  eq(printAt(1, 16).text, "You have no <PK><MN>!", "an empty party says so")
end

do
  io.write("an item's message\n")
  local panel = Panel(fakeMod())
  draw(panel, screen({ party = mons(2),
                       itemResult = { text = "TOTODILE was\ncured of poison." } })
  )
  local box = firstOf("textbox")
  ok(box ~= nil, "the engine's own textbox is what carries a two-line message")
  eq(box.ty, 12, "at the engine's own row, covering the bottom of the list")
  eq(printAt(1, 14).text, "TOTODILE was", "first line")
  eq(printAt(1, 16).text, "cured of poison.", "second")
  eq(#allOf("box"), 1, "and the footer box is not drawn under it")

  -- ...but not while the message is still climbing into place.
  draw(panel, screen({ party = mons(2), climbing = true,
                       itemResult = { text = "x" } }))
  eq(firstOf("textbox"), nil, "a climbing result is not drawn yet")
  eq(#allOf("box"), 2, "and the ordinary footer is back")
end

do
  io.write("the TM/HM list\n")
  local panel = Panel(fakeMod())
  draw(panel, screen({ party = mons(2), tmhm = { move = "SURF" },
                       able = "ABLE" }))
  ok(printAt(12, 4) ~= nil, "the verdict goes where the bar would be")
  eq(printAt(12, 4).text, "ABLE", "and says which")
  eq(#allOf("bar"), 0, "with no bar drawn under it")
  eq(printAt(13, 3), nil, "and no HP digits beside it")
end

do
  io.write("the submenu\n")
  local panel = Panel(fakeMod())
  draw(panel, screen({ party = mons(2), submenu = { index = 1 } }))
  ok(firstOf("submenu") ~= nil, "the engine draws its own submenu, last")
end

-- ---------------------------------------------------------- standing down

do
  io.write("installing\n")
  local mod = fakeMod()
  local panel = Panel(mod)
  local base = PartyMenu.drawPanel

  eq(panel.install(), true, "the class is patched")
  ok(PartyMenu.drawPanel ~= base, "and drawPanel is not the engine's any more")
  eq(panel.install(), false, "a second install is a no-op")

  -- A panel that raises hands the engine's own back and stops trying: a party
  -- screen that raises every frame is one the player cannot leave.
  local drew = 0
  PartyMenu.drawPanel = base
  PartyMenu.__gen1PartyGen2Panel = nil
  local mod2 = fakeMod()
  local panel2 = Panel(mod2)
  panel2.drawPanel = function() error("no chrome") end
  PartyMenu.drawPanel = function() drew = drew + 1 end
  local vanilla = PartyMenu.drawPanel
  panel2.install()

  PartyMenu.drawPanel(screen({ party = mons(1) }))
  eq(drew, 1, "the engine's own draw is what the player gets")
  ok(#logged > 0, "and it is reported")
  local said = #logged
  PartyMenu.drawPanel(screen({ party = mons(1) }))
  PartyMenu.drawPanel(screen({ party = mons(1) }))
  eq(drew, 3, "every frame after it goes straight there")
  eq(#logged, said, "and says nothing more -- once a session, not once a frame")
  PartyMenu.drawPanel = vanilla
end

do
  io.write("a build that cannot carry it\n")
  PartyMenu.__gen1PartyGen2Panel = nil
  local kept = PartyMenu.drawHpBar
  PartyMenu.drawHpBar = nil
  local mod = fakeMod()
  eq(Panel(mod).install(), false, "install stands down")
  ok(#logged > 0, "and names what is missing")
  PartyMenu.drawHpBar = kept
end

io.write(("party panel gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
