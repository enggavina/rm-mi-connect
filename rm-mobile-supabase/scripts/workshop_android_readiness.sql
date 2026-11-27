-- Run as the EM database owner. Recent sessions may include Operacional Web.
begin isolation level repeatable read read only;
set local search_path='';
set local statement_timeout='20s';

with sessions as materialized (
 select distinct s.id from auth.sessions s
 join rm_private.operator_delegations d on d.auth_user_id=s.user_id
 where s.updated_at>now()-interval '14 days' and (s.not_after is null or s.not_after>now())
  and not d.revoked and d.expires_at>now()
), observations as materialized (
 select a.session_id,a.workshop_id,a.app_version,a.build_code,a.observed_at
 from rm_private.workshop_android_observations a join sessions s on s.id=a.session_id
 where a.observed_at>now()-interval '14 days'
), versions as (
 select w.code,o.app_version,o.build_code,count(distinct o.session_id) observed_sessions,max(o.observed_at) last_observed_at
 from observations o join rm_private.workshop_references w on w.id=o.workshop_id
 group by w.code,o.app_version,o.build_code
)
select jsonb_build_object('read_only',current_setting('transaction_read_only')='on','window_days',14,
 'recent_sessions_with_operator_delegation',(select count(*) from sessions),
 'sessions_with_android_observation',(select count(distinct session_id) from observations),
 'sessions_without_android_observation',(select count(*) from sessions s where not exists(select 1 from observations o where o.session_id=s.id)),
 'versions',coalesce((select jsonb_agg(to_jsonb(v) order by v.code,v.build_code) from versions v),'[]'::jsonb)
) report;
commit;
