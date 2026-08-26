-- The screen itself.
--
-- The engine's mod manager is src/mods/ManagerState.lua: one stack state
-- with six modes -- list (MODS/PROFILES/ERRORS tabs), detail, options,
-- permissions, errors and apply -- and no hook anywhere on it.  What it does
-- have is a registry entry: src/ui/Screens.lua resolves an id out of
-- Data.screens BEFORE falling back to the builtin module, so registering
-- "ManagerState" replaces the screen for every route in -- the START menu,
-- the OPTION screen, F10, and Gold's own push in src/core/Game2.lua.
--
-- What is replaced here is the DRAWING, and only the drawing.  The manager's
-- logic -- ManagerState.resolveToggle's dependency closure, staged changes,
-- apply-and-restart, profiles, safe mode, the Gen 2 override -- is a
-- thousand lines where a divergence does not look like a skin bug, it looks
-- like a boot that no longer comes up.  So this builds the engine's own
-- instance and hands back that object with its draw methods swapped, which
-- is why the mod declares `engine_internals`: reaching the builtin means
-- requiring it by name, and src/mods/Loader.lua attributes any bare `src.*`
-- require to that permission.  Nothing here patches engine code in place;
-- the substitutions land on one instance, built fresh on every push.
--
-- Two independent ways back to the vanilla screen, because this is the one
-- screen a player uses to switch off a mod that is misbehaving:
--
--   * PRESENTATION: VANILLA, read on every call, so the row takes effect on
--     the next frame without leaving the screen; and
--   * a renderer that throws is logged once and permanently demoted to the
--     engine's own draw for the life of the instance.
--
-- On top of both, src/ui/Screens.lua already pcalls a mod screen's `new` and
-- falls back to the builtin, so a failure in here cannot strand anyone
-- outside the screen they need to fix it from.

local Skin = {}

-- The 20x18 tile screen, with the box border owning row 0 and row 17.
local COLS = 20
local CURSOR_X = 8         -- tile column 1
local LABEL_X = 16         -- tile column 2
local EDGE_X = 152         -- one past the last interior column
-- What a whole-width string has to fit inside, measured from the label
-- column: the interior less the margin the cursor sits in.
Skin.LINE_BUDGET = EDGE_X - LABEL_X
local RULE_FROM, RULE_TO = 1, 18

-- The card viewport, and deliberately the exact geometry
-- src/ui/OptionRows.lua uses for the game's own OPTION screen: four
-- full-width 20x4 boxes stacked down the screen, the label on the first line
-- inside each and its value indented on the second, the cursor in the margin
-- beside the label.
--
-- A card holds two whole lines, of 17 and 16 glyphs.  That is why nothing on
-- these screens is cut short any more: the layout it replaces fitted eleven
-- rows on a screen by giving each one a single line to share between a name
-- and its value, and a name of any length lost that argument.
--
-- ManagerState:moveCursor clamps self.scroll to a window of ELEVEN rows, so
-- the list re-clamps to this number itself (src/screen.lua); left alone, the
-- cursor would walk seven rows past the bottom card.
local CARD_H, CARDS = 4, 4
local INDENT_X = 24        -- tile column 3, where a card's value line starts

-- Where the game's own OPTION screen puts its more-arrow, which is the one
-- screen this mod draws that has no bands: Skin.drawPlainRows is OptionRows'
-- own four-box layout minus its CANCEL line.
local MARGIN_ROW = 16

-- ...and the column it puts it in: 18 is the last interior column of a
-- full-width box, so an arrow there sits in the frame's bottom-right corner
-- cell rather than below the frame, which is where OptionRows has a spare
-- row and the list does not.
local MORE_X = 18 * 8

-- The list is banded the way Gen1BillsBox bands its storage screen: a header
-- box across the top, the rows under it, and an info box at the bottom
-- naming what the cursor is on.  Its own header is the geometry copied here
-- -- Font.drawBox(0, 0, 20, 3), the title a column inside it, and a value
-- right-aligned to x=144, which leaves the last interior column as padding
-- rather than running text up against the border.
local HEADER_TH = 3               -- tiles, as Gen1BillsBox's HEADER_TH
local INFO_TY = 15                -- the info box's top, as its INFO_TY
local HEADER_RIGHT = 144          -- where a right-aligned header value ends

-- A list row is one thing -- a name -- so it is a three-tile box with a
-- single line in it.  An OPTION row is two things, a label and its value,
-- which is why the options page keeps the four-tile cards the game's own
-- OPTION screen uses and this does not.
--
-- How many fit depends on whether the tab has an info band under them, and
-- only the MODS tab does.  A band earns its place there by saying something
-- the row cannot -- the mod's category and its state in words.  On PROFILES
-- and ERRORS the row already IS the whole text, so a band could only repeat
-- it back, and the row it would cost is worth more than the echo.
local ROW_TOP, ROW_H = 3, 3
local ROWS_WITH_BAND, ROWS_WITHOUT = 4, 5

-- The MODS tab is tab 1; the other two run their rows to the bottom.
function Skin.rowCountFor(tab)
  return tab == 1 and ROWS_WITH_BAND or ROWS_WITHOUT
end

-- Every fixed word this screen says, in one place.
--
-- All of it is drawn at LABEL_X, which leaves column 1 for the cursor.  The
-- suite measures every one against that budget, because a string that
-- overruns does not look like a bug -- it looks like a word with its last
-- letter missing, which is how "START:APPLY B:EXIT" shipped as
-- "START:APPLY B:EXI" before the guard existed.
Skin.STRINGS = {
  line = {
    -- the header names the page you are on; left and right move between
    -- them, and wrap, which is the engine's own adjustOrTab
    pages = { "MODS", "PROFILES", "ERRORS" },
    manager = "MOD MANAGER",
    permissions = "PERMISSIONS",
    errors = "ERRORS",
    pending = "PENDING CHANGES",
    noChanges = "NO CHANGES",
    options = "OPTIONS",
    unnamed = "(NO NAME)",
    more = " MORE",
    changed = "CHANGED",
  },
  -- A mod's state in words, for the two places that have room for the word
  -- rather than the four-glyph mark a list row carries: the info band under
  -- the list, and the detail screen's own status line.
  states = {
    ON = "ENABLED", OFF = "DISABLED", STGD = "STAGED",
    ERR = "FAILED", BLKD = "BLOCKED", SKIP = "NOT THIS GAME",
  },

  -- No control hints anywhere.  Every screen here is A to choose, B to go
  -- back and the d-pad to move, which is every other menu in the game, and
  -- two lines of the sixteen spent restating it was two lines the cards
  -- wanted more.
  footer = {},
}

local S = Skin.STRINGS
local PAGES = S.line.pages

Skin.CARDS = CARDS

-- The options page sets its own window, so it also has to do its own clamp
-- (see clampOptionScroll): the engine's is OptionRows.clampScroll, sized for
-- the four 20x4 boxes vanilla draws.  Options scroll is 0-based here, the
-- way ManagerState:goTo and OptionRows.draw both treat it; every other mode
-- counts from 1.
-- The options page wears the same three bands as the list: the header names
-- the mod being edited, the info band under the cards carries the help line,
-- and the cards sit between them.  A header box costs three rows and an info
-- box three more, so three cards fit where four did -- an option still needs
-- both its lines, which is what a card is for and what a list row is not.
local OPT_TOP, OPT_COUNT = 3, 3
-- what the mod-options page shows at once, between its two bands
Skin.OPT_COUNT = OPT_COUNT

-- ------- drawing helpers
--
-- Everything measures in pixels rather than glyph counts.  A font mod can
-- ship proportional TTF glyphs (Font.advanceOf answers 5px for those, 11 for
-- double-width kana), so a budget counted in tiles would overflow the box on
-- exactly the installs least able to afford it.

local function fit(Font, text, budget)
  text = tostring(text or "")
  if budget <= 0 then return "" end
  local spans = Font.split(text)
  local shown = Font.spansFitting(spans, budget)
  if shown >= #spans then return text end
  if shown <= 0 then return "" end
  -- cut on a glyph boundary: POKeDEX is seven glyphs across eight bytes, so
  -- a plain sub() can slice a character in half
  return text:sub(1, spans[shown].to)
end

-- A choice row's help line is every choice label joined with " / ", which for
-- a four-way row is well past what a 17-glyph line holds.  Cutting it by width
-- leaves a dangling separator -- "CATEGORY / NAME /" -- so whole items come
-- off the end instead and the line always finishes on a real value.
local function trimList(Font, text, budget)
  text = tostring(text or "")
  if Font.width(text) <= budget then return text end
  if not text:find(" / ", 1, true) then return fit(Font, text, budget) end
  local parts = {}
  for part in (text .. " / "):gmatch("(.-) / ") do parts[#parts + 1] = part end
  while #parts > 1 do
    parts[#parts] = nil
    local joined = table.concat(parts, " / ")
    if Font.width(joined) <= budget then return joined end
  end
  return fit(Font, parts[1] or text, budget)
end

local function rightAt(Font, text, edge, y)
  text = tostring(text or "")
  if text == "" then return edge end
  local x = edge - Font.width(text)
  Font.draw(text, x, y)
  return x
end

local function rule(Font, y, from, to)
  local code = (Font.BORDER and Font.BORDER.h) or 0x7A
  for col = from or RULE_FROM, to or RULE_TO do
    Font.drawCode(code, col * 8, y * 8)
  end
end

-- label on the left, value on the right, and the label yields when the two
-- would collide.  One line per row is the whole point of the mod: vanilla
-- spends a bordered 20x4 box per option and fits four on a screen.
local function pair(Font, label, value, y, gap)
  local py = y * 8
  local valueX = EDGE_X
  if value and value ~= "" then
    valueX = rightAt(Font, value, EDGE_X, py)
  end
  local budget = valueX - LABEL_X - (gap or 8)
  Font.draw(fit(Font, label, budget), LABEL_X, py)
end

-- One framed card.  `value` is the indented second line and `mark` is
-- right-aligned on that same line, so on the mod list a card's category and
-- its status sit at opposite ends of it.
local function drawCard(Font, Theme, top, label, value, mark, focused)
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawBox(0, top, COLS, CARD_H)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(fit(Font, label, EDGE_X - LABEL_X), LABEL_X, (top + 1) * 8)
  local stop, gap = EDGE_X, 0
  if mark and mark ~= "" then
    stop = rightAt(Font, mark, EDGE_X, (top + 2) * 8)
    gap = 8
  end
  if value and value ~= "" then
    Font.draw(fit(Font, value, stop - INDENT_X - gap), INDENT_X, (top + 2) * 8)
  end
  if focused then Font.drawCode(Theme.cursor, CURSOR_X, (top + 1) * 8) end
end

-- The game's own OPTION screen, drawn exactly the way
-- src/ui/OptionRows.lua draws it -- same boxes, same label and value lines,
-- same cursor column, same more-arrow -- and without the fixed CANCEL line
-- underneath.  Same primitive as the mod screens, so the two cannot drift
-- apart, and no engine require: OptionRows is on the loader's Gen 1-only
-- list, and reaching for it here would be a dead patch on a Gold boot.
--
-- B and START already leave this menu, with the same sound and the same
-- pop (src/ui/OptionsMenu.lua:700), so CANCEL is a second way out rather
-- than the only one.
function Skin.drawPlainRows(ui, game, rows, index, scroll)
  local Font, Theme = ui.Font, ui.Theme
  scroll = scroll or 0
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  for slot = 1, CARDS do
    local row = rows[scroll + slot]
    if not row then break end
    local value = ""
    if row.value then
      local ok, text = pcall(row.value, game)
      value = ok and tostring(text or "") or ""
    end
    drawCard(Font, Theme, (slot - 1) * CARD_H, row.label, value, nil,
             (scroll + slot) == index)
  end
  if #rows > scroll + CARDS then
    Font.drawCode(Theme.moreArrow, 18 * 8, MARGIN_ROW * 8)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- What OptionRows.clampScroll does, without requiring it, and without the
-- bottomRow arm -- there is no bottom row here any more.
function Skin.clampPlainScroll(index, scroll, total)
  scroll = scroll or 0
  if index <= scroll then return math.max(0, index - 1) end
  if index > scroll + CARDS then return index - CARDS end
  local tail = math.max(0, total - CARDS)
  if scroll > tail then return tail end
  return scroll
end

-- Gen1BillsBox's drawHeader, with a page name instead of a box number: a
-- full-width three-tile box, the text a column inside it, and a value
-- right-aligned to x=144.  Used for both bands, since the info box at the
-- bottom is the same shape.
--
-- `reserve` gives the more-arrow the column HEADER_RIGHT already left as
-- padding, and a column of clearance before it, so the arrow does not sit
-- flush against the word beside it.
local function drawBand(Font, top, left, right, reserve)
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawBox(0, top, COLS, HEADER_TH)
  love.graphics.setColor(0, 0, 0, 1)
  -- the gap is owed to a value, so a line without one keeps that glyph:
  -- "SAVE CURRENT AS.." is 17 of the 17 a row holds, and lost its last dot
  -- to a gap it was not sharing with anything
  local edge = reserve and (HEADER_RIGHT - 8) or HEADER_RIGHT
  local stop, gap = edge, 0
  if right and right ~= "" then
    stop = rightAt(Font, right, edge, (top + 1) * 8)
    gap = 8
  end
  if left and left ~= "" then
    Font.draw(fit(Font, left, stop - LABEL_X - gap), LABEL_X, (top + 1) * 8)
  end
end

-- One list row: a three-tile box with the name on its single line, the
-- cursor in the margin beside it, and the status right-aligned against the
-- far edge.  A healthy mod has no status, so most names get the whole line.
--
-- `reserve` holds column 18 back for the more-arrow, which is drawn into
-- this box rather than under it.
local function drawRowBox(Font, Theme, top, label, mark, focused, reserve)
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawBox(0, top, COLS, ROW_H)
  love.graphics.setColor(0, 0, 0, 1)
  local stop, gap = reserve and MORE_X or EDGE_X, 0
  if mark and mark ~= "" then
    stop = rightAt(Font, mark, EDGE_X, (top + 1) * 8)
    gap = 8
  end
  Font.draw(fit(Font, label, stop - LABEL_X - gap), LABEL_X, (top + 1) * 8)
  if focused then Font.drawCode(Theme.cursor, CURSOR_X, (top + 1) * 8) end
end

-- ------- the renderer

local function newRenderer(mod, Rows, opt, Builtin)
  local Font, Theme

  local function toolkit()
    -- resolved on first draw, not at load: mod.ui loads its widgets lazily so
    -- a headless loader never drags the render stack in, and this mod is
    -- loaded by that same headless loader in its own test suite
    Font = Font or mod.ui.Font
    Theme = Theme or mod.ui.Theme
    return Font, Theme
  end

  local R = {}

  -- What the options page shows at once.  It is the card count, not a row
  -- count: the engine clamps this page with OptionRows.clampScroll, sized for
  -- the four boxes vanilla draws, and four is what this draws too -- but the
  -- clamp is still owned here rather than inherited, because the two agreeing
  -- today is a coincidence and not a contract.
  function R.optionWindow() return OPT_COUNT end

  -- ------- one row of a list

  local function drawCursor(state, index, y)
    if index == state.cursor then
      Font.drawCode(Theme.cursor, CURSOR_X, y * 8)
    end
  end

  -- A group heading: the label, then the rule running out to the right
  -- margin.  The cursor never lands here (ManagerState:moveCursor skips
  -- headers), so it reads as a divider rather than a choice.
  local function drawHeader(label, y)
    local text = fit(Font, label, EDGE_X - LABEL_X - 24)
    Font.draw(text, LABEL_X, y * 8)
    local from = math.floor((LABEL_X + Font.width(text)) / 8) + 1
    rule(Font, y, from, RULE_TO)
  end

  -- ------- list

  function R.drawList(state)
    local rows = state:rowsForScreen()
    local scroll = math.max(1, state.scroll or 1)

    local banded = state.tab == 1
    local count = Skin.rowCountFor(state.tab)

    -- The count in the header says where you are in the list; an arrow says
    -- there is more of it below, which is a different question and the one
    -- a player asks before pressing down.  It goes in the bottom-right
    -- corner cell of whatever occupies the bottom of the screen -- the info
    -- band on MODS, the fifth row on the other two -- so it is in the same
    -- place on every tab.  Both of those interior lines are row 16.
    local more = #rows > scroll + count - 1
    local moreY = (banded and INFO_TY or ROW_TOP + (count - 1) * ROW_H) + 1

    local focused
    for slot = 1, count do
      local i = scroll + slot - 1
      local row = rows[i]
      if not row then break end
      if i == state.cursor then focused = row end
      -- A row that carries no readable label -- a profile saved without a
      -- name -- would otherwise draw as an empty box.
      local label = row.label
      if label == nil or tostring(label):match("^%s*$") then
        label = S.line.unnamed
      end
      drawRowBox(Font, Theme, ROW_TOP + (slot - 1) * ROW_H, label,
                 row.state ~= "ON" and row.state or nil, i == state.cursor,
                 more and not banded and slot == count)
    end

    -- ------- the header band
    --
    -- A notice wants the header's line and is the more urgent of the two, so
    -- the page name stands down while one is up rather than being painted
    -- over -- overdraw would leave them stacked in the same place and only
    -- look right by accident.
    if state.notice then
      drawBand(Font, 0, state.notice, nil)
    else
      local total, ordinal = 0, 0
      for i, row in ipairs(rows) do
        if not (row.header or row.inert) then
          total = total + 1
          if i == state.cursor then ordinal = total end
        end
      end
      drawBand(Font, 0, PAGES[state.tab] or PAGES[1],
               total > 0 and (math.max(ordinal, 1) .. "/" .. total) or nil)
    end

    -- ------- the info band, on the MODS tab only
    --
    -- Gen1BillsBox spends its bottom three rows on "one line naming what the
    -- cursor is on".  Here that is the focused mod's category and its state
    -- in the word the detail screen uses, rather than the four-glyph mark the
    -- row carries -- both things the row has no room to say.  The other two
    -- tabs have rows that already carry their whole text, so they spend
    -- those three rows on a fifth row instead.
    if banded and focused and focused.mod then
      drawBand(Font, INFO_TY, focused.category, S.states[focused.state or "ON"],
               more)
    elseif banded then
      drawBand(Font, INFO_TY, nil, nil, more)
    end

    -- Last, so it is never the thing a band paints over.  The band's own
    -- value stops at HEADER_RIGHT, one column short of the border, which is
    -- the padding this arrow now occupies; a row yields that column through
    -- drawRowBox's `reserve`.
    if more then Font.drawCode(Theme.moreArrow, MORE_X, moreY * 8) end
  end

  -- ------- detail
  --
  -- The action rows are pinned to the bottom and the description takes
  -- whatever is left, so a mod carrying every row it can (ENABLE, OPTIONS,
  -- PERMISSIONS, the Gen 2 override, FOR, GH, EXPERIMENTAL, VIEW ERROR,
  -- BACK) still fits.  Vanilla draws that ninth row at tile 19, off the
  -- bottom of a screen that ends at 17.

  function R.drawDetail(state)
    local m = state.currentMod
    if not m then return end
    local rows = state:rowsForScreen()

    pair(Font, m.name or m.id, m.version and ("v" .. m.version) or nil, 1)
    rule(Font, 2)

    local state_ = R.stateOf(state, m)
    pair(Font, S.states[state_] or state_,
         (m.category or "OTHER") .. "/" .. (m.profile or "content"), 3)

    local actionTop = math.max(5, 17 - #rows)
    local descTop, descBottom = 4, actionTop - 2
    local lines = R.wrap(m.error and ("FAILED: " .. m.error)
      or (m.note and ("SKIPPED: " .. m.note)) or m.description or "", 16)
    local visible = descBottom - descTop + 1
    for i = 1, visible do
      local line = lines[(state.descScroll or 1) + i - 1]
      if not line then break end
      Font.draw(line, LABEL_X, (descTop + i - 1) * 8)
    end
    if (state.descScroll or 1) + visible <= #lines then
      Font.drawCode(Theme.moreArrow, 18 * 8, descBottom * 8)
    end

    rule(Font, actionTop - 1)
    for i, row in ipairs(rows) do
      local y = actionTop + i - 1
      if y <= 16 then
        Font.draw(fit(Font, row.label, EDGE_X - LABEL_X), LABEL_X, y * 8)
        drawCursor(state, i, y)
      end
    end
  end

  -- ------- permissions / errors

  function R.drawSimple(state, title)
    Font.draw(title, LABEL_X, 1 * 8)
    rule(Font, 2)
    local rows = state:rowsForScreen()
    local top, window = 3, 11
    local last = math.min(#rows, (state.scroll or 1) + window - 1)
    local y = top
    for i = state.scroll or 1, last do
      local row = rows[i]
      if row.header then
        drawHeader(row.label, y)
      elseif row.state then
        -- the mark legend: the same right-hand column the list uses, in the
        -- same place, so the two read as one thing
        pair(Font, row.label, row.state, y)
      else
        local x = LABEL_X
        if row.glyph and row.glyph ~= " " then
          Font.draw(row.glyph, LABEL_X, y * 8)
          x = LABEL_X + 16
        end
        Font.draw(fit(Font, row.label, EDGE_X - x), x, y * 8)
      end
      -- vanilla's drawRows marks any non-heading row, inert included, and a
      -- list you can scroll with nothing showing where you are in it is
      -- exactly what the ERRORS tab looked like before
      if not row.header then drawCursor(state, i, y) end
      y = y + 1
    end
    if #rows > last then
      Font.drawCode(Theme.moreArrow, 18 * 8, (top + window) * 8)
    end
    if state.notice then
      Font.draw(fit(Font, state.notice, EDGE_X - LABEL_X), LABEL_X, 16 * 8)
    end
  end

  -- ------- apply

  function R.drawApply(state)
    Font.draw(S.line.pending, LABEL_X, 1 * 8)
    rule(Font, 2)
    local staged = state:stagedList()
    local rows = state:rowsForScreen()
    local actionTop = math.max(5, 17 - #rows)

    local y = 3
    if #staged == 0 then
      Font.draw(S.line.noChanges, LABEL_X, y * 8)
    end
    -- One row is held back for the overflow line, so "N MORE" gets a line of
    -- its own rather than landing on the last staged mod's own ON/OFF.
    local slots = actionTop - 4
    local hidden = #staged - slots
    if hidden > 0 then slots = slots - 1 end
    for i = 1, math.min(#staged, slots) do
      local m = staged[i]
      pair(Font, m.name or m.id, m.enabled and "ON" or "OFF", y)
      y = y + 1
    end
    hidden = #staged - slots
    if hidden > 0 then
      -- "N MORE", not "+N": the Game Boy charmap has no + glyph (nor * ~ < >
      -- & =), and a character it does not carry is drawn as a space
      Font.draw(hidden .. S.line.more, LABEL_X, y * 8)
    end

    rule(Font, actionTop - 1)
    for i, row in ipairs(rows) do
      local ry = actionTop + i - 1
      if ry <= 16 then
        Font.draw(fit(Font, row.label, EDGE_X - LABEL_X), LABEL_X, ry * 8)
        drawCursor(state, i, ry)
      end
    end
  end

  -- ------- the per-mod options page
  --
  -- The one screen this mod exists for.  Vanilla renders it through
  -- src/ui/OptionRows.lua: four bordered 20x4 boxes, label on one line and
  -- value on the next, four options visible at a time and nothing else on
  -- screen.  Here each option is one line -- label left, value right -- so
  -- eleven fit, with the mod's name above them and a line below saying what
  -- the focused row accepts.
  --
  -- OptionRows is also on the engine's own GEN1_ONLY_MODULES list
  -- (src/mods/Loader.lua): it "paints Red's chrome over Gold's options
  -- screen, whose layout is one 18x16 box rather than four 20x4 ones".
  -- Drawing the rows here rather than through it is what makes this page
  -- right on Gold as well.

  function R.drawOptions(state)
    local m = state.currentMod
    local rows = state.optionRows or {}
    local scroll = state.scroll or 0

    for slot = 1, OPT_COUNT do
      local i = scroll + slot
      local row = rows[i]
      if not row then break end
      local value = ""
      if row.value then
        local ok, text = pcall(row.value, state.game)
        value = ok and tostring(text or "") or ""
      end
      -- CHANGED marks a value the player has moved off the author's default;
      -- it sits at the end of the value line, where there is room for it
      drawCard(Font, Theme, OPT_TOP + (slot - 1) * CARD_H, row.label, value,
               row.changed and S.line.changed or nil, i == state.cursor)
    end

    -- ------- the header band: whose options these are, and how far down them
    if state.notice then
      drawBand(Font, 0, state.notice, nil)
    else
      drawBand(Font, 0, (m and (m.name or m.id)) or S.line.options,
               #rows > OPT_COUNT
                 and (math.min(state.cursor or 1, #rows) .. "/" .. #rows)
                 or nil)
    end

    -- ------- the info band: what the focused row accepts
    --
    -- Named after what the cursor is on, the same rule the list's band
    -- follows.  With HELP LINE off that is the row's own label, which is
    -- worth having: a label too long for its card is readable here.
    local more = #rows > scroll + OPT_COUNT
    local row = rows[state.cursor]
    local text
    if row then
      if opt("help_line") and row.help then
        -- the same budget drawBand is about to apply, so whole choices come
        -- off the end here rather than fit() cutting one in half in there
        text = trimList(Font, row.help,
                        (more and HEADER_RIGHT - 8 or HEADER_RIGHT) - LABEL_X)
      else
        text = row.label
      end
    end
    drawBand(Font, INFO_TY, text, nil, more)
    -- Same corner cell as the list's, for the same reason: the count says
    -- where you are, the arrow says there is more below it.
    if more then Font.drawCode(Theme.moreArrow, MORE_X, (INFO_TY + 1) * 8) end
  end

  -- ------- shared

  -- ManagerState's own wrap, which is file-local there.  Word wrap at a
  -- column budget, one list of lines per paragraph.
  function R.wrap(text, width)
    local lines = {}
    for paragraph in tostring(text or ""):gmatch("[^\n]+") do
      local line = ""
      for word in paragraph:gmatch("%S+") do
        if line == "" then
          line = word
        elseif #line + 1 + #word <= width then
          line = line .. " " .. word
        else
          lines[#lines + 1] = line
          line = word
        end
      end
      if line ~= "" then lines[#lines + 1] = line end
    end
    return lines
  end

  -- The state word for one mod, from the same facts ManagerState:glyphFor
  -- reads.  isStaged and runsHere are methods, so this needs the instance.
  function R.stateOf(state, m)
    return Rows.stateOf({
      staged = state:isStaged(m),
      enabled = m.enabled and true or false,
      skipped = m.state == "wrong_generation" or not state:runsHere(m),
      blocked = m.state == "blocked_dependency",
      errored = m.error ~= nil,
    })
  end

  function R.draw(state)
    toolkit()

    -- The two card screens paint the way the game's own OPTION screen does:
    -- white paper, no outer frame, and the cards themselves are the chrome.
    -- Everything else is prose or a short action list, and keeps the single
    -- bordered window that suits it.
    -- All three list tabs and the options page paint the way the game's own
    -- OPTION screen does: white paper, no outer frame, the cards themselves
    -- the chrome.  Detail, permissions, errors and apply are prose or a
    -- short action list, and keep the single bordered window that suits it.
    if state.screen == "list" or state.screen == "options" then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      love.graphics.setColor(0, 0, 0, 1)
      -- Both banded screens put their own notice in their header band, the
      -- one line either has spare: every other row of both is inside a box.
      if state.screen == "list" then R.drawList(state) else R.drawOptions(state) end
      love.graphics.setColor(1, 1, 1, 1)
      -- the confirm/notice modal stays the engine's: it is a centred box with
      -- its own cursor index, and nothing about it is unreadable
      if state.overlay then Builtin.drawOverlay(state) end
      return
    end

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(1, 1, 1, 1)
    Font.drawBox(0, 0, COLS, 18)
    love.graphics.setColor(0, 0, 0, 1)

    if state.screen == "detail" then
      R.drawDetail(state)
    elseif state.screen == "permissions" then
      R.drawSimple(state, S.line.permissions)
    elseif state.screen == "errors" then
      R.drawSimple(state, S.line.errors)
    elseif state.screen == "apply" then
      R.drawApply(state)
    end

    love.graphics.setColor(1, 1, 1, 1)
    if state.overlay then Builtin.drawOverlay(state) end
  end

  return R
end

Skin.newRenderer = newRenderer

return Skin
