import { copyFile, mkdir } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

const docsDirUrl = new URL('../', import.meta.url)
const iconDirUrl = new URL(
  '../Swihomo/Assets.xcassets/AboutIcon.imageset/',
  docsDirUrl,
)
const publicDirUrl = new URL('pages/public/', docsDirUrl)

const assets = [
  ['AppIcon-light-1024.png', 'logo-light.png'],
  ['AppIcon-dark-1024.png', 'logo-dark.png'],
]

await mkdir(fileURLToPath(publicDirUrl), { recursive: true })

for (const [source, target] of assets) {
  await copyFile(
    fileURLToPath(new URL(source, iconDirUrl)),
    fileURLToPath(new URL(target, publicDirUrl)),
  )
}
