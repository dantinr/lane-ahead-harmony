const test = require('node:test');
const assert = require('node:assert/strict');
const load = require('./load-ets.cjs');
const { SearchHistory } = load('SearchHistory');

test('搜索关键词去重置顶、规范空白，最多保留最近 20 条', () => {
  const history = new SearchHistory();
  for (let i = 1; i <= 25; i++) history.remember('公共地点 ' + i, i);
  assert.equal(history.records.length, 20);
  assert.equal(history.records[0].query, '公共地点 25');
  history.remember('  公共地点   10  ', 30);
  assert.equal(history.records[0].query, '公共地点 10');
  assert.equal(history.records.filter(r => r.query === '公共地点 10').length, 1);
  history.remember('ABC', 31); history.remember('abc', 32);
  assert.equal(history.records.filter(r => r.query.toLowerCase() === 'abc').length, 1);
  const saved = history.serialize();
  for (const query of ['', '  ', 'a'.repeat(121)]) history.remember(query, 33);
  assert.equal(history.serialize(), saved);
});

test('重建历史保留搜索顺序；删除和清空可持久化，不存城市或坐标', () => {
  const original = new SearchHistory();
  original.remember('望京地铁站', 10); original.remember('图书馆', 20);
  const restored = new SearchHistory();
  assert.equal(restored.restore(original.serialize()), true);
  assert.deepEqual(restored.records.map(r => r.query), ['图书馆', '望京地铁站']);
  restored.remove('图书馆');
  assert.equal(restored.records.length, 1);
  assert.deepEqual(Object.keys(restored.records[0]).sort(), ['query', 'searchedAt']);
  assert.equal(restored.restore(new SearchHistory().serialize()), true);
  assert.equal(restored.records.length, 0);
});

test('损坏、未知版本、重复或越界历史不替换现有记录，额外字段不被传播', () => {
  const history = new SearchHistory(); history.remember('保留记录', 1);
  const record = {query:'图书馆', searchedAt:10};
  for (const value of [null, {version:2,records:[]}, {version:1,records:[null]},
    {version:1,records:[record,record]}, {version:1,records:[{...record,query:' '} ]},
    {version:1,records:[{...record,searchedAt:-1}]}, {version:1,records:Array(21).fill(record)}]) {
    assert.equal(history.restore(JSON.stringify(value)), false);
    assert.equal(history.records[0].query, '保留记录');
  }
  assert.equal(history.restore('{broken'), false);
  assert.equal(history.restore(JSON.stringify({version:1,records:[{...record, location:'private'}]})), true);
  assert.equal(history.serialize().includes('private'), false);
});

test('搜索历史原子写入后可重新读取，失败保留旧数据，损坏文件可显式清空', () => {
  const files = new Map(); let fail = false; let closed = 0;
  const { SearchHistoryStore } = load('SearchHistoryStore', {'@kit.CoreFileKit': { fileIo: {
    OpenMode: {CREATE:1,TRUNC:2,READ_WRITE:4}, accessSync: path => files.has(path),
    statSync: path => ({size:files.get(path).length}), readTextSync: path => files.get(path),
    openSync(path) { assert.ok(path.endsWith('.tmp')); return {fd:path}; },
    writeSync(fd,text) { if (fail) throw Error('full'); files.set(fd,text); },
    closeSync() { closed++; }, renameSync(from,to) { files.set(to,files.get(from)); files.delete(from); }
  }}});
  const store = new SearchHistoryStore('/private');
  assert.equal(store.load().records.length, 0);
  const history = new SearchHistory(); history.remember('图书馆', 10);
  assert.equal(store.save(history), true);
  assert.equal(new SearchHistoryStore('/private').load().records[0].query, '图书馆');
  history.remember('公园', 20); fail = true;
  assert.equal(store.save(history), false);
  assert.match(store.error, /保存失败/);
  assert.equal(store.load().records.length, 1);
  files.set('/private/search-history-v1.json', 'broken');
  assert.equal(store.load().records.length, 0);
  assert.match(store.error, /保留原文件/);
  assert.equal(files.get('/private/search-history-v1.json'), 'broken');
  fail = false; assert.equal(store.save(new SearchHistory()), true);
  assert.equal(store.load().records.length, 0);
  assert.equal(closed, 3);
});
