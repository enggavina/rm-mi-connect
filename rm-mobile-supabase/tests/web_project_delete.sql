begin;
create function pg_temp.check_delete(ok boolean,message text) returns void language plpgsql as $$ begin if not coalesce(ok,false) then raise exception 'FAIL: %',message;end if;end $$;
insert into auth.users(id) values('10390000-0000-4000-8000-000000000001'),('10390000-0000-4000-8000-000000000002');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('20390000-0000-4000-8000-000000000001','10390000-0000-4000-8000-000000000001','Delete administrator','administrador','ativo'),('20390000-0000-4000-8000-000000000002','10390000-0000-4000-8000-000000000002','Reader','padr_o','ativo');
insert into public.rm_tipos_equipamento(id,nome) values('30390000-0000-4000-8000-000000000001','Delete model');
insert into public.rm_celulas(id,nome) values('40390000-0000-4000-8000-000000000001','Delete cell');
insert into public.rm_celula_tipos_equipamento(id,celula_id,tipo_equipamento_id,ativo) values('41390000-0000-4000-8000-000000000001','40390000-0000-4000-8000-000000000001','30390000-0000-4000-8000-000000000001',true);
insert into public.rm_forms(id,titulo) values('70390000-0000-4000-8000-000000000001','Shared form');
insert into public.rm_questoes(id,form_id,enunciado,tipo) values('80390000-0000-4000-8000-000000000001','70390000-0000-4000-8000-000000000001','Question','texto_curto');
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub','10390000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1"}',true);
set local role authenticated;
select public.rm_web_mutate_v1('a0390000-0000-4000-8000-000000000001','save_project_with_equipment',jsonb_build_object('id','50390000-0000-4000-8000-000000000001','expected_updated_at',null,'changes',jsonb_build_object('nome','Delete target'),
 'equipment',jsonb_build_object('id','60390000-0000-4000-8000-000000000001','tipo_equipamento_id','30390000-0000-4000-8000-000000000001','expected_updated_at',null,'expected_context_version',null,'changes','{}'::jsonb)));
reset role;
update public.rm_projetos set bubble_id='delete-bubble-project' where id='50390000-0000-4000-8000-000000000001';
insert into public.rm_projetos(id,nome) values('50390000-0000-4000-8000-000000000002','Preserved project');
insert into public.rm_registros_formulario(id,projeto_id,form_id,celula_id) values('90390000-0000-4000-8000-000000000001','50390000-0000-4000-8000-000000000001','70390000-0000-4000-8000-000000000001','40390000-0000-4000-8000-000000000001');
insert into public.rm_respostas(id,registro_formulario_id,questao_id,resposta) values('91390000-0000-4000-8000-000000000001','90390000-0000-4000-8000-000000000001','80390000-0000-4000-8000-000000000001','Operational response');
insert into public.rm_comentarios(id,projeto_id,evento) values('92390000-0000-4000-8000-000000000001','50390000-0000-4000-8000-000000000001','Manual comment');
insert into public.rm_notificacoes(id,registro_formulario_id,mensagem) values('93390000-0000-4000-8000-000000000001','90390000-0000-4000-8000-000000000001','Notification');
insert into public.rm_propostas_controle(id,projeto_id,equipamento_id) values('94390000-0000-4000-8000-000000000001','50390000-0000-4000-8000-000000000001','60390000-0000-4000-8000-000000000001');
insert into public.rm_propostas_budgetarias(id,proposta_controle_id) values('95390000-0000-4000-8000-000000000001','94390000-0000-4000-8000-000000000001');
insert into public.rm_ordens_servico(id,numero_os,projeto_id) values('96390000-0000-4000-8000-000000000001','LOCAL-39','50390000-0000-4000-8000-000000000001');
insert into public.rm_componentes_os(id,ordem_servico_id,nome) values('97390000-0000-4000-8000-000000000001','96390000-0000-4000-8000-000000000001','Owned component');
insert into public.rm_fichas_delineamento(id,ordem_servico_id) values('98390000-0000-4000-8000-000000000001','96390000-0000-4000-8000-000000000001');
insert into public.rm_itens_ficha_delineamento(id,ficha_delineamento_id,descricao) values('99390000-0000-4000-8000-000000000001','98390000-0000-4000-8000-000000000001','Owned item');
insert into public.rm_docs(id,projeto_id,nome,arquivo_url,visivel_cliente) values('b0390000-0000-4000-8000-000000000001','50390000-0000-4000-8000-000000000001','Owned PDF','https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/web-dossier/50390000-0000-4000-8000-000000000001/b0390000-0000-4000-8000-000000000001.pdf',false);
insert into rm_private.project_attachment_uploads(id,auth_user_id,actor_id,projeto_id,nome,filename,mime_type,byte_size,sha256,object_path,status_documento,finalized_doc_id,completed_at)
 values('b0390000-0000-4000-8000-000000000001','10390000-0000-4000-8000-000000000001','20390000-0000-4000-8000-000000000001','50390000-0000-4000-8000-000000000001','Owned PDF','file.pdf','application/pdf',12,repeat('a',64),'web-dossier/50390000-0000-4000-8000-000000000001/b0390000-0000-4000-8000-000000000001.pdf','No prazo','b0390000-0000-4000-8000-000000000001',clock_timestamp());
set local role authenticated;
do $$ declare c jsonb;p jsonb;r jsonb;begin
 c:=public.rm_web_project_delete_snapshot_v1('50390000-0000-4000-8000-000000000001');
 perform pg_temp.check_delete((c->>'can_delete')::boolean,'owned graph is deletable');
 perform pg_temp.check_delete(c->'counts'->>'answers'='1' and c->'counts'->>'commercial'='2' and c->'counts'->>'laboratory'='4','ownership closure includes answers, commercial and OS descendants');
 p:=jsonb_build_object('id','50390000-0000-4000-8000-000000000001','expected_updated_at',c->'project'->>'updated_at','expected_context_version',c->>'context_version','confirm_delete',true,'justificativa','Duplicate local fixture');
 begin perform public.rm_web_mutate_v1(gen_random_uuid(),'delete_project',p-'confirm_delete');raise exception 'FAIL: no confirmation';exception when invalid_parameter_value then null;end;
 begin perform public.rm_web_mutate_v1(gen_random_uuid(),'delete_project',jsonb_set(p,'{justificativa}','"  \t "'));raise exception 'FAIL: empty reason';exception when invalid_parameter_value then null;end;
 perform set_config('request.jwt.claim.sub','10390000-0000-4000-8000-000000000002',true);
 begin perform public.rm_web_mutate_v1(gen_random_uuid(),'delete_project',p);raise exception 'FAIL: standard user deleted project';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','10390000-0000-4000-8000-000000000001',true);
 -- A failure in the deletion transaction rolls back both receipt and graph.
 perform set_config('rm.test.delete_payload',p::text,true);
 r:=public.rm_web_mutate_v1('a0390000-0000-4000-8000-000000000002','delete_project',p);
 perform pg_temp.check_delete(r->'record'->'deleted'='true'::jsonb,'authorized delete succeeds');
 perform pg_temp.check_delete((public.rm_web_mutate_v1('a0390000-0000-4000-8000-000000000002','delete_project',p)->>'idempotent_replay')::boolean,'delete replay exact');
end $$;
reset role;
select pg_temp.check_delete(not exists(select 1 from public.rm_projetos where id='50390000-0000-4000-8000-000000000001'),'project physically removed');
select pg_temp.check_delete(not exists(select 1 from public.rm_equipamentos where projeto_id='50390000-0000-4000-8000-000000000001'),'equipment removed');
select pg_temp.check_delete(not exists(select 1 from public.rm_respostas where id='91390000-0000-4000-8000-000000000001'),'responses removed');
select pg_temp.check_delete(not exists(select 1 from public.rm_ordens_servico where id='96390000-0000-4000-8000-000000000001'),'OS graph removed');
select pg_temp.check_delete(not exists(select 1 from public.rm_propostas_controle where id='94390000-0000-4000-8000-000000000001'),'commercial graph removed');
select pg_temp.check_delete(exists(select 1 from public.rm_forms where id='70390000-0000-4000-8000-000000000001') and exists(select 1 from public.rm_tipos_equipamento where id='30390000-0000-4000-8000-000000000001') and exists(select 1 from public.rm_projetos where id='50390000-0000-4000-8000-000000000002'),'shared/global records preserved');
select pg_temp.check_delete((select payload?'original_sha256' and before_record is null and result->'resource_deleted'='true'::jsonb from rm_private.web_mutation_receipts where client_submission_id='a0390000-0000-4000-8000-000000000001'),'old receipt reduced to protocol hash');
do $$ begin
 begin insert into public.rm_projetos(id,nome) values('50390000-0000-4000-8000-000000000001','Must not resurrect');raise exception 'FAIL: UUID resurrected';exception when sqlstate 'PT410' then null;end;
 begin insert into public.rm_projetos(id,bubble_id,nome) values(gen_random_uuid(),'delete-bubble-project','Must not reimport');raise exception 'FAIL: Bubble resurrected';exception when sqlstate 'PT410' then null;end;
end $$;
set local role authenticated;
do $$ begin
 begin perform public.rm_project_delete_files_claim_v1();raise exception 'FAIL: client claimed GC';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
do $$ declare jobs jsonb;j jsonb;begin
 jobs:=public.rm_project_delete_files_claim_v1(1,'a0390000-0000-4000-8000-000000000002');perform pg_temp.check_delete(jsonb_array_length(jobs)=1,'committed cleanup claim');j:=jobs->0;
 perform pg_temp.check_delete(public.rm_project_delete_files_finish_v1((j->>'id')::uuid,(j->>'lease_token')::uuid,true),'physical cleanup ack');
 perform pg_temp.check_delete(not public.rm_project_delete_files_finish_v1((j->>'id')::uuid,(j->>'lease_token')::uuid,true),'stale lease cannot ack twice');
end $$;
reset role;
select 'PASS: 039 explicit project hard delete, ownership, minimal receipt, tombstone and durable file cleanup' result;
rollback;
