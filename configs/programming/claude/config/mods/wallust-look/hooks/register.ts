import type { Register, ThemeSetArgs } from 'claude-code'

import { makeColors } from './make-colors.js'

// The palette programming/claude's theme verb writes beside this mod on every theme switch (wal's colors.json), read
// at each session start and again whenever it changes, so a switch reaches open sessions too. A missing palette
// leaves the app's own look.
const PALETTE = 'palette.json'
// how often an open session looks at the palette's mtime: one stat, a theme switch shows within this
const PALETTE_POLL_MS = 3000

type Rgb = [number, number, number]

const channel = (hex: string, i: number): number => parseInt(hex.slice(1 + 2 * i, 3 + 2 * i), 16)
const rgb = (hex: string): Rgb => [channel(hex, 0), channel(hex, 1), channel(hex, 2)]
const hex = (c: Rgb): string => '#' + c.map(v => Math.round(v).toString(16).padStart(2, '0')).join('')
const mix = (a: string, b: string, t: number): string => {
  const [xr, xg, xb] = rgb(a)
  const [yr, yg, yb] = rgb(b)
  return hex([xr + (yr - xr) * t, xg + (yg - xg) * t, xb + (yb - xb) * t])
}
const linear = (v: number): number => {
  const s = v / 255
  return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
}
const luminance = (c: string): number => {
  const [r, g, b] = rgb(c)
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
}

const contrast = (a: string, b: string): number => {
  const [x, y] = [luminance(a), luminance(b)]
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05)
}

// A text colour walked toward black (light palette) or white (dark) until it reaches ratio on every surface given,
// so a theme whose own foreground is weak still gets readable text instead of Desktop refusing the whole look.
const readable = (color: string, surfaces: string[], ratio: number, light: boolean): string => {
  const end = light ? '#000000' : '#ffffff'
  for (let t = 0; t <= 1.0001; t += 0.02) {
    const c = mix(color, end, t)
    if (surfaces.every(s => contrast(c, s) >= ratio)) return c
  }
  return end
}

// Surfaces step from the background toward the text, a few percent each, so cards read as the same paper; the text
// levels meet the design system's floors on every surface. One mode only: the palette is either light or dark.
type Palette = {
  special: { background: string; foreground: string }
  colors: Record<'color1' | 'color2' | 'color3' | 'color4' | 'color5', string>
}

export function look(palette: Palette): {
  args: ThemeSetArgs
  problems: string[]
} {
  const bg = palette.special.background.toLowerCase()
  const fg = palette.special.foreground.toLowerCase()
  const c = palette.colors
  const light = luminance(bg) > 0.5
  const surfaces: [string, string, string, string] = light
    ? [mix(bg, fg, 0.06), mix(bg, fg, 0.03), bg, bg]
    : [bg, mix(bg, fg, 0.03), mix(bg, fg, 0.05), mix(bg, fg, 0.07)]
  const primary = readable(fg, surfaces, 7, light)
  const mode = {
    gray: {
      anchors: {
        'surface-0': surfaces[0],
        'surface-1': surfaces[1],
        'surface-2': surfaces[2],
        'surface-3': surfaces[3],
        'text-primary': primary,
        'text-secondary': readable(mix(primary, bg, 0.2), surfaces, 5.5, light),
        'text-muted': readable(mix(primary, bg, 0.35), surfaces, 4.5, light),
      },
    },
    git: { added: c.color2, removed: c.color1, modified: c.color3 },
  }
  // a bright palette amber fills comment highlights too strongly for the text over them: its fill steps toward the
  // surface until Desktop paints the look
  const shades = light ? [undefined, 300, 200, 100] : [undefined, 700, 800, 900]
  let made = { theme: undefined as unknown as ThemeSetArgs['colors'], problems: [] as string[] }
  for (const fillShade of shades) {
    made = makeColors({
      label: 'Wallust',
      only: light ? 'light' : 'dark',
      roles: { accent: c.color4, danger: c.color1, success: c.color2, warning: { seed: c.color3, fillShade }, pro: c.color5 },
      ...(light ? { light: mode } : { dark: mode }),
    })
    if (!made.problems.some(line => line.startsWith("Desktop won't paint"))) break
  }
  return { args: { colors: made.theme }, problems: made.problems }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const path = `${$.plugin.root}/${PALETTE}`
    // the look for the palette as it is now; a palette Desktop refuses to paint is a real failure: said once per
    // version, the look in place stays
    const paint = async (): Promise<void> => {
      try {
        const { args, problems } = look(JSON.parse(await $.fs.read(path)) as Palette)
        const unpainted = problems.find(line => line.startsWith("Desktop won't paint"))
        if (unpainted !== undefined) $.ui.log(`wallust-look: ${unpainted}`)
        else await $.theme.set(args)
      } catch (error) {
        $.ui.log(`wallust-look: ${PALETTE}: ${String(error)}`)
      }
    }
    const mtime = async (): Promise<number> => {
      try {
        return (await $.fs.stat(path)).mtimeMs
      } catch {
        return 0 // no palette (yet): the app's own look, nothing to say
      }
    }
    let seen = await mtime()
    await paint()
    $.clock.every(PALETTE_POLL_MS, async () => {
      const now = await mtime()
      if (now === seen) return
      seen = now
      if (now !== 0) await paint()
    })
    return next(e)
  })
}
