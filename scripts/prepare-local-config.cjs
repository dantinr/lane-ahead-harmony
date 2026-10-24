const fs = require('node:fs');
const path = require('node:path');

function prepareLocalConfig(root) {
  function readKey(name) {
    const file = path.join(root, '.local', name);
    if (!fs.existsSync(file)) return '';
    const matches = [...new Set(fs.readFileSync(file, 'utf8').match(/(?<![a-f0-9])[a-f0-9]{32}(?![a-f0-9])/gi) || [])];
    if (matches.length !== 1) throw Error('Invalid local map configuration: ' + name);
    return matches[0];
  }
  const content = JSON.stringify({ webKey: readKey('gaode'), harmonyKey: readKey('gaode-harmony') });
  const output = path.join(root, 'entry/src/main/resources/rawfile/map-keys.json');
  fs.mkdirSync(path.dirname(output), { recursive: true });
  if (!fs.existsSync(output) || fs.readFileSync(output, 'utf8') !== content) fs.writeFileSync(output, content);
}

if (require.main === module) prepareLocalConfig(path.resolve(__dirname, '..'));
module.exports = { prepareLocalConfig };
