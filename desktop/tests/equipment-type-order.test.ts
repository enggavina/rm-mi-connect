import assert from 'node:assert/strict';
import test from 'node:test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createWebData } from '../src/server/web/data';
import { equipmentTypeLabel } from '../src/components/web/engineering-model';

type Row = { id: string; nome: string; sigla: string; created_at: string };
function fixture(rows: Row[]) {
  const calls: { table: string; orders: string[]; search: string | null; from: number; to: number }[] = [];
  const client = { from(table: string) {
    let orders: string[] = [], search: string | null = null;
    return {
      select() { return this; },
      order(key: string) { orders.push(key); return this; },
      or(value: string) { search = value; return this; },
      async range(from: number, to: number) {
        calls.push({ table, orders: [...orders], search, from, to });
        const term = search?.match(/\.ilike\.%([^%]+)%/)?.[1]?.toLowerCase();
        const found = rows.filter(row => !term || row.nome.toLowerCase().includes(term) || row.sigla.toLowerCase().includes(term));
        const sorted = [...found].sort((a, b) => {
          for (const key of orders) {
            const difference = String(a[key as keyof Row]).localeCompare(String(b[key as keyof Row]));
            if (difference) return difference;
          }
          return 0;
        });
        return { error: null, data: sorted.slice(from, to + 1), count: found.length };
      },
    };
  } };
  return { calls, data: createWebData(client as unknown as SupabaseClient, ['em.portal.read', 'em.catalogs.read']) };
}

test('equipment catalog keeps chronological creation order across pages with an ID tiebreaker and search', async () => {
  const rows: Row[] = Array.from({ length: 54 }, (_, n) => ({
    id: String(54 - n).padStart(3, '0'), nome: n % 2 ? `Motor ${n}` : `Bomba ${n}`,
    sigla: n % 2 ? 'MTR' : 'BMB', created_at: `2026-01-${String(1 + Math.floor(n / 3)).padStart(2, '0')}T00:00:00Z`,
  }));
  const { data, calls } = fixture(rows.reverse());
  const allFirst = await data.getCatalogs({ kind: 'types', page: 1 });
  const allSecond = await data.getCatalogs({ kind: 'types', page: 2 });
  const expected = [...rows].sort((a, b) => a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id));
  assert.equal(allFirst.total, 54); assert.equal(allSecond.total, 54);
  assert.deepEqual([...allFirst.rows, ...allSecond.rows].map(row => row.id), expected.map(row => row.id));
  assert.deepEqual(calls.map(call => call.orders), [['created_at', 'id'], ['created_at', 'id']]);
  assert.deepEqual(calls.map(call => [call.from, call.to]), [[0, 49], [50, 99]]);
  const matches = await data.getCatalogs({ kind: 'types', q: 'MTR' });
  assert.equal(matches.total, 27);
  assert.ok(matches.rows.every(row => row.sigla === 'MTR'));
  assert.match(calls[2].search!, /nome\.ilike\.%MTR%,sigla\.ilike\.%MTR%/);
});

test('equipment options display abbreviation and name without using them as identifiers', () => {
  assert.equal(equipmentTypeLabel({ id: 'uuid', sigla: ' MTR ', nome: ' Motor Elétrico ' }), 'MTR - Motor Elétrico');
  assert.equal(equipmentTypeLabel({ id: 'uuid', sigla: null, nome: 'Motor' }), 'Motor');
  assert.equal(equipmentTypeLabel({ id: 'uuid', sigla: 'MTR', nome: null }), 'MTR');
  assert.equal(equipmentTypeLabel({ id: 'uuid', sigla: '', nome: '' }), 'Tipo de equipamento sem nome');
});
