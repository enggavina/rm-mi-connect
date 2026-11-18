-- Owner-only counts. Direct pair consistency is not complete isolation.
begin isolation level repeatable read read only;
set local statement_timeout='20s';
set local search_path='';
select jsonb_build_object('format_version',1,'source','postgresql_direct_reference_counts',
 'captured_at',clock_timestamp(),'transaction_read_only',current_setting('transaction_read_only'),
 'readiness',rm_private.workshop_reference_readiness_v1()) report;
commit;
