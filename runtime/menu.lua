-- The bundle's own OPTION screens.
--
-- A bundle of a dozen mods that dumped a dozen mods' worth of rows onto one
-- flat list would be worse than the twelve mods it replaced.  So the rows are
-- kept in the shape players already understand them in: one row per feature,
-- switched ON or OFF right there, and that feature's own settings one press of
-- A away, under its own name.
--
--   OPTION
--     GEN1WILD QOL      CONFIGURE
--       SPRINT          ON (CONFIGURE)   -- A opens:
--         HOLD          B
--         SPRINT SPEED  2x
--         BIKE SPEED    2x
--         RESET DEFAULTS
--       AUTO SAVE       OFF
--       ...
--
-- Nothing here knows what any particular feature does: the screens are built
-- from the merged option schema, so a row a mod adds upstream shows up here on
-- the next sync without this file changing.
--
-- The chrome is the engine's own -- src.ui.OptionRows on Red/Blue/Yellow,
-- src.ui.gen2.Chrome on Gold -- so the screens are drawn in the same idiom as
-- the OPTION screen they hang off, rather than in a look of their own.

local Menu = {}

local GEN2_VISIBLE_ROWS = 7
-- Gold's own OptionsMenu puts its value column at 11, which suits values like
-- ON and STEREO.  These are longer ("ON (CONFIGURE)"), so they start earlier.
local GEN2_VALUE_TX = 4

local RESET_ROW = "__reset_defaults"

local function labelForValue(row, value)
  if row.type == "toggle" then
    return value and "ON" or "OFF"
  end
  if row.type == "choice" then
    for _, choice in ipairs(row.choices or {}) do
      if choice[2] == value then return tostring(choice[1]) end
    end
    return tostring(value)
  end
  if row.type == "number" then
    return tostring(value) .. (row.suffix and (" " .. row.suffix) or "")
  end
  return tostring(value)
end

local function stepValue(row, value, dir)
  if row.type == "toggle" then return not value end
  if row.type == "choice" then
    local choices = row.choices or {}
    if #choices == 0 then return value end
    local index = 1
    for i, choice in ipairs(choices) do
      if choice[2] == value then index = i break end
    end
    return choices[((index - 1 + dir) % #choices) + 1][2]
  end
  if row.type == "number" then
    local step = row.step or 1
    local next_ = (tonumber(value) or row.default or 0) + step * dir
    local min, max = row.min, row.max
    if min and max then
      if next_ > max then next_ = min elseif next_ < min then next_ = max end
    elseif min and next_ < min then next_ = min
    elseif max and next_ > max then next_ = max
    end
    return next_
  end
  return value
end

-- feature.description is a sentence; the engine's TextBox wants it broken into
-- lines it can fit, with \f between pages.  Anything already carrying a newline
-- is assumed to be written for the box already and is left alone.
local function asTextBox(text)
  text = tostring(text or "")
  if text:find("[\n\f]") then return text end
  local lines, line = {}, ""
  for word in text:gmatch("%S+") do
    local candidate = (line == "") and word or (line .. " " .. word)
    if #candidate > 17 then
      lines[#lines + 1] = line
      line = word
    else
      line = candidate
    end
  end
  if line ~= "" then lines[#lines + 1] = line end

  local pages, page = {}, {}
  for _, entry in ipairs(lines) do
    page[#page + 1] = entry
    if #page == 2 then
      pages[#pages + 1] = table.concat(page, "\n")
      page = {}
    end
  end
  if #page > 0 then pages[#pages + 1] = table.concat(page, "\n") end
  return table.concat(pages, "\f")
end

function Menu.new(context)
  local mod = context.mod
  local optionset = context.optionset
  local spec = context.spec
  local features = context.features

  local self = {}
  local rootScreenId = spec.screen_id
  local restartPending = {}

  local function featureScreenId(feature)
    return rootScreenId .. "_" .. feature.id
  end

  local function read(key) return optionset.read(mod, key) end
  local function write(game, key, value) return optionset.write(mod, key, value, game) end

  -- ---- the per-feature settings screen

  -- `visible_if = { key = ..., equals = ... }` hides a row whose governing row
  -- is set some other way -- Gen151 hides its nine content rows behind its own
  -- master, Gen1Sprint hides the sprint rows when sprinting is off.  Hiding
  -- never changes the stored value, so a row that comes back shows what the
  -- player last chose.  The rows are recomputed per screen build, which is why
  -- turning a governing row is reflected the moment the screen redraws.
  local function visible(row)
    local condition = row.visible_if
    if type(condition) ~= "table" or type(condition.key) ~= "string" then
      return true
    end
    if condition.equals ~= nil then
      return read(condition.key) == condition.equals
    end
    if condition.not_equals ~= nil then
      return read(condition.key) ~= condition.not_equals
    end
    return true
  end

  local function featureRows(feature, game)
    local group = optionset.groups[feature.id]
    local rows = {}
    if not group then return rows end
    for _, row in ipairs(group.rows) do
      if visible(row) then
        rows[#rows + 1] = {
          kind = "option",
          key = row.key,
          row = row,
          label = row.label or row.key,
          description = row.description or row.help,
        }
      end
    end
    -- Rows a feature keeps outside the option schema entirely.  Exp Share is
    -- the case: it stores its mode in the save's own options rather than in
    -- mod options, and drives them through cycle functions instead of a
    -- schema, so its adapter contributes rows in that shape instead.
    local custom = context.customRows and context.customRows[feature.id]
    if type(custom) == "function" then
      local ok, extra = pcall(custom)
      if ok and type(extra) == "table" then
        for _, entry in ipairs(extra) do
          local show = true
          if type(entry.visible) == "function" then
            local okVisible, visibleNow = pcall(entry.visible, game)
            show = okVisible and visibleNow ~= false
          end
          if show then
            rows[#rows + 1] = {
              kind = "custom",
              key = entry.id or entry.label,
              label = entry.label,
              description = entry.description,
              value = entry.value,
              step = entry.step,
            }
          end
        end
      end
    end

    if #rows > 0 then
      rows[#rows + 1] = {
        kind = "action",
        key = RESET_ROW,
        label = "RESET DEFAULTS",
        description = "PUTS EVERY ROW ON\nTHIS SCREEN BACK\fTO THE VALUE IT\nSHIPPED WITH.",
      }
    end
    return rows
  end

  -- ---- the feature list

  local function rootRows(game)
    local rows = {}
    for _, feature in ipairs(features) do
      local group = optionset.groups[feature.id]
      if group and group.masterKey then
        rows[#rows + 1] = {
          kind = "feature",
          feature = feature,
          key = group.masterKey,
          row = optionset.byKey[group.masterKey],
          label = feature.label,
          description = feature.description,
          hasSettings = #(group.rows or {}) > 0
            or type(context.customRows and context.customRows[feature.id]) == "function",
        }
      end
    end
    return rows
  end

  -- A feature whose master switch only gates installation cannot come to life
  -- mid-session, so saying ON when nothing is installed would be a lie.  It
  -- reads ON* until the game is relaunched, and the footer says why.
  local function masterLabel(entry)
    local value = read(entry.key)
    local on = value ~= false
    local pending = restartPending[entry.feature.id]

    -- A feature whose master is one of its own rows and is not a plain toggle
    -- -- the area banner's master is its duration -- says what it is set to
    -- rather than just ON, because the value is the interesting part.
    local base
    if entry.row and entry.row.type ~= "toggle" then
      base = labelForValue(entry.row, value)
    elseif not on then
      base = "OFF"
    else
      base = entry.hasSettings and "ON (CONFIGURE)" or "ON"
    end

    if pending ~= nil and pending ~= on then return base .. " *" end
    return base
  end

  local function valueLabel(entry, game)
    if entry.kind == "feature" then return masterLabel(entry) end
    if entry.kind == "action" then return "" end
    if entry.kind == "custom" then
      if type(entry.value) ~= "function" then return "" end
      local ok, label = pcall(entry.value, game)
      return ok and tostring(label or "") or ""
    end
    return labelForValue(entry.row, read(entry.key))
  end

  -- ---- screen factory, shared by the root and every feature screen

  local function makeScreen(screenId, buildRows, title)
    return function(game)
      local screen = {
        screenId = screenId,
        game = game,
        entries = buildRows(game),
        index = 1,
        scroll = 0,
        isOpaque = true,
      }

      screen.rows = screen.entries

      -- Rows are rebuilt every frame rather than once on push, because a row
      -- can govern whether its neighbours are drawn at all: Gen151's CABLE
      -- SOUND belongs to TRADE EVOS on the same screen, and Exp Share's
      -- PERCENT rows exist only in CUSTOM.  Turning the governing row has to
      -- take the others with it on the next frame, not on the next visit.
      local function refresh(s)
        s.entries = buildRows(s.game)
        s.rows = s.entries
        if #s.entries == 0 then return false end
        if s.index > #s.entries then s.index = #s.entries end
        if s.index < 1 then s.index = 1 end
        return true
      end

      function screen:sgbPalettes(g)
        local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
        if ok and PaletteFX and PaletteFX.wholeNamed then
          return PaletteFX.wholeNamed(g.data, "MEWMON")
        end
        return nil
      end

      local function activate(entry)
        if entry.kind == "feature" then
          if not entry.hasSettings then
            self.showText(screen.game, entry.description)
          elseif read(entry.key) ~= false then
            mod.ui.push(screen.game, featureScreenId(entry.feature))
          else
            self.showText(screen.game,
              "SWITCH " .. entry.label .. " ON\nTO CONFIGURE IT.")
          end
        elseif entry.kind == "action" and entry.key == RESET_ROW then
          for _, other in ipairs(screen.entries) do
            if other.kind == "option" then
              write(screen.game, other.key, other.row.default)
            end
          end
          -- Custom rows are deliberately left alone: their storage is not
          -- this bundle's to reset.
        else
          self.showText(screen.game, entry.description or entry.label)
        end
      end

      local function step(entry, dir)
        if entry.kind == "action" then return end
        if entry.kind == "custom" then
          if type(entry.step) == "function" then
            pcall(entry.step, screen.game, dir)
          end
          return
        end
        local current = read(entry.key)
        local next_ = stepValue(entry.row, current, dir)
        if entry.kind == "feature" then
          local feature = entry.feature
          -- Record the state the feature was actually installed in the first
          -- time its switch is moved, so the footer can say whether the
          -- session matches the setting.
          if restartPending[feature.id] == nil and not feature.live_toggle then
            restartPending[feature.id] = feature.installed == true
          end
        end
        write(screen.game, entry.key, next_)
      end

      function screen:update()
        if not refresh(self) then self.game.stack:pop() return end
        local input = self.game.input
        local entry = self.entries[self.index]
        if not entry then self.game.stack:pop() return end

        if input:wasPressed("up") then
          self.index = (self.index - 2) % #self.entries + 1
        elseif input:wasPressed("down") then
          self.index = self.index % #self.entries + 1
        elseif input:wasPressed("left") then
          step(entry, -1)
        elseif input:wasPressed("right") then
          step(entry, 1)
        elseif input:wasPressed("a") then
          activate(entry)
        elseif input:wasPressed("b") then
          self.game.stack:pop()
        end

        if context.isGen2 then
          if self.index <= self.scroll then
            self.scroll = self.index - 1
          elseif self.index > self.scroll + GEN2_VISIBLE_ROWS then
            self.scroll = self.index - GEN2_VISIBLE_ROWS
          end
          self.scroll = math.max(0, math.min(self.scroll,
            math.max(0, #self.entries - GEN2_VISIBLE_ROWS)))
        else
          local ok, OptionRows = pcall(require, "src.ui.OptionRows")
          if ok and OptionRows and OptionRows.clampScroll then
            self.scroll = OptionRows.clampScroll(
              self.index, self.scroll, #self.entries, nil)
          end
        end
      end

      -- The engine's OptionRows wants rows carrying a `value(game)`; build that
      -- view fresh each frame so a row reflects a write made on this one.
      local function drawable()
        local out = {}
        for i, entry in ipairs(screen.entries) do
          out[i] = {
            label = entry.label,
            key = entry.key,
            value = function() return valueLabel(entry, screen.game) end,
          }
        end
        return out
      end

      local function footerFor(entry)
        if entry.kind == "feature" then
          if read(entry.key) ~= false and entry.hasSettings then
            return "A:CONFIGURE B:BACK"
          end
          return "A:INFO B:BACK"
        end
        if entry.kind == "action" then return "A:RESET B:BACK" end
        return "A:INFO B:BACK"
      end

      local function anyRestartPending()
        for id, was in pairs(restartPending) do
          local group = optionset.groups[id]
          if group and group.masterKey and (read(group.masterKey) ~= false) ~= was then
            return true
          end
        end
        return false
      end

      local function drawGen1(s)
        local OptionRows = require("src.ui.OptionRows")
        local Font = require("src.render.Font")
        OptionRows.draw(s.game, drawable(), s.index, s.scroll)
        love.graphics.setColor(0, 0, 0, 1)
        local footer = anyRestartPending() and "* RESTART TO APPLY"
          or footerFor(s.entries[s.index])
        Font.draw(footer, 8, 136)
        love.graphics.setColor(1, 1, 1, 1)
      end

      local function drawGen2(s)
        local Chrome = require("src.ui.gen2.Chrome")
        Chrome.textbox(0, 0, Chrome.SCREEN_W - 2, Chrome.SCREEN_H - 2)
        local rows = drawable()
        for slot = 1, math.min(GEN2_VISIBLE_ROWS, #rows) do
          local i = slot + s.scroll
          local row = rows[i]
          if row then
            local labelY = 2 + (slot - 1) * 2
            Chrome.print(row.label, 2, labelY)
            Chrome.print(":", GEN2_VALUE_TX - 1, labelY + 1)
            Chrome.print(row.value() or "", GEN2_VALUE_TX, labelY + 1)
          end
        end
        Chrome.cursor(1, 2 + (s.index - s.scroll - 1) * 2)
        if s.scroll + GEN2_VISIBLE_ROWS < #rows then
          local Font = require("src.render.Font")
          love.graphics.setColor(0, 0, 0, 1)
          Font.drawCode(Chrome.DOWN_ARROW, 8, (2 + GEN2_VISIBLE_ROWS * 2 - 1) * 8)
          love.graphics.setColor(1, 1, 1, 1)
        end
      end

      screen.draw = context.isGen2 and drawGen2 or drawGen1
      return screen
    end
  end

  function self.showText(game, text)
    if not (mod.ui and mod.ui.TextBox) then return end
    game.stack:push(mod.ui.TextBox.new(game, asTextBox(text)))
  end

  -- ---- registration

  function self.install()
    mod.content.screens:register(rootScreenId, {
      new = makeScreen(rootScreenId, rootRows, spec.menu_label),
    })
    for _, feature in ipairs(features) do
      local id = featureScreenId(feature)
      mod.content.screens:register(id, {
        new = makeScreen(id, function(game) return featureRows(feature, game) end,
          feature.label),
      })
    end

    -- Gold's OPTION screen has no MODS row; CANCEL is its last row, the way
    -- MODS is Gen 1's.
    local anchor = context.isGen2 and "CANCEL" or "MODS"
    mod.hooks:wrap("ui.options.rows", function(next, game, rows)
      local out = next(game, rows)
      if type(out) ~= "table" then return out end
      return mod.ui.insertBefore(out, anchor, {
        id = spec.id .. "_root",
        label = spec.menu_label,
        value = function() return "CONFIGURE" end,
        activate = function(g) mod.ui.push(g, rootScreenId) end,
      })
    end)

    -- MODS > <bundle> > OPTIONS should land on these screens rather than on
    -- the manager's generic schema list, which would show all sixty rows flat
    -- with no idea which feature owns which.
    mod.events:once("mods.loaded", function()
      local ok, ManagerState = pcall(require, "src.mods.ManagerState")
      if not ok or type(ManagerState) ~= "table" then return end
      local routes = rawget(ManagerState, "__modOptionScreenRoutes")
      if not routes then
        routes = {}
        local openOptions = ManagerState.openOptions
        ManagerState.openOptions = function(state, manifest)
          local screenId = manifest and routes[manifest.id]
          if screenId then
            return require("src.ui.Screens").push(state.game, screenId)
          end
          return openOptions(state, manifest)
        end
        ManagerState.__modOptionScreenRoutes = routes
      end
      routes[mod.id] = rootScreenId
    end)
  end

  -- Called by the bundle once each feature has been installed (or skipped), so
  -- the menu can tell a switch that needs a relaunch from one that does not.
  function self.noteInstalled(feature, installed)
    feature.installed = installed
    if not feature.live_toggle then
      restartPending[feature.id] = installed
    end
  end

  return self
end

return Menu
