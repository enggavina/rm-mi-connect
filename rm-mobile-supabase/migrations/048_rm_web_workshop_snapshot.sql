-- The internal workshop reads the same project/cell/equipment data as the EM.
-- Read-only, bounded, one MVCC statement; no backfill, new grants or business writes.
begin;
create function public.rm_web_workshop_snapshot_v1() returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 if not coalesce(rm_private.web_gantt_read_allowed_v1(),false) then
  raise exception 'Acesso ao gemeo digital nao autorizado.' using errcode='42501';
 end if;
 with cohort as materialized (
  select p.* from public.rm_projetos p
  where p.data_real_de_entrega is null
   and p.chegada_do_equipamento is not null
   and (p.chegada_do_equipamento at time zone 'America/Sao_Paulo')::date <= (statement_timestamp() at time zone 'America/Sao_Paulo')::date
   and p.status_pcp in('equipamento_inspecionado','executando','aguardando_aprova__o','revis_o_comercial','revis_o_comercial0',
    'susponso__hold_','equipamento_em_inspe__o','sem_previs_o','investiga__o_de_garantia','executando_com_garantia')
 ), allocations as materialized (
  select a.* from public.rm_celulas_projeto a join cohort p on p.id=a.projeto_id where not a.retirada
 ), counts as materialized (
  select (select count(*) from cohort) projects,(select count(*) from allocations) allocations,(select count(*) from public.rm_celulas) cells
 )
 select case when n.projects>2000 or n.allocations>20000 or n.cells>2000 then null else jsonb_build_object(
  'as_of',statement_timestamp(),'project_count',n.projects,'allocation_count',n.allocations,'cell_count',n.cells,
  'projects',coalesce((select jsonb_agg(jsonb_build_object(
   'id',p.id,'numero',p.numero,'nome',p.nome,'descricao_equipamento',p.descricao_equipamento,'status_pcp',p.status_pcp,
   'chegada_do_equipamento',p.chegada_do_equipamento,'data_real_de_entrega',p.data_real_de_entrega,
   'data_prevista_final',p.data_prevista_final,'data_contratual',p.data_contratual,'data_renegociada',p.data_renegociada,
   'cliente_nome',coalesce(nullif(c.nome,''),nullif(p.cliente_nome_exportacao,'')),'gestor_nome',u.nome,
   'equipamento_tipo',t.nome,'equipamento_descricao',e.descricao,'fabricante',e.fabricante,'modelo',e.modelo,
   'potencia',e.potencia,'rotacao',e.rotacao,'numero_serie',e.numero_serie,'equipment_binding',e.id is not null
  ) order by p.numero,p.id)
  from cohort p
  left join public.rm_clientes c on c.id=p.cliente_id
  left join public.rm_users u on u.id=p.gestor_responsavel_id
  left join public.rm_tipos_equipamento t on t.id=rm_private.effective_project_type_v1(p)
  left join lateral (
   select e.* from public.rm_equipamentos e where e.id=p.equipamento_id and e.projeto_id=p.id
    and not exists(select 1 from public.rm_projetos other where other.equipamento_id=e.id and other.id<>p.id)
  ) e on true),'[]'),
  'allocations',coalesce((select jsonb_agg(jsonb_build_object(
   'id',a.id,'projeto_id',a.projeto_id,'celula_id',a.celula_id,'status',a.status,'bloqueada',a.bloqueada,
   'motivo_bloqueio',a.motivo_bloqueio,'data_inicio',a.data_inicio,'data_limite',a.data_limite,'data_fim_real',a.data_fim_real,
   'responsavel_nome',u.nome,'prioridade',a.prioridade,'horas_previstas',a.horas_previstas::text,
   'horas_realizadas',a.horas_realizadas::text,'visibilidade',a.visibilidade,'indice',a.indice
  ) order by a.projeto_id,a.indice nulls last,a.id) from allocations a left join public.rm_users u on u.id=a.responsavel_id),'[]'),
  'cells',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'nome',c.nome,'ordem',coalesce(c.ordem,c.indice))
   order by coalesce(c.ordem,c.indice) nulls last,c.id) from public.rm_celulas c),'[]')
 ) end into result from counts n;
 if result is null or octet_length(result::text)>10485760 then
  raise exception 'O conjunto da oficina excedeu o limite de leitura completa.' using errcode='PT413';
 end if;
 return result;
end $$;
revoke all on function public.rm_web_workshop_snapshot_v1() from public,anon,authenticated,service_role;
grant execute on function public.rm_web_workshop_snapshot_v1() to authenticated;
notify pgrst,'reload schema';
commit;
