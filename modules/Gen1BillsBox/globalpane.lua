-- The GLOBAL BOX at runtime: the pages the box screen shows, and the one
-- conversion that lets one store serve both generations.
--
-- globalbox.lua is the STORE -- buckets, ids, claims, the union view -- and
-- knows nothing about a game being open.  This is the layer between it and a
-- screen: it finds the saves, holds the session's view of them, and converts a
-- POKeMON when, and only when, it crosses generations.
--
-- ------- nothing is converted on the way IN, and nothing mounts a dataset
--
-- The box keeps each POKeMON in its OWN generation's shape and records which
-- (globalbox.lua, FORMAT 2).  So a deposit is a copy and a stamp, from either
-- game, and a withdrawal converts only when the stored shape is not this
-- game's:
--
--   Gen 1 -> Gen 1, Gen 2 -> Gen 2   nothing to do
--   Gen 1 -> Gen 2                   Convert.toGen2
--   Gen 2 -> Gen 1                   Convert.toGen1, which may REFUSE
--
-- Both of those read the other generation's dataset only as a FALLBACK -- for
-- a POKeMON with no stats (src/online/Convert.lua:126) or no maxHp (:262) --
-- and a stored POKeMON has both, because the deposit side makes sure of them.
-- So each conversion runs on the LIVE game's own dataset and this mod never
-- mounts anything.
--
-- The version that did mount is why: it stored one shape, Gen 1's, so a Gen 2
-- deposit had to compute a Gen 1 POKeMON, which genuinely needs Gen 1's base
-- stats and growth rates.  That put a whole dataset mount behind a keypress,
-- made the feature unusable for anyone with no Gen 1 game imported, and
-- reported every way it could fail as the same "RED, BLUE or YELLOW must be
-- imported" -- including the ways that had nothing to do with an import.
--
-- ------- and a refusal is about the game taking it OUT
--
-- "RED never heard of that move" is not a fact about storing a POKeMON, it is
-- a fact about handing it to RED.  So the Time Capsule's refusals are asked at
-- the withdrawal into a Gen 1 game and nowhere else.  A Johto POKeMON goes in
-- the box happily from Gold and simply will not come out on Red.
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

  -- ------- the one conversion

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

  -- Into the box: a copy, with its stats made sure of, in whatever shape it
  -- already is.  Nothing is converted and nothing can be refused for being
  -- the wrong generation, because the box holds both.
  --
  -- `Stats.ensure` is the one piece of work, and it is what keeps the OTHER
  -- generation's withdrawal free: Convert falls back to the far dataset only
  -- for a POKeMON whose stats are missing, so a stored POKeMON that has them
  -- can be converted by a game that has never seen its dataset.
  local function toStored(game, mon)
    if type(mon) ~= "table" or mon.species == nil then return nil, "not_a_mon" end
    -- The one thing a DEPOSIT still refuses, and it is the cart's own rule
    -- rather than the Time Capsule's: Gold will not put a POKeMON holding MAIL
    -- into storage at all ("Remove MAIL.", src/ui/gen2/BoxMenu.lua), because
    -- sPartyMail is keyed by party slot and a boxed POKeMON has none.  Nothing
    -- to do with which generation is reading it later.
    if mon.mail ~= nil then return nil, "has_mail" end
    local Mail = requireOr("src.core.gen2.Mail")
    if Mail and type(Mail.monHoldsMail) == "function" then
      local okMail, holds = pcall(Mail.monHoldsMail, mon)
      if okMail and holds then return nil, "has_mail" end
    end
    local stored = copyMon(mon)
    -- Gen 1 only, because there is no gen2 Stats module and no need for one:
    -- Gold's own POKeMON carry `stats` and `maxHp` already, and a Gen 1 box
    -- POKeMON is the one that can reach here without them (an imported .sav,
    -- the vanilla PC's own deposit).  src/pokemon/Stats.lua is Red's.
    if generation() ~= 2 then
      local Stats = requireOr("src.pokemon.Stats")
      local def = game and game.data and game.data.pokemon
        and game.data.pokemon[mon.species]
      if Stats and def and type(Stats.ensure) == "function" then
        pcall(Stats.ensure, def, stored)
      end
    end
    return stored
  end

  -- Out of the box, in THIS game's shape.
  --
  -- Same generation: a copy, stripped of the box's own bookkeeping -- a
  -- POKeMON in your party has no business carrying the id it had in storage.
  -- Crossing: Convert's, on the live dataset, and the Gen 2 -> Gen 1 direction
  -- is the one that can say no.
  local function fromStored(game, mon)
    if type(mon) ~= "table" then return nil, "not_a_mon" end
    local here, stored = generation(), GlobalBox.genOf(mon)
    local data = game and game.data or {}
    local out, reason
    if here == stored then
      out = copyMon(mon)
    elseif not Convert then
      return nil, "not_a_mon"
    elseif here == 2 then
      out, reason = Convert.toGen2(mon, nil, data)
    else
      out, reason = Convert.toGen1(mon, nil, data)
    end
    if not out then return nil, tostring(reason or "not_a_mon") end
    out.gbId, out.gbSent, out.gbGen = nil, nil, nil
    return out
  end

  -- Whether this game could take a stored POKeMON out, without taking it out.
  -- The box screen asks before it draws a cell as one you can pick up, and the
  -- refusal it answers with is the Time Capsule's own.
  function Pane.refusalForTaking(game, mon)
    local out, reason = fromStored(game, mon)
    if out then return nil end
    return reason or "not_a_mon"
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

  -- Which generation this game is, for the store to stamp on a deposit.
  Pane.generation = generation

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
    local id, why = GlobalBox.deposit(self.bucket, self.view, stored,
                                      generation())
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
