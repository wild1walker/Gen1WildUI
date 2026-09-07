-- UI THEME on a Gen 2 boot: the same two themes, through Gold's own colour.
--
-- ------- why this is a second file and not a branch in theme.lua
--
-- runtime/theme.lua works by rewriting the SGB zone list: Red draws every
-- page in four DMG shades and the colour arrives afterwards, from a pass that
-- blits the finished frame once per rectangle through that rectangle's own
-- four colours.  Swapping those four is why DARK cannot move a glyph.
--
-- Gold is a CGB game and has no such pass.  `render.zones` is still raised at
-- the same instant (src/core/Game2.lua:1551) and a mod may still return a zone
-- list, but Gold computes none of its own unless CLASSIC is on -- the comment
-- there says it plainly: "Gold is a CGB game whose colour is already IN the
-- picture".  There is nothing to reverse.  A theme built on that hook would
-- have exactly the failure the Gen 1 file's own history warns about: it would
-- never fire.
--
-- ------- the seam Gold does have
--
-- Gold's colour goes on while the page is DRAWN, per tile, out of a palette
-- the drawing routine is handed.  Nearly every one of them is handed nothing
-- and falls back to one table:
--
--     Chrome.DEFAULT_BOX_PALETTE   (src/ui/gen2/Chrome.lua:137)
--
-- `Chrome.box`, `Chrome.textbox`, `Chrome.print`, `Chrome.printRight`,
-- `Chrome.clear`, `Chrome.paletteFill` and `Chrome.letterbox` all read it,
-- all read it AT CALL TIME, and fifty-two files under src/ draw through them.
-- It is the same four numbers a Gen 1 zone carries, in the same order --
-- colour 0 the paper, colour 3 the ink -- doing the same job one step earlier
-- in the frame.
--
-- So this file is the Gen 1 file's mechanism moved one step earlier: rewrite
-- those four, in place, once a frame.  Nothing is redrawn, no screen is
-- edited, no feature learns that themes exist, and a theme that cannot move a
-- glyph cannot move a glyph off the screen -- the property the whole design
-- is for, kept for the same reason and by the same means.
--
-- ------- in place, and why that matters
--
-- The four entries are overwritten inside the existing table rather than the
-- table being replaced.  Two things depend on it.  `src/ui/gen2/TrainerCard.
-- lua` passes `Chrome.DEFAULT_BOX_PALETTE` explicitly to seventeen calls, so
-- identity has to keep holding or the card would be the one page that stayed
-- light.  And anything that captured the table at load -- a third-party Gold
-- mod, a future engine screen -- keeps reading the live value instead of a
-- snapshot of white.
--
-- ------- when
--
-- `core.update`, which main.lua raises once a frame on both generations
-- (src/core/PlatformHooks.lua:11) and which runs BEFORE the frame is drawn.
-- `render.zones` is the wrong end: by the time it fires the page has already
-- been painted in whatever the palette said a moment ago.
--
-- The decision is per frame rather than per page because on Gold one frame is
-- one page: the top state owns the picture, and an overlay stacked on it -- a
-- text box over the overworld -- is drawn through this same chrome and wants
-- the same answer.  That is the one visible difference from Gen 1, and it is
-- the right one: under DARK, Gold's own message boxes go dark with the menus
-- instead of staying white over a dark page.
--
-- ------- what is NOT themed
--
-- Everything that hands Chrome a palette of its own, which is Gold's way of
-- saying "these colours are the content": the pack's pocket tabs, the dex's
-- inverted page, the trainer card's badges, every mon and item sprite, the
-- battle HUD.  They keep their own colours exactly as they are, and the text
-- and chrome around them themes -- which is the same split the Gen 1 file
-- draws between a page and the true-colour art sitting on it, arrived at from
-- the other side.
--
-- And, as on Gen 1, the frames that are PICTURES rather than pages: the
-- overworld, a battle, the title screen, the intros and the animations.
--
-- That exclusion is the one thing this arm has to do real work for, and it is
-- worth saying why rather than leaving it as a list.  On Gen 1 a battle is
-- excluded for free: it never asks for the four greys, so the zone rule never
-- claims it.  Here it is the opposite -- Gold's battle field is literally
-- `Chrome.clear()`, the first line of `BattleState:drawPanel`
-- (src/ui/gen2/BattleState.lua:4246), which is a whole-screen fill through
-- this very table.  Left alone, DARK would paint every battle's field black.
--
-- So the page has to be identified before the palette is set, and it is
-- identified exactly the way the Gen 1 arm identifies one: the topmost state
-- that either says it is ours (`state.gen1wildTheme`, set on every screen
-- this suite registers) or is one of the engine classes in `Theme2.PAGES`.
-- Gold's overworld is not a stack state at all, so a plain overworld frame
-- finds nothing and is left alone -- and so is a text box standing over it,
-- which is the same answer Gen 1 gives for the same frame.

local PAGE_MODULES = {
  -- The menus and text pages.  Every one of these is a full-screen box-and-
  -- text page in the same sense Red's OPTION screen is, which is the test the
  -- Gen 1 list applies.
  "src.ui.gen2.PokedexMenu",
  "src.ui.gen2.PartyMenu",
  "src.ui.gen2.SummaryMenu",
  "src.ui.gen2.TrainerCard",
  "src.ui.gen2.PackMenu",
  "src.ui.gen2.MartMenu",
  "src.ui.gen2.OptionsMenu",
  "src.ui.gen2.Pokegear",
  -- Bill's PC and the four other things a PC is on Gold.
  "src.ui.gen2.PcMenu",
  "src.ui.gen2.BoxMenu",
  "src.ui.gen2.CenterPcMenu",
  "src.ui.gen2.ItemPcMenu",
  "src.ui.gen2.MailboxMenu",
  -- MAIL, the day-care, the held-item row, decorations, the trade desk.
  "src.ui.gen2.MailMenu",
  "src.ui.gen2.MailRead",
  "src.ui.gen2.MailCompose",
  "src.ui.gen2.DayCareMenu",
  "src.ui.gen2.HeldItemMenu",
  "src.ui.gen2.DecorationMenu",
  "src.ui.gen2.TradeMenu",
  -- The move screens.
  "src.ui.gen2.MoveDeleter",
  "src.ui.gen2.MoveTutor",
  -- The START menu, and the lift panel that is the same idea on a smaller
  -- box.  Both stand OVER the world rather than replacing it, and that is
  -- exactly why the Gen 1 arm leaves Red's START menu alone -- there, the
  -- box takes its four colours from the zone the map is wearing, so
  -- reversing them reverses the map with it.  Here nothing of the sort is
  -- true: the world is drawn from its own tile palettes and never reads this
  -- table (there is not one `Chrome.` call in src/world/gen2/World.lua),
  -- while the box, its rows and its cursor are `Chrome.box` / `Chrome.print`
  -- and read nothing else.  So the reversal lands on the box and stops
  -- there, and the reason Red's is excluded does not survive the crossing.
  "src.ui.gen2.StartMenu",
  "src.ui.gen2.ElevatorMenu",
  -- The incoming-call strip, for exactly the reason the two above are here.
  -- It is pushed as a stack state (CallAsm's showCallerBox), it is drawn with
  -- nothing but `Chrome.textbox` and `Chrome.print`, and the overworld behind
  -- it reads none of these four numbers -- so the reversal lands on the strip
  -- and stops there.  Without it a call came up as the cart's white box on a
  -- black page: the one thing on screen that had not been told the lights
  -- were off.
  --
  -- A call puts a TEXT PAGE over the box while it is being read, so the top of
  -- the stack during one is a TextBox rather than this -- which is already the
  -- case `pageOf` walks down through, the same way it does for a box over any
  -- other page.
  "src.ui.gen2.CallerBox",
  -- Naming, and the boot menu behind the title.
  "src.ui.gen2.NamingScreen",
  "src.ui.gen2.NamePick",
  "src.ui.gen2.MainMenu",
  "src.ui.gen2.SaveMenu",
  "src.ui.gen2.InitClock",
  "src.ui.gen2.GenderSelect",
  -- Oak's speech.  It is the one entry here that is a PICTURE by the rule
  -- above -- it owns the frame and draws portraits on it -- and it is a page
  -- anyway, for the reason the Gen 1 arm gives for the same screen: it is the
  -- first thing a new game shows, and it was the one place DARK stayed light
  -- all the way through.  What makes it safe is the pair of wraps in
  -- `install` below, which move its own white page and the white plate behind
  -- its portraits onto the theme.  Without those this entry alone is a dark
  -- box on a white page; without this entry those wraps never fire.
  "src.ui.gen2.OakSpeech",
  -- The desks and counters: Mom's bank, the prize counters, the contest sign
  -- up, the radio, the Battle Tower, Buena's password.
  "src.ui.gen2.BankOfMom",
  "src.ui.gen2.PrizeMenu",
  "src.ui.gen2.ContestMenu",
  "src.ui.gen2.MapRadio",
  "src.ui.gen2.BattleTowerMenu",
  "src.ui.gen2.BuenaPassword",
  "src.ui.gen2.ScriptMenu",
  -- The mod manager, which is the same class on both generations and is
  -- already named in the Gen 1 arm's list for the same reason.
  "src.mods.ManagerState",
}

-- Left out deliberately, and each was read before being left out.
--
-- The pictures: `BattleState` (its field is `Chrome.clear`, see above --
-- except on the frames BACKDROPS has replaced that call with art, which the
-- walk asks the instance about),
-- `TitleState`, `GoldSilverIntro`, `CrystalIntro`, `CopyrightSplash`,
-- `CrystalSplash`, `GameFreakPresents`, `Credits`, `HallOfFame`, `Diploma`,
-- `EvolutionAnim`, `EggHatchAnim`, `TradeAnim`, `SlotMachine`, `CardFlip`,
-- `UnownPuzzle`, `UnownPrinter`, `PhotoStudio`, `MagnetTrainRide`.
--
-- The transitions, which are a fade and nothing else: `BattleTransition`,
-- `MenuFade`, `BlankScreen`, `WaitPlaySFX`.
--
-- `OakSpeech`, and this one differs from Gen 1 on purpose.  The Gen 1 arm
-- themes it and gets away with it because Red's portraits are true-colour
-- rectangles the shade pass never touches, with runtime/matte.lua painting
-- the page colour underneath them.  Gold has neither: the portraits are drawn
-- into the picture in their own colours, and there is no matte because there
-- is nothing raw to repair.  Reversing the box palette there would put a
-- lit white portrait on a black page with a white seam around it, which is
-- worse than the light screen it replaced.
--
-- ------- the one box that is not reached by four numbers
--
-- The YES/NO box (`src/ui/ChoiceBox.lua`) is shared between the generations
-- and paints like a Gen 1 screen: `Font.drawBox` for the box, `Font.draw` and
-- `Font.drawCode` for the labels and the cursor.  None of those reads the
-- table this file rewrites, so no swap of four numbers can move it, and it
-- stayed white under DARK while every box around it went black.
--
-- 0.32.25 said that could not be closed without drawing.  The second half of
-- that is true and the first half was wrong: `Chrome.paletteBox` IS
-- `Font.drawBox` with a palette shader around it, so drawing the same box out
-- of the same glyphs through the same four numbers is a fold, not a redesign.
-- runtime/choicebox2.lua is that fold, and it is a file of its own precisely
-- because it draws -- which is the one thing this file promises never to do,
-- and the promise is worth more than the convenience of putting them
-- together.
--
-- What is left here is the walk: the box is FURNITURE below, so a question
-- standing on a page leaves the page themed.  It was not, and that cost more
-- than the box's own colours -- see the note on the list itself.
local Theme2 = {}
Theme2.PAGES = PAGE_MODULES

-- What Gold ships (src/ui/gen2/Chrome.lua:137).  Held by value, because the
-- table itself is the one being rewritten and LIGHT has to put it back.
local VANILLA = {
  { 255, 255, 255 }, { 255, 255, 255 }, { 255, 255, 255 }, { 0, 0, 0 },
}

-- DARK, and it is the reversal rather than a second design: paper black, ink
-- white, and the two between them exchanged -- the same transform
-- runtime/theme.lua applies to a Gen 1 zone, applied to the same four
-- numbers.  Gold's default has three whites and a black, so the reversal is
-- one white and three blacks, and a glyph's own anti-aliased midtones come
-- out light on dark instead of dark on light.
local DARK = {
  { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 255, 255, 255 },
}

Theme2.VANILLA = VANILLA
Theme2.DARK = DARK

-- Same two names, same order, same default as the Gen 1 arm.  A player who
-- moves a save between the two generations finds the row where they left it,
-- because it is stored under the same key with the same values.
Theme2.ORDER = { "light", "dark" }
Theme2.LABELS = { light = "LIGHT", dark = "DARK" }
Theme2.DEFAULT = "light"

-- Copy `from` over `into` without changing which table `into` is.
local function overwrite(into, from)
  for i = 1, 4 do
    local c = from[i]
    into[i] = { c[1], c[2], c[3] }
  end
end

Theme2.overwrite = overwrite

-- Whether two palettes carry the same four colours, so a frame that would
-- write what is already there writes nothing.  Twelve compares beats twelve
-- table allocations every frame of the game.
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for i = 1, 4 do
    local x, y = a[i], b[i]
    if type(x) ~= "table" or type(y) ~= "table" then return false end
    if x[1] ~= y[1] or x[2] ~= y[2] or x[3] ~= y[3] then return false end
  end
  return true
end

Theme2.same = same

-- The page classes, resolved to the class tables themselves so a state can be
-- matched by `getmetatable`.  Built on the first frame that needs them rather
-- than at load, because a require is cheap but not free and a LIGHT boot
-- never asks.  A module this build does not carry -- the three Crystal-only
-- screens on a Gold cart, say -- resolves to nothing and simply has no entry.
local pageClasses

local function classes()
  if pageClasses then return pageClasses end
  pageClasses = {}
  for _, path in ipairs(PAGE_MODULES) do
    local ok, class = pcall(require, path)
    if ok and type(class) == "table" then pageClasses[class] = true end
  end
  return pageClasses
end

-- Is this frame a page of ours?
--
-- Top of the stack downwards, and the first state that answers ends the walk:
-- a state that says it is ours, or is one of the classes above, is the page;
-- anything else that is a full-screen owner is a picture and the frame is not
-- a page.  Unlike the Gen 1 arm there is no `sgbPalettes` to ask "do you own
-- this frame's colours", because on Gold nothing does -- so the test is
-- simply the topmost state, plus a step over the overlays that are not pages
-- in their own right.
--
-- Gold's overworld is not a stack state, so an empty stack is the world: not
-- a page, and left alone.  That is also what makes a text box over the
-- overworld come out unthemed, which is the answer Gen 1 gives for the same
-- frame.
-- Two kinds of thing stand on top of a page, and they want opposite answers
-- when there is no page underneath.
--
-- FURNITURE is drawn through this very table: Gold's dialogue box asks for
-- `Chrome.paletteBox(..., Chrome.DEFAULT_BOX_PALETTE)` and takes its glyph
-- colours out of the same four (src/render/TextBox.lua:669-678).  So a
-- message box is not something standing in front of the page -- on the frames
-- it is the only box on the screen it IS the page, in the only sense this
-- file means the word: the thing whose colours these four numbers are.
--
-- A VEIL is drawn through nothing.  MenuFade, BlankScreen and WaitPlaySFX are
-- a rectangle and a wait; reversing the palette under one changes no pixel
-- while it is up and the wrong pixels the frame it comes off.
--
-- Both are stepped over on the way down -- a confirm box over the PACK leaves
-- the PACK themed, which is the answer either kind wants there.  They differ
-- only at the bottom of the walk, and that difference is the overworld: a
-- veil over the map is the map, and the map is a picture; a message box over
-- the map is a box, and every box in this game is ours to colour.
--
-- That is a change from 0.32.23, which treated the two alike and so left
-- Gold's most-seen box -- every line of dialogue in the game -- white on a
-- dark boot, while the menu it had just come out of was black.  The header
-- above already promised the opposite ("Gold's own message boxes go dark with
-- the menus"); this is the walk finally saying it.
local FURNITURE_MODULES = {
  "src.render.TextBox",
  -- The YES/NO box, which stands on top of the text box that asked the
  -- question -- so leaving it out did not merely leave IT unthemed, it ended
  -- the walk one state early and took the page underneath with it: answer a
  -- `yesorno` on a dark PACK and the PACK went white for as long as the
  -- question was up.  It is furniture for the same reason the text box is,
  -- once runtime/choicebox2.lua has it drawing through this table.
  "src.ui.ChoiceBox",
}

local VEIL_MODULES = {
  "src.ui.gen2.MenuFade",
  "src.ui.gen2.BlankScreen",
  "src.ui.gen2.WaitPlaySFX",
}

local function resolver(paths)
  local resolved
  return function()
    if resolved then return resolved end
    resolved = {}
    for _, path in ipairs(paths) do
      local ok, class = pcall(require, path)
      if ok and type(class) == "table" then resolved[class] = true end
    end
    return resolved
  end, function() resolved = nil end
end

local furniture, forgetFurniture = resolver(FURNITURE_MODULES)
local veils, forgetVeils = resolver(VEIL_MODULES)

-- Below all three resolvers, because it calls all three.  A `local` read
-- above its own declaration is a GLOBAL read and therefore nil, which is the
-- mistake that took the battle UI out in 0.32.3; tools/check.py fails on it
-- now, and this is the shape it looks for.
Theme2.forgetClasses = function()
  pageClasses = nil
  forgetFurniture()
  forgetVeils()
end

function Theme2.pageOf(game)
  local stack = game and game.stack
  local states = stack and stack.states
  if type(states) ~= "table" then return nil end
  local pages, boxes, fades = classes(), furniture(), veils()
  -- The topmost piece of furniture stepped over, kept in case the walk
  -- reaches the bottom without finding a page under it.
  local carried
  for i = #states, 1, -1 do
    local state = states[i]
    if type(state) == "table" then
      -- One of ours: every screen this suite registers is marked on the way
      -- out of runtime/facade.lua, so a feature's own page needs no entry in
      -- the list above and no edit here when a new one is added.
      if state.gen1wildTheme then return state end
      local class = getmetatable(state)
      if class and pages[class] then return state end
      -- A battle standing on a BACKDROP, which is the one exclusion below
      -- that stops being true under a condition rather than never.
      --
      -- The reason a battle is not a page is exact: Gold's field is
      -- `Chrome.clear()`, a whole-screen fill through this very table, so
      -- theming one would paint every field black.  BACKDROPS replaces that
      -- call with a picture, and when it does the fill never happens -- so
      -- there is no field for four numbers to reach and the boxes, the HUD
      -- plates and the message box can go dark with the rest of the game.
      --
      -- Set by Gen1Arena on the instance, per frame, and only for the frames
      -- it actually took (`consumed`): a battle it found no backdrop for is
      -- still the cart's white field and still not a page.  Read one frame
      -- behind, because the theme runs before the draw that sets it -- which
      -- costs the first frame of a battle its theme and nothing after it.
      if state.gen1wildArenaField then return state end
      if class and boxes[class] then
        -- stepped over, but remembered: if there is a page under it that
        -- page is what is on the screen, and if there is not, this is.
        carried = carried or state
      elseif not (class and fades[class]) then
        -- Anything else is a picture and ends the walk, because whatever is
        -- under it is not what is on the screen.  A battle's own message box
        -- comes out here rather than themed, which is right: the field
        -- behind it is `Chrome.clear` and cannot go with it.
        return nil
      end
    end
  end
  -- The bottom of the stack, which on Gold is the overworld.  A veil there
  -- leaves nothing carried and the map is left alone; a box there is the one
  -- thing on the screen wearing these four colours.
  return carried
end

function Theme2.new(context)
  local mod = context.mod
  local optionset = context.optionset
  -- The SAME key the Gen 1 arm owns.  One row, one stored value, both
  -- generations -- see the ORDER note above.
  local KEY = "ui_theme"

  local self = {}

  -- ------- read once a frame
  --
  -- Same cache, same reason, same invalidation as runtime/theme.lua's: the
  -- read walks the live game's save, the mod's option store and the row's
  -- fallbacks behind two pcalls, and it is asked on every frame.  Kept
  -- against `optionset.generation()` so a write made through the other
  -- bundle's menu or the bench -- neither of which comes through this file --
  -- still lands on the next frame.
  local answer, answerAt

  function self.read()
    local now = optionset.generation and optionset.generation() or nil
    if answer and answerAt == now then return answer end
    local value = optionset.read(mod, KEY)
    if not Theme2.LABELS[value] then value = Theme2.DEFAULT end
    answer, answerAt = value, now
    return value
  end

  function self.forget()
    answer, answerAt = nil, nil
  end

  function self.write(value, game)
    if not Theme2.LABELS[value] then return end
    self.forget()
    return optionset.write(mod, KEY, value, game)
  end

  function self.label(value)
    return Theme2.LABELS[value or self.read()] or Theme2.LABELS[Theme2.DEFAULT]
  end

  function self.step(direction, game)
    local current = self.read()
    local at = 1
    for index, name in ipairs(Theme2.ORDER) do
      if name == current then at = index end
    end
    local next_ = Theme2.ORDER[((at - 1 + (direction or 1)) % #Theme2.ORDER) + 1]
    self.write(next_, game)
    return next_
  end

  function self.defineRow()
    optionset.own({
      key = KEY,
      type = "choice",
      label = "UI THEME",
      choices = {
        { Theme2.LABELS.light, "light" },
        { Theme2.LABELS.dark, "dark" },
      },
      default = Theme2.DEFAULT,
    })
  end

  -- The palette this theme wants on the frame about to be drawn.
  function self.palette()
    return self.read() == "dark" and DARK or VANILLA
  end

  -- What a screen of ours should paint behind a picture, in the same shape
  -- the Gen 1 arm's `matte` answers: the page's own paper colour, or nil when
  -- there is nothing to match.  LIGHT is white paper, which is what an
  -- unpainted box already is, so it answers nil and nothing is painted.
  function self.matte()
    if self.read() ~= "dark" then return nil end
    return { 0, 0, 0 }
  end

  -- Gold's art is not blitted raw past a shade pass the way a Gen 1
  -- true-colour mark is, so there is no hairline to skirt and nothing here
  -- has to paint one.  Present and answering nil so a caller written against
  -- the Gen 1 arm needs no generation test of its own.
  function self.skirt()
    return nil
  end

  -- ------- what the bench reads
  --
  -- Same three names the Gen 1 arm publishes, so the bench's rows need no
  -- generation branch.  Boxes and panels are Gen 1 ideas -- this arm records
  -- neither, because it never has to find a box to repaint -- so they answer
  -- zero, and `zones` answers how many frames this theme has actually
  -- painted, which is the number that says whether it is running.
  local painted = 0

  function self.probe()
    return 0, 0, painted
  end

  function self.artProbe()
    return 0, self.label(), painted > 0
  end

  function self.install()
    local Chrome = require("src.ui.gen2.Chrome")
    local live = Chrome.DEFAULT_BOX_PALETTE
    if type(live) ~= "table" or type(live[4]) ~= "table" then
      error("src.ui.gen2.Chrome has no DEFAULT_BOX_PALETTE to theme", 0)
    end

    -- What Gold actually shipped, read off the module rather than trusted
    -- from the constant above: an engine that retunes its default, or another
    -- mod that has already recoloured it, is what LIGHT has to put back.
    -- Taken once, at install, before this file has written anything.
    local vanilla = {}
    overwrite(vanilla, live)

    -- Guarded and reported once, for the reason the Gen 1 arm gives at the
    -- same place: this runs on every frame of every screen, a theme is
    -- decoration, and the right outcome for a broken one is the frame it was
    -- handed in the colours it already had -- not a crash in the middle of
    -- somebody's game over a tint.  After the first failure it stands down
    -- for the session and puts the vanilla four back.
    local broken = false

    mod.hooks:wrap("core.update", function(nextLink, game, dt)
      -- the frame boundary, here rather than inside `apply` so a theme that
      -- has stood down still forgets what it read
      self.forget()
      if not broken then
        local ok, problem = pcall(function()
          -- Both halves of the decision, in the order that makes the cheap
          -- one first: LIGHT wants the vanilla four whatever is on the
          -- screen, so a light boot never walks the stack at all.
          local wanted = vanilla
          if self.read() == "dark" and Theme2.pageOf(game) then
            wanted = DARK
          end
          if not same(live, wanted) then
            overwrite(live, wanted)
          end
          if wanted ~= vanilla then painted = painted + 1 end
        end)
        if not ok then
          broken = true
          overwrite(live, vanilla)
          mod.log:warn("UI THEME stood down for this session: %s",
                       tostring(problem))
        end
      end
      return nextLink(game, dt)
    end)

    -- ------- the pages that print through a palette of their OWN
    --
    -- Rewriting `Chrome.DEFAULT_BOX_PALETTE` reaches every screen that draws
    -- through the default, which is most of them.  It does not reach a screen
    -- that hands `printThrough` a palette it built itself -- and six do:
    --
    --   TrainerCard   `colorsAt`, the CGB zone under each cell
    --   PokedexMenu   `dexPalette`, off the dex's own .pal
    --   PackMenu      `gfx:colorsAt`, the pack's
    --   Pokegear      `pals[1]`, the town map's
    --   SummaryMenu   the stats page's three
    --   NamingScreen  the diploma's
    --
    -- Every one of those is a trainer or art palette bracketed WHITE ... BLACK
    -- -- `LoadPalette_White_Col1_Col2_Black`, which is how every palette of
    -- that shape is used in this game.  White is colour 0 and black is colour
    -- 3, which are the paper and the ink: exactly the two a theme owns.
    --
    -- So on a themed page the fill went dark and the text did not, and since
    -- `printThrough` paints a `width x 8` cell of colour 0 before its first
    -- glyph, every string on those pages arrived as a WHITE BOX with black
    -- letters in it.  Reported against the trainer card, where the name, the
    -- ID, the money, the dex count, the play time and BADGES are all one.
    --
    -- Colours 1 and 2 are left exactly alone, and that is not a compromise:
    -- Gold's font pages are ink on transparent (`inkFrom1bpp` /
    -- `inkFrom2bpp`), so a glyph has no shade but 3 and the middle two are
    -- never drawn in text at all.  Substituting them would change nothing;
    -- substituting 0 and 3 changes the only two that appear.
    --
    -- Gated on the theme being APPLIED this frame rather than on a list of
    -- screens, which is what makes it safe everywhere it is not wanted: the
    -- credits, the diploma and every other page that is not in PAGES leaves
    -- `live` equal to `vanilla`, and a palette is then handed straight back.
    do
      local marked = "gen1wildUnthemed"
      -- ------- and the one page that prints BACKWARDS
      --
      -- `invert` is not a decoration on these calls, it is the whole of how
      -- Gold's POKeDEX is white on black.  Pokedex_LoadInvertedFont xors both
      -- bitplanes of the font, so a glyph pixel of shade s arrives as shade
      -- 3 - s -- and Chrome answers it by reading the palette backwards:
      --
      --     if invert then pal = { pal[4], pal[3], pal[2], pal[1] } end
      --
      -- So on an inverted print `pal[1]` -- the cell `printThrough` fills
      -- behind the string -- is the palette's colour THREE, and the glyphs
      -- take colour ZERO.  Substituting paper into 0 and ink into 3 without
      -- knowing that put the ink in the cell and the paper in the letters:
      -- every row of the dex came out as a WHITE BAR with black dashes in it,
      -- which is the same white-box bug this substitution exists to fix,
      -- arriving through the one screen that reads its palette the other way
      -- up.
      --
      -- The answer is not a special case, it is the same substitution handed
      -- over pre-reversed, so the reversal lands it where it was going.
      local function reshade(palette, invert)
        if same(live, vanilla) then return palette end
        if type(palette) ~= "table" then return palette end
        -- the default is already the themed one, and a caller that has opted
        -- out (the battle HUD, which is ink on a PHOTOGRAPH rather than ink
        -- in a box -- see modules/Gen1Arena) says so on the table
        if palette == live or palette[marked] then return palette end
        local paper, ink = live[1], live[4]
        if type(paper) ~= "table" or type(ink) ~= "table" then return palette end
        if invert then
          return { ink, palette[3] or ink, palette[2] or paper, paper }
        end
        return { paper, palette[2] or paper, palette[3] or ink, ink }
      end

      -- ------- and the trainer card's TILES, which are chrome and not art
      --
      -- The card is drawn almost entirely out of tiles rather than text: the
      -- frame, the rules under NAME, the corner notches, the `ID No` badge,
      -- the `STATUS` and `BADGES` captions and the blinking colon in PLAY
      -- TIME are all `TileSheet:draw` through the same `colorsAt` the text
      -- uses.  Reshading only what goes through Chrome left every one of them
      -- as a white box on a black card -- reported as "some of the detail
      -- pieces, the trainer sprite, the clock".
      --
      -- All of those are LINE ART: colour 0 is the paper the mark sits on, so
      -- it is the page's paper, exactly as it is for the text beside them.
      --
      -- Two things on the card are not, and they are the reason this is a
      -- pair of suspensions rather than a blanket rule:
      --
      --   the PORTRAIT      colour 0 is the space around the player AND the
      --                     white in their own sprite -- shirt, socks, shoes.
      --                     Darkening the one darkens the other, and what
      --                     comes back is a silhouette with hair.
      --   the LEADER FACES  eight more of the same thing on the badge pages.
      --
      -- So they keep the cart's white and read as photographs on the card,
      -- which is what they are.  The `BADGES` caption above them comes off
      -- the same sheet and IS reshaded, because it is a word.
      local okCard, TrainerCard = pcall(require, "src.ui.gen2.TrainerCard")
      if okCard and type(TrainerCard) == "table"
          and not rawget(TrainerCard, "__gen1wildCardPaper") then
        TrainerCard.__gen1wildCardPaper = true
        local art = false
        local baseColors = TrainerCard.colorsAt
        if type(baseColors) == "function" then
          TrainerCard.colorsAt = function(card, tx, ty)
            local palette = baseColors(card, tx, ty)
            if art then return palette end
            return reshade(palette)
          end
        end
        for _, name in ipairs({ "drawPortrait", "drawLeaderFace" }) do
          local base = TrainerCard[name]
          if type(base) == "function" then
            TrainerCard[name] = function(card, ...)
              art = true
              local ok, result = pcall(base, card, ...)
              art = false
              if not ok then error(result, 0) end
              return result
            end
          else
            mod.log:warn("src.ui.gen2.TrainerCard has no %s; the card's art "
              .. "goes dark with its chrome", name)
          end
        end
      end

      -- ------- and the POKeGEAR, which paints its own paper
      --
      -- The gear is in PAGES and its TEXT was already themed -- it hands
      -- `pals[1]` to `Chrome.printThrough`, which the wrap below reshades --
      -- but the page under that text stayed the cart's pale cream, so the
      -- phone came out as white-on-black bars floating on a green card.
      --
      -- Nothing on this screen goes through `Chrome.DEFAULT_BOX_PALETTE`.  The
      -- gear draws itself out of `PokegearPals` (gfx/pokegear/pokegear.pal),
      -- and its colour 0 is not white -- it is `RGB 28, 31, 20`, a pale cream
      -- plate.  So the palette this theme rewrites in place is not one the
      -- gear ever reads, and the page it draws is untouched by it.
      --
      -- Three seams, and the split between them is the trainer card's rule
      -- again: WORDS follow the theme, PICTURES keep the cart's colours.
      --
      --   paperColor   the plate.  It is `pals[1][1]`, and every ' ' cell and
      --                every `drawPlate` fill reads it, so this one number is
      --                the whole of the page's ground under the text.
      --
      --   colorsFor    the tile palettes, reshaded ONLY for the font page.
      --                The gear's own split is the same one: `colorsFor`
      --                answers `pals[1]` for every tile id >= $60 -- the font
      --                page, so every glyph cell and every blank -- and a
      --                mapped art palette below that (TownMapPals).  Above
      --                $60 is writing and follows the page; below it is the
      --                card icons and the town map, which are pictures and
      --                keep what they are.
      --
      --   textbox      its frame.  `Font.drawCode` sets no colour of its own,
      --                so the cart tints the border glyphs by setting black
      --                just before drawing them -- black being the gear's ink.
      --                On a themed page that is the paper's colour, and the
      --                box would have drawn its frame in the same black as the
      --                plate behind it.  The tint is moved to the theme's ink
      --                by lending `Font.drawCode` the colour for the length of
      --                that one call; `drawPlate` fills with `rectangle` and
      --                is not touched by it.
      --
      -- `groundColor` is deliberately NOT wrapped.  It reads the LAST entry of
      -- the same palette rather than the first -- the gear sits on a solid
      -- $4f fill, which is colour 3 -- so it is already black on the cart and
      -- reshading it would have handed the gear a WHITE ground under DARK.
      local okGear, Pokegear = pcall(require, "src.ui.gen2.Pokegear")
      if okGear and type(Pokegear) == "table"
          and not rawget(Pokegear, "__gen1wildGearPaper") then
        Pokegear.__gen1wildGearPaper = true

        local basePaper = Pokegear.paperColor
        if type(basePaper) == "function" then
          Pokegear.paperColor = function(gear)
            if same(live, vanilla) then return basePaper(gear) end
            return live[1] or basePaper(gear)
          end
        else
          mod.log:warn("src.ui.gen2.Pokegear has no paperColor; the gear keeps "
            .. "the cart's cream plate under a themed page")
        end

        local baseColorsFor = Pokegear.colorsFor
        if type(baseColorsFor) == "function" then
          -- TownMapPals' own boundary (pokegear.asm): $60 and up is the font
          -- page and takes palette 0.
          local FONT_PAGE = 0x60
          Pokegear.colorsFor = function(gear, tile)
            local palette = baseColorsFor(gear, tile)
            if type(tile) == "number" and tile >= FONT_PAGE then
              return reshade(palette)
            end
            return palette
          end
        else
          mod.log:warn("src.ui.gen2.Pokegear has no colorsFor; the gear's "
            .. "lettering keeps the cart's plate behind it")
        end

        local baseTextbox = Pokegear.textbox
        local okFont, Font = pcall(require, "src.render.Font")
        if type(baseTextbox) == "function" and okFont and type(Font) == "table"
            and type(Font.drawCode) == "function" then
          Pokegear.textbox = function(gear, ...)
            if same(live, vanilla) then return baseTextbox(gear, ...) end
            local ink = live[4]
            if type(ink) ~= "table" then return baseTextbox(gear, ...) end
            local realDrawCode = Font.drawCode
            Font.drawCode = function(code, x, y)
              love.graphics.setColor(ink[1] / 255, ink[2] / 255,
                                     ink[3] / 255, 1)
              return realDrawCode(code, x, y)
            end
            local drawn, problem = pcall(baseTextbox, gear, ...)
            Font.drawCode = realDrawCode
            if not drawn then error(problem, 0) end
            return problem
          end
        elseif type(baseTextbox) == "function" then
          mod.log:warn("no Font.drawCode to lend the gear's textbox an ink; "
            .. "its frame stays the cart's black")
        end
      end

      -- ------- and the INTRO, which paints its own page and its own portraits
      --
      -- Reported as "Prof Oak speech isn't dark mode", and it is the same
      -- complaint the Gen 1 arm already answers in its own list: "a white
      -- screen behind Oak, the rival and the NIDORINO is the one place DARK
      -- stayed light all the way through, and it is the first thing a new
      -- game shows" (runtime/theme.lua, `src.ui.OakSpeech`).
      --
      -- Putting the class in PAGE_MODULES is necessary and NOT sufficient.
      -- That much makes `pageOf` find a page under the speech's text box, so
      -- the box and its glyphs reverse -- but the page they sit on is a
      -- hardcoded white fill, not a palette:
      --
      --     G.setColor(1, 1, 1, 1)
      --     G.rectangle("fill", 0, 0, 160, 144)   -- OakSpeech:drawPanel
      --
      -- Nothing in `Chrome.DEFAULT_BOX_PALETTE` reaches it, so the entry
      -- alone would have given a DARK box on a WHITE page, which is worse
      -- than leaving it. Both halves are needed, which is the shape the Gen 1
      -- note gives for the same screen -- there it is the page plus
      -- runtime/matte.lua; here it is the page plus the two wraps below.
      --
      --   the ground   that one fill, repainted in the theme's paper. It is
      --                caught by lending `love.graphics.rectangle` a shim for
      --                the length of `drawPanel` and matching the full-page
      --                fill exactly, because there is no named seam to wrap.
      --                An engine that moves the call fails to match and the
      --                page comes back white -- the old bug, not a new one.
      --
      --   the pics     Oak, the player and the icon are drawn through
      --                `GbcPalette.with`, whose shade 0 is OPAQUE and, for a
      --                trainer palette, WHITE (_CGB_PlayerOrMonFrontpicPals
      --                brackets the pic's two shipped colours with white and
      --                black). On a dark page that is a white plate around
      --                Oak. `GbcPalette.keyedWith` is the same draw with
      --                shade 0 keyed to alpha 0, so the page shows through
      --                instead. That is what Gen 1's matte does, said in
      --                Gold's terms: it is the page colour that has to appear
      --                under the art, not the cart's white.
      --
      -- The portraits themselves keep the cart's colours either way -- only
      -- the shade the cart uses as BACKGROUND is taken away. Pictures keep
      -- what they are; this is the paper behind them, which is a page.
      local okOak, OakSpeech = pcall(require, "src.ui.gen2.OakSpeech")
      if okOak and type(OakSpeech) == "table"
          and not rawget(OakSpeech, "__gen1wildIntroPage") then
        OakSpeech.__gen1wildIntroPage = true

        -- The theme's paper as love wants it, or nil while LIGHT stands.
        local function paper()
          if same(live, vanilla) then return nil end
          local c = live[1]
          if type(c) ~= "table" then return nil end
          return c[1] / 255, c[2] / 255, c[3] / 255
        end

        local basePanel = OakSpeech.drawPanel
        if type(basePanel) == "function" then
          OakSpeech.drawPanel = function(speech, ...)
            local r, g, b = paper()
            if not r then return basePanel(speech, ...) end
            local G = love.graphics
            local realRect = G.rectangle
            local done = false
            G.rectangle = function(mode, x, y, w, h, ...)
              if not done and mode == "fill" and x == 0 and y == 0
                  and w == 160 and h == 144 then
                done = true
                G.setColor(r, g, b, 1)
                realRect(mode, x, y, w, h)
                G.setColor(1, 1, 1, 1)
                return
              end
              return realRect(mode, x, y, w, h, ...)
            end
            local ok, err = pcall(basePanel, speech, ...)
            G.rectangle = realRect
            if not ok then error(err, 0) end
            return err
          end
        else
          mod.log:warn("src.ui.gen2.OakSpeech has no drawPanel; the intro "
            .. "keeps the cart's white page")
        end

        local okGbc, GbcPalette = pcall(require, "src.render.GbcPalette")
        local keyable = okGbc and type(GbcPalette) == "table"
          and type(GbcPalette.with) == "function"
          and type(GbcPalette.keyedWith) == "function"
        if keyable then
          -- One wrap, used by both pic sites: for the length of the call the
          -- plain remap IS the keyed one, so the shade the cart would have
          -- painted white drops out and the page carries it.
          local function overPage(base)
            return function(speech, ...)
              if same(live, vanilla) then return base(speech, ...) end
              local realWith = GbcPalette.with
              GbcPalette.with = GbcPalette.keyedWith
              local ok, err = pcall(base, speech, ...)
              GbcPalette.with = realWith
              if not ok then error(err, 0) end
              return err
            end
          end
          for _, name in ipairs({ "drawPic", "drawPlayerIcon" }) do
            local base = OakSpeech[name]
            if type(base) == "function" then
              OakSpeech[name] = overPage(base)
            end
          end
        else
          mod.log:warn("no GbcPalette.keyedWith; the intro's portraits keep "
            .. "the cart's white plate on a themed page")
        end

        -- The letterbox around the 160x144 panel, which `drawWidescreen`
        -- opens in white for the same reason the panel does.  Lending
        -- IntroFade.surround the paper as its BASE keeps the fade maths --
        -- the intro fades through this colour and has to go on doing so.
        local baseWide = OakSpeech.drawWidescreen
        local okFade, IntroFade = pcall(require, "src.ui.gen2.IntroFade")
        if type(baseWide) == "function" and okFade and type(IntroFade) == "table"
            and type(IntroFade.surround) == "function" then
          OakSpeech.drawWidescreen = function(speech, winW, winH)
            local r, g, b = paper()
            if not r then return baseWide(speech, winW, winH) end
            local realSurround = IntroFade.surround
            IntroFade.surround = function(state) return realSurround(state, r, g, b) end
            local ok, err = pcall(baseWide, speech, winW, winH)
            IntroFade.surround = realSurround
            if not ok then error(err, 0) end
            return err
          end
        end
      end

      if not rawget(Chrome, "__gen1wildPagePalettes") then
        Chrome.__gen1wildPagePalettes = true
        local basePrint = Chrome.printThrough
        if type(basePrint) == "function" then
          Chrome.printThrough = function(text, tx, ty, palette, invert, ...)
            return basePrint(text, tx, ty, reshade(palette, invert), invert, ...)
          end
        end
        local baseRight = Chrome.printRightThrough
        if type(baseRight) == "function" then
          Chrome.printRightThrough = function(text, txEnd, ty, palette, invert, ...)
            return baseRight(text, txEnd, ty, reshade(palette, invert), invert, ...)
          end
        end
        local baseCursor = Chrome.cursorThrough
        if type(baseCursor) == "function" then
          Chrome.cursorThrough = function(tx, ty, palette, invert, ...)
            return baseCursor(tx, ty, reshade(palette, invert), invert, ...)
          end
        end
      end
    end

    -- ------- the one thing on a themed page that is not drawn through these
    -- four numbers
    --
    -- An HP bar is tiles, not text, and `BattleHud:barColors` builds its
    -- palette from `palettes.hpBar` with colour 0 pinned to WHITE:
    --
    --     { zero or { 255, 255, 255 }, pal[1], pal[2], { 0, 0, 0 } }
    --
    -- Colour 0 is the bar's TRACK -- the empty half -- and on the cart's white
    -- page it is invisible, which is exactly why it was written as a literal.
    -- Turn the page black and it is a white slab hanging off the end of every
    -- bar in the party menu.  Reported against the party list, where six of
    -- them stack up.
    --
    -- The engine already has the parameter for this and says what it is for:
    -- `zero` overrides colour 0, "the stats screen puts the page tint there"
    -- (BattleHud:drawHpBar, gen1recomp#1693).  SummaryMenu passes one;
    -- PartyMenu does not, and neither does the battle.  So the DEFAULT
    -- becomes the page's own paper -- which is these four numbers, read live,
    -- so it is white on a light page and cannot disagree with the box it is
    -- sitting in.
    --
    -- Left alone wherever the caller has already decided: a non-nil `zero` is
    -- passed straight through, so the stats screen keeps its tint.  And on a
    -- LIGHT boot the substitution puts back the same white it took.
    do
      local okHud, BattleHud = pcall(require, "src.ui.gen2.BattleHud")
      if okHud and type(BattleHud) == "table"
          and not rawget(BattleHud, "__gen1wildBarPaper") then
        BattleHud.__gen1wildBarPaper = true
        local function paper()
          local entry = live[1]
          if type(entry) ~= "table" then return nil end
          return { entry[1], entry[2], entry[3] }
        end
        for _, name in ipairs({ "barColors", "expColors" }) do
          local base = BattleHud[name]
          if type(base) == "function" then
            if name == "barColors" then
              BattleHud[name] = function(selfHud, key, zero)
                return base(selfHud, key, zero or paper())
              end
            else
              BattleHud[name] = function(selfHud, zero)
                return base(selfHud, zero or paper())
              end
            end
          else
            mod.log:warn("src.ui.gen2.BattleHud has no %s; a bar on a dark "
              .. "page keeps its white track", name)
          end
        end
      end
    end

    mod.log:info("UI THEME is on Gold's box palette")
  end

  return self
end

return Theme2
