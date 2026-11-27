begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create function public.rm_mobile_workshop_media_v1(p_auth_user_id uuid,p_session_id uuid,p_operator_token text,
 p_workshop_context jsonb,p_urls text[]) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid; office_id uuid; files jsonb;
begin
 if coalesce(cardinality(p_urls),0) not between 1 and 25 or exists(select 1 from unnest(p_urls) u
  where u is null or length(u) not between 9 and 2048 or u not like 'https://%' or u~'[[:cntrl:]]') then
  raise exception 'Referência de mídia inválida.' using errcode='22023';
 end if;
 select i.operator_subject into actor_id from rm_private.online_operator_identity_v1(p_auth_user_id,p_session_id,p_operator_token) i;
 if actor_id is null then raise exception 'Identifique novamente o operador.' using errcode='28000';end if;
 office_id:=rm_private.online_workshop_context_v1(p_workshop_context,p_auth_user_id,actor_id);
 if office_id is null then raise exception 'Oficina indisponível.' using errcode='42501';end if;

 with requested as materialized (select distinct u url from unnest(p_urls) u),
 visible_cells as materialized (
  select c.cell_id from rm_private.workshop_cell_ownership c where c.workshop_id=office_id
   and rm_private.operator_can_access_cell(actor_id,c.cell_id)
 ), visible_projects as materialized (
  select distinct a.projeto_id id from public.rm_celulas_projeto a join visible_cells c on c.cell_id=a.celula_id
   where not a.retirada and a.visibilidade and rm_private.workshop_project_owned_v1(a.projeto_id,office_id)
  union select o.project_id from rm_private.receiving_openings o
   where o.auth_user_id=p_auth_user_id and o.operator_id=actor_id
    and rm_private.workshop_project_owned_v1(o.project_id,office_id)
 ), photos as (
  select u.url,'project_photo' source from requested u join public.rm_fotos f on f.foto_url=u.url
  where not f.lixeira and (
   (f.projeto_id is null and f.celula_projeto_id is null and exists(select 1 from public.rm_celula_tipos_equipamento t
     join visible_cells c on c.cell_id=t.celula_id where t.id=f.celula_tipo_equipamento_id
     and (f.celula_id is null or f.celula_id=t.celula_id)
     and rm_private.workshop_mobile_cell_type_owned_v1(t.id,office_id)))
   or (exists(select 1 from visible_projects p where p.id=f.projeto_id)
    and (f.celula_id is null or rm_private.workshop_cell_owned_v1(f.celula_id,office_id))
    and (f.celula_projeto_id is null or exists(select 1 from public.rm_celulas_projeto a
     where a.id=f.celula_projeto_id and a.projeto_id=f.projeto_id and rm_private.workshop_cell_owned_v1(a.celula_id,office_id)
      and (f.celula_id is null or f.celula_id=a.celula_id)))))
 ), answers as (
  select u.url,case when a.assinatura_url=u.url then 'answer_signature' else 'answer_photo' end source
  from requested u join public.rm_respostas a on (a.assinatura_url=u.url or u.url=any(a.fotos_urls))
  join public.rm_registros_formulario f on f.id=a.registro_formulario_id
  join visible_projects p on p.id=f.projeto_id join visible_cells c on c.cell_id=f.celula_id
  where rm_private.workshop_form_record_owned_v1(f.projeto_id,f.celula_id,f.form_id,office_id)
 ), documents as (
  select u.url,'document' source from requested u join public.rm_projetos p on u.url in(p.arquivo_nota_fiscal_url,p.documento_proposta_url)
   where exists(select 1 from visible_projects v where v.id=p.id)
  union all select u.url,'document' from requested u join public.rm_documentos d on d.arquivo_url=u.url
   join visible_projects p on p.id=d.projeto_id
  union all select u.url,'document' from requested u join public.rm_docs d on d.arquivo_url=u.url
   join visible_projects p on p.id=d.projeto_id
 ), draft as materialized (
  -- Unsubmitted drafts have no project yet. Use the original device, operator,
  -- storage namespace and an independently classified customer when restoring them.
  select d.payload from rm_private.receiving_drafts d
  where d.auth_user_id=p_auth_user_id and d.operator_id=actor_id and d.state='draft'
   and (exists(select 1 from rm_private.receiving_openings o join visible_projects p on p.id=o.project_id where o.client_submission_id=d.id)
    or rm_private.workshop_read_owned_v1('client',case when (d.payload->>'cliente')~*'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
     then (d.payload->>'cliente')::uuid end,office_id))
 ), draft_files as (
  select u.url,'document' source from requested u join draft d on d.payload->>'arquivoNotaFiscal'=u.url
   where u.url like 'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/'||p_auth_user_id::text||'/%'
  union all select u.url,'project_photo' from requested u join draft d on true
   cross join lateral jsonb_array_elements(case when jsonb_typeof(d.payload->'fotos')='array' then d.payload->'fotos' else '[]'::jsonb end) f
   where coalesce(f->>'uri',f#>>'{}')=u.url
    and u.url like 'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/rm-fotos/'||p_auth_user_id::text||'/%'
 ), matches as (
  select * from photos union select * from answers union select * from documents union select * from draft_files
 )
 select coalesce(jsonb_agg(jsonb_build_object('url',url,'source',source) order by url,source),'[]'::jsonb) into files from matches;
 return jsonb_build_object('workshop_id',office_id,'files',files);
end
$$;
revoke all on function public.rm_mobile_workshop_media_v1(uuid,uuid,text,jsonb,text[]) from public,anon,authenticated,service_role;
grant execute on function public.rm_mobile_workshop_media_v1(uuid,uuid,text,jsonb,text[]) to service_role;
notify pgrst,'reload schema';
commit;
