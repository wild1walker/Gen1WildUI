-- The GLOBAL BOX: one store of POKeMON that every SAVE on the installation can
-- reach, and that lives inside those saves.
--
-- Deposit a POKeMON in one game, withdraw it in another.  That is the whole
-- feature, and everything below is what it costs.
--
-- "Another game" means any other save this install has, and the distinction
-- matters because the two kinds are registered and read differently: a plain
-- RED/BLUE/YELLOW/GOLD/SILVER/CRYSTAL playthrough keeps its slots under
-- saves/<version>/ and is found through SaveData.listSlots/readSlotSource,
-- while a cartridge keeps its own under saves/cart_<id>/ and is found through
-- listCartSlots/readCartSlotSource.  `readAll` walks BOTH, so this is a
-- Gen1BillsBox feature and not a cartridge one: install this mod on a plain
-- RED and a plain GOLD and the box is shared between them with no cart
-- anywhere.  Two cartridges are simply the case that prompted it.
--
-- ------- where it lives, and why it is not a file of its own
--
-- The first build of this put the box in `mod.cache`
-- (`mod_cache/<modId>/globalbox`, src/mods/ImportAccess.lua:73): no game
-- version, no playthrough and no cart in the path, so both cartridges opened
-- the same file.  It worked and it was wrong, for a reason that only shows up
-- later: SAVE SYNC does not carry it.
--
-- Sync moves two things and no others.  SyncEngine uploads save SLOT SOURCES
-- (SaveData.readSlotSource / readCartSlotSource) through `PUT /sync/save`, and
-- SyncMods uploads the mod roster and its option values through
-- `PUT /sync/mods`.  There is no third endpoint, and `mod_storage` and
-- `mod_cache` are named nowhere in src/ outside the modules that implement
-- them.  A box in either is a box that does not follow the player to their
-- other machine, is not in a backup of their saves, and does not come back
-- with RESTORE.
--
-- So the box lives where sync can see it: `mod.save`, which the engine backs
-- with `save.modData[<modId>]` on both generations (src/core/Game.lua:1222,
-- src/core/Game2.lua:199).  That is inside the save blob, so it syncs, it
-- backs up, and it rolls back with the save that holds it.
--
-- ------- how "inside the saves" can still be one box
--
-- A save is per cart and per slot; there is no shared one.  So the GLOBAL BOX
-- is not one list -- it is the UNION of one OUTBOX per save, and every save
-- carries its own.
--
--   * Your own save's outbox is the only thing you ever write.
--   * Every other save on the installation is read, read-only, through
--     SaveData.readCartSlotSource / readSlotSource -- the same call sync
--     itself makes -- and decoded for its bucket.
--   * Withdrawing a POKeMON that came out of SOMEONE ELSE'S outbox writes a
--     CLAIM into your own save instead: "this one is mine now".  Claims are
--     read by everybody, so the POKeMON leaves the box for every cartridge
--     the moment you take it, and the save that still physically holds it
--     drops it the next time it boots (`reconcile`).
--
-- Two consequences worth knowing rather than discovering:
--
--   * A deposit is part of a save, so it is written when the GAME writes.
--     Quit without saving after a SEND and the SEND is gone with everything
--     else you did -- which is what a player already expects of a save, and
--     is exactly what the cache-file version did NOT do.
--   * Delete the save that a claimed POKeMON was withdrawn INTO before the
--     sender next boots, and it reappears in the sender's outbox.  The
--     failure mode of this design is a POKeMON coming back, never one going
--     missing.
--
-- ------- what may live in it
--
-- Any POKeMON either generation can hold, in the shape the game that sent it
-- had it in (see FORMAT below).  The box refuses almost nothing.
--
-- What a GAME will take back out is a different question, and it is the Time
-- Capsule's -- the engine's own rule, which this reuses whole
-- (src/online/Convert.lua) rather than restating.  A Johto species, a Gen 2
-- move, a held MAIL or an EGG cannot come out on a Gen 1 game, and is refused
-- there with the cartridge's own reason.  It comes out on Gold exactly as it
-- went in.
--
-- That is one rule asked at one place, and it is the right place: "RED never
-- heard of that move" is a fact about handing a POKeMON to RED, not about
-- storing it.

local GlobalBox = {}

-- The cartridge's own box holds twenty, and a page that matched nothing would
-- be a page whose "full" a player has no feel for.
GlobalBox.PAGE = 20

-- Twenty pages is four hundred POKeMON, which is more than the twelve boxes
-- of a Gen 1 cartridge (240) and more than Gold's fourteen (280).  The cap is
-- on the UNION, not on one save: it is what the player sees, and it is what
-- keeps any single save's bucket from growing without an end.
GlobalBox.MAX_PAGES = 20
GlobalBox.CAPACITY = GlobalBox.PAGE * GlobalBox.MAX_PAGES

-- The mod.save key the bucket hangs from.
GlobalBox.KEY = "globalbox"

-- FORMAT 2 keeps each POKeMON in ITS OWN generation's shape and says which,
-- where format 1 kept everything in Gen 1's.
--
-- One shape was the wrong trade.  It meant a Gen 2 game had to convert on the
-- way IN, which needs Gen 1's base stats, moves and growth rates -- so a Gold
-- player with no Gen 1 game imported could not use the box at all, and one WITH
-- a Gen 1 game imported paid for a whole dataset mount to send a POKeMON to
-- himself.  It also meant a player whose games are all Gen 2 could never put a
-- Johto POKeMON in, which is most of what such a player has.
--
-- Storing the native shape costs nothing and pays twice.  A deposit converts
-- NOTHING, ever.  A withdrawal converts only when the POKeMON is crossing
-- generations, and Convert reaches for the OTHER generation's dataset only as
-- a fallback for a POKeMON missing its stats (src/online/Convert.lua:126) or
-- its maxHp (:262) -- which a stored POKeMON never is.  So both conversions
-- run on the live game's own dataset and no dataset is ever mounted.
--
-- What moves is WHEN a POKeMON is refused.  "RED never heard of that move" is
-- not a fact about storing it, it is a fact about handing it to RED, so it is
-- asked at the withdrawal into a Gen 1 game and nowhere else.  A Johto POKeMON
-- sits in the box perfectly well; it simply will not come out on Red.
GlobalBox.FORMAT = 2

-- Format 1 buckets are read, not discarded: everything in one is a Gen 1 shape
-- by construction, so it reads as `gbGen = 1` and needs no rewrite to be
-- understood.  Only OUR OWN bucket is ever stamped up to 2, and only when the
-- save it lives in is next written.
GlobalBox.READABLE = { [1] = true, [2] = true }

-- Which generation's shape a stored POKeMON is in.  Absent means format 1,
-- which means Gen 1.
function GlobalBox.genOf(mon)
  if type(mon) ~= "table" then return 1 end
  local gen = tonumber(mon.gbGen)
  return (gen == 2) and 2 or 1
end

-- ------- the rules, borrowed rather than restated

-- The reasons Convert.refusalFor answers with, in the cartridge's own voice.
-- `species_too_new` is the one a player meets: a Johto POKeMON goes in the box
-- happily and will not come out on a Gen 1 game.
--
-- RED stands for the Gen 1 games here, the way the Time Capsule's own refusals
-- do.  Every one of these is now a WITHDRAWAL refusal -- what RED will not
-- take out -- rather than something the box refused to hold.
GlobalBox.REFUSALS = {
  not_a_mon       = "That can't be\nsent.",
  is_egg          = "An EGG can't be\nsent.",
  species_too_new = "Only POKeMON RED\nknows can go in\fthe GLOBAL BOX.",
  has_mail        = "Take the MAIL off\nfirst.",
  move_too_new    = "It knows a move\nRED has never\fheard of.",
  full            = "The GLOBAL BOX is\nfull!",
  no_save         = "There's no save to\nput it in.",
  -- Asked for by a cell that no longer holds what the caller was told it
  -- held.  The GLOBAL BOX is a QUEUE and a withdrawal closes it up, so a
  -- position taken a moment ago is not a position now -- which is why every
  -- caller should be resolving its ID again first (Session:locate).  This
  -- is what a caller that did not gets told, and it used to fall through
  -- to "That can't be sent" -- a sentence about the POKeMON, when the
  -- POKeMON was never the problem.
  empty_cell      = "It's not in the\nGLOBAL BOX now.",
}

function GlobalBox.refusalText(reason)
  return GlobalBox.REFUSALS[reason] or GlobalBox.REFUSALS.not_a_mon
end

-- ------- one save's bucket
--
-- `origin` names the save that owns the bucket and never changes once set: it
-- is half of every id this bucket ever mints, so re-minting it would orphan
-- the claims other saves hold against it.  `seq` is the other half and only
-- ever counts up, so an id is never reused even after the POKeMON that had it
-- has been withdrawn and the slot reused.

local function randomOrigin()
  local time = (os.time and os.time()) or 0
  local clock = math.floor(((os.clock and os.clock()) or 0) * 1000)
  local noise = math.random(0, 0xffffff)
  return ("%x-%x-%x"):format(time, clock, noise)
end

function GlobalBox.newOrigin()
  return randomOrigin()
end

-- What a well-formed bucket looks like, or nil for anything else.  A bucket
-- written by a LATER format reads as ABSENT rather than as one to rewrite: a
-- rewrite would drop whatever this build did not understand, and dropping is
-- how a POKeMON disappears.
function GlobalBox.isBucket(value)
  if type(value) ~= "table" then return false end
  if not GlobalBox.READABLE[tonumber(value.format)] then return false end
  if type(value.origin) ~= "string" or value.origin == "" then return false end
  return true
end

function GlobalBox.bucketOf(modSave)
  if type(modSave) ~= "table" then return nil end
  local bucket = modSave[GlobalBox.KEY]
  if not GlobalBox.isBucket(bucket) then return nil end
  return bucket
end

-- Every bucket in one mod's save data, WHATEVER KEY it was filed under.
--
-- `mod.save:set(KEY, ...)` does not necessarily write at KEY.  Inside the
-- Gen1WildUI bundle each vendored mod gets a facade whose save proxy prefixes
-- every key with the feature's id (runtime/facade.lua, keyedProxy/joinKey), so
-- the bucket this mod writes as "globalbox" is filed as "box.globalbox" -- and
-- the standalone mod, with no facade in front of it, writes the bare name.
--
-- That is invisible to a mod reading back its OWN data, because it reads
-- through the same proxy that wrote it.  It is not invisible to this, which
-- reads other saves RAW off disk: a bucket looked for at "globalbox" in a save
-- the bundle wrote is a bucket that is not there -- which is exactly the bug a
-- player saw as "I put a POKeMON in the GLOBAL BOX in one game and the other
-- game's is empty".
--
-- So the key is not what identifies a bucket; its SHAPE is.  That holds for
-- the prefix this bundle happens to use today, for a different one tomorrow,
-- and for the standalone mod's bare key, without any of them having to be
-- named here.
function GlobalBox.bucketsIn(modSave)
  local out = {}
  if type(modSave) ~= "table" then return out end
  local keys = {}
  for key in pairs(modSave) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do
    local value = modSave[key]
    if GlobalBox.isBucket(value) then out[#out + 1] = value end
  end
  return out
end

-- The same, but minting the bucket when the save has none.  Only ever called
-- for the save the player is IN: a foreign save is read, never written.
function GlobalBox.ensureBucket(modSave)
  if type(modSave) ~= "table" then return nil, "no_save" end
  local bucket = GlobalBox.bucketOf(modSave)
  if bucket then
    bucket.mons = type(bucket.mons) == "table" and bucket.mons or {}
    bucket.claims = type(bucket.claims) == "table" and bucket.claims or {}
    bucket.seq = tonumber(bucket.seq) or 0
    -- A format 1 bucket holds Gen 1 shapes and nothing else, so saying so is
    -- the whole migration.  Done to OUR OWN bucket only, and in place: the ids
    -- do not change, so a claim another save is holding against one of these
    -- still names it.
    if tonumber(bucket.format) ~= GlobalBox.FORMAT then
      for _, mon in ipairs(bucket.mons) do
        if type(mon) == "table" and mon.gbGen == nil then mon.gbGen = 1 end
      end
      bucket.format = GlobalBox.FORMAT
    end
    return bucket
  end
  -- A bucket this build cannot read is left exactly where it is: replacing it
  -- is the one move that loses POKeMON, and the player is better served by a
  -- box that reads empty on an old build than by one that eats a new save.
  if modSave[GlobalBox.KEY] ~= nil then return nil, "foreign_format" end
  bucket = {
    format = GlobalBox.FORMAT,
    origin = GlobalBox.newOrigin(),
    seq = 0,
    mons = {},
    claims = {},
  }
  modSave[GlobalBox.KEY] = bucket
  return bucket
end

-- ------- sources
--
-- A source is one save's bucket plus the key that says which save it came
-- from, so the box screen can name where a POKeMON is sitting and so the live
-- save is never read twice (its bucket in memory is ahead of its bucket on
-- disk, and the one in memory is the true one).

local function sourceFrom(key, bucket, live)
  -- Every format this build can READ, not just the one it writes: another
  -- cartridge running an older build keeps a format 1 bucket, and a box that
  -- stopped seeing it the moment this one updated would not be one box.
  if not GlobalBox.isBucket(bucket) then return nil end
  return {
    key = key,
    origin = bucket.origin,
    mons = type(bucket.mons) == "table" and bucket.mons or {},
    claims = type(bucket.claims) == "table" and bucket.claims or {},
    live = live and true or false,
  }
end

GlobalBox.sourceFrom = sourceFrom

-- Every slot on the installation, the live one included, as sources.
--
-- Deps are injectable so this is testable without a filesystem; in the game
-- they default to the engine's own modules and to the save the player is in.
-- Reading every slot means decoding every slot, which is why the box screen
-- calls this ONCE when it opens rather than every frame.
function GlobalBox.readAll(deps)
  deps = deps or {}
  local function want(name, fallback)
    local given = deps[name]
    if given ~= nil then return given end
    local ok, module = pcall(require, fallback)
    return ok and module or nil
  end
  local SaveData = want("SaveData", "src.core.SaveData")
  local Serializer = want("Serializer", "src.core.SaveSerializer")
  local GameVersion = want("GameVersion", "src.core.GameVersion")
  -- `modId` is no longer how a bucket is found -- it is accepted and ignored,
  -- because a caller that stopped passing it would otherwise read as a caller
  -- that meant something by it.
  local sources = {}

  local liveKey = deps.liveKey
  local liveBucket = deps.liveBucket
  local liveSource = liveKey and sourceFrom(liveKey, liveBucket, true) or nil
  if liveSource then sources[#sources + 1] = liveSource end

  if type(SaveData) ~= "table" or type(Serializer) ~= "table" then
    return sources
  end

  -- Every bucket in a save: every mod id, and every key under each of them.
  --
  -- Neither half of that is optional.  `save.modData` is keyed by MOD ID, and
  -- the same feature ships under more than one -- the stable bundle, the
  -- nightly channel's copy of it, and the standalone mod.  And the KEY inside
  -- one of those is not the key this mod asked for, because a bundle facade
  -- may prefix it (see `bucketsIn`).  Reading only "our id, our key" is
  -- reading only saves written by this exact build, which is not what a box
  -- shared across two cartridges means.
  --
  -- The live save's OWN bucket is the one thing skipped, and it is recognised
  -- by its ORIGIN rather than by where it was filed: the copy in memory is
  -- ahead of the copy on disk, and reading both would show every deposit made
  -- since the last save twice.  Any OTHER bucket in the live save -- one this
  -- save carries from a different channel -- is read like anyone else's.
  local liveOrigin = type(liveBucket) == "table" and liveBucket.origin or nil

  local function take(key, body)
    if type(body) ~= "string" or body == "" then return end
    local okDecode, save = pcall(Serializer.decode, body)
    if not okDecode or type(save) ~= "table" then return end
    local modData = save.modData
    if type(modData) ~= "table" then return end
    local ids = {}
    for id in pairs(modData) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    for _, id in ipairs(ids) do
      for _, bucket in ipairs(GlobalBox.bucketsIn(modData[id])) do
        if not (liveOrigin and bucket.origin == liveOrigin) then
          local source = sourceFrom(key, bucket, false)
          if source then sources[#sources + 1] = source end
        end
      end
    end
  end

  local function slotsOf(lister, ...)
    if type(lister) ~= "function" then return {} end
    local ok, list = pcall(lister, ...)
    return (ok and type(list) == "table") and list or {}
  end

  local okCarts, carts = pcall(SaveData.cartsWithSlots)
  for _, cartId in ipairs((okCarts and type(carts) == "table") and carts or {}) do
    for _, slot in ipairs(slotsOf(SaveData.listCartSlots, cartId)) do
      if slot.exists and slot.id then
        local okRead, body = pcall(SaveData.readCartSlotSource, cartId, slot.id)
        if okRead then take(GlobalBox.cartKey(cartId, slot.id), body) end
      end
    end
  end

  local versions = type(GameVersion) == "table"
    and type(GameVersion.VERSIONS) == "table" and GameVersion.VERSIONS or {}
  local names = {}
  for id in pairs(versions) do names[#names + 1] = id end
  table.sort(names)
  for _, version in ipairs(names) do
    for _, slot in ipairs(slotsOf(SaveData.listSlots, version)) do
      if slot.exists and slot.id then
        local okRead, body = pcall(SaveData.readSlotSource, version, slot.id)
        if okRead then take(GlobalBox.gameKey(version, slot.id), body) end
      end
    end
  end

  return sources
end

function GlobalBox.cartKey(cartId, slotId)
  return ("cart:%s/%s"):format(tostring(cartId), tostring(slotId))
end

function GlobalBox.gameKey(version, slotId)
  return ("game:%s/%s"):format(tostring(version), tostring(slotId))
end

-- Which save the player is in right now, in the same shape.  nil when the
-- engine cannot say -- a launcher screen, a link battle -- and a nil live key
-- is what makes the box read-only rather than what makes it fail.
function GlobalBox.liveKey(SaveData, GameVersion)
  if type(SaveData) ~= "table" then return nil end
  local okCart, cartId = pcall(SaveData.getCart)
  if okCart and cartId then
    local okSlot, slotId = pcall(SaveData.activeCartSlot, cartId)
    if okSlot and type(slotId) == "string" and slotId ~= "" then
      return GlobalBox.cartKey(cartId, slotId)
    end
    return nil
  end
  local version = nil
  if type(GameVersion) == "table" and type(GameVersion.get) == "function" then
    local okVersion, got = pcall(GameVersion.get)
    version = okVersion and got or nil
  end
  local okSlot, slotId = pcall(SaveData.activeSlot, version)
  if okSlot and type(slotId) == "string" and slotId ~= "" then
    return GlobalBox.gameKey(version or "red", slotId)
  end
  return nil
end

-- ------- the view
--
-- What the player sees is every outbox laid end to end with every claimed
-- POKeMON taken out.  It has to be the SAME list whichever cartridge asks,
-- because a page and a slot are how the box screen and the player refer to
-- one -- so the order is a property of the POKeMON, not of the order the
-- saves happened to be read in.  `sent` first, id second: two deposits in the
-- same second are still separated, and one save's own deposits stay in the
-- order they were made because its ids count up.

local function claimedIds(sources)
  local claimed = {}
  for _, source in ipairs(sources or {}) do
    for id, taken in pairs(source.claims or {}) do
      if taken then claimed[id] = true end
    end
  end
  return claimed
end

GlobalBox.claimedIds = claimedIds

function GlobalBox.view(sources)
  local claimed = claimedIds(sources)
  local seen, out = {}, {}
  for _, source in ipairs(sources or {}) do
    for _, mon in ipairs(source.mons or {}) do
      local id = type(mon) == "table" and mon.gbId
      if type(id) == "string" and not claimed[id] and not seen[id] then
        seen[id] = true
        out[#out + 1] = {
          id = id,
          mon = mon,
          origin = source.origin,
          key = source.key,
          live = source.live,
          sent = tonumber(mon.gbSent) or 0,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.sent ~= b.sent then return a.sent < b.sent end
    return a.id < b.id
  end)
  return out
end

-- ------- pages
--
-- The view is flat and the pages are a VIEW of it, so "it adds another page
-- when it fills" needs no bookkeeping: there is always exactly one page more
-- than the full ones, and it is empty.  A box you cannot see an open slot in
-- is a box you cannot deposit into.

function GlobalBox.pages(view)
  local n = type(view) == "table" and #view or 0
  local pages = math.floor(n / GlobalBox.PAGE) + 1
  if pages > GlobalBox.MAX_PAGES then return GlobalBox.MAX_PAGES end
  return pages
end

function GlobalBox.indexAt(page, slot)
  page, slot = tonumber(page), tonumber(slot)
  if not (page and slot) then return nil end
  if page < 1 or page > GlobalBox.MAX_PAGES then return nil end
  if slot < 1 or slot > GlobalBox.PAGE then return nil end
  return (page - 1) * GlobalBox.PAGE + slot
end

function GlobalBox.at(view, page, slot)
  local index = GlobalBox.indexAt(page, slot)
  if not (index and type(view) == "table") then return nil end
  return view[index]
end

function GlobalBox.count(view)
  return type(view) == "table" and #view or 0
end

function GlobalBox.full(view)
  return GlobalBox.count(view) >= GlobalBox.CAPACITY
end

-- ------- what goes in
--
-- What the STORE refuses, which is now almost nothing: it holds whatever
-- generation's shape it is handed, so there is no conversion here to fail.
--
-- An EGG is not refused any more.  It was, when everything had to be a Gen 1
-- shape and Gen 1 has no eggs -- but a Gen 2 box holds one perfectly well, and
-- an egg that will not come out on Red is a withdrawal Red refuses, not a
-- deposit anybody should have been stopped from making.
function GlobalBox.accepts(view, mon)
  if type(mon) ~= "table" or mon.species == nil then return nil, "not_a_mon" end
  if GlobalBox.full(view) then return nil, "full" end
  return true
end

-- Deposit into YOUR OWN save's bucket, which is the only one anybody writes.
-- Appended rather than placed, because the box is a queue of what you sent
-- rather than a grid you arrange: SEND from a party menu has no cell to aim
-- at, and a cell in a union of outboxes is not one save's to hand out.
function GlobalBox.deposit(bucket, view, mon, generation)
  if type(bucket) ~= "table" or type(bucket.mons) ~= "table" then
    return nil, "no_save"
  end
  local ok, reason = GlobalBox.accepts(view, mon)
  if not ok then return nil, reason end
  local seq = (tonumber(bucket.seq) or 0) + 1
  bucket.seq = seq
  mon.gbId = ("%s#%d"):format(bucket.origin, seq)
  mon.gbSent = (os.time and os.time()) or seq
  -- the shape it is in, recorded at the one moment anybody knows it for
  -- certain: the game that put it there is the game it came out of
  mon.gbGen = (tonumber(generation) == 2) and 2 or 1
  bucket.mons[#bucket.mons + 1] = mon
  return mon.gbId
end

-- Take the POKeMON at a cell out of the box.
--
-- Out of your own outbox it is a removal.  Out of anyone else's it is a
-- CLAIM: their save is not yours to write, so what you write is the note that
-- says this one has left -- which every cartridge reads, so it leaves the box
-- everywhere at once.  Either way the caller gets the POKeMON.
--
-- The second return is a TICKET, and it is not a status string: it is what
-- `restore` needs to undo this exact withdrawal.  A box screen picks a
-- POKeMON up and the player presses B, and the one thing that must not happen
-- then is the POKeMON reappearing somewhere else in the box with a new id --
-- so the way back is spelled out here rather than approximated with a second
-- deposit.
function GlobalBox.withdraw(bucket, sources, view, page, slot)
  if type(bucket) ~= "table" then return nil, "no_save" end
  local entry = GlobalBox.at(view, page, slot)
  if not entry then return nil, "empty_cell" end
  if entry.origin == bucket.origin then
    local mons = type(bucket.mons) == "table" and bucket.mons or {}
    for index, mon in ipairs(mons) do
      if type(mon) == "table" and mon.gbId == entry.id then
        table.remove(mons, index)
        return entry.mon, { how = "removed", id = entry.id, mon = mon }
      end
    end
    return nil, "empty_cell"
  end
  bucket.claims = type(bucket.claims) == "table" and bucket.claims or {}
  bucket.claims[entry.id] = true
  return entry.mon, { how = "claimed", id = entry.id }
end

-- Put a withdrawal back exactly where it was.
--
-- A claim is undone by dropping the claim, which is the whole of it: the
-- POKeMON never left the save that holds it, and the box has been hiding it
-- rather than moving it.  A removal is undone by putting the SAME table back
-- in the outbox with the SAME id and the same sent time, so the view sorts it
-- into the cell it came out of.  Neither mints an id, which is what keeps a
-- press of B from being a second deposit.
function GlobalBox.restore(bucket, ticket)
  if type(bucket) ~= "table" or type(ticket) ~= "table" then return false end
  if ticket.how == "claimed" then
    local claims = type(bucket.claims) == "table" and bucket.claims or {}
    bucket.claims = claims
    if ticket.id == nil then return false end
    claims[ticket.id] = nil
    return true
  end
  if ticket.how ~= "removed" or type(ticket.mon) ~= "table" then return false end
  local mons = type(bucket.mons) == "table" and bucket.mons or {}
  bucket.mons = mons
  for _, mon in ipairs(mons) do
    if type(mon) == "table" and mon.gbId == ticket.id then return false end
  end
  mons[#mons + 1] = ticket.mon
  return true
end

-- ------- reconciliation, run once when a save loads
--
-- Two jobs, and both are tidying rather than truth: the view already hides a
-- claimed POKeMON everywhere, and this is what stops the saves growing a copy
-- of it forever.
--
--   * Anything in MY outbox that anybody has claimed has been withdrawn on
--     another cartridge, so it goes.
--   * Any claim of MINE whose POKeMON is in nobody's outbox any more has
--     nothing left to hide, so it goes too.  Not before: the sender may not
--     have booted since, and dropping the claim early would put the POKeMON
--     back in the box after the player already has it.
--
-- Returns how many of each it dropped, so the caller can log a real number
-- rather than "did something".
function GlobalBox.reconcile(bucket, sources)
  if type(bucket) ~= "table" then return 0, 0 end
  local claimed = claimedIds(sources)
  local mons = type(bucket.mons) == "table" and bucket.mons or {}
  local dropped = 0
  for index = #mons, 1, -1 do
    local mon = mons[index]
    local id = type(mon) == "table" and mon.gbId
    if type(id) ~= "string" or claimed[id] then
      table.remove(mons, index)
      dropped = dropped + 1
    end
  end
  local held = {}
  for _, source in ipairs(sources or {}) do
    for _, mon in ipairs(source.mons or {}) do
      local id = type(mon) == "table" and mon.gbId
      if type(id) == "string" then held[id] = true end
    end
  end
  local claims = type(bucket.claims) == "table" and bucket.claims or {}
  local released = 0
  for id in pairs(claims) do
    if not held[id] then
      claims[id] = nil
      released = released + 1
    end
  end
  return dropped, released
end

return GlobalBox
