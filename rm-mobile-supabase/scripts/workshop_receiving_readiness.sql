-- Run as the database owner on the EM database. Results contain counts only.
begin isolation level repeatable read read only;
set local statement_timeout = '20s';
set local search_path = '';

with protocols as materialized (
  select coalesce(o.client_submission_id,s.submission_id) as submission_id,
    coalesce(o.project_id,s.project_id) as project_id,
    o.client_submission_id is not null as has_opening, s.submission_id is not null as scoped_protocol
  from rm_private.receiving_openings o
  full join rm_private.receiving_workshop_protocols s on s.submission_id=o.client_submission_id
), evidence as materialized (
  select o.*,
         p.workshop_id, w.code,
         org.workshop_id is not null and r.object_id is null as origin_confirmed,
         proof.creation_phase, proof.completed
  from protocols o
  join public.rm_projetos project on project.id = o.project_id
  left join rm_private.workshop_project_ownership p on p.id = o.project_id
  left join rm_private.workshop_references w on w.id = p.workshop_id
  left join rm_private.workshop_object_origins org
    on org.object_kind = 'project' and org.object_id = p.id and org.workshop_id = p.workshop_id
  left join rm_private.workshop_origin_retirements r
    on r.object_kind = 'project' and r.object_id = o.project_id
  left join rm_private.workshop_receiving_creation_evidence_v1() proof using(submission_id)
), progress as (
  select o.code, count(*) filter (where o.has_opening) as mobile_openings,
    count(*) filter (where o.creation_phase='open') as verified_openings,
    count(*) filter (where o.creation_phase='open' and o.completed) as completed_same_protocol,
    count(*) filter (where o.creation_phase='complete' and o.completed) as completed_without_opening,
    count(*) filter (where o.scoped_protocol and o.creation_phase is null) as scoped_without_proven_creation,
    count(*) filter (where o.creation_phase is not null and exists (
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
  'pilot_receiving_evidence_ready', rm_private.workshop_receiving_pilot_ready_v1(),
  'legacy_only_completion_receipts', (select count(*) from rm_private.mobile_mutation_receipts receipt
    where receipt.rpc_name='rm_submit_recebimento_v1' and not exists(select 1 from rm_private.receiving_workshop_protocols scoped
      where scoped.submission_id=receipt.client_submission_id and scoped.completed_at is not null)),
  'without_confirmed_origin', (select count(*) from evidence where not origin_confirmed),
  'by_workshop', coalesce((select jsonb_agg(to_jsonb(progress) order by code) from progress), '[]'::jsonb)
) report;

commit;
