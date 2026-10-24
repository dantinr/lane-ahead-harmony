const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const version = fs.readFileSync(path.join(root, 'VERSION'), 'utf8').trim();
if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version)) {
  throw new Error('VERSION must contain a version such as 0.0.10');
}

const updates = [];
function prepare(file, field, updateCode = false) {
  const filename = path.join(root, file);
  const source = fs.readFileSync(filename, 'utf8');
  const pattern = new RegExp('("' + field + '"\\s*:\\s*")([^"]*)(")', 'g');
  const matches = [...source.matchAll(pattern)];
  if (matches.length !== 1) throw new Error('Expected one ' + field + ' in ' + file);
  let output = source.replace(pattern, (_, prefix, previous, suffix) => prefix + version + suffix);
  if (updateCode && matches[0][2] !== version) {
    // Keep upgrades possible even when adopting a smaller versionName.
    const codePattern = /("versionCode"\s*:\s*)(\d+)/g;
    const codes = [...source.matchAll(codePattern)];
    const next = codes.length === 1 ? Number(codes[0][2]) + 1 : NaN;
    if (!Number.isSafeInteger(next) || next > 2147483647) {
      throw new Error('Invalid versionCode in ' + file);
    }
    output = output.replace(codePattern, (_, prefix) => prefix + next);
  }
  updates.push({ filename, source, output });
}

prepare('AppScope/app.json5', 'versionName', true);
prepare('oh-package.json5', 'version');
for (const { filename, source, output } of updates) {
  if (output !== source) fs.writeFileSync(filename, output);
}
console.log('Application version: ' + version);
