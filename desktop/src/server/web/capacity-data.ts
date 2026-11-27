import type { SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { uuid } from './policy';
import { calendarDay } from './gantt';
import { ganttRevision } from './gantt-policy';
import { createGanttData, ganttSnapshotSchema, GanttSelectionUnavailable } from './gantt-data';
import { CAPACITY_MAX_BOOKINGS, CAPACITY_MAX_RESOURCES, CAPACITY_READ_SCOPES, capacityDaySchema, capacityExceptionsSchema, capacityFiltersSchema, capacityKindSchema, capacityWeekSchema, type CapacityFilters } from './capacity-policy';
import type { CorporateCapability } from './sso-policy';
import type { WorkshopRead } from './workshop-read-policy';

const timestamp = z.string().datetime({ offset: true }), text = z.string().nullable();
export const capacityResourceSchema = z.object({ id: uuid, name: z.string().min(1).max(120), kind: capacityKindSchema, active: z.boolean(),
  weekly_minutes: capacityWeekSchema, exceptions: capacityExceptionsSchema, updated_at: timestamp, version: ganttRevision,
  booked_days: z.array(z.object({ date: capacityDaySchema, minutes: z.number().int().min(1).max(Number.MAX_SAFE_INTEGER) })).max(20000) });
export const capacityBookingSchema = z.object({ id: uuid, resource_id: uuid, allocation_id: uuid, day: capacityDaySchema, minutes: z.number().int().min(1).max(1440), updated_at: timestamp,
  allocation_updated_at: timestamp, project_id: uuid, numero_projeto: text, cell_name: text, status: text, retired: z.boolean(), project_closed: z.boolean(),
  planned_start: timestamp.nullable(), planned_end: timestamp.nullable(), project_working: z.boolean() });
export const capacitySnapshotSchema = z.object({ as_of: timestamp, start: capacityDaySchema, days: z.union([z.literal(7), z.literal(14), z.literal(28)]), complete: z.boolean(),
  totals: z.object({ resources: z.number().int().nonnegative(), bookings: z.number().int().nonnegative() }),
  resources: z.array(capacityResourceSchema).max(CAPACITY_MAX_RESOURCES), bookings: z.array(capacityBookingSchema).max(CAPACITY_MAX_BOOKINGS), project_plan: ganttSnapshotSchema.nullable() });
export type CapacitySnapshot = z.infer<typeof capacitySnapshotSchema>;
export type CapacityResource = z.infer<typeof capacityResourceSchema>;
export type CapacityBooking = z.infer<typeof capacityBookingSchema>;
const unavailable = () => new Error('Não foi possível consultar a capacidade. Tente novamente.');
const key = (id: string) => id.toLowerCase();
export function createCapacityData(client: SupabaseClient, capabilities?: readonly CorporateCapability[], workshopRead?: WorkshopRead, canManage = false) {
  return { async getCapacitySnapshot(input: CapacityFilters): Promise<CapacitySnapshot> {
    if (capabilities && !CAPACITY_READ_SCOPES.every(scope => capabilities.includes(scope))) throw new Error('Acesso não autorizado a esta área.');
    const filters = capacityFiltersSchema.safeParse(input); if (!filters.success) throw unavailable();
    let snapshot: unknown;
    if (workshopRead) {
      snapshot = await workshopRead('capacity_snapshot', { ...filters.data, can_manage: canManage && (capabilities?.includes('em.planning.manage') ?? true) });
      if (snapshot === null && filters.data.project_id) throw new GanttSelectionUnavailable();
    } else {
      let result;
      try { result = await client.rpc('rm_web_capacity_snapshot_v1', { p_filters: filters.data }); } catch { throw unavailable(); }
      if (result.error) throw result.error.code === 'PT413' ? new Error('A consulta de capacidade excede o limite. Reduza o período.') : unavailable();
      snapshot = result.data;
    }
    try { if (Buffer.byteLength(JSON.stringify(snapshot), 'utf8') > 10 * 1024 * 1024) throw unavailable(); } catch { throw unavailable(); }
    const parsed = capacitySnapshotSchema.safeParse(snapshot); if (!parsed.success) throw unavailable();
    const data = parsed.data;
    if (data.start !== filters.data.start || data.days !== filters.data.days) throw unavailable();
    if (!data.complete) {
      if (data.resources.length || data.bookings.length || data.project_plan) throw unavailable();
      return data;
    }
    if (data.resources.length !== data.totals.resources || data.bookings.length !== data.totals.bookings || !!data.project_plan !== !!filters.data.project_id) throw unavailable();
    const resources = new Set(data.resources.map(row => key(row.id))), ids = new Set<string>(), pairs = new Set<string>();
    if (resources.size !== data.resources.length || new Set(data.resources.map(row => row.name.trim().toLowerCase())).size !== data.resources.length) throw unavailable();
    if (data.resources.reduce((sum, row) => sum + row.booked_days.length, 0) > 20000 || data.resources.some(row => new Set(row.booked_days.map(day => day.date)).size !== row.booked_days.length)) throw unavailable();
    const start = calendarDay(data.start)!;
    const windowTotals = new Map<string, number>();
    for (const row of data.bookings) {
      const composite = `${key(row.resource_id)}:${key(row.allocation_id)}:${row.day}`, day = calendarDay(row.day)!;
      if (!resources.has(key(row.resource_id)) || ids.has(key(row.id)) || pairs.has(composite) || day < start || day >= start + data.days) throw unavailable();
      ids.add(key(row.id)); pairs.add(composite);
      const bucket = `${key(row.resource_id)}:${row.day}`;
      windowTotals.set(bucket, (windowTotals.get(bucket) ?? 0) + row.minutes);
    }
    for (const resource of data.resources) for (const day of resource.booked_days) {
      if (calendarDay(day.date)! >= start && calendarDay(day.date)! < start + data.days) {
        const bucket = `${key(resource.id)}:${day.date}`;
        if (windowTotals.get(bucket) !== day.minutes) throw unavailable();
        windowTotals.delete(bucket);
      }
    }
    if (windowTotals.size) throw unavailable();
    if (data.project_plan) {
      const nested = data.project_plan;
      const bridge = { rpc: async () => ({ data: nested, error: null }) } as unknown as SupabaseClient;
      try { data.project_plan = await createGanttData(bridge, capabilities).getGanttSnapshot({ project_id: filters.data.project_id, cell_id: null, include_closed: true }); } catch { throw unavailable(); }
      if (!data.project_plan.complete) throw unavailable();
      for (const row of data.bookings.filter(row => key(row.project_id) === key(filters.data.project_id!) && !row.retired)) {
        const allocation = data.project_plan.items.find(item => key(item.id) === key(row.allocation_id));
        if (!allocation || allocation.updated_at !== row.allocation_updated_at || allocation.data_inicio !== row.planned_start || allocation.data_limite !== row.planned_end || allocation.status !== row.status) throw unavailable();
      }
    }
    return data;
  } };
}
export async function getCapacitySnapshot(filters: CapacityFilters) {
  const { requireWebUser } = await import('./auth');
  const { ssoWorkshopRead } = await import('./sso-bridge');
  const session = await requireWebUser(CAPACITY_READ_SCOPES);
  const workshopRead = session.sso ? ssoWorkshopRead(session.sso, session.client) : undefined;
  const canManage = ['administrador', 'padr_o'].includes(session.profile.perfil);
  return createCapacityData(session.client, session.sso?.capabilities, workshopRead, canManage).getCapacitySnapshot(filters);
}
