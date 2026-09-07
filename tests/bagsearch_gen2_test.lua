-- SEARCH on Gold's PACK: the way in, and the way back out.
--
-- The way out is the whole subject.  Gold's naming screen does not take itself
-- down and it has no cancel:
--
--   * `NamingScreen:accept` calls `onDone(name)` and RETURNS.  Every one of the
--     cart's own five callers pops it from inside that callback.
--   * B is DELETE, not cancel -- the `.b` arm is `deleteCharacter`.
--   * `onCancel` is stored by NamingScreen.new and called by nothing.
--
-- So a caller that does not pop leaves the player on a keyboard with no exit:
-- B eats the query one letter at a time and END confirms and leaves the screen
-- standing, over a PACK that has been filtered and cannot be seen.  That was
-- the bug.
--
-- Those three facts are the test, so they are asserted against the CART's own
-- NamingScreen rather than described in a comment: if the engine ever gives
-- that screen a cancel, this file says so instead of quietly passing.
--
-- Run:  luajit tests/bagsearch_gen2_test.lua

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
  if actual ~= expected then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(actual == expected, description)
end

-- ---- the engine, for the three facts above
--
-- Read as SOURCE rather than loaded: NamingScreen pulls in the whole Gen 2
-- render stack, and what is being asserted is the shape of its input handler,
-- which reading it states exactly.

local ENGINE do
  local candidates = { os.getenv("GEN1RECOMP") }
  for _, prefix in ipairs({ "..", "../../..", "../../../..", "../..",
                            "../../../../.." }) do
    candidates[#candidates + 1] = prefix .. "/bryanthaboi/gen1recomp"
    candidates[#candidates + 1] = prefix .. "/gen1recomp"
  end
  for _, dir in ipairs(candidates) do
    if dir then
      local probe = io.open(dir .. "/src/ui/gen2/NamingScreen.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end

if ENGINE then
  local handle = assert(io.open(ENGINE .. "/src/ui/gen2/NamingScreen.lua"))
  local source = handle:read("*a")
  handle:close()

  -- accept() hands the name over and returns; it does not pop.
  local accept = source:match("function NamingScreen:accept%(%)(.-)\nend")
  ok(accept ~= nil, "the cart's naming screen has an accept")
  ok(accept and accept:find("onDone", 1, true),
     "accept calls onDone")
  ok(accept and not accept:find("pop", 1, true),
     "and does NOT pop itself -- the caller owns that")

  -- B deletes.  The arm is right there.
  local bArm = source:match('wasPressed%("b"%)(.-)elseif')
  ok(bArm ~= nil, "the naming screen reads B")
  ok(bArm and bArm:find("deleteCharacter", 1, true),
     "and B is DELETE, not cancel")

  -- onCancel is stored and never called: there is no call site anywhere in
  -- the file, only the assignment and the doc line above it.
  ok(source:find("self%.onCancel%s*=") ~= nil,
     "the naming screen stores an onCancel")
  ok(source:find("self%.onCancel%s*%(") == nil
     and source:find("self:onCancel") == nil,
     "and never calls it, so a handler passed to it is dead code")
else
  io.write("  note: no engine tree; the three cart facts are not re-checked\n")
end

-- ---- the shipped askQuery, driven end to end

package.loaded["src.ui.Screens"] = {
  push = function(game, id, opts)
    local inst = { screenId = id, opts = opts }
    game.stack:push(inst)
    return inst
  end,
}

local BagGen2 = assert(loadfile("modules/Gen1ModernBag/gen2.lua"))()

-- The factory wants a mod; only the pieces askQuery touches are needed.
local mod = {
  log = { info = function() end, warn = function() end, error = function() end },
  options = { get = function() return nil end, set = function() end },
  save = { get = function(_, _, d) return d end, set = function() end },
  hooks = { wrap = function() end },
  ui = { Menu = { new = function() return {} end } },
}
local arm = BagGen2.new and BagGen2.new(mod) or nil
if type(arm) ~= "table" then arm = BagGen2(mod) end
ok(type(arm.askQuery) == "function", "the Gold arm publishes askQuery")

local function scene(existing)
  local stack = { states = {} }
  function stack:push(s) self.states[#self.states + 1] = s end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  local pack = { screenId = "Gen2PackMenu", rebuilds = 0 }
  pack.game = { stack = stack }
  pack.rebuild = function(self) self.rebuilds = self.rebuilds + 1 end
  pack.gen1bagQuery = existing
  stack:push(pack)
  return pack, stack
end

-- ---- END with a query: the keyboard goes, the filter stays

do
  local pack, stack = scene(nil)
  arm.askQuery(pack)
  eq(#stack.states, 2, "SEARCH opens the cart's keyboard over the PACK")
  local keyboard = stack:top()
  eq(keyboard.screenId, "Gen2NamingScreen", "and it is the cart's own screen")
  eq(keyboard.opts.prompt, "SEARCH FOR?", "asked in the mod's own words")
  eq(keyboard.opts.initial, "", "starting empty")

  keyboard.opts.onDone("POTION")
  eq(stack:top(), pack, "END takes the keyboard back down")
  eq(#stack.states, 1, "leaving the PACK where it was")
  eq(pack.gen1bagQuery, "POTION", "with the query applied")
  eq(pack.rebuilds, 1, "and the pocket rebuilt once")
end

-- ---- END with nothing typed: the way out, and the search cleared

do
  local pack, stack = scene("POTION")
  arm.askQuery(pack)
  eq(stack:top().opts.initial, "POTION", "an open search is offered for editing")
  stack:top().opts.onDone("")
  eq(stack:top(), pack, "END on an empty query still leaves the keyboard")
  eq(pack.gen1bagQuery, nil, "and clears the search, which is the cancel")
end

-- ---- and it never pops something that is not the keyboard

do
  local pack, stack = scene(nil)
  arm.askQuery(pack)
  local keyboard = stack:top()
  local intruder = { screenId = "SomethingElse" }
  stack:push(intruder)
  keyboard.opts.onDone("BALL")
  eq(stack:top(), intruder, "a screen pushed over the keyboard is left alone")
  eq(#stack.states, 3, "and nothing else is taken off the stack")
  eq(pack.gen1bagQuery, "BALL", "the query still lands")
end

-- ---- no dead cancel handler is passed any more

do
  local pack, stack = scene(nil)
  arm.askQuery(pack)
  eq(stack:top().opts.onCancel, nil,
     "no onCancel is passed: the cart never calls one")
end

io.write(("bagsearch_gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
