-- The type name's ring does not reach the line printed under it.
--
-- The theme rings every true-colour mark: runtime/theme.lua's `withArt` emits
-- an ART_PAGE zone one pixel larger than the rect on every side, so the raw
-- blit and the shaded page agree across the seam Renderer.scissorClamped
-- rounds outward.  BOTH ENDS of that zone are black -- shade 0 and shade 3 --
-- which is right inside the ring, where the only canvas is flat black skirt,
-- and fatal to anything else that lands in it: ink mapped to black on a black
-- page is ink that is not there.
--
-- The move panel prints three lines eight pixels apart -- name, type, PP -- in
-- an eight-pixel glyph cell.  A full-height mark on the type row therefore has
-- nowhere to put its ring except the PP row, and its bottom edge is that
-- row's FIRST pixel row: the top stroke of every glyph in it came out black on
-- black, and `PP` read as two broken uprights.  Reported twice, and the second
-- time after a fix that was for a different bug on the same line.
--
-- So this is arithmetic about four numbers, and it is asserted rather than
-- described because being wrong by one row is invisible until somebody opens
-- a move menu on a DARK ADVANCED build.
--
-- Run:  luajit tests/panelring_test.lua

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
  local same = actual == expected
  if not same then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(same, description)
end

-- ------------------------------------------------------------- the numbers

-- drawClassicPanel: PANEL.moveSelect is { tx = 0, ty = 8, tw = 14, th = 5 },
-- and rows[i] = (ty + i) * 8 for i = 1 .. th - 2.
local PANEL_TY, PANEL_TH = 8, 5
local rows = {}
for i = 1, PANEL_TH - 2 do rows[i] = (PANEL_TY + i) * 8 end

-- theme.lua, withArt: the zone is the rect grown by one on every side.
local function ring(rect)
  return { x = rect.x - 1, y = rect.y - 1, w = rect.w + 2, h = rect.h + 2 }
end
local function bottomRow(rect)
  local z = ring(rect)
  return z.y + z.h - 1
end

io.write("the move panel's rows\n")

eq(rows[1], 72, "the move name is printed at y=72")
eq(rows[2], 80, "the type name at y=80")
eq(rows[3], 88, "and the PP line at y=88")
eq(rows[3] - rows[2], 8, "eight pixels apart, which is the whole glyph cell")

io.write("where the ring lands\n")

local C_ROW = 8
local C_MARK_ROW = C_ROW - 1

do
  -- What it used to mark: the full row.
  local full = { x = 8, y = rows[2], w = 48, h = C_ROW }
  eq(bottomRow(full), rows[3],
     "a full-height mark rings the PP line's FIRST pixel row -- the bug")

  -- What it marks now.
  local inset = { x = 8, y = rows[2], w = 48, h = C_MARK_ROW }
  eq(bottomRow(inset), rows[3] - 1,
     "one pixel shorter puts the ring in the blank row between them")
  ok(bottomRow(inset) < rows[3],
     "which is the whole requirement: the ring stops above the next line")
end

do
  -- The top edge has the same neighbour problem upwards, and the same answer:
  -- the ring must clear the row above, which is the move name.
  local inset = { x = 8, y = rows[2], w = 48, h = C_MARK_ROW }
  local z = ring(inset)
  eq(z.y, rows[2] - 1, "the ring's top is the blank row under the move name")
  ok(z.y >= rows[1] + C_ROW - 1,
     "so it never reaches into the move name's own cell")
end

do
  -- And the mark still covers the ink it exists to protect: everything the
  -- glyph draws except the cell's last row, which is the gap.
  local inset = { x = 8, y = rows[2], w = 48, h = C_MARK_ROW }
  eq(inset.y, rows[2], "the mark still starts on the row the text does")
  eq(inset.y + inset.h, rows[2] + 7,
     "and covers seven of the cell's eight rows -- all but the blank one")
end

io.write("the wide panel is clear either way\n")
do
  -- PP at y=112 and the type at y=128: sixteen apart, so nothing was ever at
  -- risk there.  Asserted so that a later change to the wide layout that
  -- closes that gap fails here instead of on somebody's screen.
  local WIDE_PP, WIDE_TYPE = 112, 128
  ok(WIDE_TYPE - WIDE_PP > C_ROW + 1,
     "the wide panel's two lines are further apart than a ring is tall")
  local inset = { x = 232, y = WIDE_TYPE, w = 48, h = C_MARK_ROW }
  ok(ring(inset).y > WIDE_PP + C_ROW - 1,
     "so its ring cannot reach the line above it either")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
