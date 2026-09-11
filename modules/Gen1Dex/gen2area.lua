-- Gen1Dex on Gold, Silver and Crystal: a line under the AREA map saying how to
-- get there.
--
-- Returns a factory: factory(mod, DexData) -> { install, provide, caption,
-- probe, COLS, UNKNOWN }, which main.lua builds on Gold in place of area.lua.
--
-- ------- why this is a second file and not a branch in area.lua
--
-- area.lua is the Gen 1 AREA screen and almost all of it is Red's: it wraps
-- `src.ui.TownMap`, it steers a cursor, it flies, and it opens INSPECT.  Gold
-- has none of that.  Its AREA page is a VIEW inside `src.ui.gen2.PokedexMenu`
-- (`self.view == "area"`), drawn by `PokedexMenu:drawArea`, with no cursor and
-- with A and B both meaning "back to the entry".
--
-- And underneath, the encounter tables are a different table.  Red keys wild
-- data by map and then by kind; Gold keys it by KIND and then by map, splits
-- grass three ways by time of day, and carries four more kinds Red has no word
-- for -- fishing groups, headbutt trees, rock smash and swarms.  Its evolution
-- rows spell the target `into` rather than `species` and its methods are
-- `EVOLVE_LEVEL` rather than `LEVEL`.
--
-- A branch in area.lua would have been one file reading two schemas through a
-- flag, and the flag is exactly how the last four Gen 2 bugs got written: a
-- Gen 1 reader pointed at a Gen 2 table returns nil rather than an error, and
-- nil is a caption that never draws and never says why.  So this file reads
-- Gold's tables in Gold's spelling and nothing else.
--
-- ------- what it costs the map, and where the line goes
--
-- ONE ROW, at the very bottom, and that is not a style choice.  Gold's nest
-- icons are drawn at (mark.x - 4, mark.y - 4) out of the landmark table, whose
-- lowest y is 132: data/maps/landmarks.asm writes `\2 + 16`, but that sixteen
-- is the HARDWARE SPRITE offset and RomExtractorGen2 takes it straight back
-- off, so the macro's own argument IS the screen row.  The lowest icon on
-- either map therefore occupies y 128 to 135, and row 17 begins at 136.
--
-- A one-row strip there covers no nest on either region.  A two-row strip
-- would cover the southernmost ones on both -- which are the answer the player
-- opened the page for.  Red's screen could afford a four-row box because its
-- caption had to say two things at once and its map had room; this one cannot,
-- so the line says less and the map keeps all of itself.
--
-- It is drawn the way the cart draws the line at the TOP of the same screen --
-- `PokedexMenu:drawAreaHeader`: a solid bar in the map palette's colour 3,
-- then an INVERTED print over it.  Same paint, same palette, same call, so the
-- two ends of the screen match each other and the theme colours both of them
-- in one place rather than two.
--
-- ------- and what another mod gets to say
--
-- The same contract as Red's, deliberately: `provide` takes a function
-- returning two lines, or `false` for a seal, or nil for no opinion, and a
-- provider written for the Gen 1 screen works here unchanged.  The two lines
-- are JOINED into one while they fit and truncated to the first when they do
-- not -- which is the only difference, and it is the box's business rather
-- than the provider's, the same way Red's per-line clamp is.

return function(mod, DexData)
  local self = {}

  local Font = mod.ui.Font

  -- ------- the strip
  --
  -- Row 17, full width, printed one column in.  The header prints two columns
  -- in and runs to the right edge; this one gives the last column back so the
  -- line does not touch the corner, which is the only place a bottom strip can
  -- look unfinished.
  local STRIP_TY = 17
  local TEXT_TX = 1
  -- Nineteen columns: one in from the left, and the last glyph runs to the
  -- right edge.  The header can afford to inset both sides because it prints
  -- one short name; this line prints a whole answer, and the difference
  -- between eighteen columns and nineteen is literally whether "SURF Lv20-25
  -- COMMON" says how often.  There is no border to collide with -- the bar
  -- under the text is the full width of the screen -- so the only cost is the
  -- last glyph column touching the edge, and the vanilla sheet's glyphs carry
  -- their own blank column on that side.
  self.COLS = 19

  -- What the strip says when NOBODY can answer.  Red's two lines, joined the
  -- way a provider's two would be -- so a species with no answer reads the
  -- same on both cartridges, which is the point of it having words at all.
  -- See area.lua: a blank strip cannot tell "no hint for you" from "the hint
  -- did not draw", and a seal must be indistinguishable from an ordinary
  -- blank or the seal announces what it is hiding.
  self.UNKNOWN = { "NO RECORD REMAINS", "GO ADVENTURING!" }

  -- ------- the odds, in Gold's own scale
  --
  -- data/wild/probabilities.asm.  Red's ten slots are cumulative out of 256;
  -- Gold's seven grass slots and three water slots are cumulative out of 100,
  -- and `ChooseWildEncounter` rolls `cp 100` against them.  Different scale,
  -- so different numbers -- the same numbers would have read every grass slot
  -- as VERY RARE.
  local GRASS_BUCKETS = { 30, 60, 80, 90, 95, 99, 100 }
  local WATER_BUCKETS = { 60, 90, 100 }

  -- The same four words Red's strip uses at the same four odds: 51/256 is
  -- 19.9%, 25/256 is 9.8%, 10/256 is 3.9%.  A wild RATTATA describes itself
  -- the same way on both cartridges, which is the whole reason to convert the
  -- scale here rather than invent a second vocabulary.
  local function tierFor(percent)
    if percent >= 20 then return "COMMON" end
    if percent >= 10 then return "UNCOMMON" end
    if percent >= 4 then return "RARE" end
    return "VERY RARE"
  end

  local TOD = { "MORN", "DAY", "NITE" }

  local function encounters(game)
    local data = game and game.data
    return (data and data.gen2Encounters) or {}
  end

  -- A cumulative table -> the width of slot `index`, which is that slot's own
  -- share.  Slots past the table's end are a mod's appended rows: they have no
  -- bucket, so they get no share and the caption drops the tier rather than
  -- guessing one (the same call area.lua makes for the same reason).
  local function widthOf(buckets, index)
    local edge = buckets[index]
    if not edge then return nil end
    return edge - (buckets[index - 1] or 0)
  end

  local function band(lo, hi)
    if not lo then return nil end
    if lo == hi then return ("Lv%d"):format(lo) end
    return ("Lv%d-%d"):format(lo, hi)
  end

  -- ------- grass
  --
  -- One row per map, and inside it one seven-slot table per time of day.  The
  -- map reported is the one where the species has the biggest share summed
  -- across the times it appears at; the level band is that map's, because a
  -- band pooled over every map reads "Lv3-40" for ZUBAT and tells nobody
  -- anything.
  --
  -- Which TIMES it appears at is carried out with it, and it is the fact this
  -- screen has that Red's does not: a player standing in the right grass at
  -- the wrong hour is being told nothing by a blinking nest.
  local function fromGrass(game, species, key)
    local rows = encounters(game)[key or "grass"] or {}
    local best, lo, hi, times = nil, nil, nil, nil
    for _, row in pairs(rows) do
      local slots = type(row) == "table" and row.slots or nil
      if type(slots) == "table" then
        local share, low, high, here = 0, nil, nil, {}
        for _, tod in ipairs(TOD) do
          local list = slots[tod]
          if type(list) == "table" then
            local found = false
            for index, slot in ipairs(list) do
              if slot and slot.species == species then
                found = true
                -- three tables of seven, so the share is per time of day and
                -- the sum over three times is a percentage of three rolls --
                -- divided back down below so it stays a percentage of one.
                share = share + (widthOf(GRASS_BUCKETS, index) or 0)
                low = math.min(low or slot.level, slot.level)
                high = math.max(high or slot.level, slot.level)
              end
            end
            if found then here[#here + 1] = tod end
          end
        end
        if low and (best == nil or share > best) then
          best, lo, hi, times = share, low, high, here
        end
      end
    end
    if not lo then return nil end
    return { share = (best or 0) / #TOD, lo = lo, hi = hi, times = times }
  end

  -- ------- water
  --
  -- No time-of-day split: one rate and one three-slot table per map.
  local function fromWater(game, species, key)
    local rows = encounters(game)[key or "water"] or {}
    local best, lo, hi = nil, nil, nil
    for _, row in pairs(rows) do
      local slots = type(row) == "table" and row.slots or nil
      if type(slots) == "table" then
        local share, low, high = 0, nil, nil
        for index, slot in ipairs(slots) do
          if slot and slot.species == species then
            share = share + (widthOf(WATER_BUCKETS, index) or 0)
            low = math.min(low or slot.level, slot.level)
            high = math.max(high or slot.level, slot.level)
          end
        end
        if low and (best == nil or share > best) then
          best, lo, hi = share, low, high
        end
      end
    end
    if not lo then return nil end
    return { share = best or 0, lo = lo, hi = hi }
  end

  -- ------- fishing
  --
  -- A map's rod points at a NAMED GROUP and the group carries a table per rod,
  -- so the species is looked up in the groups rather than in the maps -- the
  -- strip does not have to say which pond, because the nests already did.
  --
  -- The weakest rod that can catch it wins: a player who can be told OLD ROD
  -- should not be sent for the SUPER ROD.  A row may defer to a time group
  -- (TimeFishGroups) for its day and night halves, so both are read.
  local RODS = { { "old", "OLD ROD" }, { "good", "GOOD ROD" },
                 { "super", "SUPER ROD" } }

  local function fishSlotSpecies(enc, row)
    local out = {}
    for _, sub in ipairs({ "day", "nite" }) do
      local slot = row[sub]
      if not slot and row.timeGroup then
        local tg = (enc.timeFishGroups or {})[row.timeGroup]
        slot = tg and tg[sub]
      end
      if slot then out[#out + 1] = slot end
    end
    if #out == 0 then out[1] = row end
    return out
  end

  local function fromFishing(game, species)
    local enc = encounters(game)
    for _, rod in ipairs(RODS) do
      local key, word = rod[1], rod[2]
      local lo, hi
      for _, group in pairs(enc.fishGroups or {}) do
        for _, row in ipairs((type(group) == "table" and group[key]) or {}) do
          for _, slot in ipairs(fishSlotSpecies(enc, row)) do
            if slot.species == species and slot.level then
              lo = math.min(lo or slot.level, slot.level)
              hi = math.max(hi or slot.level, slot.level)
            end
          end
        end
      end
      if lo then return { how = word, lo = lo, hi = hi } end
    end
    return nil
  end

  -- ------- headbutt and rock smash
  --
  -- `trees` and `rocks` are both map -> set name and both index `treeSets`, so
  -- the SET does not know which of the two reached it.  Which word the strip
  -- uses is therefore decided by which registry points at a set holding the
  -- species, with HEADBUTT first because a set reachable both ways is a tree
  -- set that four Rock Smash maps also point at.
  --
  -- This is the case the strip exists for on Gold.  `Nests.find` reads grass,
  -- water and the roamers and nothing else, so a HEADBUTT-only species -- the
  -- whole of HERACROSS, PINECO, EXEGGCUTE, AIPOM -- opens an AREA page with a
  -- blank map, and before this there was no way for the game to tell the
  -- player why.
  local function setHasSpecies(set, species)
    local lo, hi
    for _, listKey in ipairs({ "common", "rare" }) do
      for _, slot in ipairs((type(set) == "table" and set[listKey]) or {}) do
        if slot.species == species and slot.level and slot.level > 0 then
          lo = math.min(lo or slot.level, slot.level)
          hi = math.max(hi or slot.level, slot.level)
        end
      end
    end
    if not lo then return nil end
    return lo, hi
  end

  local function fromTrees(game, species)
    local enc = encounters(game)
    for _, pair in ipairs({ { "trees", "HEADBUTT" }, { "rocks", "ROCK SMASH" } }) do
      local registry, word = pair[1], pair[2]
      local lo, hi
      for _, setName in pairs(enc[registry] or {}) do
        local a, b = setHasSpecies((enc.treeSets or {})[setName], species)
        if a then
          lo = math.min(lo or a, a)
          hi = math.max(hi or b, b)
        end
      end
      if lo then return { how = word, lo = lo, hi = hi } end
    end
    return nil
  end

  -- ------- the roamers
  --
  -- The three legendary beasts, which live in no wild table at all -- the map
  -- page finds them through `Roamers`, and so does this.  Their level never
  -- changes (the roam struct has no experience), so the band is a single Lv40.
  local function fromRoamer(game, species)
    local ok, Roamers = pcall(require, "src.core.gen2.Roamers")
    if not (ok and type(Roamers) == "table"
            and type(Roamers.roster) == "function") then
      return nil
    end
    local rosterOk, roster = pcall(Roamers.roster, encounters(game))
    if not rosterOk or type(roster) ~= "table" then return nil end
    for _, row in ipairs(roster) do
      if row.species == species then
        return { how = "ROAMING", lo = row.level, hi = row.level }
      end
    end
    return nil
  end

  -- ------- given, not found
  --
  -- Reported as two bugs and it is one: "some pokemon like the other starters
  -- aren't showing in the dex search area. So means their data isn't in the
  -- dex?", and "Eevee doesn't show up in the dex as well. Encountered it on
  -- Route 34 ... it said No Area recorded".
  --
  -- The data is all there.  The starters and EEVEE are GIFTS -- and Bill's
  -- house, which is where EEVEE comes from, IS on Route 34, so the second
  -- report is the first one twice.  Neither is in any wild table, and neither
  -- evolves from anything, so every reading above answered nil and the page
  -- fell through to NO RECORD REMAINS.  Which reads as "this cartridge has
  -- lost your POKeMON's data", and the truth is the opposite: somebody hands
  -- it to you.
  --
  -- `givepoke` is the cart's own word for that, and the extractor keeps it --
  -- species, level and all -- in the script pool.  So the answer is read out
  -- of the same bytecode the game runs when it gives you one.
  --
  -- The species is a RAW ROM BYTE there, not a key: `cmd.species = args[1]`,
  -- which `src/world/gen2/World.lua` resolves through `def.index` when it
  -- actually gives the POKeMON.  Resolved the same way here, so a cartridge
  -- whose species order is not the vanilla one still answers correctly.
  --
  -- Scanned ONCE per dataset and remembered against it: the caption is built
  -- on every frame of the AREA page, and walking the whole script pool sixty
  -- times a second is a stutter on the one screen that is meant to sit still.
  local giftsByData = setmetatable({}, { __mode = "k" })

  local function speciesByIndex(pokemon, index)
    if not (pokemon and index) then return nil end
    for id, def in pairs(pokemon) do
      if type(def) == "table" and def.index == index then return id end
    end
    return nil
  end

  local function giftsIn(game)
    local data = game and game.data
    if type(data) ~= "table" then return {} end
    local hit = giftsByData[data]
    if hit then return hit end

    local out = {}
    for _, script in pairs(data.gen2Scripts or {}) do
      if type(script) == "table" then
        for _, cmd in ipairs(script) do
          if type(cmd) == "table" and cmd.op == "givepoke" then
            local index = cmd.species or (cmd.args and cmd.args[1])
            local id = speciesByIndex(data.pokemon, index)
            if id then
              local level = tonumber(cmd.level
                or (cmd.args and cmd.args[2])) or nil
              local row = out[id]
              if not row then
                out[id] = { lo = level, hi = level }
              elseif level then
                row.lo = math.min(row.lo or level, level)
                row.hi = math.max(row.hi or level, level)
              end
            end
          end
        end
      end
    end
    giftsByData[data] = out
    return out
  end

  local function fromGift(game, species)
    local row = giftsIn(game)[species]
    if not row then return nil end
    return { how = "GIFT", lo = row.lo, hi = row.hi }
  end

  -- ------- not wild anywhere
  --
  -- Gold's evolution rows spell the target `into`, not `species`, and their
  -- methods are `EVOLVE_LEVEL`, `EVOLVE_ITEM`, `EVOLVE_TRADE`,
  -- `EVOLVE_HAPPINESS` and `EVOLVE_STAT` -- Red's reader looks for `species`
  -- and `"TRADE"` and would silently find nothing on every one of them.
  --
  -- The name of what it evolves FROM is masked the way every other name on
  -- this screen is: a player who has met a QUILAVA and never a CYNDAQUIL is
  -- owed the shape of the answer and not the name of a POKeMON they have not
  -- met.
  local function evolvesFrom(game, species)
    local seenName = self.seenName
    for id, def in pairs((game.data or {}).pokemon or {}) do
      for _, evo in ipairs((type(def) == "table" and def.evolutions) or {}) do
        if evo.into == species then
          local from = seenName(game, id)
          if evo.method == "EVOLVE_TRADE" then
            return { "LINK CABLE", "ON " .. from }
          end
          if evo.method == "EVOLVE_ITEM" and evo.item then
            local item = ((game.data or {}).items or {})[evo.item] or {}
            return { item.name or evo.item, "ON " .. from }
          end
          if evo.method == "EVOLVE_HAPPINESS" then
            return { "BE KIND TO", from }
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

  -- The dex's own silence, in the one spelling that works on both cartridges:
  -- Red writes `save.pokedex.owned`, Gold writes `save.pokedex.caught`, and
  -- both write `save.pokedex.seen`.  SEEN is the right test either way -- this
  -- screen names what you have met, not what you have caught.
  function self.seenName(game, species)
    local data = game and game.data
    local def = type(data) == "table" and data.pokemon
      and data.pokemon[species] or nil
    local name = (type(def) == "table" and def.name) or species
    local dex = game and game.save and game.save.pokedex
    if type(dex) ~= "table" then return "?????" end
    local seen = (dex.seen and dex.seen[species])
      or (dex.caught and dex.caught[species])
      or (dex.owned and dex.owned[species])
    return seen and name or "?????"
  end

  -- ------- putting the line together
  --
  -- The parts in the order a player needs them, appended only while they fit.
  -- Red's box clamps each of its two lines to its own budget; this one has a
  -- single line and one budget, so the truncation falls on the LAST part
  -- rather than mid-word in the middle of the sentence -- which is why the
  -- order is method, then level, then time, then how often.
  --
  -- The tier goes last because it is the part the player can do least with,
  -- and the time goes ahead of it because standing in the right grass at the
  -- wrong hour is the failure the strip is there to prevent.
  local function fits(text)
    local spans = Font.split(text)
    return Font.spansFitting(spans, self.COLS * 8) >= #spans
  end

  -- ONE space between parts, where Red's box uses two.  Red has two lines and
  -- thirty-five columns for the same answer; this has one line and nineteen,
  -- and every doubled space here costs a word off the end -- "GRASS  Lv2-4
  -- COMMON" is twenty columns and "GRASS Lv2-4 COMMON" is eighteen.  Two
  -- spaces would have read slightly better and said slightly less, on the
  -- screen whose whole complaint was that it said nothing.
  -- The parts, packed.  Two of them are optional -- the time of day is absent
  -- for a species that appears at all three, and the tier is absent for every
  -- kind whose odds do not convert -- and a list literal with a nil in the
  -- middle of it is a list `ipairs` stops at.  That is not a hypothetical: it
  -- dropped COMMON off every grass line that had no hour to report, which is
  -- most of them, and the strip still LOOKED right.
  local function packed(...)
    local out, n = {}, select("#", ...)
    for i = 1, n do
      local part = select(i, ...)
      if part ~= nil and part ~= "" then out[#out + 1] = part end
    end
    return out
  end

  local function joinFitting(parts)
    local out = nil
    for _, part in ipairs(parts) do
      if part and part ~= "" then
        local candidate = out and (out .. " " .. part) or part
        if not fits(candidate) then break end
        out = candidate
      end
    end
    return out
  end

  -- A provider's two lines, or the built-ins' two lines, reduced to one.  The
  -- pair is joined while it fits and cut to the first when it does not -- and
  -- the first is itself truncated rather than dropped, because a strip with
  -- nothing in it is the blank this whole file exists to replace.
  local function clamp(lines)
    if type(lines) ~= "table" then return nil end
    local first = type(lines[1]) == "string" and lines[1] or nil
    if not first then return nil end
    local joined = joinFitting(packed(first,
      type(lines[2]) == "string" and lines[2] or nil))
    if joined then return joined end
    local spans = Font.split(first)
    local room = Font.spansFitting(spans, self.COLS * 8)
    return first:sub(1, spans[math.max(room, 1)].to)
  end

  local providers = {}

  -- The same registration Red's screen publishes, so a mod that captions a
  -- species does it once and gets both cartridges.  `owner` is only ever used
  -- to name the mod in the warning when its provider throws.
  function self.provide(fn, owner)
    if type(fn) ~= "function" then return false end
    providers[#providers + 1] = { fn = fn, owner = owner }
    return true
  end

  -- The built-in readings, in the order the cart itself would rank them: what
  -- the nests are already showing first, then the kinds the nests cannot show,
  -- then not-wild-at-all.
  local function builtin(game, species)
    local grass = fromGrass(game, species, "grass")
    local water = fromWater(game, species, "water")
    if grass or water then
      -- both, occasionally (TENTACOOL is neither) -- the bigger share wins,
      -- and a tie goes to the grass because that is where a player will stand
      -- without needing SURF.
      if grass and (not water or grass.share >= water.share) then
        local times = grass.times or {}
        local when = (#times > 0 and #times < #TOD)
          and table.concat(times, "/") or nil
        local tier = grass.share > 0 and tierFor(grass.share) or nil
        return packed("GRASS", band(grass.lo, grass.hi), when, tier)
      end
      local tier = water.share > 0 and tierFor(water.share) or nil
      return packed("SURF", band(water.lo, water.hi), tier)
    end

    -- The swarm tables shadow their base table while a swarm is running, so a
    -- species that is ONLY in one is only ever there during the swarm -- which
    -- is the fact worth printing, rather than the odds.
    local swarm = fromGrass(game, species, "swarmGrass")
    local swarmWater = not swarm and fromWater(game, species, "swarmWater")
    if swarm then return packed("SWARM", band(swarm.lo, swarm.hi)) end
    if swarmWater then return packed("SWARM", band(swarmWater.lo, swarmWater.hi)) end

    -- Fishing, headbutt and rock smash carry no odds the strip can honestly
    -- convert: a fishing row is gated by the group's own bite chance and a
    -- tree slot by a coordinate score, so a tier here would be a number that
    -- looks like the grass ones and is not comparable to them.  The method
    -- and the level band are the whole answer, and they are the parts that
    -- change what the player does.
    local rod = fromFishing(game, species)
    if rod then return packed(rod.how, band(rod.lo, rod.hi)) end
    local tree = fromTrees(game, species)
    if tree then return packed(tree.how, band(tree.lo, tree.hi)) end
    local roam = fromRoamer(game, species)
    if roam then return packed(roam.how, band(roam.lo, roam.hi)) end

    -- Somebody hands it to you: the starters, EEVEE, the fossils, the Odd
    -- Egg's TOGEPI, the Karate King's TYROGUE.  Before `evolvesFrom` on
    -- purpose -- a gift is a place to walk to, an evolution is a thing to do
    -- to a POKeMON you may not have yet -- and after every wild reading,
    -- because a species that is both (DRATINI) is worth finding in the grass.
    local gift = fromGift(game, species)
    if gift then return packed(gift.how, band(gift.lo, gift.hi)) end

    -- Not obtainable in the wild at all on this cartridge: the baby stages
    -- that only hatch, the stone and trade evolutions, and everything a mod
    -- has taken out of the tables.  The evolution table still owes the player
    -- an answer and has one, and it is not a guess -- it is the same table
    -- the game evolves from.
    return evolvesFrom(game, species)
  end

  -- The registered providers first, in the order they registered, then the
  -- readings above.  A provider that throws is dropped and reported rather
  -- than taking the screen down: a mod that cannot caption a species is a
  -- missing line, not a broken AREA page.
  --
  -- nil means NOBODY ANSWERED, a seal included -- a seal is a refusal to
  -- answer rather than an answer.  The strip draws self.UNKNOWN over both,
  -- which is what keeps a seal from reading as one.
  function self.caption(game, species)
    if not (game and species) then return nil end
    for _, entry in ipairs(providers) do
      local ok, answer = pcall(entry.fn, game, species)
      if not ok then
        mod.log:warn("the caption provider from %s failed on %s (%s); it is "
          .. "dropped rather than asked again", tostring(entry.owner or "a mod"),
          tostring(species), tostring(answer))
        for i, candidate in ipairs(providers) do
          if candidate == entry then table.remove(providers, i) break end
        end
        -- the list shrank under the iterator, so this species falls through to
        -- whatever is left rather than skipping the next provider
        return self.caption(game, species)
      elseif answer == false then
        return nil
      elseif answer ~= nil then
        return clamp(answer)
      end
    end
    local parts = builtin(game, species)
    if not parts then return nil end
    return joinFitting(parts)
  end

  -- What the strip would say right now, for the check script and the tests.
  function self.probe(game, species)
    return self.caption(game, species) or clamp(self.UNKNOWN)
  end

  -- ------- installing

  local MARK = "__gen1DexGen2Area"

  function self.install()
    local okDex, PokedexMenu = pcall(require, "src.ui.gen2.PokedexMenu")
    if not (okDex and type(PokedexMenu) == "table") then
      mod.log:warn("no src.ui.gen2.PokedexMenu; the AREA caption stands down")
      return false
    end
    if rawget(PokedexMenu, MARK) then return true end
    local baseArea = PokedexMenu.drawArea
    if type(baseArea) ~= "function" then
      mod.log:warn("src.ui.gen2.PokedexMenu has no drawArea; the AREA caption "
        .. "stands down")
      return false
    end

    local okChrome, Chrome = pcall(require, "src.ui.gen2.Chrome")
    local okGbc, GbcPalette = pcall(require, "src.render.GbcPalette")
    if not (okChrome and type(Chrome) == "table"
            and type(Chrome.printThrough) == "function") then
      mod.log:warn("no src.ui.gen2.Chrome; the AREA caption stands down")
      return false
    end

    -- Asked every frame rather than captured, so turning the row off is the
    -- cart's own AREA page back with no relaunch -- and turning it off takes
    -- the caption away from a mod that registered one too, because a player
    -- who turned hints off turned them off.
    local function enabled()
      return mod.options:get("area_hints") ~= false
    end

    -- Reported once and then stood down from, the way the theme is: this runs
    -- on every frame of the AREA page, and a caption that cannot be built
    -- should cost the line rather than the screen.
    local broken = false

    -- The bar, painted exactly as `drawAreaHeader` paints its own: the map
    -- palette's colour 3 behind, an inverted print over it.  `printThrough`
    -- only fills the width of the string, so the full-width bar is drawn
    -- first -- otherwise the strip would be a ragged tab rather than a line.
    local function drawStrip(screen, text)
      local pals = screen.mapGfx and screen.mapGfx.palettes
      local pal = pals and pals[1]
      local paper = { 0, 0, 0 }
      if pal and okGbc and type(GbcPalette) == "table"
          and type(GbcPalette.color) == "function" then
        paper = GbcPalette.color(pal, 4) or paper
      end
      local G = love.graphics
      G.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
      G.rectangle("fill", 0, STRIP_TY * 8, Chrome.SCREEN_W * 8, 8)
      G.setColor(1, 1, 1, 1)
      Chrome.printThrough(text, TEXT_TX, STRIP_TY, pal, true, true)
    end

    PokedexMenu.drawArea = function(screen, ...)
      baseArea(screen, ...)
      if broken or not enabled() then return end
      local row = screen.current and screen:current()
      if not (row and row.species) then return end
      local ok, problem = pcall(function()
        -- No answer is an answer here: every AREA page gets a line, so a
        -- species nobody can speak for says so rather than showing a bar of
        -- nothing (see self.UNKNOWN).
        local text = self.caption(screen.game, row.species) or clamp(self.UNKNOWN)
        if text then drawStrip(screen, text) end
      end)
      if not ok then
        broken = true
        mod.log:warn("the AREA caption stood down for this session: %s",
                     tostring(problem))
      end
    end

    PokedexMenu[MARK] = true
    mod.log:info("the AREA map carries its caption on Gold")
    return true
  end

  return self
end
