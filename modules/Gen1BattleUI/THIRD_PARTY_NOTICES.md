# Third-party notices

## Pokeball Colors

The ball colouring in `pokeballs.lua` — the colours themselves, the
`BAND_TILES` pixel-role table behind the seam band, and both draw seams it
is installed through — is a port of **[Pokeball
Colors](https://github.com/mistermiracle3036/Pokeball-Colors)** by Mister
Miracle, cut down to the five balls Red, Blue and Yellow ship with. It is
used here under its MIT licence, reproduced in full:

```
MIT License

Copyright (c) 2026 Mister Miracle

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## The XP bar

`xpbar.lua` is the experience bar from **[unxpected-uxp's Quality of
Life](https://github.com/unxpected-uxp/pokemon-gen1-recomp-mod-qol)** mod,
by way of Gen1WildQOL, which maintained it and wrote the faint guard it
still carries.

## Plain Pixel

**Plain Pixel** by Douglas Vautour, CC-BY 4.0. Bundled by gen1recomp for its
translation mode; this mod borrows it for move names that will not fit the
tile font. No copy of the font ships here.

## gen1recomp

This mod targets the [gen1recomp](https://github.com/bryanthaboi/gen1recomp)
engine (mod API 2) and reaches engine internals under the
`engine_internals` permission.

## Ball tile artwork is never redistributed

The seam band needs the ball sprite's colour indices rearranged. Rather than
ship an edited copy of that artwork — which is ROM-derived — the mod rebuilds
it in memory each session from the sheet the player's own game extracted from
their own cartridge dump. What this repository contains is a table of which
pixels play which role, not the pixels themselves.

## Licence scope

The MIT licence in [LICENSE](LICENSE) covers this mod's own code. It makes no
claim over ROM-derived material or Nintendo trademarks and grants no rights in
either. Pokémon and all related names are trademarks of Nintendo / Creatures
Inc. / GAME FREAK inc. This mod contains no ROM data and no copyrighted
assets; it is a fan-made script mod and requires the player's own copy of the
game.
