// Run the application's pure ArkTS sources on Node. This does not check ArkUI or ArkTS rules.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const sdkHome = process.env.DEVECO_SDK_HOME;
const tsPath = process.env.LANEAHEAD_TYPESCRIPT || (sdkHome && path.join(sdkHome,
  'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
if (!tsPath) throw new Error('请设置 LANEAHEAD_TYPESCRIPT，或通过 scripts/build.ps1 运行测试');
const ts = require(tsPath);
const sourceDir = path.join(__dirname, '../entry/src/main/ets/navigation');
const cache = new Map();
function load(name) {
  if (cache.has(name)) return cache.get(name);
  const filename = path.join(sourceDir, name + '.ets');
  const js = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const mod = { exports: {} };
  vm.runInThisContext('(function(require, module, exports) {' + js + '\n})', { filename })(
    (ref) => load(ref.replace('./', '')), mod, mod.exports);
  cache.set(name, mod.exports);
  return mod.exports;
}
module.exports = load;
