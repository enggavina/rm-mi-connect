import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import { Bridge } from '../src/server/bridge/engine';
import type { BubbleClient } from '../src/server/bridge/client';
import { getEntity, type Row } from '../src/server/bridge/mapping';

type Result = { data: Row | Row[] | null; error: null };

function fixture(pendingRecordId: string, status = 'pending') {
  const tables: Record<string, Row[]> = {
    rm_respostas: [],
    rm_registros_formulario: [{ id: 'record-id', bubble_id: 'bubble-record', projeto_id: 'project-id' }],
    rm_questoes: [{ id: 'question-id', bubble_id: 'bubble-question' }],
    rm_sync_outbox: [{ id: 1, record_id: pendingRecordId, target_system: 'bubble_data_api', status }],
  };
  const writes: Row[] = [];
  class Query implements PromiseLike<Result> {
    private filters: ((row: Row) => boolean)[] = [];
    private singleton = false;
    private payload?: Row;
    constructor(private table: string) {}
    select(_columns = '*') { return this; }
    eq(column: string, value: unknown) { this.filters.push(row => row[column] === value); return this; }
    neq(column: string, value: unknown) { this.filters.push(row => row[column] !== value); return this; }
    in(column: string, values: unknown[]) { this.filters.push(row => values.includes(row[column])); return this; }
    limit(_count: number) { return this; }
    single() { this.singleton = true; return this; }
    maybeSingle() { this.singleton = true; return this; }
    upsert(row: Row) { writes.push(row); this.payload = row; return this; }
    then<TResult1 = Result, TResult2 = never>(
      fulfilled?: ((value: Result) => TResult1 | PromiseLike<TResult1>) | null,
      rejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
    ): PromiseLike<TResult1 | TResult2> {
      const rows = this.payload ? [{ ...this.payload, id: 'answer-id' }]
        : (tables[this.table] || []).filter(row => this.filters.every(filter => filter(row)));
      return Promise.resolve({ data: this.singleton ? rows[0] || null : rows, error: null } as Result).then(fulfilled, rejected);
    }
  }
  const db = { from: (table: string) => new Query(table) } as unknown as SupabaseClient;
  const bubble = { get: async () => assert.fail('All referenced records already exist locally.') } as unknown as BubbleClient;
  const bridge = new Bridge(db, bubble);
  const raw: Row = {
    _id: 'bubble-new-answer', 'Modified Date': '2026-10-27T12:00:00Z',
    Registro_Formulario: 'bubble-record', Questao: 'bubble-question', Resposta: 'Updated on desktop',
  };
  return { bridge, raw, writes };
}

test('apply refuses a new answer while its form record has a pending local bundle', async () => {
  const { bridge, raw, writes } = fixture('record-id');
  await assert.rejects(bridge.apply(getEntity('rm_respostas'), raw), /Conflito pendente/);
  assert.equal(writes.length, 0, 'The conflict must be detected before upsert is invoked.');
});

test('apply checks the project ancestor before importing a new answer', async () => {
  const { bridge, raw, writes } = fixture('project-id', 'failed');
  await assert.rejects(bridge.apply(getEntity('rm_respostas'), raw), /Conflito pendente/);
  assert.equal(writes.length, 0, 'A project bundle awaiting retry protects its new descendant answer.');
});

test('a completed project bundle allows the new answer to be imported', async () => {
  const { bridge, raw, writes } = fixture('project-id', 'completed');
  assert.equal(await bridge.apply(getEntity('rm_respostas'), raw), 'answer-id');
  assert.equal(writes.length, 1);
  assert.equal(writes[0].registro_formulario_id, 'record-id');
  assert.equal(writes[0].questao_id, 'question-id');
});
