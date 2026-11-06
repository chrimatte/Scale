import test from 'node:test';
import assert from 'node:assert/strict';
import {parseLine,verifyReading,dayInZone} from './core.mjs';
test('captures final measured weight, not live advertisements',()=>{
 assert.deepEqual(parseLine('2026 [Sync] Measurement: 71.90 kg / 0 Ohm'),{type:'measurement',weight:71.9});
 assert.equal(parseLine('Weight: 72.5 kg | Impedance: Measuring...'),null);
});
test('success requires reading the saved wellness value',()=>{
 assert.ok(verifyReading({weight:71.9,bodyFat:13},71.9,13.02,true));
 assert.ok(!verifyReading({weight:70,bodyFat:13},71.9,13.02,true));
 assert.ok(!verifyReading({weight:71.9,bodyFat:null},71.9,13.02,true));
 assert.ok(!verifyReading({weight:null},71.9,null,false));
});
test('weight-only permits existing body-fat field without claiming to update it',()=>{
 assert.ok(verifyReading({weight:71.9,bodyFat:18.5},71.9,null,false));
});
test('uses athlete calendar day around midnight',()=>{
 assert.equal(dayInZone('Europe/Rome',new Date('2026-11-05T23:30:00Z')),'2026-11-06');
});
test('parses explicit server acknowledgment date',()=>{
 assert.deepEqual(parseLine('[Intervals] Intervals.icu wellness updated for 2026-11-05.'),{type:'uploaded',date:'2026-11-05'});
});
