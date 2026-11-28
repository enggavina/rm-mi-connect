-- Run as the EM database owner. User-Agent categories guide field verification.
-- They never establish the APK version, workshop identity, or authorization.
begin isolation level repeatable read read only;
set local search_path='';
set local statement_timeout='20s';

with sessions as materialized (
 select s.id, case
  when nullif(btrim(s.user_agent),'') is null then 'missing'
  when s.user_agent~*'(^|[[:space:];(])(android|okhttp|expo)(/|[[:space:]);]|$)' then 'android'
  when s.user_agent~*'(^|[[:space:]])(node|undici|deno)(/|$)' then 'server'
  when s.user_agent ilike '%Mozilla/%' then 'browser'
  else 'other' end as agent_hint
 from auth.sessions s
 where s.updated_at>now()-interval '14 days' and (s.not_after is null or s.not_after>now())
 and exists(select 1 from rm_private.operator_delegations d
  where d.auth_user_id=s.user_id and not d.revoked and d.expires_at>now())
), observations as materialized (
 select a.session_id,a.workshop_id,a.app_version,a.build_code,a.observed_at
 from rm_private.workshop_android_observations a join sessions s on s.id=a.session_id
 where a.observed_at>now()-interval '14 days'
), session_coverage as (
 select s.agent_hint, exists(select 1 from observations o where o.session_id=s.id) as version_seen
 from sessions s
), agent_summary as (
 select agent_hint, count(*) as sessions,
   count(*) filter(where version_seen) as with_android_observation,
   count(*) filter(where not version_seen) as without_android_observation
 from session_coverage group by agent_hint
), versions as (
 select w.code,o.app_version,o.build_code,count(distinct o.session_id) observed_sessions,max(o.observed_at) last_observed_at
 from observations o join rm_private.workshop_references w on w.id=o.workshop_id
 group by w.code,o.app_version,o.build_code
)
select jsonb_build_object('read_only',current_setting('transaction_read_only')='on','window_days',14,
 'recent_sessions_with_operator_delegation',(select count(*) from sessions),
 'sessions_with_android_observation',(select count(*) from session_coverage where version_seen),
 'sessions_without_android_observation',(select count(*) from session_coverage where not version_seen),
 'session_hints',coalesce((select jsonb_agg(to_jsonb(a) order by a.agent_hint) from agent_summary a),'[]'::jsonb),
 'versions',coalesce((select jsonb_agg(to_jsonb(v) order by v.code,v.build_code) from versions v),'[]'::jsonb)
) report;
commit;
