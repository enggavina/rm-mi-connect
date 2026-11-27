-- Run as the database owner on the EM database. Results contain counts only.
begin isolation level repeatable read read only;
set local statement_timeout = '20s';
set local search_path = '';

with openings as materialized (
  select o.project_id, o.equipment_id, o.operator_id, o.auth_user_id, o.client_submission_id,
         p.workshop_id, w.code,
         org.workshop_id is not null and r.object_id is null as origin_confirmed,
         e.id is not null as equipment_confirmed
  from rm_private.receiving_openings o
  join public.rm_projetos project on project.id = o.project_id
  left join rm_private.workshop_project_ownership p on p.id = o.project_id
  left join rm_private.workshop_references w on w.id = p.workshop_id
  left join rm_private.workshop_object_origins org
    on org.object_kind = 'project' and org.object_id = p.id and org.workshop_id = p.workshop_id
  left join rm_private.workshop_origin_retirements r
    on r.object_kind = 'project' and r.object_id = o.project_id
  left join public.rm_equipamentos e on e.id = o.equipment_id and e.projeto_id = o.project_id
), progress as (
  select o.code, count(*) as mobile_openings,
    count(*) filter (where o.origin_confirmed and o.equipment_confirmed) as verified_openings,
    count(*) filter (where o.origin_confirmed and o.equipment_confirmed and exists (
      select 1 from rm_private.mobile_mutation_receipts receipt
      where receipt.client_submission_id = o.client_submission_id
        and receipt.auth_user_id = o.auth_user_id and receipt.operator_id = o.operator_id
        and receipt.rpc_name = 'rm_submit_recebimento_v1'
        and receipt.result->>'projeto_id' = o.project_id::text
        and receipt.result->>'resource_deleted' is distinct from 'true'
    )) as completed_same_protocol,
    count(*) filter (where o.origin_confirmed and exists (
      select 1 from public.rm_celulas_projeto slot
      join rm_private.workshop_cell_ownership cell on cell.cell_id = slot.celula_id
        and cell.workshop_id = o.workshop_id
      where slot.projeto_id = o.project_id and not slot.retirada
        and slot.data_inicio is not null and slot.data_limite >= slot.data_inicio
    )) as with_dated_allocation
  from openings o group by o.code
)
select jsonb_build_object(
  'transaction_read_only', current_setting('transaction_read_only') = 'on',
  'captured_at', clock_timestamp(),
  'root_guard_active', exists(select 1 from rm_private.workshop_root_enforcement where activated_at is not null),
  'without_confirmed_origin', (select count(*) from openings where not origin_confirmed),
  'by_workshop', coalesce((select jsonb_agg(to_jsonb(progress) order by code) from progress), '[]'::jsonb)
) report;

commit;
