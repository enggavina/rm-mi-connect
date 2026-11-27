-- Run as the database owner on the EM database. Results contain counts only.
begin isolation level repeatable read read only;
set local statement_timeout = '20s';
set local search_path = '';

with protocols as materialized (
  select coalesce(o.client_submission_id,s.submission_id) as submission_id,
    coalesce(o.project_id,s.project_id) as project_id, coalesce(o.equipment_id,s.equipment_id) as equipment_id,
    coalesce(o.operator_id,s.operator_id) as operator_id, coalesce(o.auth_user_id,s.auth_user_id) as auth_user_id,
    o.client_submission_id is not null as has_opening, s.opened_at is not null as scoped_open,
    s.completed_at is not null as scoped_completion, s.workshop_id as confirmed_workshop_id,
    s.submission_id is not null and (o.client_submission_id is null or
       (o.project_id,o.equipment_id,o.operator_id,o.auth_user_id) is not distinct from
       (s.project_id,s.equipment_id,s.operator_id,s.auth_user_id)) as proof_matches
  from rm_private.receiving_openings o
  full join rm_private.receiving_workshop_protocols s on s.submission_id=o.client_submission_id
), evidence as materialized (
  select o.*,
         p.workshop_id, w.code,
         org.workshop_id is not null and r.object_id is null as origin_confirmed,
         e.id is not null and project.equipamento_id=e.id as equipment_confirmed,
         o.proof_matches and o.confirmed_workshop_id=p.workshop_id as scoped_protocol,
         exists (
           select 1 from rm_private.mobile_mutation_receipts receipt
           where receipt.client_submission_id=o.submission_id and receipt.auth_user_id=o.auth_user_id
             and receipt.operator_id=o.operator_id and receipt.rpc_name='rm_submit_recebimento_v1'
             and receipt.result->>'projeto_id'=o.project_id::text and receipt.result->>'equipamento_id'=o.equipment_id::text
             and receipt.result->>'resource_deleted' is distinct from 'true'
         ) as exact_completion
  from protocols o
  join public.rm_projetos project on project.id = o.project_id
  left join rm_private.workshop_project_ownership p on p.id = o.project_id
  left join rm_private.workshop_references w on w.id = p.workshop_id
  left join rm_private.workshop_object_origins org
    on org.object_kind = 'project' and org.object_id = p.id and org.workshop_id = p.workshop_id
  left join rm_private.workshop_origin_retirements r
    on r.object_kind = 'project' and r.object_id = o.project_id
  left join public.rm_equipamentos e on e.id = o.equipment_id and e.projeto_id = o.project_id
), progress as (
  select o.code, count(*) filter (where o.has_opening) as mobile_openings,
    count(*) filter (where o.has_opening and o.scoped_open and o.scoped_protocol and o.origin_confirmed and o.equipment_confirmed) as verified_openings,
    count(*) filter (where o.has_opening and o.scoped_completion and o.scoped_protocol and o.origin_confirmed
      and o.equipment_confirmed and o.exact_completion) as completed_same_protocol,
    count(*) filter (where not o.has_opening and o.scoped_completion and o.scoped_protocol and o.origin_confirmed
      and o.equipment_confirmed and o.exact_completion) as completed_without_opening,
    count(*) filter (where o.scoped_protocol and o.origin_confirmed and exists (
      select 1 from public.rm_celulas_projeto slot
      join rm_private.workshop_cell_ownership cell on cell.cell_id = slot.celula_id
        and cell.workshop_id = o.workshop_id
      where slot.projeto_id = o.project_id and not slot.retirada
        and slot.data_inicio is not null and slot.data_limite >= slot.data_inicio
    )) as with_dated_allocation
  from evidence o group by o.code
)
select jsonb_build_object(
  'transaction_read_only', current_setting('transaction_read_only') = 'on',
  'captured_at', clock_timestamp(),
  'root_guard_active', exists(select 1 from rm_private.workshop_root_enforcement where activated_at is not null),
  'without_confirmed_origin', (select count(*) from evidence where not origin_confirmed),
  'by_workshop', coalesce((select jsonb_agg(to_jsonb(progress) order by code) from progress), '[]'::jsonb)
) report;

commit;
