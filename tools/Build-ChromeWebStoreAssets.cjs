const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const projectRoot = path.resolve(__dirname, '..');
const sources = path.join(projectRoot, 'assets', 'chrome-web-store', 'sources');
const output = path.join(projectRoot, 'outputs', 'ChromeWebStore-Assets-1.7.0');
const filmSource = path.join(sources, 'film-dialog-source.png');
const collectionSource = path.join(sources, 'collection-dialog-source.png');
const backgroundSource = path.join(sources, 'promotional-background-generated.png');
const iconSource = path.join(projectRoot, 'browser-extension', 'icons', 'icon128.png');

fs.mkdirSync(output, { recursive: true });

function svg(width, height, body) {
  return Buffer.from(`
    <svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" xmlns="http://www.w3.org/2000/svg">
      <style>
        .ui { font-family: "Segoe UI", Arial, sans-serif; }
      </style>
      ${body}
    </svg>
  `);
}

async function roundedScreenshot(source, width, height, radius = 20) {
  const image = await sharp(source)
    .resize(width, height, { fit: 'cover', position: 'centre' })
    .png()
    .toBuffer();
  const mask = svg(width, height, `<rect width="${width}" height="${height}" rx="${radius}" fill="#fff"/>`);
  return sharp(image).composite([{ input: mask, blend: 'dest-in' }]).png().toBuffer();
}

async function savePng(pipeline, name) {
  const file = path.join(output, name);
  await pipeline
    .flatten({ background: '#081019' })
    .removeAlpha()
    .png({ compressionLevel: 9, palette: false })
    .toFile(file);
  return file;
}

async function buildScreenshots() {
  await savePng(
    sharp(filmSource).resize(1280, 800, { fit: 'cover', position: 'centre' }),
    'capture-01-film-1280x800.png'
  );
  await savePng(
    sharp(collectionSource).resize(1280, 800, { fit: 'cover', position: 'centre' }),
    'capture-02-collection-1280x800.png'
  );

  const film = await roundedScreenshot(filmSource, 548, 308, 18);
  const collection = await roundedScreenshot(collectionSource, 548, 308, 18);
  const labels = svg(1280, 800, `
    <rect width="1280" height="800" fill="rgba(2,8,15,.36)"/>
    <text class="ui" x="64" y="92" fill="#63cef4" font-size="18" font-weight="700" letter-spacing="2">JELLYFIN VLC BRIDGE</text>
    <text class="ui" x="64" y="148" fill="#ffffff" font-size="42" font-weight="700">Choisissez. Prévisualisez. Lancez.</text>
    <text class="ui" x="64" y="190" fill="#b9c7d5" font-size="21">Un film ou toute une collection, directement dans VLC.</text>
    <rect x="52" y="232" width="572" height="384" rx="24" fill="#111a24" stroke="#28465a" stroke-width="2"/>
    <rect x="656" y="232" width="572" height="384" rx="24" fill="#111a24" stroke="#28465a" stroke-width="2"/>
    <text class="ui" x="76" y="660" fill="#ffffff" font-size="22" font-weight="700">Lecture d’un film</text>
    <text class="ui" x="76" y="692" fill="#9eb0bf" font-size="17">Reprendre ou recommencer depuis le début.</text>
    <text class="ui" x="680" y="660" fill="#ffffff" font-size="22" font-weight="700">Lecture d’une collection</text>
    <text class="ui" x="680" y="692" fill="#9eb0bf" font-size="17">Vérifier la liste avant de lancer VLC.</text>
    <rect x="64" y="738" width="246" height="42" rx="12" fill="#068ec0"/>
    <text class="ui" x="187" y="766" text-anchor="middle" fill="#ffffff" font-size="17" font-weight="700">Lecture locale et privée</text>
  `);

  await savePng(
    sharp(backgroundSource)
      .resize(1280, 800, { fit: 'cover' })
      .composite([
        { input: labels, left: 0, top: 0 },
        { input: film, left: 64, top: 250 },
        { input: collection, left: 668, top: 250 }
      ]),
    'capture-03-fonctionnalites-1280x800.png'
  );
}

async function buildSmallPromo() {
  const icon = await sharp(iconSource).resize(68, 68).png().toBuffer();
  const overlay = svg(440, 280, `
    <rect width="440" height="280" fill="rgba(2,8,15,.28)"/>
    <text class="ui" x="116" y="48" fill="#63cef4" font-size="12" font-weight="700" letter-spacing="1.5">JELLYFIN VLC BRIDGE</text>
    <text class="ui" x="30" y="128" fill="#ffffff" font-size="29" font-weight="700">Jellyfin dans VLC.</text>
    <text class="ui" x="30" y="160" fill="#c3d0dc" font-size="16">Films, séries et collections.</text>
    <rect x="30" y="190" width="164" height="42" rx="11" fill="#078fbe"/>
    <text class="ui" x="112" y="217" text-anchor="middle" fill="#ffffff" font-size="16" font-weight="700">Lire avec VLC</text>
    <text class="ui" x="30" y="256" fill="#8ea4b6" font-size="12">Reprise et progression synchronisées</text>
  `);
  await savePng(
    sharp(backgroundSource)
      .resize(440, 280, { fit: 'cover', position: 'right' })
      .composite([
        { input: icon, left: 30, top: 24 },
        { input: overlay, left: 0, top: 0 }
      ]),
    'promotion-petite-440x280.png'
  );
}

async function buildMarquee() {
  const icon = await sharp(iconSource).resize(82, 82).png().toBuffer();
  const screenshot = await roundedScreenshot(filmSource, 620, 349, 22);
  const shadow = svg(660, 389, `
    <rect x="20" y="18" width="620" height="349" rx="22" fill="rgba(0,0,0,.55)"/>
    <rect x="20" y="18" width="620" height="349" rx="22" fill="none" stroke="#3a7895" stroke-width="2"/>
  `);
  const overlay = svg(1400, 560, `
    <rect width="1400" height="560" fill="rgba(2,8,15,.22)"/>
    <text class="ui" x="178" y="93" fill="#63cef4" font-size="16" font-weight="700" letter-spacing="2">JELLYFIN VLC BRIDGE</text>
    <text class="ui" x="72" y="202" fill="#ffffff" font-size="50" font-weight="750">Votre médiathèque Jellyfin.</text>
    <text class="ui" x="72" y="263" fill="#ffffff" font-size="50" font-weight="750">La lecture puissante de VLC.</text>
    <text class="ui" x="72" y="326" fill="#b9c7d5" font-size="23">Reprise, collections et progression synchronisée.</text>
    <rect x="72" y="377" width="214" height="54" rx="14" fill="#078fbe"/>
    <text class="ui" x="179" y="412" text-anchor="middle" fill="#ffffff" font-size="20" font-weight="700">Lire avec VLC</text>
    <text class="ui" x="72" y="478" fill="#8ea4b6" font-size="16">Local • sans publicité • sans télémétrie</text>
  `);
  await savePng(
    sharp(backgroundSource)
      .resize(1400, 560, { fit: 'cover', position: 'right' })
      .composite([
        { input: shadow, left: 720, top: 86 },
        { input: screenshot, left: 740, top: 104 },
        { input: icon, left: 72, top: 48 },
        { input: overlay, left: 0, top: 0 }
      ]),
    'promotion-marquee-1400x560.png'
  );
}

(async () => {
  await buildScreenshots();
  await buildSmallPromo();
  await buildMarquee();
  for (const name of fs.readdirSync(output).sort()) {
    const metadata = await sharp(path.join(output, name)).metadata();
    console.log(`${name}: ${metadata.width}x${metadata.height}, ${metadata.channels} canaux`);
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
