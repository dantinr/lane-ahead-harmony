// Manual asset generation; sharp is only needed when rebuilding the atlas.
// Logo source: https://commons.wikimedia.org/wiki/File:Volkswagen_logo_2019.svg
const fs = require('node:fs');
const path = require('node:path');
const sharp = require(process.env.LANEAHEAD_SHARP || 'sharp');
const root = path.resolve(__dirname, '..');
const logo = fs.readFileSync(path.join(root, 'assets/volkswagen-logo.svg'), 'utf8');
const body = logo.replace(/<\?xml[^>]*\?>/g, '').replace(/<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '')
  .replace(/#[a-fA-F0-9]{6}/g, '#FFFFFF').replace(/fill:\s*rgb\([^)]*\)/g, 'fill: #FFFFFF');
const size = 112, frames = 72;
async function main() {
  const images = [];
  for (let i = 0; i < frames; i++) {
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="112" height="112" viewBox="0 0 112 112">
      <circle cx="56" cy="56" r="47" fill="#FFFFFF"/>
      <circle cx="56" cy="56" r="45" fill="#001E50"/>
      <path d="M56 0L48 11L64 11Z" fill="#B5F489" stroke="#001E50" stroke-width="1"/>
      <g transform="translate(17 17) scale(0.076171875)"><g transform="rotate(${i * 5} 512 512)">${body}</g></g>
    </svg>`;
    images.push({ input: await sharp(Buffer.from(svg)).png().toBuffer(), left: 0, top: i * size });
  }
  await sharp({ create: { width: size, height: size * frames, channels: 4, background: '#00000000' } })
    .composite(images).png().toFile(path.join(root, 'entry/src/main/resources/rawfile/volkswagen-car-frames.png'));
  console.log('Generated 72 transparent 112px vehicle icon frames');
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
