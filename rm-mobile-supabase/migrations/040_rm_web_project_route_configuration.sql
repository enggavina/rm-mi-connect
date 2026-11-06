-- Per-project route maintenance. Operational evidence is preserved per resource.
-- No data backfill; removed slots/rules/allocations remain recovery tombstones.
begin;

-- A reset of the live decision state must not erase the fact that a legacy
-- rule was used. Existing rows are not rewritten; the first future change
-- seals any evidence in OLD before the mutable status can be cleared.
alter table public.rm_aprovacoes_etapas add column configuracao_utilizada boolean not null default false;
create function rm_private.seal_route_stage_usage_v1() returns trigger
language plpgsql set search_path='' as $$
begin
 new.configuracao_utilizada:=new.configuracao_utilizada
  or(tg_op='UPDATE' and(old.configuracao_utilizada or coalesce(old.status,'nulo')<>'nulo' or old.aprovado_por_id is not null or old.data_aprovacao is not null))
  or coalesce(new.status,'nulo')<>'nulo' or new.aprovado_por_id is not null or new.data_aprovacao is not null;
 return new;
end $$;
revoke all on function rm_private.seal_route_stage_usage_v1() from public,anon,authenticated,service_role;
create trigger rm_guard_route_stage_usage before insert or update on public.rm_aprovacoes_etapas for each row execute function rm_private.seal_route_stage_usage_v1();
do $$ declare d text;needle text;begin
 d:=pg_get_functiondef('rm_private.stage_rule_metadata_v1(uuid)'::regprocedure);
 needle:='   coalesce(r.status,''nulo'')<>''nulo'' or r.aprovado_por_id is not null';
 if strpos(d,needle)=0 then raise exception 'Unexpected stage usage metadata';end if;
 execute replace(d,needle,'   r.configuracao_utilizada or coalesce(r.status,''nulo'')<>''nulo'' or r.aprovado_por_id is not null');
end $$;

create function rm_private.route_cell_form_used_v1(p_project uuid,p_cell uuid,p_form uuid) returns text
language sql stable security definer set search_path='' as $$
 select case
  when exists(select 1 from public.rm_registros_formulario r where r.projeto_id=p_project and r.celula_id=p_cell and r.form_id=p_form)
   then 'Há um registro de formulário iniciado ou respondido nesta célula.'
  when exists(select 1 from public.rm_aprovacoes_registro r where r.projeto_id=p_project and r.celula_id=p_cell and r.form_id=p_form)
   then 'Há histórico de avaliação deste formulário nesta célula.'
  when exists(select 1 from public.rm_respostas_temp d where d.projeto_id=p_project and d.form_id=p_form)
   then 'Há rascunho persistido deste formulário no projeto; o contexto deve ser preservado.'
  else null end;
$$;
revoke all on function rm_private.route_cell_form_used_v1(uuid,uuid,uuid) from public,anon,authenticated,service_role;

create function rm_private.guard_route_cell_forms_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare f uuid;reason text;begin
 if old.forms_ids is not distinct from new.forms_ids then return new;end if;
 perform 1 from public.rm_projetos where id=old.projeto_id for update nowait;
 for f in select x from unnest(old.forms_ids) x where not x=any(coalesce(new.forms_ids,'{}')) loop
  reason:=rm_private.route_cell_form_used_v1(old.projeto_id,old.celula_id,f);
  if reason is not null then raise exception '%',reason using errcode='PT409';end if;
 end loop;
 return new;
exception when lock_not_available then raise exception 'Há trabalho concorrente no projeto. Tente novamente com o mesmo protocolo.' using errcode='PT409';
end $$;
revoke all on function rm_private.guard_route_cell_forms_v1() from public,anon,authenticated,service_role;
create trigger rm_guard_route_cell_forms before update of forms_ids on public.rm_celulas_projeto
 for each row execute function rm_private.guard_route_cell_forms_v1();

create function rm_private.guard_route_form_draft_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare project_id uuid;begin
 for project_id in select distinct x from unnest(case when tg_op='INSERT' then array[new.projeto_id] else array[old.projeto_id,new.projeto_id] end) x where x is not null order by x loop
  perform 1 from public.rm_projetos where id=project_id for update nowait;
 end loop;
 return new;
exception when lock_not_available then raise exception 'A configuração do projeto está sendo alterada. O rascunho deve ser reenviado com o mesmo protocolo.' using errcode='PT409';
end $$;
revoke all on function rm_private.guard_route_form_draft_v1() from public,anon,authenticated,service_role;
create trigger rm_guard_route_form_draft before insert or update on public.rm_respostas_temp for each row execute function rm_private.guard_route_form_draft_v1();

create function rm_private.route_cell_removal_metadata_v1(p_allocation uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare a public.rm_celulas_projeto%rowtype;proof jsonb;result jsonb;begin
 if not rm_private.is_rm_authenticated() then return null;end if;
 select * into a from public.rm_celulas_projeto where id=p_allocation;if not found then return null;end if;
 proof:=rm_private.stage_rule_metadata_v1(a.projeto_id);
 with records as materialized(select * from public.rm_registros_formulario where projeto_id=a.projeto_id and celula_id=a.celula_id),
 drafts as materialized(select * from public.rm_respostas_temp d where(d.projeto_id=a.projeto_id and d.form_id=any(a.forms_ids)) or d.registro_formulario_id in(select id from records)),
 photos as materialized(select * from public.rm_fotos f where f.celula_projeto_id=a.id or(f.projeto_id=a.projeto_id and f.celula_id=a.celula_id)),
 rules as materialized(select * from public.rm_aprovacoes_etapas s where s.celula_projeto_id=a.id or(s.projeto_id=a.projeto_id and(s.celula_origem_id=a.celula_id or s.celula_destino_id=a.celula_id))),
 families as materialized(select distinct family.value::uuid id from jsonb_array_elements(coalesce(proof->'items','[]')) m cross join lateral jsonb_array_elements_text(m->'family_ids') family(value)
  where m->>'id' in(select id::text from rules)),
 comments as materialized(select * from public.rm_comentarios where projeto_id=a.projeto_id and celula_id=a.celula_id),
 logs as materialized(select * from public.rm_logs_aprovacao where projeto_id=a.projeto_id and celula_id=a.celula_id),
 reviews as materialized(select * from public.rm_aprovacoes_registro where(projeto_id=a.projeto_id and celula_id=a.celula_id) or registro_formulario_id in(select id from records)),
 mobile as materialized(select m.client_submission_id,m.created_at from rm_private.mobile_mutation_receipts m
  where m.rpc_name in('rm_submit_form_inspection_v1','rm_submit_form_revision_v1','rm_record_cell_photo_v1','rm_update_cell_status_v1','rm_add_cell_comment_v1','rm_transition_stage_approval_v1') and(
   lower(m.params->>'p_celula_projeto_id')=a.id::text or m.result->>'celula_projeto_id'=a.id::text
   or(lower(m.params->>'p_projeto_id')=a.projeto_id::text and lower(m.params->>'p_celula_id')=a.celula_id::text)
   or(m.result->>'projeto_id'=a.projeto_id::text and m.result->>'celula_id'=a.celula_id::text)
   or lower(m.params->>'p_registro_formulario_id') in(select id::text from records) or m.result->>'registro_formulario_id' in(select id::text from records)
   or lower(m.params->>'p_foto_id') in(select id::text from photos) or m.result->>'foto_id' in(select id::text from photos)
   or lower(m.params->>'p_aprovacao_etapa_id') in(select id::text from rules) or m.result->>'aprovacao_etapa_id' in(select id::text from rules))),
 jobs as materialized(select o.id,o.created_at,o.status from public.rm_sync_outbox o where o.entity_type in('Celula_Projeto_Status','Comentario_Celula','Registro_Formulario_Bundle','Registro_Formulario_Revision','Aprovacao_Etapa_Transition','Fotos_RM_Sync') and(
   o.record_id=a.id or o.record_id in(select id from records) or o.record_id in(select id from rules) or o.record_id in(select id from photos)
   or o.payload->>'foto_id' in(select id::text from photos) or o.payload->>'celula_projeto_id'=a.id::text
   or(o.payload->>'projeto_id'=a.projeto_id::text and o.payload->>'celula_id'=a.celula_id::text)
   or(o.payload->>'projeto_id'=a.projeto_id::text and o.entity_type like 'Registro_Formulario%' and o.payload->>'form_id'=any(array(select x::text from unnest(a.forms_ids) x))))),
 evidence as(select case
  when a.retirada then 'A célula já foi retirada do roteiro.'
  when a.status<>'pendente' or exists(select 1 from unnest(a.status_historico) s where s is distinct from 'pendente'::public.rm_status_cel_proj_enum)
   or coalesce(a.horas_realizadas,0)<>0 or a.data_fim_real is not null then 'Há evidência de execução nesta célula.'
  when exists(select 1 from records) then 'Há registros de formulário iniciados ou respondidos nesta célula.'
  when exists(select 1 from drafts) then 'Há rascunhos persistidos compatíveis com os formulários desta célula.'
  when exists(select 1 from photos f where f.projeto_id is distinct from a.projeto_id or f.celula_id is distinct from a.celula_id or(f.celula_projeto_id is not null and f.celula_projeto_id<>a.id)) then 'Há vínculos de foto divergentes que exigem reconciliação.'
  when exists(select 1 from photos f where nullif(btrim(f.foto_url),'') is not null or f.selecao_relatorio or exists(select 1 from unnest(f.fotos_arquivos_urls) u where nullif(btrim(u),'') is not null)) then 'Há fotos registradas ou selecionadas para relatório nesta célula.'
  when exists(select 1 from comments) or exists(select 1 from logs) then 'Há comentários ou histórico operacional desta célula.'
  when exists(select 1 from reviews) then 'Há histórico de avaliação de formulário relacionado à célula.'
  when(select count(*) from public.rm_aprovacoes_etapas where projeto_id=a.projeto_id)>1000 or(select count(*) from photos)>2000 then 'O conjunto excede o limite de conferência completa.'
  when exists(select 1 from rules s where s.projeto_id is distinct from a.projeto_id or(s.celula_projeto_id=a.id and s.celula_origem_id is distinct from a.celula_id)) then 'Há vínculos de aprovação divergentes que exigem reconciliação.'
  when exists(select 1 from jsonb_array_elements(coalesce(proof->'items','[]')) m where(m->>'id')::uuid in(select id from families) and(coalesce((m->>'used')::boolean,true) or coalesce((m->>'history_ambiguous')::boolean,true)))
   or exists(select 1 from rules where status_cel_proj='retornado') then 'Há aprovação executada ou histórico de aprovação que deve ser preservado.'
  when exists(select 1 from rules s join public.rm_celulas_projeto x on x.projeto_id=s.projeto_id and x.retirada and(x.celula_id=s.celula_origem_id or x.celula_id=s.celula_destino_id) where s.ativo) then 'Uma regra ativa aponta para outra alocação retirada; revise as regras antes de remover.'
  when exists(select 1 from mobile) or exists(select 1 from jobs) then 'Há recibos ou eventos de execução relacionados a esta célula.'
  else null end reason)
 select jsonb_build_object('remove_reason',e.reason,'photo_count',(select count(*) from photos where not lixeira),
  'rule_count',(select count(*) from rules where ativo),'reviewer_count',(select count(*) from public.rm_form_reviewer_assignments where celula_projeto_id=a.id),
  'fingerprint',encode(sha256(convert_to(jsonb_build_object(
   'records',coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from records),'[]'),
   'drafts',coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from drafts),'[]'),
   'photos',coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from photos),'[]'),
   'rules',coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from rules),'[]'),
   'comments',coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from comments),'[]'),
   'logs',coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from logs),'[]'),
   'reviews',coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from reviews),'[]'),
   'mobile',coalesce((select jsonb_agg(jsonb_build_object('id',client_submission_id,'at',created_at) order by client_submission_id) from mobile),'[]'),
   'jobs',coalesce((select jsonb_agg(jsonb_build_object('id',id,'at',created_at,'status',status) order by id) from jobs),'[]'),
   'reviewers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from public.rm_form_reviewer_assignments where celula_projeto_id=a.id),'[]'),
   'stage_proof',proof->>'version','reason',e.reason)::text,'UTF8')),'hex')) into result from evidence e;
 return result;
end $$;
revoke all on function rm_private.route_cell_removal_metadata_v1(uuid) from public,anon,authenticated,service_role;

create function public.rm_web_project_route_cell_snapshot_v1(p_project_id uuid,p_allocation_id uuid,p_include_choices boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.rm_projetos%rowtype;a public.rm_celulas_projeto%rowtype;closed boolean;metadata jsonb;form_rows jsonb;catalog_total int;complete boolean;form_reason text;version text;begin
 if not rm_private.can_read_project_dossier_v1() then raise exception 'Consulta restrita à equipe interna.' using errcode='42501';end if;
 select * into p from public.rm_projetos where id=p_project_id;if not found then return null;end if;
 select * into a from public.rm_celulas_projeto where id=p_allocation_id and projeto_id=p.id;if not found then return null;end if;
 closed:=p.data_real_de_entrega is not null or coalesce(p.status_pcp in('cancelado','finalizando_para_faturar'),false);
 metadata:=rm_private.route_cell_removal_metadata_v1(a.id);
 select count(*) into catalog_total from public.rm_forms f where f.ativo or f.id=any(a.forms_ids);
 complete:=catalog_total<=2000 and cardinality(a.forms_ids)<=2000 and not exists(select 1 from unnest(a.forms_ids) x where not exists(select 1 from public.rm_forms f where f.id=x));
 form_reason:=case when closed then 'Projeto encerrado: somente consulta.' when a.retirada then 'Célula retirada: restaure o contexto antes de configurar.' when a.status in('finalizado','n_a') then 'Célula concluída ou N/A: somente consulta.'
  when exists(select 1 from unnest(a.forms_ids) x where not exists(select 1 from public.rm_forms f where f.id=x)) then 'Há vínculo de formulário indisponível que exige reconciliação.'
  when not complete or cardinality(a.forms_ids)>500 then 'O conjunto excede o limite de edição completa.' else null end;
 select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'titulo',coalesce(f.titulo,f.title),'ativo',f.ativo,'assigned',f.id=any(a.forms_ids),
  'can_remove',f.id=any(a.forms_ids) and rm_private.route_cell_form_used_v1(p.id,a.celula_id,f.id) is null,
  'reason',case when f.id=any(a.forms_ids) then rm_private.route_cell_form_used_v1(p.id,a.celula_id,f.id) end) order by coalesce(f.titulo,f.title),f.id),'[]') into form_rows
 from public.rm_forms f where complete and(f.id=any(a.forms_ids) or(p_include_choices and f.ativo));
 version:=encode(sha256(convert_to(jsonb_build_object('project',p.id,'project_version',p.updated_at,'allocation',to_jsonb(a),
  'evidence',metadata->>'fingerprint','catalog',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'updated_at',f.updated_at) order by f.id) from public.rm_forms f where f.ativo or f.id=any(a.forms_ids)),'[]'))::text,'UTF8')),'hex');
 return jsonb_build_object('project',jsonb_build_object('id',p.id,'numero',p.numero,'status_pcp',p.status_pcp,'data_real_de_entrega',p.data_real_de_entrega,'updated_at',p.updated_at,'closed',closed),
  'allocation',jsonb_build_object('id',a.id,'projeto_id',p.id,'celula_id',a.celula_id,'celula_nome',(select nome from public.rm_celulas where id=a.celula_id),'status',a.status,'retirada',a.retirada,'updated_at',a.updated_at,'forms_ids',a.forms_ids),
  'forms',form_rows,'context_version',version,'can_edit_forms',form_reason is null,'forms_reason',form_reason,
  'can_remove_cell',not closed and complete and metadata is not null and metadata->>'remove_reason' is null,'remove_reason',case when closed then 'Projeto encerrado: somente consulta.' when not complete then coalesce(form_reason,'O conjunto exige conferência completa antes de remover.') else metadata->>'remove_reason' end,
  'removal_counts',jsonb_build_object('photos',(metadata->>'photo_count')::int,'rules',(metadata->>'rule_count')::int,'reviewer_assignments',(metadata->>'reviewer_count')::int),'complete',complete);
end $$;
revoke all on function public.rm_web_project_route_cell_snapshot_v1(uuid,uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_project_route_cell_snapshot_v1(uuid,uuid,boolean) to authenticated;

create or replace function public.rm_web_project_route_snapshot_v1(p_project_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 with route as materialized(
  select a.*,c.nome celula_nome,c.updated_at cell_updated_at from public.rm_celulas_projeto a left join public.rm_celulas c on c.id=a.celula_id where a.projeto_id=p_project_id and not a.retirada
 ),proof as materialized(select rm_private.stage_rule_metadata_v1(p_project_id) v),
 protected_cells as materialized(
  select distinct unnest(array[s.celula_origem_id,s.celula_destino_id]) id from public.rm_aprovacoes_etapas s cross join proof p where s.projeto_id=p_project_id
   and((select count(*) from public.rm_aprovacoes_etapas where projeto_id=p_project_id)>1000 or exists(select 1 from jsonb_array_elements(coalesce(p.v->'items','[]')) m where m->>'id'=s.id::text and(coalesce((m->>'used')::boolean,true) or coalesce((m->>'history_ambiguous')::boolean,true))))
 ),aggregate as(
  select count(*) total,
   coalesce(jsonb_agg(jsonb_build_object('id',a.id,'updated_at',a.updated_at,'indice',a.indice,'celula_id',a.celula_id,'cell_updated_at',a.cell_updated_at) order by a.indice nulls last,a.id),'[]') revisions,
   coalesce(jsonb_agg(jsonb_build_object('id',a.id,'celula_id',a.celula_id,'celula_nome',a.celula_nome,'status',a.status,'visibilidade',a.visibilidade,'indice',a.indice,'updated_at',a.updated_at,
    'can_reorder',not exists(select 1 from protected_cells x where x.id=a.celula_id),'reorder_reason',case when exists(select 1 from protected_cells x where x.id=a.celula_id) then 'Há aprovação executada ou histórico operacional relacionado. A posição deve ser preservada.' end) order by a.indice nulls last,a.id),'[]') items from route a
 ),project as(
  select p.id,p.updated_at,jsonb_build_object('id',p.id,'numero',p.numero,'nome',p.nome,'status_pcp',p.status_pcp,'data_real_de_entrega',p.data_real_de_entrega,'updated_at',p.updated_at,
   'closed',p.data_real_de_entrega is not null or coalesce(p.status_pcp in('cancelado','finalizando_para_faturar'),false)) dto from public.rm_projetos p where p.id=p_project_id
 ) select jsonb_build_object('initialized_from_type',coalesce((rm_private.project_route_state_v1(p.id)->>'initialized_from_type')::boolean,false),'source_type_id',rm_private.project_route_state_v1(p.id)->'source_type_id',
  'project',p.dto,'total',a.total,'complete',a.total<=2000,'items',case when a.total<=2000 then a.items else '[]'::jsonb end,
  'route_version',encode(sha256(convert_to(jsonb_build_object('project',p.dto,'revisions',a.revisions,'stage_proof',proof.v->>'version')::text,'UTF8')),'hex'))
 from project p cross join aggregate a cross join proof;
$$;

-- Resource-specific guards also cover direct import writes. A capture or a
-- decision never freezes unrelated forms or other unused configuration.
create function rm_private.guard_used_route_photo_config_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare used boolean;begin
 if old.projeto_id is null then return case when tg_op='DELETE' then old else new end;end if;
 if tg_op='DELETE' and rm_private.project_deletion_in_progress_v1(old.projeto_id) then return old;end if;
 used:=nullif(btrim(old.foto_url),'') is not null or old.selecao_relatorio or exists(select 1 from unnest(old.fotos_arquivos_urls) x where nullif(btrim(x),'') is not null);
 if tg_op='UPDATE' and(nullif(btrim(old.foto_url),'') is not null or exists(select 1 from unnest(old.fotos_arquivos_urls) x where nullif(btrim(x),'') is not null))
  and nullif(btrim(new.foto_url),'') is null and not exists(select 1 from unnest(new.fotos_arquivos_urls) x where nullif(btrim(x),'') is not null) then
  raise exception 'O arquivo registrado não pode ser apagado para liberar a configuração da foto.' using errcode='PT409';end if;
 if used and(tg_op='DELETE' or(to_jsonb(new)-array['foto_url','fotos_arquivos_urls','legenda','tag','selecao_relatorio','created_by_user_id','modified_by_id','updated_at','bubble_id','bubble_modified_at','sync_source'])
  is distinct from(to_jsonb(old)-array['foto_url','fotos_arquivos_urls','legenda','tag','selecao_relatorio','created_by_user_id','modified_by_id','updated_at','bubble_id','bubble_modified_at','sync_source'])) then
  raise exception 'A foto já foi registrada ou selecionada. Sua configuração deve ser preservada.' using errcode='PT409';end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
revoke all on function rm_private.guard_used_route_photo_config_v1() from public,anon,authenticated,service_role;
create trigger rm_guard_used_route_photo_config before update or delete on public.rm_fotos for each row execute function rm_private.guard_used_route_photo_config_v1();

create function rm_private.guard_used_route_stage_state_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare proof jsonb;begin
 if old.projeto_id is null then return case when tg_op='DELETE' then old else new end;end if;
 if tg_op='DELETE' then
  if rm_private.project_deletion_in_progress_v1(old.projeto_id) then return old;end if;
  raise exception 'A regra preserva sua identidade. Retire a configuração não utilizada pelo roteiro.' using errcode='PT409';end if;
 if new.ativo is not distinct from old.ativo then return new;end if;
 proof:=rm_private.stage_rule_metadata_v1(old.projeto_id);
 if(select count(*) from public.rm_aprovacoes_etapas where projeto_id=old.projeto_id)>1000 or old.configuracao_utilizada or old.status is distinct from 'nulo'::public.rm_status_etapa_enum or old.aprovado_por_id is not null or old.data_aprovacao is not null
  or exists(select 1 from jsonb_array_elements(coalesce(proof->'items','[]')) m where(m->>'id'=old.id::text or m->'family_ids'?old.id::text) and(coalesce((m->>'used')::boolean,true) or coalesce((m->>'history_ambiguous')::boolean,true))) then
  raise exception 'A regra possui decisão ou histórico operacional. Sua configuração deve ser preservada.' using errcode='PT409';end if;
 return new;
end $$;
revoke all on function rm_private.guard_used_route_stage_state_v1() from public,anon,authenticated,service_role;
create trigger rm_guard_used_route_stage_state before update of ativo or delete on public.rm_aprovacoes_etapas for each row execute function rm_private.guard_used_route_stage_state_v1();

-- Extend the existing photo DTO; replacement keeps the old UUID retired so an
-- offline capture can never be silently attached to a different configuration.
do $$ declare d text;needle text;begin
 d:=pg_get_functiondef('public.rm_web_operational_photos_snapshot_v1(uuid,uuid,boolean)'::regprocedure);
 needle:='''categoria_foto'',f.categoria_foto,''tag'',f.tag,''numero'',f.numero,''updated_at'',f.updated_at,';
 if strpos(d,needle)=0 then raise exception 'Unexpected operational photo DTO';end if;
 d:=replace(d,needle,'''categoria_foto'',f.categoria_foto,''tag'',f.tag,''numero'',f.numero,''descricao'',f.descricao,''updated_at'',f.updated_at,
   ''can_replace'',not c.closed and not c.retirada and not coalesce(c.status in(''finalizado'',''n_a''),false) and coalesce(f.categoria_foto=''obrigat_ria'',false) and not f.lixeira and not f.captured and not f.selecao_relatorio,
   ''replace_reason'',case when f.captured or f.selecao_relatorio then ''Foto já registrada ou selecionada: a configuração utilizada deve ser preservada.'' when f.lixeira then ''Item retirado: restaure o mesmo item quando permitido.'' else null end,');
 execute d;
end $$;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_before_route_config_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype;receipt rm_private.web_mutation_receipts%rowtype;p public.rm_projetos%rowtype;a public.rm_celulas_projeto%rowtype;
 f public.rm_fotos%rowtype;title public.rm_cadastro_fotos%rowtype;snapshot jsonb;before_record jsonb;result jsonb;inner_result jsonb;
 project_id uuid;allocation_id uuid;action text;forms uuid[];removed_forms uuid[];photo_ids uuid[];rule_ids uuid[];old_id uuid;new_id uuid;title_id uuid;
 expected_project timestamptz;expected_allocation timestamptz;expected_photo timestamptz;allowed text[];item jsonb;proof jsonb;ordinal bigint;
begin
 if p_operation='save_project_route' and not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id) then
  select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
  if actor.id is null or not coalesce(actor.perfil in('administrador','padr_o'),false) then raise exception 'Operação restrita ao planejamento.' using errcode='42501';end if;
  if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified') and(auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501';end if;
  if p_client_submission_id is null or jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'Envio inválido.' using errcode='22023';end if;
  perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
  if exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id) then return rm_private.web_mutate_before_route_config_v1(p_client_submission_id,p_operation,p_payload);end if;
  -- A decision's source/destination positions are fixed, while unused segments
  -- can still be reordered. The lower command performs all normal authorization,
  -- payload and receipt checks; this precondition does not grant any write.
  project_id:=(p_payload->>'projeto_id')::uuid;
  perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
  perform 1 from public.rm_projetos where id=project_id for update;
  perform 1 from public.rm_celulas_projeto where projeto_id=project_id order by id for update;
  if jsonb_typeof(p_payload->'items')='array' then
   proof:=rm_private.stage_rule_metadata_v1(project_id);
   if exists(with current_order as(select x.id,x.celula_id,row_number() over(order by x.indice nulls last,x.id) n from public.rm_celulas_projeto x where x.projeto_id=project_id and not x.retirada),
    proposed as(select(x->>'id')::uuid id,n from jsonb_array_elements(p_payload->'items') with ordinality t(x,n)),
    used_rules as(select s.* from public.rm_aprovacoes_etapas s where s.projeto_id=project_id and(exists(select 1 from jsonb_array_elements(coalesce(proof->'items','[]')) m where m->>'id'=s.id::text and(coalesce((m->>'used')::boolean,true) or coalesce((m->>'history_ambiguous')::boolean,true)))
     or(select count(*) from public.rm_aprovacoes_etapas z where z.projeto_id=project_id)>1000))
    select 1 from current_order c join proposed n on n.id=c.id where c.n<>n.n and exists(select 1 from used_rules s where s.celula_origem_id=c.celula_id or s.celula_destino_id=c.celula_id)) then
    raise exception 'A posição de uma célula com aprovação executada deve ser preservada. Reordene apenas as células não utilizadas.' using errcode='PT409';end if;
  end if;
 end if;
 if p_operation is distinct from 'manage_project_route_cell' and not coalesce(p_operation='manage_operational_photos' and p_payload->>'action'='replace',false) then
  return rm_private.web_mutate_before_route_config_v1(p_client_submission_id,p_operation,p_payload);
 end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or not coalesce(actor.perfil in('administrador','padr_o'),false) then raise exception 'Operação restrita ao planejamento.' using errcode='42501';end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified') and(auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501';end if;
 if p_client_submission_id is null or jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'Envio inválido.' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.result->>'resource_deleted'='true' then return rm_private.web_mutate_before_route_config_v1(p_client_submission_id,p_operation,p_payload);end if;
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then raise exception 'Protocolo já utilizado com outros dados.' using errcode='23505';end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 action:=p_payload->>'action';
 allowed:=array['action','projeto_id','celula_projeto_id','expected_project_updated_at','expected_allocation_updated_at','confirm_change'];
 if p_operation='manage_project_route_cell' then
  allowed:=allowed||array['expected_context_version'];
  if action='forms' then allowed:=allowed||array['forms_ids'];elsif action is distinct from 'remove' then raise exception 'Ação de roteiro inválida.' using errcode='22023';end if;
 else
  allowed:=allowed||array['expected_photos_version','foto_id','expected_foto_updated_at','new_id','cadastro_foto_id','numero','descricao','tag'];
 end if;
 if not p_payload ?& allowed or exists(select 1 from jsonb_object_keys(p_payload) k where not k=any(allowed))
  or p_payload->'confirm_change' is distinct from 'true'::jsonb
  or exists(select 1 from unnest(array['action','projeto_id','celula_projeto_id','expected_project_updated_at','expected_allocation_updated_at']) k where jsonb_typeof(p_payload->k) is distinct from 'string')
  or p_payload->>'expected_project_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
  or p_payload->>'expected_allocation_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
  then raise exception 'Confirmação, campos ou versões inválidos.' using errcode='22023';end if;
 project_id:=(p_payload->>'projeto_id')::uuid;allocation_id:=(p_payload->>'celula_projeto_id')::uuid;
 expected_project:=(p_payload->>'expected_project_updated_at')::timestamptz;expected_allocation:=(p_payload->>'expected_allocation_updated_at')::timestamptz;
 perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
 select * into p from public.rm_projetos where id=project_id for update;if not found then raise exception 'Projeto não encontrado.' using errcode='P0002';end if;
 perform 1 from public.rm_celulas_projeto where projeto_id=project_id order by id for update;
 select * into a from public.rm_celulas_projeto where id=allocation_id and projeto_id=project_id;if not found then raise exception 'Alocação não encontrada.' using errcode='P0002';end if;
 if p.updated_at<>expected_project or a.updated_at<>expected_allocation then raise exception 'Projeto ou alocação alterados. Recarregue.' using errcode='PT409';end if;
 if p_operation='manage_project_route_cell' then
  if jsonb_typeof(p_payload->'expected_context_version') is distinct from 'string' or p_payload->>'expected_context_version' !~ '^[a-f0-9]{64}$' then raise exception 'Contexto inválido.' using errcode='22023';end if;
  snapshot:=public.rm_web_project_route_cell_snapshot_v1(project_id,allocation_id,true);
  if snapshot->>'context_version' is distinct from p_payload->>'expected_context_version' then raise exception 'Configurações ou evidências alteradas. Recarregue.' using errcode='PT409';end if;
  if action='forms' then
   if not(snapshot->>'can_edit_forms')::boolean then raise exception '%',snapshot->>'forms_reason' using errcode='22023';end if;
   if jsonb_typeof(p_payload->'forms_ids') is distinct from 'array' or jsonb_array_length(p_payload->'forms_ids')>500 then raise exception 'Lista de formulários inválida.' using errcode='22023';end if;
   forms:=array(select jsonb_array_elements_text(p_payload->'forms_ids'))::uuid[];
   if exists(select 1 from unnest(forms) x group by x having count(*)>1) or exists(select 1 from unnest(forms) x where x is null) then raise exception 'Formulários repetidos ou inválidos.' using errcode='22023';end if;
   select coalesce(array_agg(x),'{}') into removed_forms from unnest(a.forms_ids) x where not x=any(forms);
   inner_result:=rm_private.web_mutate_before_route_config_v1(gen_random_uuid(),'plan_cell',jsonb_build_object('projeto_id',project_id,'celula_id',a.celula_id,'expected_updated_at',a.updated_at,'changes',jsonb_build_object('forms_ids',forms)));
   delete from public.rm_form_reviewer_assignments where celula_projeto_id=a.id and form_id=any(removed_forms);
  else
   if not(snapshot->>'can_remove_cell')::boolean then raise exception '%',snapshot->>'remove_reason' using errcode='PT409';end if;
   perform 1 from public.rm_fotos where celula_projeto_id=a.id or(projeto_id=p.id and celula_id=a.celula_id) order by id for update;
   perform 1 from public.rm_aprovacoes_etapas where projeto_id=p.id order by id for update;
   -- The project row lock excludes every supported capture/response/decision.
   -- Direct technical child writes use the inherited NOWAIT parent guard.
   snapshot:=public.rm_web_project_route_cell_snapshot_v1(project_id,allocation_id,true);
   if snapshot->>'context_version' is distinct from p_payload->>'expected_context_version' or not(snapshot->>'can_remove_cell')::boolean then raise exception 'As evidências da célula mudaram.' using errcode='PT409';end if;
   before_record:=jsonb_build_object('allocation',to_jsonb(a),'photos',coalesce((select jsonb_agg(jsonb_build_object('id',id,'lixeira',lixeira) order by id) from public.rm_fotos where celula_projeto_id=a.id or(projeto_id=p.id and celula_id=a.celula_id)),'[]'),
    'rules',coalesce((select jsonb_agg(jsonb_build_object('id',id,'ativo',ativo) order by id) from public.rm_aprovacoes_etapas where projeto_id=p.id and(celula_projeto_id=a.id or celula_origem_id=a.celula_id or celula_destino_id=a.celula_id)),'[]'));
   with changed as(update public.rm_fotos set lixeira=true,modified_by_id=actor.id,sync_source='supabase' where not lixeira and(celula_projeto_id=a.id or(projeto_id=p.id and celula_id=a.celula_id)) returning id)
    select coalesce(array_agg(id),'{}') into photo_ids from changed;
   with changed as(update public.rm_aprovacoes_etapas set ativo=false,sync_source='supabase' where ativo and projeto_id=p.id and(celula_projeto_id=a.id or celula_origem_id=a.celula_id or celula_destino_id=a.celula_id) returning id)
    select coalesce(array_agg(id),'{}') into rule_ids from changed;
   insert into rm_private.stage_rule_events(projeto_id,etapa_id,actor_id,action,client_submission_id) select p.id,x,actor.id,'retire',p_client_submission_id from unnest(rule_ids) x;
   delete from public.rm_form_reviewer_assignments where celula_projeto_id=a.id;
   insert into rm_private.cell_availability_events(projeto_id,celula_projeto_id,actor_id,action,old_visibility,new_visibility,old_retired,new_retired,allocation_version,client_submission_id)
    values(p.id,a.id,actor.id,'retire',a.visibilidade,false,a.retirada,true,a.updated_at,p_client_submission_id);
   update public.rm_celulas_projeto set forms_ids='{}',visibilidade=false,retirada=true,modified_by_id=actor.id,sync_source='supabase' where id=a.id;
  end if;
  select * into a from public.rm_celulas_projeto where id=allocation_id;
  snapshot:=public.rm_web_project_route_cell_snapshot_v1(project_id,allocation_id,true);
  result:=jsonb_build_object('operation',p_operation,'id',a.id,'projeto_id',p.id,'updated_at',a.updated_at,'idempotent_replay',false,
   'record',jsonb_build_object('projeto_id',p.id,'celula_projeto_id',a.id,'action',action,'context_version',snapshot->>'context_version','changed_ids',jsonb_build_array(a.id),'retirada',a.retirada,'forms_ids',a.forms_ids,
    'retired_photo_ids',coalesce(to_jsonb(photo_ids),'[]'),'retired_rule_ids',coalesce(to_jsonb(rule_ids),'[]')));
 else
  if jsonb_typeof(p_payload->'expected_photos_version') is distinct from 'string' or p_payload->>'expected_photos_version' !~ '^[a-f0-9]{64}$'
   or jsonb_typeof(p_payload->'numero') is distinct from 'number' or(p_payload->>'numero') !~ '^[0-9]+$'
   or jsonb_typeof(p_payload->'descricao') not in('string','null') or length(p_payload->>'descricao')>4000
   or jsonb_typeof(p_payload->'tag') not in('string','null') or length(p_payload->>'tag')>2000 then raise exception 'Configuração de foto inválida.' using errcode='22023';end if;
  old_id:=(p_payload->>'foto_id')::uuid;new_id:=(p_payload->>'new_id')::uuid;title_id:=(p_payload->>'cadastro_foto_id')::uuid;ordinal:=(p_payload->>'numero')::bigint;
  if old_id is null or new_id is null or title_id is null or new_id=old_id or ordinal<1 or ordinal>1000000 then raise exception 'Identificador ou ordem de foto inválido.' using errcode='22023';end if;
  expected_photo:=(p_payload->>'expected_foto_updated_at')::timestamptz;
  perform pg_advisory_xact_lock_shared(hashtextextended('rm.web.catalogs',17));
  perform 1 from public.rm_cadastro_fotos where id=title_id for share;
  perform 1 from public.rm_fotos where projeto_id=p.id and celula_id=a.celula_id and(celula_projeto_id=a.id or celula_projeto_id is null) order by id for update;
  snapshot:=public.rm_web_operational_photos_snapshot_v1(p.id,a.id,true);
  if snapshot->>'photos_version' is distinct from p_payload->>'expected_photos_version' then raise exception 'As fotos ou títulos mudaram. Recarregue.' using errcode='PT409';end if;
  if not(snapshot->>'complete')::boolean or not(snapshot->>'titles_complete')::boolean or(snapshot->>'total')::int>=2000 then raise exception 'O conjunto excede o limite de edição completa.' using errcode='22023';end if;
  select * into f from public.rm_fotos where id=old_id and projeto_id=p.id and celula_id=a.celula_id and(celula_projeto_id=a.id or celula_projeto_id is null);
  if not found then raise exception 'Foto não pertence à alocação.' using errcode='22023';end if;
  if f.updated_at<>expected_photo then raise exception 'A foto mudou. Recarregue.' using errcode='PT409';end if;
  select x into item from jsonb_array_elements(snapshot->'photos') x where x->>'id'=old_id::text;
  if not coalesce((item->>'can_replace')::boolean,false) then raise exception 'Foto registrada, selecionada, retirada ou contexto encerrado: configuração preservada.' using errcode='PT409';end if;
  if exists(select 1 from public.rm_fotos where id=new_id) then raise exception 'UUID da nova foto já utilizado.' using errcode='22023';end if;
  if not exists(select 1 from jsonb_array_elements(snapshot->'titles') x where x->>'id'=title_id::text) then raise exception 'Título não é aplicável à célula.' using errcode='22023';end if;
  select * into title from public.rm_cadastro_fotos where id=title_id;
  if exists(select 1 from public.rm_fotos x where x.id<>old_id and x.projeto_id=p.id and x.celula_id=a.celula_id and not x.lixeira and(x.celula_projeto_id=a.id or x.celula_projeto_id is null) and x.categoria_foto='obrigat_ria'
   and(x.cadastro_foto_id=title_id or lower(btrim(regexp_replace(x.titulo,'[[:space:]]+',' ','g')))=lower(btrim(regexp_replace(title.titulo,'[[:space:]]+',' ','g'))))) then raise exception 'Título já atribuído a outro item ativo.' using errcode='22023';end if;
  before_record:=snapshot;
  update public.rm_fotos set lixeira=true,modified_by_id=actor.id,sync_source='supabase' where id=old_id;
  insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,cadastro_foto_id,categoria_foto,titulo,numero,descricao,tag,created_by_user_id,modified_by_id,sync_source)
   values(new_id,p.id,a.celula_id,a.id,title_id,'obrigat_ria',title.titulo,ordinal::int,p_payload->>'descricao',p_payload->>'tag',actor.id,actor.id,'supabase');
  snapshot:=public.rm_web_operational_photos_snapshot_v1(p.id,a.id,true);
  result:=jsonb_build_object('operation',p_operation,'id',a.id,'projeto_id',p.id,'updated_at',clock_timestamp(),'idempotent_replay',false,
   'record',jsonb_build_object('projeto_id',p.id,'celula_projeto_id',a.id,'action','replace','photos_version',snapshot->>'photos_version','changed_ids',jsonb_build_array(old_id,new_id)));
 end if;
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,before_record);
 return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
 if p_operation='manage_project_route_cell' or(p_operation='manage_operational_photos' and p_payload->>'action'='replace') then raise exception 'Identificador, data ou configuração inválida.' using errcode='22023';end if;raise;
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_before_route_config_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;

-- Projected events come from the same receipts; no duplicate audit store.
do $$ declare d text;needle text;events text;begin
 d:=pg_get_functiondef('rm_private.project_audit_events_v1(uuid,text,text[])'::regprocedure);
 needle:='''manage_operational_photos'',''manage_stage_rules'',''assign_form_reviewer'')';
 if strpos(d,needle)=0 then raise exception 'Unexpected project audit source';end if;
 d:=replace(d,needle,'''manage_operational_photos'',''manage_stage_rules'',''assign_form_reviewer'',''manage_project_route_cell'')');
 needle:=' ) select ''audit:''||';
 if strpos(d,needle)=0 then raise exception 'Unexpected project audit event envelope';end if;
 events:=$events$
  union all
  select 'web:'||w.client_submission_id||':route-cell','cells','allocation_retire',a.id,a.celula_id,a.id,w.actor_id,w.created_at,'web',true,
   rm_private.project_audit_changes_v1(w.before_record->'allocation',w.result->'record',array['retirada','forms_ids']),null
  from web w join public.rm_celulas_projeto a on a.id::text=w.payload->>'celula_projeto_id' and a.projeto_id=p_project_id
  where w.operation='manage_project_route_cell' and w.payload->>'action'='remove' and p_kind='cells'
  union all
  select 'web:'||w.client_submission_id||':route-form-links','forms','form_links_changed',a.id,a.celula_id,a.id,w.actor_id,w.created_at,'web',true,
   rm_private.project_audit_changes_v1(w.before_record->'allocation',w.result->'record',array['forms_ids']),null
  from web w join public.rm_celulas_projeto a on a.id::text=w.payload->>'celula_projeto_id' and a.projeto_id=p_project_id
  where w.operation='manage_project_route_cell' and w.payload->>'action'='remove' and p_kind='operations' and 'forms'=any(p_topics)
  union all
  select 'web:'||w.client_submission_id||':route-photo:'||f.id,'photos','photo_retire',f.id,f.celula_id,f.celula_projeto_id,w.actor_id,w.created_at,'web',true,
   rm_private.project_audit_changes_v1(old_photo.value,jsonb_build_object('lixeira',true),array['lixeira']),null
  from web w cross join lateral jsonb_array_elements(w.before_record->'photos') old_photo
   join public.rm_fotos f on f.id::text=old_photo.value->>'id' and f.projeto_id=p_project_id
  where w.operation='manage_project_route_cell' and w.payload->>'action'='remove' and w.result->'record'->'retired_photo_ids'?f.id::text and p_kind='operations' and 'photos'=any(p_topics)
  union all
  select 'web:'||w.client_submission_id||':route-rule:'||s.id,'approvals','stage_rule_retire',s.id,s.celula_origem_id,s.celula_projeto_id,w.actor_id,w.created_at,'web',true,
   rm_private.project_audit_changes_v1(old_rule.value,jsonb_build_object('ativo',false),array['ativo']),null
  from web w cross join lateral jsonb_array_elements(w.before_record->'rules') old_rule
   join public.rm_aprovacoes_etapas s on s.id::text=old_rule.value->>'id' and s.projeto_id=p_project_id
  where w.operation='manage_project_route_cell' and w.payload->>'action'='remove' and w.result->'record'->'retired_rule_ids'?s.id::text and p_kind='operations' and 'approvals'=any(p_topics)
$events$;
 d:=replace(d,needle,events||needle);
 -- A replacement is a retirement of the old configuration and creation of a
 -- new one. Its immutable predecessor remains available for offline recovery.
 needle:='   case w.payload->>''action''';
 if strpos(d,needle)=0 then raise exception 'Unexpected photo audit action';end if;
 -- Keep all existing event projections intact. Replacement gets its own branch.
 events:=$events$
  union all
  select 'web:'||w.client_submission_id||':photo-replacement:'||f.id,'photos',case when f.id::text=w.payload->>'foto_id' then 'photo_retire' else 'photo_add' end,
   f.id,f.celula_id,f.celula_projeto_id,w.actor_id,w.created_at,'web',f.id::text=w.payload->>'foto_id',
   case when f.id::text=w.payload->>'foto_id' then rm_private.project_audit_changes_v1(jsonb_build_object('lixeira',false),jsonb_build_object('lixeira',true),array['lixeira'])
    else rm_private.project_audit_changes_v1(null,jsonb_build_object('titulo',(select t->'titulo' from jsonb_array_elements(w.before_record->'titles') t where t->>'id'=w.payload->>'cadastro_foto_id'),'categoria_foto','obrigat_ria','tag',w.payload->'tag'),array['titulo','categoria_foto','tag']) end,null
  from web w join public.rm_fotos f on(f.id::text=w.payload->>'foto_id' or f.id::text=w.payload->>'new_id') and f.projeto_id=p_project_id
  where w.operation='manage_operational_photos' and w.payload->>'action'='replace' and p_kind='operations' and 'photos'=any(p_topics)
$events$;
 d:=replace(d,' ) select ''audit:''||',events||' ) select ''audit:''||');
 -- Exclude replace from the old add/tag/retire/restore projection to avoid
 -- manufacturing a lixeira value for its newly inserted slot.
 needle:='where w.operation=''manage_operational_photos'' and p_kind=''operations''';
 if strpos(d,needle)=0 then raise exception 'Unexpected legacy photo audit projection';end if;
 d:=replace(d,needle,'where w.operation=''manage_operational_photos'' and w.payload->>''action''<>''replace'' and p_kind=''operations''');
 execute d;
end $$;

-- Keep the current SSO envelope and capability set; only extend its exact map.
do $$ declare d text;needle text;begin
 d:=pg_get_constraintdef((select oid from pg_constraint where conrelid='rm_private.sso_action_permits'::regclass and conname='sso_action_permits_operation_check'));
 if strpos(d,'''delete_project''::text')=0 then raise exception '039 project deletion must be installed first';end if;
 d:=replace(d,'''delete_project''::text','''delete_project''::text, ''manage_project_route_cell''::text');
 alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
 execute 'alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check '||d;
 d:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 needle:='when ''delete_project'' then ''em.projects.manage'' end;';
 if strpos(d,needle)=0 then raise exception 'Unexpected SSO map after 039';end if;
 execute replace(d,needle,'when ''delete_project'' then ''em.projects.manage'' when ''manage_project_route_cell'' then ''em.planning.manage'' end;');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
notify pgrst,'reload schema';
commit;
