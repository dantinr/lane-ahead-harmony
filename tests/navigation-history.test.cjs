const test = require('node:test');
const assert = require('node:assert/strict');
const load = require('./load-ets.cjs');
const { NavigationHistory, NavigationRecord, navigationDuration, navigationStatus, navigationTime } = load('NavigationHistory');
const now = 1792850000000;
global.AppStorage = { setOrCreate() {} };

function setup() {
  const state = { files: new Map(), failWrite: false, failRename: false, writes: 0, closed: 0, errors: [] };
  global.AppStorage = { setOrCreate(key, value) { state.errors.push(value); } };
  const path = '/private/files/navigation-history-v1.json';
  const fs = {
    OpenMode: {CREATE:1,TRUNC:2,READ_WRITE:4},
    accessSync(name) { return state.files.has(name); },
    statSync(name) { return {size: state.files.get(name).length}; },
    readTextSync(name) { return state.files.get(name); },
    openSync(name) { assert.equal(name, path + '.tmp'); return {fd: 1}; },
    writeSync(_, text) { if (state.failWrite) throw Error('full'); state.files.set(path + '.tmp', text); state.writes++; },
    closeSync() { state.closed++; },
    renameSync(from, to) { if (state.failRename) throw Error('rename'); state.files.set(to, state.files.get(from)); }
  };
  const classes = load('NavigationHistoryStore', {'@kit.CoreFileKit': {fileIo: fs}});
  state.store = new classes.NavigationHistoryStore('/private/files');
  state.session = () => new classes.NavigationHistorySession('/private/files', '测试终点', '公共地点');
  state.records = () => state.store.load().records;
  state.raw = () => state.files.get(path);
  state.path = path;
  return state;
}

test('导航开始立即持久化，重复开始只记一次，结束后重读仍有目的地与规划里程', () => {
  const s = setup(); const session = s.session();
  session.finish('ended', now);
  assert.equal(s.files.size, 0);
  session.start(17500, now); session.start(99000, now + 1);
  assert.equal(s.records().length, 1);
  assert.equal(s.records()[0].status, 'navigating');
  session.finish('ended', now + 61000); session.finish('ended', now + 62000);
  const [record] = s.records();
  assert.equal(record.destination, '测试终点'); assert.equal(record.plannedMeters, 17500);
  assert.equal(record.endedAt, now + 61000); assert.equal(navigationDuration(record), '1 分钟');
  assert.equal(s.writes, 2);
  assert.doesNotMatch(s.raw(), /coordinates|latitude|longitude|webKey|harmonyKey/);
});

test('到达不被退出覆盖，同一会话先收到停止再收到实际到达可修正状态', () => {
  for (const stopFirst of [true, false]) {
    const s = setup(); const session = s.session(); session.start(0, now);
    if (stopFirst) session.finish('ended', now + 1000);
    session.finish('arrived', now + 2000); session.finish('ended', now + 3000);
    assert.equal(s.records()[0].status, 'arrived');
    assert.equal(s.records()[0].endedAt, now + (stopFirst ? 1000 : 2000));
  }
});

test('重启仅将未完成记录标为中断，不伪造结束时间或行驶时长', () => {
  const s = setup(); s.session().start(0, now);
  s.store.recoverInterrupted();
  const [record] = s.records();
  assert.equal(record.status, 'interrupted'); assert.equal(record.endedAt, 0);
  assert.equal(navigationDuration(record), '未记录完整时长');
  assert.equal(navigationStatus(record.status), '未正常结束');
});

test('写入或重命名失败保留原文件，结束时能重试，不能伪报成功', () => {
  const s = setup(); const session = s.session(); session.start(0, now);
  const original = s.raw(); s.failRename = true;
  session.finish('ended', now + 1000);
  assert.equal(s.raw(), original); assert.match(s.errors.at(-1), /保存失败/);
  s.failRename = false; session.finish('ended', now + 2000);
  assert.equal(s.records()[0].status, 'ended'); assert.equal(s.records()[0].endedAt, now + 1000);
  assert.equal(s.errors.at(-1), '');
  s.failWrite = true;
  assert.equal(s.store.save(new NavigationHistory()), false);
  assert.equal(s.records().length, 1);
  assert.equal(s.closed, 4);
});

test('损坏或未知版本不会被新导航覆盖，明确提示读取失败', () => {
  const s = setup(); const broken = '{"version":99,"records":[]}';
  s.files.set(s.path, broken); s.session().start(0, now);
  assert.equal(s.raw(), broken); assert.match(s.errors.at(-1), /损坏或格式不支持/);
  s.store.recoverInterrupted(); assert.equal(s.raw(), broken);
});

test('历史最多保留最近200次，支持按ID删除与独立清空', () => {
  const history = new NavigationHistory();
  for (let i = 0; i < 205; i++) history.put(new NavigationRecord('trip-' + i, '终点', '', now + i, 0));
  assert.equal(history.records.length, 200); assert.equal(history.records[0].id, 'trip-204');
  assert.equal(history.records.at(-1).id, 'trip-5');
  history.remove('trip-204'); assert.equal(history.records.length, 199);
  const s = setup(); assert.equal(s.store.save(history), true);
  assert.equal(s.store.save(new NavigationHistory()), true); assert.equal(s.records().length, 0);
});

test('非法时间、状态、重复ID和超大文件均被拒绝且不污染已读历史', () => {
  const history = new NavigationHistory(); const record = new NavigationRecord('a', '终点', '', now, 0);
  history.put(record);
  for (const records of [[{...record, endedAt: now - 1, status:'ended'}], [{...record, status:'fake'}],
    [{...record, startedAt:-1}], [{...record, destination:''}], [record, record], [null]]) {
    assert.equal(history.restore(JSON.stringify({version:1,records})), false);
    assert.equal(history.records.length, 1);
  }
  assert.equal(history.restore('x'.repeat(1000001)), false);
  const loaded = new NavigationHistory(); assert.equal(loaded.restore(history.serialize()), true);
  assert.equal(loaded.records[0].id, 'a');
  assert.equal(navigationTime(0), '未记录'); assert.match(navigationTime(now), /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/);
});
