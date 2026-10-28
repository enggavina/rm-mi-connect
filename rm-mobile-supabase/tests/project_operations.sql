\set ON_ERROR_STOP on
begin;
create function pg_temp.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
insert into auth.users(id) values('11000000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,matricula,nome,perfil) values
 ('21000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','TESTADMIN','Admin fixture','administrador');
insert into rm_private.user_credentials(user_id,palavra_chave_hash) values
 ('21000000-0000-4000-8000-000000000001',extensions.crypt('fixture-password',extensions.gen_salt('bf',4)));
insert into public.rm_clientes(id,nome) values('41000000-0000-4000-8000-000000000001','Fixture client');
insert into public.rm_celulas(id,nome) values
 ('31000000-0000-4000-8000-000000000001','Cell A'),('31000000-0000-4000-8000-000000000002','Cell B');
insert into public.rm_forms(id,titulo) values('61000000-0000-4000-8000-000000000001','Fixture form');
set local role authenticated;
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000001',true);
do $$ declare a jsonb; p jsonb; first_result jsonb; begin
  a:=public.rm_authenticate_operator_v1('TESTADMIN','fixture-password');
  perform set_config('rm.test.token',a->>'operator_token',true);
  p:=jsonb_build_object('p_cliente_id','41000000-0000-4000-8000-000000000001',
    'p_chegada_equipamento','2026-10-28T10:30:00Z','p_nota_fiscal','NF-TEST',
    'p_arquivo_nota_fiscal_url','https://example.invalid/invoice.pdf','p_descricao_equipamento','Motor description',
    'p_equipamento',jsonb_build_object('placa_motor','c___placa'),'p_eventualidades','Fixture observation');
  first_result:=public.rm_mobile_mutate_v1('91000000-0000-4000-8000-000000000001','rm_submit_recebimento_v1',p,current_setting('rm.test.token'));
  perform set_config('rm.test.project',first_result->>'projeto_id',true);
  perform pg_temp.check((select numero is null and tipo_equipamento_id is null and nota_fiscal='NF-TEST' and
    arquivo_nota_fiscal_url='https://example.invalid/invoice.pdf' and descricao_equipamento='Motor description'
    and chegada_do_equipamento='2026-10-28T10:30:00Z'::timestamptz
    from public.rm_projetos where id=(first_result->>'projeto_id')::uuid),'simplified receiving preserves NF and date without invented OS/type');
  perform pg_temp.check((select placa_motor='c___placa' and descricao='Motor description' from public.rm_equipamentos
    where id=(first_result->>'equipamento_id')::uuid),'receiving equipment descriptor');
  a:=public.rm_mobile_mutate_v1('91000000-0000-4000-8000-000000000001','rm_submit_recebimento_v1',p,current_setting('rm.test.token'));
  perform pg_temp.check((a->>'idempotent_replay')::boolean,'simplified receiving idempotent');
end $$;
insert into storage.objects(bucket_id,name) values('rm-documentos','11000000-0000-4000-8000-000000000001/invoice.pdf');
do $$ begin
  begin
    insert into storage.objects(bucket_id,name) values('rm-documentos','another-account/invoice.pdf');
    raise exception 'FAIL: document upload outside own prefix accepted';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,forms_ids,visibilidade) values
 ('81000000-0000-4000-8000-000000000001',current_setting('rm.test.project')::uuid,'31000000-0000-4000-8000-000000000001','pendente',array['61000000-0000-4000-8000-000000000001']::uuid[],true),
 ('81000000-0000-4000-8000-000000000002',current_setting('rm.test.project')::uuid,'31000000-0000-4000-8000-000000000002','pendente','{}',false);
insert into public.rm_cadastro_fotos(id,celula_nome,titulo,numero) values
 ('71000000-0000-4000-8000-000000000001','Cell A','Registered title',1);
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_destino_id,status_cel_proj,bloquear_avanco_sem_aprov) values
 ('a1000000-0000-4000-8000-000000000001',current_setting('rm.test.project')::uuid,'31000000-0000-4000-8000-000000000001','31000000-0000-4000-8000-000000000002','em_dia',true);
set local role authenticated;
do $$ declare p jsonb; a jsonb; c uuid; begin
  p:=jsonb_build_object('p_celula_projeto_id','81000000-0000-4000-8000-000000000001','p_comentario','  Typed comment  ');
  a:=public.rm_mobile_mutate_v1('91000000-0000-4000-8000-000000000002','rm_add_cell_comment_v1',p,current_setting('rm.test.token'));
  c:=(a->>'comentario_id')::uuid;
  perform public.rm_mobile_mutate_v1('91000000-0000-4000-8000-000000000002','rm_add_cell_comment_v1',p,current_setting('rm.test.token'));
  perform pg_temp.check((select count(*)=1 from public.rm_comentarios where id=c and evento='Typed comment'
    and cadastrado_por_id='21000000-0000-4000-8000-000000000001'),'comment actor and replay');
  begin
    perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_update_cell_status_v1',
      jsonb_build_object('p_celula_projeto_id','81000000-0000-4000-8000-000000000001','p_status','finalizado'),current_setting('rm.test.token'));
    raise exception 'FAIL: finalized without required form';
  exception when invalid_parameter_value then null; end;
  perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_update_cell_status_v1',
    jsonb_build_object('p_celula_projeto_id','81000000-0000-4000-8000-000000000001','p_status','em_dia'),current_setting('rm.test.token'));
  perform pg_temp.check((select status='em_dia' and status_historico=array['em_dia']::public.rm_status_cel_proj_enum[]
    from public.rm_celulas_projeto where id='81000000-0000-4000-8000-000000000001'),'status history');
  a:=public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_record_cell_photo_v1',
    jsonb_build_object('p_projeto_id',current_setting('rm.test.project'),'p_celula_id','31000000-0000-4000-8000-000000000001',
      'p_foto_url','https://example.invalid/photo.jpg','p_cadastro_foto_id','71000000-0000-4000-8000-000000000001','p_titulo','Forged title'),current_setting('rm.test.token'));
  perform pg_temp.check((select titulo='Registered title' from public.rm_fotos where id=(a->>'foto_id')::uuid),'photo resolves server catalog title');
  begin
    perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_transition_stage_approval_v1',
      jsonb_build_object('p_aprovacao_etapa_id','a1000000-0000-4000-8000-000000000001','p_acao','aprovar'),current_setting('rm.test.token'));
    raise exception 'FAIL: approve shown on release stage';
  exception when invalid_parameter_value then null; end;
  a:=public.rm_mobile_mutate_v1('91000000-0000-4000-8000-000000000003','rm_transition_stage_approval_v1',
    jsonb_build_object('p_aprovacao_etapa_id','a1000000-0000-4000-8000-000000000001','p_acao','liberar'),current_setting('rm.test.token'));
  perform pg_temp.check(a->>'novo_status_etapa'='aprovado','release is approved, not nulo');
  perform pg_temp.check((select visibilidade and status='para_execu__o' from public.rm_celulas_projeto where id='81000000-0000-4000-8000-000000000002'),'release advances destination');
  perform pg_temp.check((select not visibilidade from public.rm_celulas_projeto where id='81000000-0000-4000-8000-000000000001'),'completed origin approvals hide origin');
  perform pg_temp.check((select count(*)=1 from public.rm_aprovacoes_etapas where projeto_id=current_setting('rm.test.project')::uuid
    and celula_origem_id='31000000-0000-4000-8000-000000000002' and status_cel_proj='retornado'),'release creates return path');
  a:=public.rm_mobile_mutate_v1('91000000-0000-4000-8000-000000000003','rm_transition_stage_approval_v1',
    jsonb_build_object('p_aprovacao_etapa_id','a1000000-0000-4000-8000-000000000001','p_acao','liberar'),current_setting('rm.test.token'));
  perform pg_temp.check((a->>'idempotent_replay')::boolean,'approval replay before decision validation');
end $$;
reset role;
insert into public.rm_users(id,matricula,nome,perfil) values
 ('21000000-0000-4000-8000-000000000002','TESTOTHER','Other operator','mobile');
insert into rm_private.user_credentials(user_id,palavra_chave_hash) values
 ('21000000-0000-4000-8000-000000000002',extensions.crypt('fixture-password',extensions.gen_salt('bf',4)));
set local role authenticated;
do $$ declare reverse_id uuid; a jsonb; other_token text; begin
  select id into reverse_id from public.rm_aprovacoes_etapas where projeto_id=current_setting('rm.test.project')::uuid
    and celula_origem_id='31000000-0000-4000-8000-000000000002' and status_cel_proj='retornado';
  begin
    perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_transition_stage_approval_v1',
      jsonb_build_object('p_aprovacao_etapa_id',reverse_id,'p_acao','retornar'),current_setting('rm.test.token'));
    raise exception 'FAIL: return accepted while cell not returned';
  exception when invalid_parameter_value then null; end;
  perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_update_cell_status_v1',
    jsonb_build_object('p_celula_projeto_id','81000000-0000-4000-8000-000000000002','p_status','retornado'),current_setting('rm.test.token'));
  perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_transition_stage_approval_v1',
    jsonb_build_object('p_aprovacao_etapa_id',reverse_id,'p_acao','retornar','p_observacao','Return reason'),current_setting('rm.test.token'));
  perform pg_temp.check((select status='nulo' from public.rm_aprovacoes_etapas where id='a1000000-0000-4000-8000-000000000001'),'return reopens original approval');
  perform pg_temp.check((select status='retornado' and visibilidade from public.rm_celulas_projeto where id='81000000-0000-4000-8000-000000000001'),'return shows original cell');
  perform pg_temp.check((select count(*)=2 from public.rm_logs_aprovacao where projeto_id=current_setting('rm.test.project')::uuid),'each decision has one audit log');
  perform pg_temp.check((select count(*)=1 from public.rm_comentarios where projeto_id=current_setting('rm.test.project')::uuid and evento='Return reason'),'return comment retained');
  perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_update_cell_status_v1',
    jsonb_build_object('p_celula_projeto_id','81000000-0000-4000-8000-000000000001','p_status','em_dia'),current_setting('rm.test.token'));
  perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_transition_stage_approval_v1',
    jsonb_build_object('p_aprovacao_etapa_id','a1000000-0000-4000-8000-000000000001','p_acao','liberar'),current_setting('rm.test.token'));
  perform pg_temp.check((select status='nulo' from public.rm_aprovacoes_etapas where id=reverse_id),'release reopens rejected reverse path');
  begin
    perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_transition_stage_approval_v1',
      jsonb_build_object('p_aprovacao_etapa_id',reverse_id,'p_acao','finalizar'),current_setting('rm.test.token'));
    raise exception 'FAIL: removed finalization action accepted';
  exception when invalid_parameter_value then null; end;
  a:=public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_transition_stage_approval_v1',
    jsonb_build_object('p_aprovacao_etapa_id',reverse_id,'p_acao','aprovar'),current_setting('rm.test.token'));
  perform pg_temp.check(a->>'novo_status_etapa'='aprovado','return-stage approve does not require cell Retornado');
  other_token:=public.rm_authenticate_operator_v1('TESTOTHER','fixture-password')->>'operator_token';
  begin
    perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_add_cell_comment_v1',
      jsonb_build_object('p_celula_projeto_id','81000000-0000-4000-8000-000000000001','p_comentario','Unauthorized'),other_token);
    raise exception 'FAIL: other operator inherited device administrator for comment';
  exception when insufficient_privilege then null; end;
  begin
    perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_update_cell_status_v1',
      jsonb_build_object('p_celula_projeto_id','81000000-0000-4000-8000-000000000001','p_status','pendente'),other_token);
    raise exception 'FAIL: other operator inherited device administrator for status';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id,status) values
 ('b1000000-0000-4000-8000-000000000001',current_setting('rm.test.project')::uuid,'31000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','direcionado');
insert into public.rm_respostas(bubble_id,registro_formulario_id,questao_id,indice,enunciado,resposta,tipo,revisar,sync_source) values
 ('historical-answer-one','b1000000-0000-4000-8000-000000000001',null,1.5,'Original question one','Original answer one','texto_curto',true,'bubble'),
 ('historical-answer-two','b1000000-0000-4000-8000-000000000001',null,2,'Original question two','Original answer two','texto_curto',false,'bubble');
do $$ begin
  begin
    insert into public.rm_respostas(registro_formulario_id,questao_id,resposta,sync_source)
      values('b1000000-0000-4000-8000-000000000001',null,'New local answer','supabase');
    raise exception 'FAIL: new answer without template question accepted';
  exception when check_violation then null; end;
end $$;
set local role authenticated;
do $$ begin
  perform pg_temp.check((select count(*)=2 from public.rm_respostas where registro_formulario_id='b1000000-0000-4000-8000-000000000001' and questao_id is null),'distinct orphan answer snapshots remain readable');
  begin
    perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_submit_form_inspection_v1',
      jsonb_build_object('p_projeto_id',current_setting('rm.test.project'),'p_celula_id','31000000-0000-4000-8000-000000000001',
        'p_form_id','61000000-0000-4000-8000-000000000001','p_respostas','[{"questao_id":null,"resposta":"Not allowed"}]'::jsonb),current_setting('rm.test.token'));
    raise exception 'FAIL: gateway submitted without a real question';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_submit_form_revision_v1',
      jsonb_build_object('p_registro_formulario_id','b1000000-0000-4000-8000-000000000001',
        'p_respostas_corrigidas','[{"questao_id":null,"resposta":"Not allowed"}]'::jsonb),current_setting('rm.test.token'));
    raise exception 'FAIL: orphan snapshot edited through gateway';
  exception when invalid_parameter_value then null; end;
  perform pg_temp.check((select resposta='Original answer one' and revisar from public.rm_respostas where bubble_id='historical-answer-one'),'blocked correction preserves original snapshot');
end $$;
reset role;
select pg_temp.check(not (select public from storage.buckets where id='rm-documentos'),'document bucket remains private');
select pg_temp.check(not has_function_privilege('authenticated','rm_private.add_cell_comment_v1(uuid,uuid,text)','EXECUTE'),'comment direct bypass denied');
select 'PASS: receiving, document RLS, comments, cell status, catalog photos and approval decisions' as result;
rollback;
