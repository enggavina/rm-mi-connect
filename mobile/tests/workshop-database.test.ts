import assert from 'node:assert/strict';
import test from 'node:test';
import { WorkshopRestartRequired, workshopDatabaseName } from '../src/core/workshop-database';

const first = 'a6179d35-80c6-4ecb-b4e2-e3108bb40e79';
const second = 'b0d70e79-8ff5-465d-95f5-494be41fc66e';
const third = 'd34c0ec6-05a2-4888-b9ab-bafbebedc7cb';

test('each confirmed office opens its own database and the first office keeps its existing file', () => {
  assert.equal(workshopDatabaseName(null, null), 'rm-mi-connect.db');
  assert.equal(workshopDatabaseName(first, null), 'rm-mi-connect.db');
  assert.equal(workshopDatabaseName(first, first), 'rm-mi-connect.db');
  assert.equal(workshopDatabaseName(first.toUpperCase(), first), 'rm-mi-connect.db');
  assert.equal(workshopDatabaseName(second, first), `rm-mi-connect-${second}.db`);
  assert.equal(workshopDatabaseName(third, first), `rm-mi-connect-${third}.db`);
  assert.equal(workshopDatabaseName(first, first), 'rm-mi-connect.db');
});

test('invalid stored bindings fail closed before opening a SQLite file', () => {
  for (const invalid of ['../unrelated', 'BMA', 'rm-mi-connect.db']) {
    assert.throws(() => workshopDatabaseName(invalid, first), /armazenamento da oficina/);
    assert.throws(() => workshopDatabaseName(first, invalid), /armazenamento da oficina/);
  }
  assert.equal(new WorkshopRestartRequired().code, '42501');
});
