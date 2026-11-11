import {test} from 'node:test';import assert from 'node:assert/strict';import {validate,diff} from '../src/data.js';
const valid={编号:'001',店面:'天河店',小组:'一组',楼盘:'测试盘',房间号:'0101',报价:'5,000',底价:'4500'};
test('保留编号和房间号前导零，解析金额',()=>{const r=validate([valid]);assert.equal(r.errors.length,0);assert.equal(r.rows[0].code,'001');assert.equal(r.rows[0].room,'0101');assert.equal(r.rows[0].quote,5000);});
test('拒绝重复、空价格和不合理底价',()=>{assert.ok(validate([valid,valid]).errors.length);assert.ok(validate([{...valid,报价:''}]).errors.length);assert.ok(validate([{...valid,底价:9999}]).errors.length);});
test('变更预览携带版本并区分新增、不变、变更',()=>{const r=validate([valid]).rows;assert.equal(diff(r,[])[0].kind,'新增');assert.equal(diff(r,[{...r[0],version:3}])[0].kind,'不变');const d=diff([{...r[0],quote:6000}],[{...r[0],version:3}])[0];assert.equal(d.kind,'变更');assert.equal(d.expected_version,3);});
