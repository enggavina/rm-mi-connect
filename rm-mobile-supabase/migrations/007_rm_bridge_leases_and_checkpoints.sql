-- Durable worker claims, bounded retries and serialized incremental checkpoints.
begin;
alter table public.rm_sync_outbox add column if not exists claimed_by uuid;
alter table public.rm_sync_outbox add column if not exists lease_until timestamptz;
create table public.rm_bridge_checkpoints (
  endpoint text primary key,
  cursor_at timestamptz not null,
  updated_at timestamptz not null default clock_timestamp()
);
create table rm_private.bridge_lease (
  id boolean primary key default true check(id),
  worker_id uuid not null,
  lease_until timestamptz not null
);
alter table public.rm_bridge_checkpoints enable row level security;
revoke all on public.rm_bridge_checkpoints from public,anon,authenticated;
grant all on public.rm_bridge_checkpoints,public.rm_sync_outbox to service_role;
grant usage,select on sequence public.rm_sync_outbox_id_seq to service_role;
-- Explicit privileges for the ETL/bridge; RLS bypass alone grants no table access.
do $$ declare t record; begin
  for t in select tablename from pg_tables where schemaname='public' and left(tablename,3)='rm_' loop
    execute format('grant select,insert,update,delete on table public.%I to service_role',t.tablename);
  end loop;
end $$;

create function public.rm_acquire_bridge_lease_v1(p_worker_id uuid,p_seconds integer default 300)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if p_worker_id is null then raise exception 'worker_id é obrigatório.'; end if;
  insert into rm_private.bridge_lease(id,worker_id,lease_until)
    values(true,p_worker_id,clock_timestamp()+make_interval(secs=>greatest(30,least(p_seconds,600))))
    on conflict(id) do update set worker_id=excluded.worker_id,lease_until=excluded.lease_until
      where rm_private.bridge_lease.lease_until<clock_timestamp() or rm_private.bridge_lease.worker_id=p_worker_id;
  return found;
end $$;
create function public.rm_release_bridge_lease_v1(p_worker_id uuid)
returns void language sql security definer set search_path='' as $$
  delete from rm_private.bridge_lease where worker_id=p_worker_id;
$$;
create function public.rm_advance_bridge_checkpoint_v1(p_endpoint text,p_cursor_at timestamptz)
returns void language sql security definer set search_path='' as $$
  insert into public.rm_bridge_checkpoints(endpoint,cursor_at) values(p_endpoint,p_cursor_at)
  on conflict(endpoint) do update set cursor_at=greatest(public.rm_bridge_checkpoints.cursor_at,excluded.cursor_at),
    updated_at=clock_timestamp();
$$;
create function public.rm_advance_form_sequence_v1(p_form_id uuid,p_code integer)
returns integer language sql security definer set search_path='' as $$
  insert into public.rm_numeracoes(form_id,ult_numero,sync_source)
    values(p_form_id,greatest(0,p_code),'bubble')
    on conflict(form_id) do update set ult_numero=greatest(public.rm_numeracoes.ult_numero,excluded.ult_numero),
      updated_at=clock_timestamp()
    returning ult_numero;
$$;
create function public.rm_claim_sync_events_v1(p_worker_id uuid,p_limit integer default 25)
returns setof public.rm_sync_outbox language plpgsql security definer set search_path='' as $$
begin
  if p_worker_id is null then raise exception 'worker_id é obrigatório.'; end if;
  -- A crashed final attempt must not remain processing forever.
  update public.rm_sync_outbox set status='dead_letter',claimed_by=null,lease_until=null,
    last_error=coalesce(last_error,'Worker interrompido após a última tentativa.')
    where status='processing' and lease_until<clock_timestamp() and attempts>=max_attempts;
  return query with due as (
    select id from public.rm_sync_outbox
    where attempts<max_attempts and ((status in ('pending','failed') and next_retry_at<=clock_timestamp())
      or (status='processing' and (lease_until is null or lease_until<clock_timestamp())))
    order by id for update skip locked limit greatest(1,least(p_limit,100))
  ) update public.rm_sync_outbox o set status='processing',attempts=o.attempts+1,
      claimed_by=p_worker_id,lease_until=clock_timestamp()+interval '5 minutes'
    from due where o.id=due.id returning o.*;
end $$;
create function public.rm_renew_sync_event_v1(p_id bigint,p_worker_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  update public.rm_sync_outbox set lease_until=clock_timestamp()+interval '5 minutes'
    where id=p_id and claimed_by=p_worker_id and status='processing' and lease_until>clock_timestamp();
  return found;
end $$;
create function public.rm_finish_sync_event_v1(p_id bigint,p_worker_id uuid,p_error text default null)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  update public.rm_sync_outbox set
    status=case when p_error is null then 'completed' when attempts>=max_attempts then 'dead_letter' else 'failed' end,
    last_error=left(p_error,2000),
    next_retry_at=clock_timestamp()+make_interval(secs=>least(3600,5*power(2,least(attempts,10)))::integer),
    processed_at=case when p_error is null then clock_timestamp() else null end,
    claimed_by=null,lease_until=null
  where id=p_id and claimed_by=p_worker_id and status='processing' and lease_until>clock_timestamp();
  return found;
end $$;
do $$ declare f record; begin
  for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('rm_acquire_bridge_lease_v1','rm_release_bridge_lease_v1',
      'rm_advance_bridge_checkpoint_v1','rm_advance_form_sequence_v1','rm_claim_sync_events_v1','rm_renew_sync_event_v1','rm_finish_sync_event_v1') loop
    execute format('revoke all on function %s from public,anon,authenticated',f.signature);
    execute format('grant execute on function %s to service_role',f.signature);
  end loop;
end $$;
commit;
