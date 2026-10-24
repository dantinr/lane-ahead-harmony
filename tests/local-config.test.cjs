const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { prepareLocalConfig } = require('../scripts/prepare-local-config.cjs');

test('构建注入本机默认 Key，移除本机配置后不能残留旧 Key', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'laneahead-config-'));
  try {
    fs.mkdirSync(path.join(root, '.local'));
    fs.writeFileSync(path.join(root, '.local/gaode'), 'Web Key: ' + 'a'.repeat(32));
    fs.writeFileSync(path.join(root, '.local/gaode-harmony'), 'b'.repeat(32));
    prepareLocalConfig(root);
    const output = path.join(root, 'entry/src/main/resources/rawfile/map-keys.json');
    assert.deepEqual(JSON.parse(fs.readFileSync(output)), { webKey: 'a'.repeat(32), harmonyKey: 'b'.repeat(32) });
    fs.unlinkSync(path.join(root, '.local/gaode'));
    prepareLocalConfig(root);
    assert.equal(JSON.parse(fs.readFileSync(output)).webKey, '');
    assert.ok(!fs.readFileSync(output, 'utf8').includes('a'.repeat(32)));
  } finally {
    assert.equal(path.dirname(root), path.resolve(os.tmpdir()));
    assert.ok(path.basename(root).startsWith('laneahead-config-'));
    fs.rmSync(root, { recursive: true, force: true });
  }
});
