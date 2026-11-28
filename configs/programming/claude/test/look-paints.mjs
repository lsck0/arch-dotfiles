// Every themes/*.json through the wallust-look mod: a look Desktop would refuse to paint fails the test.
import { readFileSync, readdirSync } from 'node:fs'

const [mod, dir] = process.argv.slice(2)
const { look } = await import(mod)
const refused = readdirSync(dir).filter(f => f.endsWith('.json')).flatMap(f => {
  const palette = JSON.parse(readFileSync(`${dir}/${f}`, 'utf8'))
  if (!palette.special) return []
  const line = look(palette).problems.find(l => l.startsWith("Desktop won't paint"))
  return line === undefined ? [] : [`${f}: ${line}`]
})
if (refused.length > 0) {
  console.error(refused.join('\n'))
  process.exit(1)
}
