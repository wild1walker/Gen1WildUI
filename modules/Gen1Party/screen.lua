-- Gen1Party: the party menu, drawn like the rest of the set.
--
-- Returns a factory: factory(mod, C) -> { new = function(game, opts) },
-- which main.lua installs over the builtin "PartyMenu" id.
--
-- ------- what this screen is, and is not
--
-- It is the VANILLA party menu with three of its methods replaced.  PartyMenu
-- is not one screen but seven -- the field menu, the battle switch, the
-- forced switch after a faint, the item target, the TM/HM teach list with its
-- ABLE / NOT ABLE column, the SOFTBOILED donor, the evolution-stone list --
-- and each has its own input rules, its own bottom message and its own idea
-- of what A does.  None of that is touched here: the vanilla constructor
-- builds the screen, and only `draw`, `sgbPalettes` and `update` are swapped
-- out.
--
-- The first two are the whole of this mod's opinion about how the party
-- LOOKS.  `update` is the one place it has an opinion about what the party
-- DOES, and that opinion is exactly one verb long: SWITCH becomes MOVE, and
-- a member being moved is in your HAND rather than waiting to be exchanged
-- with a second pick -- see "moving a member" below.  Every other key, on
-- every other frame, is read by the engine's own update, which this one
-- calls.
--
-- ------- the frame, and what it cost
--
-- The set's shape is a header box on rows 0-2, a body on rows 3-14 and a
-- footer box on rows 15-17.  That body is 96 pixels, which is exactly six
-- party rows of sixteen -- the slots were never the problem.  The footer was:
-- three tile rows hold ONE line of text, and four of the five prompts the
-- engine hands back are two lines (party_menu.asm via data.text).  Three rows
-- of header plus five of footer plus twelve of party is twenty against the
-- eighteen there are, so two rows have to come from somewhere.
--
-- They come from the words.  Every prompt is printed on one line: the
-- engine's own, whenever the engine's own fits -- "Choose a POKéMON." is
-- seventeen glyphs against a box that holds eighteen, so the field menu still
-- says exactly what the engine says -- and this mod's one-line wording for the
-- four that do not.  That is the trade, and it is the only one that keeps all
-- six members on screen with a sentence under them that finishes.
--
-- The alternative was five visible slots and a scroll, on a screen whose whole
-- job is showing you the party at once.
--
-- Across the row it is just as tight.  The vanilla name column runs 24..104,
-- the level 104..128 and the status 136..160 -- packed to the last pixel of
-- the screen, which is why an FNT reads as clipped rather than placed.  The
-- three changes below are the ones that buy a margin without taking anything
-- away:
--
--   * the status moves from a fixed x=136 to right-aligned on 152.  Free: the
--     level always ends at 128 (PrintLevel overwrites the <LV> tile with the
--     third digit at L100, so two digits and three end in the same place),
--     which leaves 128..136 already empty.
--   * the HP bar moves one tile left, from tile 5 to tile 4, and the HP
--     numbers right-align on 152.  The bar keeps all six segments -- it is
--     the at-a-glance read on this screen and shortening it to buy the margin
--     would have been the wrong trade -- and the gap it moves into is the one
--     between the icon and the bar, which nothing was using.
--   * the numbers keep the "%3d/%3d" padding rather than becoming variable
--     width, because that padding is load bearing: the bar's right cap sits
--     under the first glyph, and a SPACE over the cap is what makes the two
--     not collide.  Variable width would put a digit there.
--
-- The dex list's ruled icon column is here too, and it is the same eight
-- pixels again: the rule needs the names off the icon cell, ten glyphs of
-- name need every pixel from 24 to the level column, so the tenth glyph is
-- what buys it.  That was left undone for two versions on the grounds that a
-- nickname is the player's own text -- until it was pointed out that art
-- filling its 16-pixel cell (three of six is typical for an icon pack) sits
-- flush against the first letter with no air at all, which costs more than
-- the tenth glyph does.  RULED ICONS, and off restores the wide column.
--
-- ------- the icons
--
-- Vanilla lays ONE MEWMON zone over tiles (1,0)-(2,11) -- the whole icon
-- column, all six of them -- so every POKeMON in the party wears the same
-- salmon.  That single zone is what this mod replaces with one zone per
-- member, so each wears its own species colours: the same thing the dex list
-- does for its rows and Gen1BillsBox does for its grid, and the reason a
-- party opened next to either of them stops looking like a different game.

return function(mod, C)
  local Font = require("src.render.Font")
  local HudTiles = require("src.render.HudTiles")
  local PaletteFX = require("src.render.PaletteFX")
  local PartyMenu = require("src.ui.PartyMenu")
  local Sprites = require("src.pokemon.Sprites")
  local Status = require("src.battle.Status")
  local Strings = require("src.core.Strings")
  local Theme = require("src.ui.Theme")

  -- ------- geometry
  --
  -- Everything the icons touch is a whole tile, because an SGB palette zone
  -- is ADDRESSED in tiles (PaletteFX.zone) and a zone per icon is the point.
  -- Slot i's rows are tile rows BODY_TY+(i-1)*2 and the one under it.

  local ICON_X, ICON = 8, 16
  local ICON_TX1, ICON_TX2 = 1, 2        -- x 8..23

  -- ------- the icon column, ruled off
  --
  -- The dex list rules a hairline between its icons and its rows and keeps
  -- three pixels of air either side of it.  The party had NONE: the name
  -- column starts at 24, which is the pixel after the icon cell ends, so art
  -- that fills its cell (and a good deal of it does -- three of six is
  -- typical for an icon pack) touches the first letter of the name.
  --
  -- Ten glyphs of name need exactly 24..104, and 104 is where the level's
  -- <LV> tile starts, so the gap can only be bought with the tenth glyph.
  -- That is what RULED ICONS spends: names start at 32 behind a rule at 26,
  -- and a ten-glyph name comes back nine.  Off restores the full-width
  -- column, touching icons and all.
  local NAME_X, NAME_X_WIDE = 32, 24
  local NAME_GLYPHS, NAME_GLYPHS_WIDE = 9, 10
  local RULE_X = 26
  local LV_TILE, LV_X = 104, 112         -- the <LV> tile, then the digits
  local LV_WIDE_X = 104                  -- L100: the third digit takes the tile
  local ROW_H = 16

  -- The body starts under the header box rather than at the top of the screen,
  -- so every row -- and every palette zone addressed in tiles -- moves down by
  -- three tile rows.  BODY_TY is that offset in the unit zones are counted in.
  local BODY_TY = 3
  local function entryY(i) return C.BODY_TOP + (i - 1) * ROW_H end

  -- The bar, one tile left of vanilla so the numbers can keep a margin.
  local BAR_TX = 4                       -- x 32; vanilla is tile 5
  local BAR_SEGMENTS = 6
  -- the segment cells, for the colour zone: x 48..96 is tiles 6..11
  local BAR_ZONE_TX1, BAR_ZONE_TX2 = 6, 11

  -- The TM/HM and evolution-stone lists print their verdict where the bar
  -- would be.  Right-aligned so the shorter ABLE shares NOT ABLE's right edge,
  -- which is what vanilla does -- on 152 now rather than trailing off 160.
  local ABLE_END = 152

  -- ------- the header, and the one line under the body
  --
  -- The title is fixed the way the dex list's is: it says what screen you are
  -- on, and the footer says what you can do about it.  Thirteen glyphs against
  -- a box that holds eighteen, so it sits well inside the margin.  What goes in the footer
  -- is bottomMessage() flattened to one line when it fits, because the words
  -- belong to the engine wherever the engine's words will go -- a reword that
  -- SHORTENS a prompt (or a translation that does) is printed verbatim without
  -- this table being touched.  Only a prompt too wide for the box falls back
  -- to the line here.
  local TITLE = "POKéMON PARTY"

  local PROMPTS = {
    swap   = "Move it where?",
    tmhm   = "Use TM on which?",
    item   = "Use item on which?",
    battle = "Bring out which?",
  }

  -- ------- full-colour icons
  --
  -- An icon mod's authored art is re-blit UNSHADED over the colourised pass,
  -- so a species palette under it is paint nobody ever sees -- and running it
  -- through the shade remap instead would destroy it, because that remap keys
  -- off the RED channel and an orange pixel lands on the palette's white.
  -- Decide per MON rather than per species: Sprites.iconPath is raised with
  -- the live mon, which is how a shiny tells itself apart from an ordinary one
  -- of its species.
  --
  -- A built-in icon CLASS is never full colour whatever file it points at,
  -- because drawIcon bakes those through obpIcon, which flattens every pixel
  -- to a grey off its red channel.  Only a mod's own image -- an entry table
  -- rather than an icon name -- reaches the screen untouched.
  local iconColour = setmetatable({}, { __mode = "k" })   -- mon -> info
  local pathColour = {}                                   -- path -> info

  local function resolveIcon(game, mon)
    local icons = game.data and game.data.icons
    if not icons then return nil, nil end
    local def = game.data.pokemon and game.data.pokemon[mon.species]
    local entry = (icons.bySpecies and icons.bySpecies[mon.species])
      or (def and def.icon)
    local name, path
    if type(entry) == "string" then
      name = entry
      path = icons.icons and icons.icons[entry]
    elseif type(entry) == "table" then
      path = entry.image
    end
    if not path then
      name = def and def.dex and icons.byDex and icons.byDex[def.dex]
      path = name and icons.icons and icons.icons[name]
    end
    local ok, hooked = pcall(Sprites.iconPath, game.data, mon, path,
                             { name = name })
    if ok then path = hooked end
    return name, path
  end

  -- Does this file carry a colour a grey ramp cannot?  Read once per path and
  -- remembered, because it is a property of the file.
  local function scanPath(path)
    local info = pathColour[path]
    if info ~= nil then return info end
    info = { colour = false, w = ICON, h = ICON }
    pcall(function()
      local data = require("src.render.Assets").imageData(path)
      local w, h = data:getDimensions()
      info.w, info.h = w, h
      for y = 0, (h > ICON and ICON or h) - 1 do
        for x = 0, w - 1 do
          local r, g, b, a = data:getPixel(x, y)
          if a > 0 and (math.abs(r - g) > 0.02 or math.abs(g - b) > 0.02) then
            info.colour = true
            return
          end
        end
      end
    end)
    pathColour[path] = info
    return info
  end

  local function fullColour(game, mon)
    if not mon then return nil end
    local hit = iconColour[mon]
    if hit == nil then
      local name, path = resolveIcon(game, mon)
      if not path or name then
        hit = false
      else
        local info = scanPath(path)
        hit = info.colour
          and { w = info.w > ICON and ICON or info.w,
                h = info.h > ICON and ICON or info.h }
          or false
      end
      iconColour[mon] = hit
    end
    return hit or nil
  end

  -- ------- colour
  --
  -- Two rules, the same two the dex list and the box grid run on.
  --
  -- The BASE is the plain four DMG greys, so everything drawn here -- the
  -- names, the numbers, the message box, all shade 3 -- comes out black on
  -- white.  Vanilla's base is GREENBAR, which is the bar palette standing in
  -- for a screen palette.
  --
  -- Then EACH POKeMON GETS ITS OWN, in place of the single MEWMON column
  -- vanilla lays over all six icons at once.  The bar zones are kept exactly
  -- as vanilla computes them, including the stale-colour window a medicine's
  -- fill animation needs (#252) -- that is the bar's business, not this
  -- mod's.
  local function palettesFor(vanillaSgb)
    return function(self, game)
      if not C.option("species_colours", true) then
        return vanillaSgb(self, game)
      end
      local ok, zones = pcall(function()
        local out = { PaletteFX.whole(PaletteFX.GRAYS) }
        local party = self.party or (game.save and game.save.party) or {}

        for i, mon in ipairs(party) do
          -- full-colour art sits out the pass, so a zone under it is paint
          -- nobody ever sees
          if not fullColour(game, mon) then
            local colors = PaletteFX.monPal(game.data, mon.species)
            local ty = BODY_TY + (i - 1) * 2
            local zone = colors
              and PaletteFX.zone(colors, ICON_TX1, ty, ICON_TX2, ty + 1)
            if zone then out[#out + 1] = zone end
          end
        end

        -- the TM/HM list prints ABLE / NOT ABLE where the bar would be, so
        -- those rows have no bar to colour (party_menu.asm .teachMoveMenu)
        if not (self.tmhm or self.evoStone) then
          for i, mon in ipairs(party) do
            -- while a medicine's fill runs the block palette is STALE, not
            -- recomputed; hold the starting HP for exactly that window
            local hp = mon.hp
            if self.heal and self.heal.mon == mon then hp = self.heal.from end
            local bar = PaletteFX.pal(game.data,
                                      PaletteFX.barPalName(hp, mon.stats.hp))
            if bar then
              local ty = BODY_TY + (i - 1) * 2 + 1
              out[#out + 1] = PaletteFX.zone(bar, BAR_ZONE_TX1, ty,
                                             BAR_ZONE_TX2, ty)
            end
          end
        end
        return out
      end)
      -- a screen with no palette opinion inherits whatever is underneath, so
      -- falling back to vanilla's answer matters more than falling back to nil
      if ok and zones then return zones end
      return vanillaSgb(self, game)
    end
  end

  -- ------- one line under the body
  --
  -- bottomMessage() owns the words and this owns the width.  Flatten whatever
  -- it returns onto one line and print it when it fits; the field menu's
  -- "Choose a POKéMON." does, so the commonest screen in the game still says
  -- exactly what the engine says.  When it does not fit, print this mod's
  -- wording for the mode instead of a sentence cut in half -- the two-line
  -- box those prompts were written for is what the header box was paid for
  -- with, and half of "Use TM on which POKéMON?" is not an improvement on
  -- either.
  local function flatten(text)
    return (tostring(text or ""):gsub("%s*\n%s*", " "):gsub("%s+$", ""))
  end

  local function modeOf(self)
    if self.swapFrom then return "swap" end
    if self.tmhm then return "tmhm" end
    if self.softboiledFrom or self.itemUse then return "item" end
    if self.battle then return "battle" end
    return "normal"
  end

  local function fits(text)
    local ok, w = pcall(Font.width, text)
    return ok and w <= C.LINE_W
  end

  local function promptFor(self)
    local ok, message = pcall(self.bottomMessage, self)
    local line = ok and flatten(message) or ""
    if line ~= "" and fits(line) then return line end
    local ours = PROMPTS[modeOf(self)]
    -- no fallback for the field menu on purpose: if the engine's own normal
    -- prompt ever stops fitting, its FIRST line is still a whole sentence
    -- ("Choose a POKéMON.") and closer to the engine's copy than anything
    -- written here.
    if ours then
      ours = Strings(ours)
      if fits(ours) then return ours end
    end
    return C.truncate(line, 18)
  end

  -- ------- moving a member
  --
  -- The engine's answer is SWITCH: press A on one member, press A on a
  -- second, and the two change places (PartyMenu's `swapFrom`, party_menu.asm
  -- via HandlePartyMenuInput).  It is two picks over a list that never moves,
  -- and the only sign of the first one is a hollow arrow beside a row you
  -- have already left.
  --
  -- Gen1BillsBox answers the same question by putting the POKeMON in your
  -- HAND: it flashes, it goes where you go, and the screen under it is the
  -- screen you are arranging.  This is that, on the party list.  MOVE lifts
  -- the member the cursor is on; UP and DOWN carry it through the list, a row
  -- at a time, reordering the party as it goes; A lets go and B walks it
  -- home.  The popup row says MOVE because MOVE is what it now does -- SWITCH
  -- describes an exchange, and this is not one.
  --
  -- What a run of steps adds up to is an INSERTION rather than an exchange:
  -- each step takes the member out of the array and puts it back in one row
  -- further on, so carrying the fourth member to the top leaves the three it
  -- passed in the order they were already in.  Vanilla's SWITCH would have
  -- traded the first and the fourth and left the two between them alone.
  --
  -- The array is reordered on every step rather than once at the end, and
  -- that is the load-bearing part.  Party order IS battle order -- party[1]
  -- is who you send out -- so a list drawn in one order over an array stored
  -- in another has a lead POKeMON nobody on screen can see.  There is no such
  -- window here: what the list looks like is what the save says, on every
  -- frame of the carry.  It is also why letting go costs nothing to commit.
  --
  -- B is BACK, the way it is in the box rather than the way it is on this
  -- screen: it walks the member home instead of closing the menu.  Because
  -- every step leaves the OTHER members in their own order, putting this one
  -- back in the row it started in restores the party exactly, however far it
  -- travelled.  There is no way to leave this screen with a POKeMON in hand.

  -- Sixteen steps lit and eight dark at the engine's sixty a second, which is
  -- Gen1BillsBox's flash to the frame: four shades cannot dim a POKeMON, so
  -- it blinks, and it stays lit twice as long as it is dark because the thing
  -- flashing is the thing you are trying to look at.
  local FLASH_PERIOD, FLASH_ON = 24, 16

  -- The engine's own icon-animation counter wraps at 320, which 24 does not
  -- divide; the flash keeps its own so that neither jumps when the other
  -- turns over, and so that a member picked up is lit on the frame you press.
  local ICON_TICKS = 320

  local MOVE_LABEL = "MOVE"

  local function carrying(self) return self.moveFrom ~= nil end

  local function flashOn(self)
    return ((self.moveTick or 0) % FLASH_PERIOD) < FLASH_ON
  end

  -- link and scoped battles hand the menu their own party view; the swap the
  -- engine does is on that table, so the carry is too
  local function partyOf(self)
    return self.party or self.game.save.party
  end

  local function sound(self, name)
    if not self.game.data then return end
    pcall(function()
      require("src.core.Sound").play(self.game.data, name)
    end)
  end

  -- Yellow's sleeping starter Pikachu cannot be moved: the engine refuses the
  -- A press that picks it (PartyMenu's followerUnavailable -> "There isn't
  -- any response..."), which covers both ends of a swap because both ends are
  -- pressed.  A carry presses A over neither of the rows it displaces, so the
  -- same question is asked here instead -- otherwise the one rule the engine
  -- has about moving a POKeMON is walked around by moving the one beside it.
  local function immovable(self, mon)
    local ok, no = pcall(function()
      local Follower = require("src.world.PikachuFollower")
      return Follower.isFollowingDisabled(self.game.overworld)
        and Follower.isStarterPikachu(self.game.save, mon)
    end)
    return (ok and no) or false
  end

  local function refuse(self)
    pcall(function()
      local TextBox = require("src.render.TextBox")
      local text = (self.game.data and self.game.data.text) or {}
      self.game.stack:push(TextBox.new(self.game,
        text._SleepingPikachuText1 or Strings("There isn't any\nresponse...")))
    end)
  end

  -- One step of the carry.  Out of the array and back into it at the row the
  -- cursor is moving to: the same thing as an exchange for a step of one, and
  -- an insertion for a run of them.  The wrap is the list's own -- the cursor
  -- wraps, so the member does -- and there it is a rotation, which is still
  -- every other member keeping its order.
  local function carryTo(self, to)
    local party = partyOf(self)
    -- Clamped because nothing here owns the party table and the row a member
    -- was picked up from is remembered across frames: a party that got
    -- shorter under the carry would otherwise reach table.insert with a
    -- position it will throw on.  The carried member is never out of the
    -- array -- there is no hand to drop it from -- so the worst a clamp can
    -- do is put it in the wrong row of a party something else just rewrote.
    local n = #party
    if n == 0 then return end
    self.index = math.max(1, math.min(self.index, n))
    to = math.max(1, math.min(to, n))
    table.insert(party, to, table.remove(party, self.index))
    self.index = to
    -- swapFrom is the engine's own "a member is in the air" flag and what
    -- bottomMessage reads for "Move POKéMON where?", so it follows the member
    -- rather than marking the row it was picked up from
    self.swapFrom = to
    self.game.partyMenuSavedIndex = to   -- HandlePartyMenuInput #768
  end

  local function putDown(self)
    self.moveFrom, self.swapFrom = nil, nil
  end

  -- The whole of this screen's own input, and it is reached only with a
  -- POKeMON in hand.
  local function carryUpdate(self)
    local input = self.game.input
    local party = partyOf(self)
    local n = #party

    -- HandleMenuInput_ beeps SFX_PRESS_AB on any A or B whatever the menu
    -- goes on to do with it (#570), and the engine's update is not the one
    -- reading them this frame
    if input:wasPressed("a") or input:wasPressed("b") then
      sound(self, "Press_AB")
    end

    if input:wasPressed("a") then
      -- let go.  Nothing to commit: the list already is the party
      putDown(self)
      return
    end

    if input:wasPressed("b") then
      -- home, and in silence -- the beep above is the answer to the press,
      -- and the swap chirp would report a move that was just called off
      if self.index ~= self.moveFrom then carryTo(self, self.moveFrom) end
      putDown(self)
      return
    end

    local up, down = input:wasPressed("up"), input:wasPressed("down")
    if not (up or down) or n < 2 then return end
    local to
    if up then
      to = self.index > 1 and self.index - 1 or n
    else
      to = self.index < n and self.index + 1 or 1
    end

    -- every row between here and there is displaced by the step, which for a
    -- step of one is the row it swaps with and for a wrap is all of them
    for i = math.min(self.index, to), math.max(self.index, to) do
      if i ~= self.index and immovable(self, party[i]) then
        refuse(self)
        return
      end
    end

    carryTo(self, to)
    -- the sound vanilla plays when two members change places, played where
    -- they actually change places
    sound(self, "Swap")
  end

  -- ------- drawing


  -- ------- the matte behind true-colour art
  --
  -- `PaletteFX.markTrueColor` blits a rectangle RAW so a coloured icon keeps
  -- its own colours instead of being read as four shades.  Raw means raw: the
  -- white page under it stays white when everything around it goes black,
  -- which is the white box behind every icon on a dark screen.
  --
  -- So the rectangle is painted with what the theme will make of it BEFORE
  -- the art goes in.  Only ever inside a rectangle about to be marked -- a
  -- dark rectangle anywhere else is shade-3 pixels, which the theme maps to
  -- the page's ink and puts a hole in the page.
  --
  -- Under LIGHT the colour is white, which is what this drew before the theme
  -- existed, so a build with no theme in it is unchanged.
  local function matte(x, y, w, h)
    local theme = type(mod.theme) == "function" and mod.theme() or nil
    local colour = theme and type(theme.matte) == "function"
      and theme.matte() or nil
    if type(colour) ~= "table" then return end
    love.graphics.setColor(colour[1] / 255, colour[2] / 255, colour[3] / 255, 1)
    love.graphics.rectangle("fill", x, y, w, h)
  end

  -- ------- and not under a box somebody else put on top
  --
  -- A marked rectangle is blitted RAW, and raw means raw: whatever happens to
  -- be in those pixels when the frame is composed, exempt from the palette
  -- pass.  That is exactly right while the icon is the last thing drawn there,
  -- and a lie the moment anything is drawn over it.
  --
  -- The engine draws over it.  `PartyMenu:refuse` pushes a TextBox -- "<NAME>
  -- is already out!", the battle switch offering the POKeMON already in the
  -- fight -- and every message box in this game stands at tile row 12, y=96
  -- (src/render/TextBox.lua, BOX_TY).  On the ENGINE's party screen that is
  -- exactly under the sixth row, which is why the engine never had this; on
  -- THIS one the header box moved every row down by 24, so y=96 lands a row
  -- and a half INTO the body.  Slot 6's icon and slot 5's HP row end up
  -- beneath the box, and the sixth icon's mark punched a 16x16 hole of raw
  -- white page through it -- the box's own paper, un-inverted, with its black
  -- ink still sitting on it.
  --
  -- The matte goes with the mark and is not optional: a black rectangle that
  -- is NOT marked is shade-3 pixels, which the theme maps to the page's ink
  -- and puts a hole in the page.  So a covered row loses both, and keeps its
  -- icon -- drawn through the palette pass like everything else and then
  -- covered by the box, which is what a row under a box should look like.
  --
  -- ------- and only as much of it as the box actually covers
  --
  -- 1.8.1 dropped the pair for the whole CELL as soon as the box reached any
  -- part of it, and the box's top edge does not land on a row boundary: it is
  -- at y=96 and the rows are 24 apart from a header that moved them, so there
  -- is a row the box cuts THROUGH rather than covers.  That row kept the top
  -- of its icon on the page with no mark on it, and an unmarked icon is read
  -- as four shades -- the picture above the box going grey while the ones
  -- above it stayed in colour.
  --
  -- The cell is not the unit.  What re-blits over the box is the part of it
  -- UNDER the box, so that is the only part that has to let go; the strip
  -- still on the page keeps its matte and its mark.  The icon is drawn whole
  -- either way -- the box is painted after this and covers the rest -- so
  -- clipping the RECTANGLE is the whole of it.  The box's top edge is a
  -- horizontal, so one number describes what is left.
  --
  -- Gen1ModernBag makes the same cut for the same reason (1.13.1), sideways:
  -- its pop-ups are anchored to the right edge, so what they leave is a slab
  -- at the left rather than a band at the top.
  --
  -- Read off the covering state rather than assumed: a TextBox carries the
  -- geometry it was built with (`boxTy`), and the battle's switch prompt is
  -- one of the callers that passes its own.  A state above that does not say
  -- where it is falls back to the row every message box in the game uses.
  local MESSAGE_TY = 12

  local function coverTop(self)
    local stack = self.game and self.game.stack
    local states = type(stack) == "table" and stack.states or nil
    if type(states) ~= "table" then return nil end
    local above, top = false, nil
    for i = 1, #states do
      if states[i] == self then
        above = true
      elseif above and type(states[i]) == "table" then
        local ty = tonumber(states[i].boxTy) or MESSAGE_TY
        local y = ty * 8
        if not top or y < top then top = y end
      end
    end
    return top
  end

  -- How much of an icon at `y` is still clear of the box, or nil for none of
  -- it.  A copy, never the cached rect `fullColour` hands back: that one is
  -- keyed by mon and shared by every row the mon is standing in.
  local function clipped(rect, y, covered)
    if not (rect and covered) then return rect end
    local visible = covered - y
    if visible <= 0 then return nil end
    if visible >= rect.h then return rect end
    return { w = rect.w, h = visible }
  end

  local function drawIcon(self, mon, y, selected, covered)
    -- before the art, and only where the art will be marked
    local rect = clipped(fullColour(self.game, mon), y, covered)
    if rect then
      matte(ICON_X, y, rect.w, rect.h)
    end
    C.white()
    pcall(PartyMenu.drawIcon, self.game, mon, ICON_X, y, selected,
          self.blink or 0)
    if rect then
      pcall(PaletteFX.markTrueColor, ICON_X, y, rect.w, rect.h)
    end
    C.black()
  end

  local function draw(self)
    C.clear()

    -- the boxed top and bottom the rest of the set has, and the body between
    C.headerBox()
    Font.draw(Strings(TITLE), C.LEFT, C.HEADER_TEXT_Y)

    local game = self.game
    local party = self.party or game.save.party
    if #party == 0 then
      Font.draw(Strings("No POKéMON!"), 16, 64)
    end

    -- Each bar row carries its own GREENBAR / YELLOWBAR / REDBAR zone, so the
    -- fill must stay the raw DMG shade-2 grey and let the zone colour it --
    -- but only when a zone pass will actually run.  Renderer takes the shader
    -- path exactly when the zone list is non-empty AND PaletteFX.shader()
    -- resolves, which is the pair tested here; with no shader the canvas blits
    -- unshaded and drawHPBar's own tint is the only colour the bar can get.
    local barZoned = PaletteFX.shader() ~= nil
      and PaletteFX.pal(game.data, "GREENBAR") ~= nil

    -- the hairline, the dex's own, down the whole body rather than per row
    local ruled = C.option("ruled_icons", true) and #party > 0
    if ruled then
      C.black()
      C.rule(RULE_X, C.BODY_TOP, 1, C.BODY_BOTTOM - C.BODY_TOP + 1)
    end
    local nameX = ruled and NAME_X or NAME_X_WIDE
    local nameGlyphs = ruled and NAME_GLYPHS or NAME_GLYPHS_WIDE
    -- Once for the screen, not once a row: the stack does not move between
    -- two icons of the same frame.
    local covered = coverTop(self)

    for i, mon in ipairs(party) do
      local def = game.data.pokemon[mon.species]
      local y = entryY(i)
      local selected = i == self.index

      -- The member in your hand flashes, so on the dark stretch of the cycle
      -- its row is simply not drawn: four shades cannot dim a POKeMON, and
      -- the whole row is the member -- its icon, its name, its level and its
      -- bar all travel together, so all of them blink together.
      local lifted = selected and carrying(self)
      if not (lifted and not flashOn(self)) then
        drawIcon(self, mon, y, selected, covered)

        -- cut on a glyph boundary, never a byte one: a nickname can carry
        -- NIDORAN's ♂/♀, which is one glyph across several bytes
        Font.draw(C.truncate(mon.nickname or def.name, nameGlyphs), nameX, y)

        -- the level, at the column PrintLevel uses.  At L100 the third digit
        -- takes the <LV> tile's cell, which is why both cases end at 128.
        if mon.level < 100 then
          HudTiles.tile(0x6E, LV_TILE, y)
          Font.draw(tostring(mon.level), LV_X, y)
        else
          Font.draw(tostring(mon.level), LV_WIDE_X, y)
        end
        C.black()

        if self.tmhm then
          local can = false
          for _, m in ipairs(def.tmhm or {}) do
            if m == self.tmhm.move then can = true break end
          end
          local text = can and Strings("ABLE") or Strings("NOT ABLE")
          Font.draw(text, C.rightAlign(text, ABLE_END), y + 8)
        elseif self.evoStone then
          local can = false
          for _, evo in ipairs(def.evolutions or {}) do
            if evo.method == "ITEM" and evo.item == self.evoStone then
              can = true break
            end
          end
          local text = can and Strings("ABLE") or Strings("NOT ABLE")
          Font.draw(text, C.rightAlign(text, ABLE_END), y + 8)
        else
          if mon.hp <= 0 then
            local text = Strings("FNT")
            Font.draw(text, C.rightAlign(text, C.RIGHT), y)
          elseif mon.status then
            local text = Status.hudLabelFor(game.data.statuses, mon.status)
            Font.draw(text, C.rightAlign(text, C.RIGHT), y)
          end

          -- While a medicine's UpdateHPBar2 fill runs, this row draws the
          -- HP the animation has reached rather than the final value;
          -- drawHPBar reads only .hp and .stats, so a shim is enough and
          -- the real mon is never mutated for display (#252).
          local shown = mon
          if self.heal and self.heal.mon == mon then
            shown = { hp = math.floor(self.heal.shown), stats = mon.stats }
          end
          C.white()
          HudTiles.drawHPBar(game.data, BAR_TX, (y + 8) / 8, shown, nil,
                             barZoned, BAR_SEGMENTS)
          C.black()
          -- "%3d/%3d" rather than variable width on purpose: the bar's
          -- right cap sits under the first glyph, and the pad's SPACE over
          -- that cap is what keeps a two-digit HP from colliding with it.
          local hpText = ("%3d/%3d"):format(shown.hp, mon.stats.hp)
          Font.draw(hpText, C.rightAlign(hpText, C.RIGHT), y + 8)
        end
      end

      -- PartyMenuInit seeds wTopMenuItemY/X with 1/0, so the cursor sits on
      -- the entry's SECOND tile row -- level with the middle of the two-row
      -- icon, not on the name row entryY returns (#278).
      local cursorY = y + 8
      if selected then
        -- The cursor is NOT part of the flash: it is where your thumb is, and
        -- one that came and went with the row would read as dropped frames.
        -- Hollow while the row under it is in your hand -- the box's own
        -- answer, and the same glyph pair vanilla marks a pending swap with.
        Font.drawCode(lifted and Theme.cursorHollow or Theme.cursor, 0, cursorY)
      end
      -- the unfilled arrow on the row a SOFTBOILED donor was picked from, and
      -- on the swap origin when MOVE NOT SWITCH is off and the engine's own
      -- two-pick swap is running; the filled cursor replaces it in the
      -- tilemap when they share a row (#814)
      if (i == self.swapFrom or i == self.softboiledFrom) and not selected then
        Font.drawCode(Theme.cursorHollow, 0, cursorY)
      end
    end

    -- ------- the footer
    --
    -- Three rows on 15-17 with its one line on 128, the same box in the same
    -- place the dex list puts its SEEN / OWN counts.  What goes in it is
    -- promptFor: the engine's own words whenever they fit the width.
    C.footerBox()
    Font.draw(promptFor(self), C.LEFT, C.FOOTER_TEXT_Y)

    if self.submenu then
      local n = #self.subItems
      Font.drawBox(9, 17 - n * 2 - 1, 11, n * 2 + 1)
      C.black()
      local y0 = (17 - n * 2) * 8
      for si, entry in ipairs(self.subItems) do
        Font.draw(entry.label, 88, y0 + (si - 1) * 16)
      end
      Font.drawCode(Theme.cursor, 80, y0 + (self.subIndex - 1) * 16)
    end

    C.white()
  end

  -- ------- the engine's update, with one thing in front of it
  --
  -- Three jobs, in this order, and the order is the whole of the design:
  --
  --   1. a member in hand is this screen's own input, and nothing else runs
  --      that frame.  It runs whatever MOVE NOT SWITCH says now: the member
  --      is already up, an option toggled mid-carry must not be able to
  --      strand one, and the only keys that put it down are in here.
  --   2. otherwise the engine's update runs, untouched, and reads every key
  --      on this screen -- including the A that opens the popup and the A
  --      that picks a row on it.
  --   3. and if that A was SWITCH, the engine has set swapFrom and is waiting
  --      for a second pick.  Take the member out of the list's hands and into
  --      the player's instead: from here it is a carry, and the engine's own
  --      swap branch is never reached.
  --
  -- The row is relabelled here rather than through the ui.party.submenu hook,
  -- which is the engine's seam for exactly this kind of edit.  The word is a
  -- promise about what A does; what A does is this file's doing and only this
  -- file's, so a screen that is not this one must not inherit the promise.
  -- Keying on the ACTION is what keeps the battle list's own SWITCH alone --
  -- that one means "send this one out", carries battle_switch, and is a
  -- different verb wearing the same six letters.
  local function updateFor(vanillaUpdate)
    return function(self, dt)
      if carrying(self) then
        -- A medicine's fill owns the menu while it runs and no button is read
        -- until it lands (#252).  One cannot start mid-carry -- the bag is not
        -- reachable with a POKeMON in hand -- but if one ever did, the engine's
        -- own update is what steps it, and handing the frame over is what stops
        -- a fill that nothing is advancing from freezing the carry with it.
        if self.heal then
          vanillaUpdate(self, dt)
          return
        end
        -- the engine's icon animation keeps running under the flash, on the
        -- engine's own counter
        self.blink = ((self.blink or 0) + 1) % ICON_TICKS
        self.moveTick = (self.moveTick or 0) + 1
        carryUpdate(self)
        return
      end

      vanillaUpdate(self, dt)

      if not C.option("live_move", true) then return end

      if self.swapFrom and not self.softboiledFrom then
        self.moveFrom = self.swapFrom
        -- The carry's one invariant: index is the row the lifted member is
        -- ACTUALLY in, because that is the row every step takes it out of.
        -- The engine has just set swapFrom from index, so this is a no-op on
        -- the way in -- it is here for the swap that was already pending when
        -- the option was turned on, whose cursor is somewhere else entirely.
        self.index = self.swapFrom
        self.game.partyMenuSavedIndex = self.index
        self.moveTick = 0                 -- picked up lit
      end

      if self.submenu and type(self.subItems) == "table" then
        local word = Strings(MOVE_LABEL)
        for _, entry in ipairs(self.subItems) do
          if type(entry) == "table" and entry.action == "switch" then
            entry.label = word
          end
        end
      end
    end
  end

  -- ------- the screen
  --
  -- Built by the vanilla constructor, then re-dressed.  Every mode and every
  -- callback is still the engine's, and so is every key it reads -- bar the
  -- four this screen reads for itself with a POKeMON in hand.
  local Party = {}

  function Party.new(game, opts)
    local menu = PartyMenu.new(game, opts)
    local vanillaSgb = PartyMenu.sgbPalettes
    menu.draw = draw
    menu.sgbPalettes = palettesFor(vanillaSgb)
    menu.update = updateFor(PartyMenu.update)
    -- one of ours, as far as UI THEME is concerned: the theme reads this off
    -- the instance rather than matching the engine's class, and it costs
    -- nothing when no theme is installed
    menu.gen1wildTheme = "party"
    return menu
  end

  -- for the suite
  Party.geometry = {
    ICON_X = ICON_X, NAME_X = NAME_X, ROW_H = ROW_H,
    BAR_TX = BAR_TX, BAR_SEGMENTS = BAR_SEGMENTS,
    RIGHT = C.RIGHT, LEFT = C.LEFT, ABLE_END = ABLE_END,
    NAME_X_WIDE = NAME_X_WIDE, RULE_X = RULE_X,
    NAME_GLYPHS = NAME_GLYPHS, NAME_GLYPHS_WIDE = NAME_GLYPHS_WIDE,
    BODY_TOP = C.BODY_TOP, BODY_BOTTOM = C.BODY_BOTTOM, BODY_TY = BODY_TY,
    HEADER_TH = C.HEADER_TH, HEADER_TEXT_Y = C.HEADER_TEXT_Y,
    FOOTER_TY = C.FOOTER_TY, FOOTER_TEXT_Y = C.FOOTER_TEXT_Y,
    LINE_W = C.LINE_W, TITLE = TITLE,
    FLASH_PERIOD = FLASH_PERIOD, FLASH_ON = FLASH_ON,
    MOVE_LABEL = MOVE_LABEL,
  }
  Party.entryY = entryY
  Party.promptFor = promptFor
  Party.drawInto = draw

  -- `coverTop` and `clipped` are published for tests/partycover_test.lua and
  -- nothing else.  Between them they are the whole of the rule that keeps a
  -- marked icon from punching a raw hole through somebody else's message box
  -- -- where the box starts, and how much of a cell is left above it -- and
  -- both are arithmetic with no screen in it: exactly the shape a headless
  -- test can drive, and exactly the shape that is wrong quietly if it is
  -- wrong.
  return { new = Party.new, geometry = Party.geometry,
           entryY = Party.entryY, promptFor = Party.promptFor,
           coverTop = coverTop, clipped = clipped }
end
