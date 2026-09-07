-- The GLOBAL BOX at runtime: the pages the box screen shows, and the two
-- conversions that let one store serve two cartridges.
--
-- globalbox.lua is the STORE -- buckets, ids, claims, the union view -- and
-- knows nothing about a game being open.  This is the layer between it and a
-- screen: it finds the saves, holds the session's view of them, and turns a
-- POKeMON of this cartridge's generation into the Gen 1 shape the box keeps,
-- and back again.
--
-- ------- the two directions are not the same cost, and that is the design
--
-- The box keeps ONE shape, Gen 1's.  So:
--
--   * A Gen 1 cartridge deposits and withdraws with no conversion at all.
--     The only thing it does on the way in is `Stats.ensure`, so the stored
--     POKeMON carries its computed stats -- see below for why that matters to
--     the OTHER cartridge.
--   * A Gen 2 cartridge WITHDRAWING calls Convert.toGen2, which reads the Gen
--     1 dataset only as a fallback for a POKeMON whose stats are missing
--     (src/online/Convert.lua:126).  Because the deposit side guarantees they
--     are not, a withdrawal needs no Gen 1 dataset -- which is the direction
--     this feature was asked for: everything out of the Wild Green box and
--     into Wild Crystal.
--   * A Gen 2 cartridge DEPOSITING calls Convert.toGen1, which genuinely
--     needs Gen 1's base stats, moves and growth rates
--     (src/online/Convert.lua:236, :269, :281).  There is no way to compute a
--     Gen 1 POKeMON without them.
--
-- So one direction out of four mounts a Gen 1 dataset, through the engine's
-- own Trade.withDataset -- the same call the Time Capsule makes -- and the
-- result is snapshotted and kept for the rest of the session, so the cost is
-- paid once and only by a player who actually sends FROM Gold.
--
-- ------- what a screen gets
--
-- A session, opened when the box screen opens and thrown away when it closes.
-- It holds the live save's bucket (which is a table INSIDE the save, so every
-- write it makes is written when the game writes) and a rebuilt-on-demand
-- view of every save's outbox.  Pages are that view in twenties.

return function(mod, GlobalBox)
  local Pane = { PAGE = GlobalBox.PAGE, MAX_PAGES = GlobalBox.MAX_PAGES }

  local function requireOr(name)
    local ok, module = pcall(require, name)
    return ok and module or nil
  end

  local function generation()
    local GameVersion = requireOr("src.core.GameVersion")
    if not (GameVersion and type(GameVersion.generation) == "function") then
      return 1
    end
    local ok, gen = pcall(GameVersion.generation)
    return (ok and tonumber(gen)) or 1
  end

  -- ------- mod.save, as a table
  --
  -- The store works on a plain table so it can be driven by a test with no
  -- loader in it.  mod.save is a pair of accessors over the same table inside
  -- the save (src/mods/Loader.lua:1439), so this is the whole adapter: `get`
  -- hands back the live reference, which is why a bucket mutated through here
  -- is a bucket mutated in the save.
  local modSave = setmetatable({}, {
    __index = function(_, key)
      local ok, value = pcall(function() return mod.save:get(key) end)
      return ok and value or nil
    end,
    __newindex = function(_, key, value)
      pcall(function() mod.save:set(key, value) end)
    end,
  })

  -- ------- the Gen 1 dataset, for the one direction that needs it

  local snapshot, snapshotRefused

  -- Only what Convert.toGen1 reads, copied out while the dataset is mounted
  -- and kept afterwards.  A shallow copy is enough: the per-species and
  -- per-move tables are what unloadGenerated drops its references to, and
  -- holding our own keeps them alive.
  local function snapshotOf(data)
    if type(data) ~= "table" then return nil end
    local out = { pokemon = {}, moves = {}, growth_rates = data.growth_rates }
    for key, value in pairs(data.pokemon or {}) do out.pokemon[key] = value end
    for key, value in pairs(data.moves or {}) do out.moves[key] = value end
    if next(out.pokemon) == nil then return nil end
    return out
  end

  -- Red first, because that is the cartridge whose rules this box keeps; the
  -- other two are here so an installation that imported one of them and not
  -- Red is not told it has no Gen 1 game.
  local GEN1_VERSIONS = { "red", "blue", "yellow" }

  local function gen1Data()
    if snapshot then return snapshot end
    if snapshotRefused then return nil, "no_gen1_data" end
    local Trade = requireOr("src.online.Trade")
    if not (Trade and type(Trade.withDataset) == "function") then
      snapshotRefused = true
      return nil, "no_gen1_data"
    end
    -- The engine's own guard: mounting a second dataset over a live Gen 1
    -- game is what Trade itself refuses to do, and this must not be the one
    -- caller that tries it.  On Gold it is false, which is the only boot that
    -- ever gets here.
    if type(Trade.gameIsLive) == "function" then
      local okLive, live = pcall(Trade.gameIsLive)
      if okLive and live then
        snapshotRefused = true
        return nil, "no_gen1_data"
      end
    end
    for _, version in ipairs(GEN1_VERSIONS) do
      local ok, got = pcall(Trade.withDataset, version, function(data)
        return snapshotOf(data)
      end)
      if ok and type(got) == "table" then
        snapshot = got
        mod.log:info("the GLOBAL BOX reads %s for its Gen 1 rules", version)
        return snapshot
      end
    end
    snapshotRefused = true
    mod.log:warn("no Gen 1 game is imported, so nothing can be sent to the "
      .. "GLOBAL BOX from here")
    return nil, "no_gen1_data"
  end

  -- Exposed so a suite can drive the Gold arm without an import tree, and so
  -- a failed mount is not permanent across a hot reload.
  function Pane.setGen1Data(data)
    snapshot = data or nil
    snapshotRefused = false
  end

  -- ------- the two conversions

  local Convert = requireOr("src.online.Convert")

  -- A POKeMON crossing between the box and a game is COPIED, never shared.
  --
  -- Convert builds a fresh table on both of its paths, so this is only the
  -- Red arm's problem -- and it is a real one: the box stamps an id onto what
  -- it stores, and a stored POKeMON that is also the one in your party is a
  -- POKeMON whose id you can level up, evolve and rename.  Worse, taking one
  -- out hands back the table the withdrawal TICKET is holding, so stripping
  -- the id off what the player gets would strip it off the thing that has to
  -- be put back if they press B.
  local function copyMon(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do out[copyMon(key, seen)] = copyMon(item, seen) end
    return out
  end

  -- Into the box.  On Red this is a copy of the POKeMON with its stats made
  -- sure of -- Gold's withdrawal reads those stats and computes its own from
  -- them (src/online/Convert.lua:126), so a POKeMON stored without them is
  -- one that arrives on Gold with the wrong HP.  On Gold it is Convert's,
  -- refusals and all.
  local function toStored(game, mon)
    if type(mon) ~= "table" or mon.species == nil then return nil, "not_a_mon" end
    if mon.isEgg then return nil, "is_egg" end
    if generation() ~= 2 then
      local Stats = requireOr("src.pokemon.Stats")
      local def = game and game.data and game.data.pokemon
        and game.data.pokemon[mon.species]
      local stored = copyMon(mon)
      if Stats and def then pcall(Stats.ensure, def, stored) end
      return stored
    end
    if not Convert then return nil, "no_gen1_data" end
    local data, why = gen1Data()
    if not data then return nil, why end
    local out, reason = Convert.toGen1(mon, game and game.data or {}, data)
    if not out then return nil, tostring(reason or "not_a_mon") end
    return out
  end

  -- Out of the box.  The Gen 1 dataset is passed when it happens to be in
  -- hand and left out when it is not: toGen2 only reaches for it when the
  -- stored POKeMON has no stats, and toStored is what makes sure it does.
  local function fromStored(game, mon)
    if type(mon) ~= "table" then return nil, "not_a_mon" end
    if generation() ~= 2 then
      local out = copyMon(mon)
      -- the box's own bookkeeping is the box's; a POKeMON in your party has
      -- no business carrying the id it had while it was in storage
      out.gbId, out.gbSent = nil, nil
      return out
    end
    if not Convert then return nil, "not_a_mon" end
    local out, reason = Convert.toGen2(mon, snapshot, game and game.data or {})
    if not out then return nil, tostring(reason or "not_a_mon") end
    return out
  end

  Pane.toStored, Pane.fromStored = toStored, fromStored

  -- Would this POKeMON be refused, asked WITHOUT opening a session.
  --
  -- Opening one reads and decodes every save on the installation, and the
  -- party menu asks this every time a POKeMON's popup is built -- so the row
  -- test is the conversion alone, which needs no disk at all.  What it cannot
  -- see is a box that is full; that is caught on the press, where there is a
  -- text box to say it in.
  function Pane.wouldRefuse(game, mon)
    local out, reason = toStored(game, mon)
    if out then return nil end
    return reason or "not_a_mon"
  end

  -- ------- a session

  local Session = {}
  Session.__index = Session

  local function readSources(bucket, liveKey)
    return GlobalBox.readAll({
      modId = mod.id,
      liveKey = liveKey,
      liveBucket = bucket,
    })
  end

  -- Rebuilt after every write, because a page and a cell are positions in the
  -- view and a write moves them.  Reading the OTHER saves off disk again is
  -- the expensive half, so that is done once per session and only the union
  -- is recomputed -- a second cartridge cannot be running to change them.
  function Session:refresh()
    self.view = GlobalBox.view(self.sources)
    return self.view
  end

  function Session:reload()
    self.sources = readSources(self.bucket, self.liveKey)
    return self:refresh()
  end

  function Session:writable() return self.bucket ~= nil end

  function Session:pages() return GlobalBox.pages(self.view) end

  function Session:count() return GlobalBox.count(self.view) end

  function Session:capacity() return GlobalBox.PAGE end

  -- How many are on ONE page, which is what a header counts.
  function Session:countOn(page)
    local total = self:count()
    local before = (tonumber(page) or 1) - 1
    return math.max(0, math.min(GlobalBox.PAGE, total - before * GlobalBox.PAGE))
  end

  -- The stored POKeMON, in the box's own Gen 1 shape.  This is what a screen
  -- DRAWS: species is a name on both generations, so an icon and a nickname
  -- need no conversion, and converting one every frame to draw it would be
  -- the most expensive thing this screen does.
  function Session:at(page, cell)
    local entry = GlobalBox.at(self.view, page, cell)
    return entry and entry.mon or nil
  end

  function Session:entryAt(page, cell)
    return GlobalBox.at(self.view, page, cell)
  end

  -- Where an id sits right now, as a page and a cell.  A box screen that has
  -- just put a POKeMON back asks this rather than remembering where it was:
  -- the cell it came out of is a position in a view that has been rebuilt
  -- since, and the id is the only thing that survives that.
  function Session:locate(id)
    if id == nil then return nil end
    for index, entry in ipairs(self.view) do
      if entry.id == id then
        return math.floor((index - 1) / GlobalBox.PAGE) + 1,
               ((index - 1) % GlobalBox.PAGE) + 1
      end
    end
    return nil
  end

  -- Whether this POKeMON could be sent, without sending it.  Used to leave
  -- the SEND row off a POKeMON that would only refuse, and to answer before
  -- the box takes one out of the party.
  function Session:refusalFor(game, mon)
    if not self:writable() then return "no_save" end
    if GlobalBox.full(self.view) then return "full" end
    local out, reason = toStored(game, mon)
    if not out then return reason or "not_a_mon" end
    return nil
  end

  -- Deposit.  Answers with where it landed -- page and cell -- because the
  -- box is a queue and the cell the player was aiming at is not necessarily
  -- the one it went into; the cursor follows this rather than guessing.
  function Session:put(game, mon)
    if not self:writable() then return nil, "no_save" end
    local stored, reason = toStored(game, mon)
    if not stored then return nil, reason end
    local id, why = GlobalBox.deposit(self.bucket, self.view, stored)
    if not id then return nil, why end
    self:refresh()
    for index, entry in ipairs(self.view) do
      if entry.id == id then
        return index, math.floor((index - 1) / GlobalBox.PAGE) + 1,
               ((index - 1) % GlobalBox.PAGE) + 1
      end
    end
    return nil, "full"
  end

  -- Withdraw, in this cartridge's shape.  The ticket is how `untake` puts it
  -- back; a caller that drops the ticket has moved a POKeMON permanently.
  function Session:take(game, page, cell)
    if not self:writable() then return nil, "no_save" end
    local entry = GlobalBox.at(self.view, page, cell)
    if not entry then return nil, "empty_cell" end
    -- converted BEFORE the store is touched, so a refusal leaves the box
    -- exactly as it was
    local mon, reason = fromStored(game, entry.mon)
    if not mon then return nil, reason end
    local _, ticket = GlobalBox.withdraw(self.bucket, self.sources, self.view,
                                         page, cell)
    if type(ticket) ~= "table" then return nil, tostring(ticket or "empty_cell") end
    self:refresh()
    return mon, ticket
  end

  function Session:untake(ticket)
    if not (self:writable() and type(ticket) == "table") then return false end
    local ok = GlobalBox.restore(self.bucket, ticket)
    self:refresh()
    return ok
  end

  function Session:refusalText(reason)
    return GlobalBox.refusalText(reason)
  end

  -- Opening a session is also when the saves are reconciled: anything of ours
  -- that another cartridge has taken leaves our outbox here, and a claim of
  -- ours whose POKeMON is gone from every outbox is released.  Done on open
  -- rather than on load because this is the one moment we have already paid
  -- to read every save.
  function Pane.open(game)
    local SaveData = requireOr("src.core.SaveData")
    local GameVersion = requireOr("src.core.GameVersion")
    local liveKey = GlobalBox.liveKey(SaveData, GameVersion)
    local bucket = liveKey and GlobalBox.ensureBucket(modSave) or nil
    local session = setmetatable({
      game = game, bucket = bucket, liveKey = liveKey,
    }, Session)
    session:reload()
    if bucket then
      local dropped, released = GlobalBox.reconcile(bucket, session.sources)
      if dropped > 0 or released > 0 then
        mod.log:info("the GLOBAL BOX let go of %d taken and %d stale claim(s)",
          dropped, released)
        session:refresh()
      end
    end
    return session
  end

  return Pane
end
