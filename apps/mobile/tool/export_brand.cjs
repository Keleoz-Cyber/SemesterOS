// From repository root:
// npm install --prefix tmp/brand-export --no-audit --no-fund @resvg/resvg-js@2.6.2
// node apps/mobile/tool/export_brand.cjs tmp/brand-export/node_modules/@resvg/resvg-js
// Rendering is build-time only; Flutter needs no SVG runtime dependency.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {Resvg} = require(process.argv[2] ? path.resolve(process.argv[2]) : '@resvg/resvg-js');
const mobile = path.resolve(__dirname, '..');
const res = path.join(mobile, 'android/app/src/main/res');
const source = fs.readFileSync(path.join(mobile, 'assets/brand/app_icon.svg'), 'utf8');

// The supplied artwork has an inset iOS tile; keep the source unchanged.
const defs = source.match(/<defs>[\s\S]*?<\/defs>/)[0];
const parts = source.split('<!-- Main mark -->');
if (parts.length !== 2) throw new Error('Brand SVG main mark boundary is missing');
const mark = parts[1].replace(/<\/svg>\s*$/, '');
const wrap = (definitions, body, viewBox = '0 0 1024 1024') =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" fill="none" viewBox="${viewBox}">${definitions}${body}</svg>`;
const insetTile = source.replace('viewBox="0 0 1024 1024"', 'viewBox="104 96 816 816"');
const fullBackground = parts[0]
  .replace(' filter="url(#tileShadow)"', '')
  .replaceAll('x="104" y="96" width="816" height="816" rx="180"',
    'x="0" y="0" width="1024" height="1024" rx="0"') + '</svg>';
// Fit sun rays and calendar inside the circular safe area, with room for parallax.
const transform = 'translate(512 512) scale(0.80) translate(-536 -502)';
const foreground = wrap(defs, `<g transform="${transform}">${mark}</g>`);
const monoDefs = defs.replace('</defs>', '<filter id="mono"><feColorMatrix type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 1 0"/></filter></defs>');
const monochrome = wrap(monoDefs, `<g filter="url(#mono)" transform="${transform}">${mark}</g>`);

function exportPng(svg, pixels, destination) {
  const image = new Resvg(svg, {fitTo: {mode: 'width', value: pixels}, font: {loadSystemFonts: false}}).render();
  fs.mkdirSync(path.dirname(destination), {recursive: true});
  fs.writeFileSync(destination, image.asPng());
}
exportPng(insetTile, 512, path.join(mobile, 'assets/brand/brand_mark.png'));
for (const [density, scale] of Object.entries({mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4})) {
  const folder = path.join(res, `mipmap-${density}`);
  exportPng(insetTile, Math.round(48 * scale), path.join(folder, 'ic_launcher.png'));
  for (const [name, svg] of Object.entries({background: fullBackground, foreground, monochrome})) {
    exportPng(svg, Math.round(108 * scale), path.join(folder, `ic_launcher_${name}.png`));
  }
}
console.log('Exported shared brand and 5 Android launcher densities.');
