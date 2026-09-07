-- The BOX row on a NEW GAME, where the party is empty.
--
-- This is the one arm of the row every playthrough runs, and it crashed the
-- game outright:
--
--   src/script/Tokens.lua:28: attempt to call method 'gsub' (a nil value)
--
-- `Boxes.canUsePc` answers `false, <refusal text>` and that second return is a
-- STRING.  `TextBox.new(game, text, onDone, opts)` takes the text as its
-- SECOND argument, not an options table -- and it was being handed
-- `{ text = why }`.  Nothing complains at the call: the table travels all the
-- way into `Tokens.expand`, which does `text:gsub`, and a table has no gsub.
--
-- tests/billsbox2_test.lua stands up its own Boxes and its own screen, which
-- is right for what it asserts -- that no POKeMON is ever lost -- and is
-- exactly why this got through: a stub TextBox takes a table without a
-- murmur.  So this file uses the CART's `src.render.TextBox` and the CART's
-- `src.core.gen2.Boxes`, and the row's own body read out of the shipped
-- module.  The crash is reproduced by construction if the fix comes out.
--
-- Run:  luajit tests/boxrow_gen2_test.lua

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

local ENGINE do
  local candidates = { os.getenv("GEN1RECOMP") }
  for _, prefix in ipairs({ "..", "../../..", "../../../..", "../..",
                            "../../../../.." }) do
    candidates[#candidates + 1] = prefix .. "/bryanthaboi/gen1recomp"
    candidates[#candidates + 1] = prefix .. "/gen1recomp"
  end
  for _, dir in ipairs(candidates) do
    if dir then
      local probe = io.open(dir .. "/src/core/gen2/Boxes.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end
if not ENGINE then
  io.write("boxrow_gen2: SKIPPED -- no engine tree found "
    .. "(set GEN1RECOMP to a gen1recomp checkout)\n")
  os.exit(0)
end
package.path = ENGINE .. "/?.lua;" .. package.path

local noop = function() end
_G.love = {
  timer = { getTime = function() return 0 end },
  audio = {},
  window = { getMode = function() return 160, 144 end },
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  graphics = setmetatable({}, { __index = function() return noop end }),
}
-- The font has no sheet in a headless run and says so for every glyph; the
-- pagination it feeds is still real.  Quiet, so a failure is readable.
require("src.core.Logger").warn = noop

require("src.core.GameVersion").set("crystal")
local TextBox = require("src.render.TextBox")
local Boxes = require("src.core.gen2.Boxes")

-- ---- the cart's own refusal, read rather than assumed

local emptySave = { party = {} }
local usable, why = Boxes.canUsePc(emptySave)
eq(usable, false, "the cart refuses the PC with an empty party")
eq(type(why), "string", "and its reason is a STRING, which is what TextBox takes")

local held = { party = { { species = "CYNDAQUIL" } } }
eq(Boxes.canUsePc(held), true, "with a POKeMON in the party it opens")

-- ---- the shipped body

local function slurp(path)
  local handle = assert(io.open(path), path)
  local text = handle:read("*a")
  handle:close()
  return text
end

local openBox do
  local body = slurp("modules/Gen1BillsBox/main.lua")
    :match("(  local function openBox%(game%).-\n  end)\n")
  assert(body, "could not find openBox in modules/Gen1BillsBox/main.lua")
  openBox = assert(load("local mod, gen2 = ...\n" .. body .. "\nreturn openBox",
                        "@Gen1BillsBox/main.lua"))
end

-- ---- the row, driven on a new game

local function run(save)
  local pushed, opened = {}, {}
  local mod = {
    ui = {
      TextBox = TextBox,
      push = function(_, id, opts) opened[#opened + 1] = { id = id, opts = opts } end,
    },
  }
  local game = {
    data = {},
    save = save,
    stack = {
      push = function(_, state) pushed[#pushed + 1] = state end,
      top = function() return nil end,
      pop = noop,
    },
  }
  -- `gen2` is the module's own upvalue for "this boot is Gold"; true here.
  local fn = openBox(mod, true)
  local ran, err = pcall(fn, game)
  return ran, err, pushed, opened
end

do
  local ran, err, pushed, opened = run({ party = {} })
  ok(ran, "opening BOX on a new game does not raise (" .. tostring(err) .. ")")
  eq(#opened, 0, "and no box screen is opened with nothing to put in it")
  eq(#pushed, 1, "one thing is pushed: the cart's refusal")
  local box = pushed[1]
  eq(getmetatable(box), TextBox, "and it is a real TextBox")
  if type(box) == "table" and type(box.pages) == "table" then
    ok(#box.pages > 0, "which paginated the refusal, so a STRING reached it")
  else
    ok(false, "which paginated the refusal, so a STRING reached it")
  end
end

do
  local ran, err, pushed, opened = run({ party = { { species = "CYNDAQUIL" } } })
  ok(ran, "and with a POKeMON it does not raise either (" .. tostring(err) .. ")")
  eq(#pushed, 0, "nothing is refused")
  eq(#opened, 1, "the box screen is opened instead")
  eq(opened[1] and opened[1].id, "Gen2BoxMenu", "and it is Gold's own")
end

-- ---- the shape of the mistake, so it cannot come back unnoticed
--
-- Stated against the real constructor: this is what an options table does at
-- that argument, and it is what the crash report said word for word.

do
  local game = { data = {}, stack = { push = noop } }
  local fine = pcall(TextBox.new, game, why)
  ok(fine, "the refusal string builds a text box")
  local bad, err = pcall(TextBox.new, game, { text = why })
  ok(not bad, "and a table at the same argument does not")
  ok(tostring(err):find("gsub", 1, true) ~= nil,
     "failing on gsub, which is the crash that was reported")
end

io.write(("boxrow_gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
