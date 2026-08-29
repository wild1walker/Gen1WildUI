-- Gen1Dex: the AREA screen -- opened on a POKéMON you have never met, and
-- with a line under the map saying how to get there.
--
-- Returns a factory: factory(mod, C) -> a table of helpers, which main.lua
-- installs and list.lua wires its rows into.
--
-- ------- why this lives in the dex mod
--
-- A player looking for a POKéMON opens the POKéDEX and presses AREA.  That
-- is the surface, and this mod owns it: both dex screens are registered
-- here, so the row that has to answer A on an undiscovered entry is a row
-- this mod built.  The first version of all of this shipped inside a content
-- mod (Gen151), which had to wrap two engine screens from the outside to
-- reach a list it did not own -- and did, twice, once for the vanilla list
-- and once for this one, because a dex mod is free to replace the rows.  The
-- screen belongs to whoever draws it.
--
-- So this does three things and nothing else:
--
--   * AREA opens on an UNDISCOVERED entry.  Vanilla refuses -- PokedexMenu's
--     onChoose returns early unless the entry is seen or owned -- which is
--     exactly backwards on the screen a player opens to find out where
--     something lives.
--   * The AREA map gets a line under it saying how to get there, for ALL 151
--     rather than only the ones some mod placed.  The blinking nests say
--     WHERE; they cannot say "in the grass, around level ten, and rare", and
--     that is the half a player actually needs.  A wild POKéMON's line is
--     read straight out of the live encounter tables, so it is right by
--     construction and costs no data of its own; one that is not wild
--     anywhere is answered out of the evolution table instead.
--   * A press takes the line away, because the strip covers two tile rows of
--     Kanto and one of those rows has nests in it.  The first A dismisses the
--     hint; the second closes the screen, which is what A always did.  With
--     it down the screen is the plain town map, cursor and all, and START
--     puts the hint back.
--
-- ------- and what another mod gets to say
--
-- The encounter tables answer "where does this live" for every species the
-- cartridge can produce, and nothing else.  A mod that ADDS a spawn knows
-- things the tables cannot carry -- which tier it rolled the spawn at, what
-- HM the player needs to reach the map, whether the spawn is behind an event
-- that has not fired yet -- so it can hand this screen the words instead:
--
--   local dex = mod.find("Gen1Dex")
--   if dex then
--     dex.exports.area.provide(function(game, species)
--       ...
--       return { "SUPER ROD  Lv15-25", "VERY RARE" }   -- draw these
--       -- or false                     -- mine, and deliberately unanswered
--       -- or nil                       -- no opinion
--     end)
--   end
--
-- Providers are asked in the order they registered and the first one with an
-- opinion wins; the two built-in readings below are last, so a mod's answer
-- for a species always outranks the generic one.  `false` is the seal: it is
-- how a mod says "this species is mine and its answer is deliberately
-- withheld" -- Gen151's MEW, whose whole design is that the dex cannot spoil
-- the basement -- and it stops the built-ins from answering in its place.
-- The screen then draws A.UNKNOWN, the same words it draws for a species
-- nobody has an answer for, which is what keeps a seal from reading as one.
--
-- ------- what it costs
--
-- TownMap is an engine screen with no hook on it, so it is reached for
-- directly, which is part of what buys this mod its engine_internals
-- permission.  It is not replaced: TownMap.new is wrapped and the original
-- called, and the caption is installed as instance fields over the screen it
-- built, so the engine's own draw and update run untouched underneath.

return function(mod, C)
  local A = {}

  local Font = mod.ui.Font
  local Theme = mod.ui.Theme
  local Menu = mod.ui.Menu

  -- The hint goes in a box built from the game's own frame tiles -- Font.drawBox
  -- draws the same borders, and every position below is the same arithmetic on
  -- the box's own corners that src/render/TextBox.lua does on its.  A bare white
  -- strip with two lines painted into it, which is what this was first, read as
  -- a debug overlay rather than as the game talking to the player.
  --
  -- FOUR rows, not the dialogue box's six.  The dialogue box double-spaces its
  -- two lines because it is typing a story out at you, and it can afford the
  -- bottom third of the screen because there is nothing behind it.  Here there
  -- is a map behind it, with nests on it, and this is a two-line label rather
  -- than a conversation: the pair reads as one block, and the sixteen pixels
  -- that buys back are two whole tile rows of Kanto.
  local BOX_TX, BOX_TY, BOX_TW, BOX_TH = 0, 14, 20, 4
  local TEXT_X = (BOX_TX + 1) * 8
  local LINE1_Y = (BOX_TY + 1) * 8
  local LINE2_Y = (BOX_TY + 2) * 8
  local ARROW_X = (BOX_TX + BOX_TW - 2) * 8
  local ARROW_Y = (BOX_TY + BOX_TH - 1) * 8 - 4

  -- The interior of that box is 18 columns, the same budget TextBox.paginate
  -- wraps to -- but only for the FIRST line.  The blinking prompt sits in the
  -- last column of the second one, and in a four-row box there is no blank row
  -- under the text for it to sit in the way the dialogue box gives it one.  So
  -- the second line gets 17 and the arrow gets the eighteenth, rather than the
  -- arrow being drawn on top of the last glyph.
  local LINE_COLS = { 18, 17 }
  A.CAPTION_COLS = LINE_COLS[2]

  -- What the box says when NOBODY can answer for a species: the four
  -- legendaries, which are statics and live in no wild table, a species some
  -- mod has placed behind an event that has not fired yet, and anything else
  -- the tables below have nothing on.
  --
  -- A blank screen was the old answer, and it is the wrong one twice over.  A
  -- player who presses AREA on MOLTRES and gets a map with nothing on it
  -- cannot tell "this mod has no hint for you" from "the hint did not draw" --
  -- and a POKéDEX that shrugs is still allowed to have a voice while it does
  -- it.  So the box comes up either way, and says what the game would say.
  --
  -- The SAME words for a species nobody knows and a species somebody is
  -- deliberately withholding (a provider's `false`), which is load-bearing
  -- rather than lazy: Gen151's MEW is sealed until the Mansion journals are
  -- read, and a seal that read differently from an ordinary blank would tell
  -- a player MEW is in there somewhere -- which is precisely the thing the
  -- seal exists to not say.
  A.UNKNOWN = { "NO RECORD REMAINS", "GO ADVENTURING!" }

  -- The header strip the engine paints across the top of the AREA screen is
  -- 160px wide with its text inset 8px, so 19 columns of room -- and vanilla
  -- writes into it without measuring.  "CHARIZARD AREA UNKNOWN" is 22, so it
  -- ran off the right edge of the screen mid-word.
  local HEADER_COLS = 19
  local HEADER_Y = 0

  -- Gen 1's ten cumulative slot thresholds out of 256 (wild_encounters.asm).
  -- The dataset carries its own under constants.encounterBuckets; this is the
  -- fallback for a stub that does not.
  local BUCKETS = { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }

  -- The strip is not a sentence: the blinking nests have already said WHERE,
  -- so this is the rest of the answer in as few glyphs as will carry it.
  local SHORT_METHODS = {
    grass = "GRASS",
    water = "SURF",
    super_rod = "SUPER ROD",
  }

  -- Wrapping a module function stacks, and this mod's entry chunk runs again on
  -- every hot reload and every profile switch -- so the second load would paint
  -- a second strip over the first.  The pristine constructor is parked on the
  -- module under a key of this mod's own so a re-install always wraps the
  -- original rather than the last wrap.
  local PRISTINE = "__gen1dex_pristine_new"

  local function wrapNew(module, make)
    local original = rawget(module, PRISTINE) or module.new
    rawset(module, PRISTINE, original)
    module.new = make(original)
    return original
  end

  -- ------------------------------------------------- what the box will say

  local providers = {}

  -- Register a caption provider.  Tolerates area:provide(fn) as well as the
  -- documented area.provide(fn), the way the loader's own mod.find does --
  -- the caller is another mod's code and the colon is an easy slip to make.
  -- Hands back a function that unregisters it again, for a mod that installs
  -- one per playthrough.
  --
  -- `owner` is optional and should be the calling mod's id.  A mod's entry
  -- chunk runs again on every hot reload and every profile switch, and this
  -- registry outlives that: without an owner the second load stacks a second
  -- provider, closed over the FIRST load's tables, and the stale one is the
  -- one that answers.  With it, the new registration replaces the old.
  function A.provide(first, second, third)
    local fn, owner = first, second
    if type(first) == "table" then fn, owner = second, third end
    if type(fn) ~= "function" then
      mod.log:warn("a caption provider that is not a function was ignored")
      return function() end
    end
    local entry = { fn = fn, owner = owner }
    if owner ~= nil then
      for i, candidate in ipairs(providers) do
        if candidate.owner == owner then table.remove(providers, i) break end
      end
    end
    providers[#providers + 1] = entry
    return function()
      for i, candidate in ipairs(providers) do
        if candidate == entry then table.remove(providers, i) return end
      end
    end
  end

  -- A species' share of one map's encounters -> the vocabulary a placement
  -- mod's tiers use, so a wild RATTATA and a placed BULBASAUR describe
  -- themselves in one language.
  local function tierFor(share)
    if share >= 51 then return "COMMON" end       -- a whole top bucket, 20%
    if share >= 25 then return "UNCOMMON" end     -- ~10%
    if share >= 10 then return "RARE" end
    return "VERY RARE"
  end

  -- Anything in the live encounter tables, which is every wild POKéMON on the
  -- cartridge and every one a mod added a slot for.  The map reported is the
  -- one where the species has the biggest share of the encounters, and the
  -- level band is that map's -- a band pooled across every map would read
  -- "Lv6-40" for ZUBAT and tell nobody anything.
  local function fromEncounters(game, species)
    local data = game.data
    local buckets = (data.constants or {}).encounterBuckets or BUCKETS
    local best, kind, lo, hi = 0, nil, nil, nil
    for _, record in pairs(data.encounters or {}) do
      for group, entry in pairs(record) do
        if group == "grass" or group == "water" then
          local share, low, high, previous = 0, nil, nil, 0
          for index, slot in ipairs(entry.slots or {}) do
            local edge = buckets[index]
            local width = edge and (edge - previous) or 0
            if edge then previous = edge end
            if slot.species == species then
              share = share + width
              low = math.min(low or slot.level, slot.level)
              high = math.max(high or slot.level, slot.level)
            end
          end
          if low and share >= best then
            best, kind, lo, hi = share, group, low, high
          end
        end
      end
    end
    if not kind then return nil end
    local how = SHORT_METHODS[kind] or kind:upper()
    local band = lo == hi and ("Lv%d"):format(lo) or ("Lv%d-%d"):format(lo, hi)
    -- share 0 means every slot it sits in is past the tenth bucket, i.e. it
    -- is a mod's appended slot and its real odds are that mod's roll rather
    -- than a bucket.  Its own provider answers those; this is the leftover
    -- case, and guessing COMMON for it would be a lie.
    if best <= 0 then return { how .. "  " .. band } end
    return { how .. "  " .. band, tierFor(best) }
  end

  -- Not a wild POKéMON on this cartridge at all.  The dex still owes the
  -- player an answer, and the evolution table has one: nothing here is a
  -- guess, it is the same table the game evolves from.
  local function fromEvolution(game, species)
    for id, def in pairs(game.data.pokemon or {}) do
      for _, evo in ipairs(def.evolutions or {}) do
        if evo.species == species then
          local from = (game.data.pokemon[id] or {}).name or id
          if evo.method == "TRADE" then
            return { "LINK CABLE", "ON " .. from }
          end
          if evo.method == "ITEM" and evo.item then
            local item = (game.data.items or {})[evo.item] or {}
            return { item.name or evo.item, "ON " .. from }
          end
          if evo.level then
            return { "EVOLVE " .. from, ("AT LV%d"):format(evo.level) }
          end
          return { "EVOLVE " .. from }
        end
      end
    end
    return nil
  end

  -- One clamp for every source, at the box's own per-line budget, measured in
  -- the pixels the glyphs draw rather than in bytes -- a variable-advance
  -- font skin makes those different numbers.  Each source could mind its own
  -- width, and then a new one would forget to; the box knows how wide it is,
  -- so the box decides.
  local function clamp(lines)
    if type(lines) ~= "table" then return nil end
    local out = {}
    for index, line in ipairs(lines) do
      if type(line) ~= "string" then break end
      local budget = LINE_COLS[index] or LINE_COLS[#LINE_COLS]
      local spans = Font.split(line)
      local room = Font.spansFitting(spans, budget * 8)
      if room < #spans then
        out[index] = line:sub(1, spans[math.max(room, 1)].to)
      else
        out[index] = line
      end
      if index >= #LINE_COLS then break end
    end
    if out[1] == nil then return nil end
    return out
  end

  -- The registered providers first, in the order they registered, then the
  -- two readings this mod can make on its own.  A provider that throws is
  -- skipped and reported rather than taking the screen down with it: a mod
  -- that cannot caption a species is a missing line, not a broken POKéDEX.
  --
  -- nil means NOBODY ANSWERED -- a seal included, since a seal is a refusal to
  -- answer rather than an answer.  What the screen draws in that case is
  -- A.UNKNOWN; this function stays the place to ask whether an answer exists
  -- at all, which is a different question and worth being able to ask.
  function A.caption(game, species)
    for _, entry in ipairs(providers) do
      local ok, answer = pcall(entry.fn, game, species)
      if not ok then
        mod.log:warn("the caption provider from %s failed on %s (%s); it is "
          .. "dropped rather than asked again", tostring(entry.owner or "a mod"),
          tostring(species), tostring(answer))
        for i, candidate in ipairs(providers) do
          if candidate == entry then table.remove(providers, i) break end
        end
        -- the list shrank under the iterator, so this species falls through
        -- to whatever is left rather than skipping the next provider
        return A.caption(game, species)
      elseif answer == false then
        -- the seal: this species is somebody's and its answer is withheld.
        -- No built-in reading gets to fill it in, and the screen says the
        -- same thing over it that it says over any other blank.
        return nil
      elseif answer ~= nil then
        return clamp(answer)
      end
    end
    local wild = fromEncounters(game, species)
    if wild then return clamp(wild) end
    return clamp(fromEvolution(game, species))
  end

  -- ------------------------------------------------------ the caption strip

  -- Whether a string fits a column budget, measured the way the text box
  -- measures it: in the pixels the glyphs actually draw, not in bytes.  A
  -- variable-advance font (a TTF skin) makes those two different numbers, and
  -- the header that overflowed was counted in bytes.
  local function fits(text, cols)
    local spans = Font.split(text)
    return Font.spansFitting(spans, cols * 8) >= #spans
  end

  local function shorten(text, cols)
    local spans = Font.split(text)
    local room = Font.spansFitting(spans, cols * 8)
    if room >= #spans then return text end
    return text:sub(1, spans[math.max(room, 1)].to)
  end

  local function drawBox(lines, arrow)
    Font.drawBox(BOX_TX, BOX_TY, BOX_TW, BOX_TH)
    C.black()
    Font.draw(lines[1] or "", TEXT_X, LINE1_Y)
    if lines[2] then Font.draw(lines[2], TEXT_X, LINE2_Y) end
    -- the same blinking prompt the engine prints at the end of a page, in
    -- the same corner of the same box: "there is a press waiting here" said
    -- the way the rest of the game says it
    if arrow then Font.drawCode(Theme.moreArrow or 0xEE, ARROW_X, ARROW_Y) end
    C.white()
  end

  -- The header.  Two cases, and vanilla measures neither of them.
  --
  --   <NAME>'s NEST      left alone when it fits, shortened when it does not
  --   <NAME> UNKNOWN     always ours
  --
  -- The nest line is the engine's and mostly fits, so it is repainted only
  -- when it would have run off the edge.  The unknown line never really fitted:
  -- "<NAME> AREA UNKNOWN" is 12 glyphs plus the name, so every name of 8 or
  -- more -- MOLTRES, ARTICUNO, CHARIZARD, half the dex -- ran off the right
  -- edge of the screen mid-word.  AREA is dropped rather than the name
  -- truncated, because the screen the player is standing on is already called
  -- AREA and the word was doing no work: what the line has to carry is WHICH
  -- POKéMON and that nothing is known about it.
  local function headerFor(screen, species)
    local def = screen.game.data.pokemon[species]
    local name = (def and def.name) or species
    if #screen.nests > 0 then
      local nest = name .. "'s NEST"
      if fits(nest, HEADER_COLS) then return nil end
      return shorten(nest, HEADER_COLS)
    end
    local unknown = name .. " UNKNOWN"
    if fits(unknown, HEADER_COLS) then return unknown end
    return shorten(name, HEADER_COLS)
  end

  -- TownMap's own markerXY (src/ui/TownMap.lua:129).  The Kanto art is inset
  -- two tiles across and one down inside the screen, so a location's entry
  -- coordinate from the ROM is not its pixel -- which is why a nest looks two
  -- tiles right of where town_map_entries.asm says it is, and is not.
  -- Mirrored rather than reached for, because it is a local in that file: the
  -- cursor drawn here has to land on the same pixels as the nests and the
  -- player marker, which the engine draws through that same expression.
  local function markerXY(loc)
    return loc.x * 8 + 16, loc.y * 8 + 8
  end

  -- The selection box the plain town map blinks on the cursor, in AREA mode
  -- where vanilla never drew one.
  local function drawCursor(screen)
    local sel = screen.locs and screen.locs[screen.sel]
    if not sel or (screen.blink or 0) >= 25 then return end
    local x, y = markerXY(sel)
    if screen.bg and screen.bg.cursor then
      C.white()
      -- the asset is a 16x16 hollow frame centred on its own (8,8), so -4,-4
      -- encloses the cell -- the engine's comment, and its arithmetic
      love.graphics.draw(screen.bg.cursor, x - 4, y - 4)
    else
      C.black()
      love.graphics.rectangle("line", x + 0.5, y + 0.5, 7, 7)
      C.white()
    end
  end

  local function drawHeader(text)
    C.white()
    love.graphics.rectangle("fill", 0, HEADER_Y, 160, 8)
    C.black()
    Font.draw(text, 8, HEADER_Y)
    C.white()
  end

  -- ------------------------------------------------------------ the screens

  function A.install()
    local TownMap = require("src.ui.TownMap")
    wrapNew(TownMap, function(baseTownMap)
    return function(game, opts)
      local screen = baseTownMap(game, opts)
      local species = opts and opts.nestSpecies
      if not (species and type(screen) == "table") then return screen end
      -- read per open rather than once at load, so turning AREA HINTS off in
      -- the manager shows up the next time the screen is opened
      if not C.option("area_hints", true) then return screen end
      local ok, answer = pcall(A.caption, game, species)
      if not ok then
        mod.log:warn("the AREA caption did not build for %s: %s",
          tostring(species), tostring(answer))
        answer = nil
      end
      -- No answer is an answer here: see A.UNKNOWN.  Every AREA screen gets
      -- the box, which is also what makes the header below always ours to
      -- repaint -- the case that overflowed was exactly the case that used to
      -- return early.
      local lines = (answer and answer[1]) and answer or A.UNKNOWN

      -- Instance fields shadow the metatable methods, so the engine's own draw
      -- and update run untouched underneath.
      local showing = true
      local baseDraw = screen.draw or TownMap.draw
      local baseUpdate = screen.update or TownMap.update

      local header = headerFor(screen, species)

      -- Two different questions, and conflating them was wrong.
      --
      -- Whether the d-pad should MOVE anything is about having somewhere to
      -- move to, and vanilla's AREA branch ignores the d-pad on every build.
      --
      -- Whether to DRAW a cursor and a banner is about which path the engine's
      -- own draw took: it returns early from the AREA branch only when the real
      -- background art loaded.  Without it, TownMap falls through to a list that
      -- already draws its own cursor and its own banner, and a second pair on
      -- top of those is not navigation, it is a mess.
      --
      -- Both are asked per frame rather than captured, because the background
      -- is loaded by the constructor and a caller may still be assembling the
      -- screen when the wrap returns.
      local function canMove(self)
        return type(self.locs) == "table" and #self.locs > 1
      end
      local function drawsOwnChrome(self)
        return self.mode == "grid" and self.bg ~= nil
      end

      -- ------- the vanilla no-nests box
      --
      -- With nothing to mark, town_map.asm:403 puts a 17x4 box across the
      -- middle of the map reading AREA UNKNOWN.  On this screen that is the
      -- third thing saying so at once: the header above it already reads
      -- "<NAME> UNKNOWN", and the strip below carries the half that is worth
      -- reading -- what the POKéMON comes from, which the box does not know.
      -- So a screen that HAS an answer was covering half its own map to say
      -- it has none.
      --
      -- Dropped by not drawing it rather than by painting over it: the map
      -- underneath would have to be redrawn to hide it, and redrawing the art
      -- to cover one box is more fragile than not putting the box down.
      -- Font.drawBox and Font.draw are stood in for across the engine's draw,
      -- the two calls that make that box are recognised by exactly where they
      -- land, and everything else on the pass goes through untouched.  Both
      -- are put back whatever happens, so an error inside the engine's draw
      -- cannot leave the font module stubbed for the rest of the game.
      --
      -- Only while the strip is up.  A puts the hint away for a look at the
      -- bare map, and with the strip gone the box is the only thing left on
      -- the screen saying why the map is empty -- so there it stays, and
      -- START brings both back together.
      local UNKNOWN_BOX = { 1, 7, 17, 4 }
      local UNKNOWN_TEXT_X, UNKNOWN_TEXT_Y = 16, 72

      local function drawWithoutUnknownBox(self)
        local realBox, realDraw = Font.drawBox, Font.draw
        Font.drawBox = function(tx, ty, tw, th, ...)
          if tx == UNKNOWN_BOX[1] and ty == UNKNOWN_BOX[2]
              and tw == UNKNOWN_BOX[3] and th == UNKNOWN_BOX[4] then
            return
          end
          return realBox(tx, ty, tw, th, ...)
        end
        -- By position rather than by the string: the engine writes a bare
        -- literal there, but a build that translates it still puts it in the
        -- same place, and nothing else in this branch draws on that pixel.
        Font.draw = function(text, x, y, ...)
          if x == UNKNOWN_TEXT_X and y == UNKNOWN_TEXT_Y then return end
          return realDraw(text, x, y, ...)
        end
        local ok, err = pcall(baseDraw, self)
        Font.drawBox, Font.draw = realBox, realDraw
        if not ok then error(err, 0) end
      end

      screen.draw = function(self)
        if showing and #(self.nests or {}) == 0 then
          drawWithoutUnknownBox(self)
        else
          baseDraw(self)
        end
        if showing then
          if header then drawHeader(header) end
          -- blinking in time with the map's own nests rather than to a clock
          -- of its own: one screen, one pulse
          drawBox(lines, (self.blink or 0) < 25)
        elseif drawsOwnChrome(self) then
          -- hint down: the screen becomes the plain town map, cursor and all,
          -- and the strip says where the cursor is rather than what you were
          -- looking up.  START puts the hint back.
          local sel = self.locs[self.sel]
          if sel then drawHeader(shorten(self:bannerText(sel), HEADER_COLS)) end
          drawCursor(self)
        elseif header then
          drawHeader(header)
        end
      end

      -- The engine plays Press_AB on every A this screen answers
      -- (TownMap:update).  Reached through TextBox.soundOpts rather than by
      -- requiring the sound module, because that is the arming the mod surface
      -- offers and it is the same call underneath.
      local function pressSound()
        local opts = mod.ui.TextBox.soundOpts(game, "Press_AB")
        local play = opts and opts.auto and opts.auto.sound
        if play then play() end
      end

      -- and Tink on every cursor step, which is what TownMap:moveList plays
      local function moveSound()
        local opts = mod.ui.TextBox.soundOpts(game, "Tink")
        local play = opts and opts.auto and opts.auto.sound
        if play then play() end
      end

      -- Snap the cursor to the nearest location the key actually points at.
      --
      -- Done here rather than called on the screen because TownMap has no
      -- grid move to call: its d-pad handling is moveList, which walks the
      -- list in cursor order with UP and DOWN and ignores LEFT and RIGHT
      -- (engine/items/town_map.asm:74), and on an AREA screen it does not run
      -- at all -- the nestSpecies branch answers A and nothing else.  This
      -- used to call a `moveGrid` that no version of TownMap has ever had, so
      -- the first d-pad press on the AREA map raised "attempt to call method
      -- 'moveGrid' (a nil value)" and took the game down with it.
      --
      -- Nearest IN THAT DIRECTION, not nearest overall: a cone of 45 degrees
      -- either side of the key, so LEFT off Pallet Town reaches the coast
      -- rather than the town one row up that happens to be fewer cells away.
      -- Off-axis is scored harder than distance so the straight neighbour
      -- wins a tie, and a key with nothing in front of it does nothing --
      -- the cursor stays where it is instead of leaping across Kanto.
      local function moveGrid(self, dx, dy)
        local locs = self.locs
        local from = locs and locs[self.sel]
        if not (from and from.x and from.y) then return false end
        local best, bestScore
        for i, loc in ipairs(locs) do
          if i ~= self.sel and loc.x and loc.y then
            local ox, oy = loc.x - from.x, loc.y - from.y
            local along = ox * dx + oy * dy
            local across = math.abs(ox * dy) + math.abs(oy * dx)
            if along > 0 and along >= across then
              local score = across * 3 + along
              if not bestScore or score < bestScore then
                best, bestScore = i, score
              end
            end
          end
        end
        if not best then return false end
        self.sel = best
        moveSound()
        return true
      end

      screen.update = function(self, dt)
        local input = self.game.input
        -- A on the AREA screen closes it (TownMap:update).  While the hint is
        -- up, A means "I have read it" instead -- so the box comes off the
        -- bottom of Kanto, nests included, and the NEXT A closes the screen the
        -- way it always did.  B is untouched: it still leaves immediately, for
        -- anyone who does not want the hint at all.
        if showing then
          if input:wasPressed("a") then
            showing = false
            pressSound()
            return
          end
        elseif canMove(self)
            and (input:wasPressed("up") or input:wasPressed("down")
                 or input:wasPressed("left") or input:wasPressed("right")) then
          -- the plain map's own snap-to-nearest, sound and all
          if self.mode == "grid" then
            local dx = (input:wasPressed("right") and 1 or 0)
              - (input:wasPressed("left") and 1 or 0)
            local dy = (input:wasPressed("down") and 1 or 0)
              - (input:wasPressed("up") and 1 or 0)
            -- LEFT and RIGHT together, or a key with nothing in front of it,
            -- leave the cursor alone; UP and DOWN then still walk the list,
            -- so a d-pad press is never simply swallowed on a map that has
            -- somewhere to go.
            if (dx ~= 0 or dy ~= 0) and not moveGrid(self, dx, dy)
               and dy ~= 0 then
              self:moveList(dy > 0 and -1 or 1)
            end
          else
            self:moveList(input:wasPressed("down") and 1 or -1)
          end
          return baseUpdate(self, dt)
        elseif input:wasPressed("start") then
          -- and START brings it back, because dismissing a hint you have not
          -- finished reading should not mean leaving the screen and coming in
          -- again.  START does nothing at all on this screen in vanilla, so
          -- nothing is taken away to pay for it.
          showing = true
          pressSound()
          return
        end
        return baseUpdate(self, dt)
      end
      return screen
    end
    end)

    mod.log:info("AREA opens on undiscovered entries, with a hint under the "
      .. "map for every species the data can answer for")
  end

  -- ------------------------------------------- AREA on an undiscovered entry

  local warned = false

  -- Called by list.lua on the list it just built.  Every row this mod builds
  -- carries `species` whether the entry has been discovered or not, which is
  -- what makes this a two-line wrap rather than the index arithmetic it used
  -- to take from the outside: a dex list is free to sort, filter or replace
  -- its rows, and the moment it does, position N stops meaning species N.
  -- ------- the box the side menu never had
  --
  -- The vanilla dex prints DATA / CRY / AREA / QUIT permanently into the
  -- block down the right of its screen, so PokedexMenu's side menu draws the
  -- cursor and those labels alone -- "the block is already on screen", as its
  -- own comment puts it, and it is, because the vanilla list drew it.
  --
  -- This list does not.  The right of the screen is where the names run, and
  -- SEEN / OWN moved into a footer box, so there is no block for a menu to be
  -- the cursor on: on a discovered entry the engine's menu came up as four
  -- bare words floating over the list, the last of them printed across the
  -- footer, with QUIT past the bottom of the screen.
  --
  -- One box, drawn where this mod's own menus are drawn.  Bottom-aligned on
  -- the last row of the body, so two entries sit exactly where they always
  -- have and four grow UPWARD into the list rather than down through the
  -- footer.  Clamped to the top of the body for Yellow's five, which fill it.
  local FOOTER_TY = C.FOOTER_TY                 -- 15: first row of the footer
  local BODY_TOP_TILE = C.BODY_TOP / 8          -- 3:  first row under the header

  local function sideMenu(game, entries)
    local th = #entries * 2 + 2
    local ty = math.max(BODY_TOP_TILE, FOOTER_TY - 1 - th)
    return Menu.new(game, entries, { tx = 12, ty = ty, tw = 8, th = th })
  end

  function A.wireList(game, list, opts)
    if type(list) ~= "table" then return list end

    local unseenMenu = C.option("area_unseen", true)
    local baseChoose = list.onChoose

    -- A discovered entry: the engine's menu, in a box.
    --
    -- Rather than rebuild DATA and CRY -- they are the engine's, Yellow adds
    -- PRNT to them, and every one of them is a closure over state this mod
    -- does not have -- chooseEntry is RUN and the menu it pushes is taken.
    -- Everything else it does still happens on the way past, which is the
    -- hollow cursor it leaves on the chosen row; the entries that come back
    -- are its own, so what a press does is unchanged.  Only the box is ours.
    local function boxedEngineMenu(item, dexList)
      if not baseChoose then return end
      local stack = game.stack
      if type(stack) ~= "table" or type(stack.push) ~= "function" then
        return baseChoose(item, dexList)
      end
      local realPush, captured = stack.push, nil
      stack.push = function(_, screen) captured = screen end
      local ok, err = pcall(baseChoose, item, dexList)
      stack.push = realPush
      if not ok then
        mod.log:warn("the dex side menu did not build: %s", tostring(err))
        return
      end
      local entries = type(captured) == "table" and captured.items or nil
      if type(entries) ~= "table" or #entries == 0 then
        -- Something other than a menu, or a menu with no rows: hand back
        -- whatever it was rather than swallow the press.  An unboxed menu
        -- still works; a press that does nothing is worse.
        if captured ~= nil then stack:push(captured) end
        return
      end
      stack:push(sideMenu(game, entries))
    end

    local choose
    choose = function(item, dexList)
      if item.value then return boxedEngineMenu(item, dexList) end
      if not unseenMenu then
        if baseChoose then return baseChoose(item, dexList) end
        return
      end
      local species = item.species
      if type(species) ~= "string" then
        -- Something replaced the rows with entries that name no species.
        -- Nothing sensible is left to open, so say so once rather than
        -- returning silently -- a menu that does nothing when pressed is the
        -- hardest kind of bug to report.
        if not warned then
          warned = true
          mod.log:warn("a dex row carries no species, so AREA cannot be "
            .. "opened on it; something has replaced the rows this mod built")
        end
        return
      end
      -- AREA and QUIT only.  DATA on a POKéMON you have never met would hand
      -- over the height, the weight and the dex paragraph, which is a good
      -- deal more than "where do I look" -- and nobody asked for it.
      local entries = {
        { label = "AREA", onSelect = function()
            mod.ui.push(game, "TownMap", { nestSpecies = species })
          end },
        { label = "QUIT", onSelect = function()
            dexList:close()
            if opts and opts.onCancel then opts.onCancel() end
          end },
      }
      -- The chosen row goes hollow while this is up, the way the engine's own
      -- side menu leaves it; PokedexMenu:update clears it on the way back.
      dexList.hollowIndex = dexList.index
      game.stack:push(sideMenu(game, entries))
    end

    -- Marked so a bench -- this mod's, or a content mod's -- can say in one
    -- press which link of this chain is missing on an install that is not
    -- behaving.  The difference between "the rows were replaced" and "the A
    -- handler was replaced" decides the fix, and guessing between them from a
    -- bug report is what cost a release.
    list.onChoose = choose
    -- The probe's marker means "AREA on an undiscovered entry is wired", so
    -- it is set only when it is.  The boxed menu above is wired either way --
    -- a broken box is not an option this mod offers.
    list.__gen1dexArea = unseenMenu or nil
    list.__gen1dexChoose = choose
    return list
  end

  -- ------------------------------------------------------------- the probe

  -- Every link that has to hold for a press on an undiscovered entry to open
  -- AREA, reported from the list the game would actually build -- through the
  -- screens registry, so whichever factory is really installed is the one
  -- that answers.  Paged with \f, because it is printed in a text box.
  function A.probe(game)
    local Screens = require("src.ui.Screens")
    local factory = Screens.get(game, "PokedexMenu")
    local ok, list = pcall(factory.new, game, {})
    if not ok or type(list) ~= "table" then
      return "The dex list did\nnot build.\f" .. tostring(list)
    end
    local owner = factory.__modOwned and "A MOD" or "VANILLA"
    if not list.__gen1dexArea then
      if not C.option("area_unseen", true) then
        return "DEX: " .. owner .. "\fAREA ON UNSEEN is\noff in GEN1DEX's\foptions."
      end
      return "DEX: " .. owner .. "\fIt is not this\nmod's list,\fso AREA cannot\nbe added."
    end
    if list.onChoose ~= list.__gen1dexChoose then
      return "DEX: " .. owner .. "\fSomething replaced\nthe A handler,\fso AREA cannot\nbe added."
    end
    local unknown, named = nil, 0
    for _, item in ipairs(list.items or {}) do
      if not item.value then
        unknown = unknown or item
        if type(item.species) == "string" then named = named + 1 end
      end
    end
    if not unknown then
      return "DEX: " .. owner .. "\fEvery entry is\nalready seen,\fso there is nothing\nto test."
    end
    if type(unknown.species) ~= "string" then
      return "DEX: " .. owner .. "\fIts rows do not\nname a species,\fso AREA cannot\nbe added."
    end
    return "DEX: " .. owner .. "\fWrap on, rows\nnamed.\f" .. tostring(named)
      .. " unseen rows\nwill open AREA."
  end

  return A
end
