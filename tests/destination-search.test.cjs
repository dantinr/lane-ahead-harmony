const test = require('node:test');
const assert = require('node:assert/strict');
const load = require('./load-ets.cjs');
const { DestinationSearchSession } = load('DestinationSearchSession');
const { Place } = load('RoutePlanning');

test('选择结果只回填当前搜索会话一次，取消返回没有结果', () => {
  const session = new DestinationSearchSession();
  const id = session.begin('北京市', 'a'.repeat(32));
  assert.equal(session.request(id).city, '北京市');
  const place = new Place('test', '测试公共地点', '测试地址', '116.4,39.9');
  assert.equal(session.select(id, place), true);
  assert.equal(session.finish(id), place);
  assert.equal(session.finish(id), undefined);
  assert.equal(session.request(id), undefined);
  assert.equal(session.select(id, place), false);
  assert.equal(session.finish(session.begin('天津市', 'b'.repeat(32))), undefined);
});

test('旧页面的选择和清理不能覆盖或取消新页面的结果，交接后释放请求', () => {
  const session = new DestinationSearchSession();
  const old = session.begin('北京市', 'a'.repeat(32));
  const id = session.begin('天津市', 'b'.repeat(32));
  const place = new Place('test', '测试公共地点', '', '117.2,39.1');
  assert.equal(session.request(old), undefined);
  assert.equal(session.select(old, place), false);
  assert.equal(session.select(id, place), true);
  assert.equal(session.finish(old), undefined);
  assert.equal(session.request(id).city, '天津市');
  assert.equal(session.finish(id), place);
  assert.equal(session.request(id), undefined);
});
