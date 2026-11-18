-- Technical owner-only diagnostic. Counts never prove complete isolation.
begin isolation level repeatable read read only;
set local statement_timeout='15s';
set local search_path='';
select jsonb_build_object('format_version',1,'source','postgresql_private_counts',
 'captured_at',clock_timestamp(),'transaction_read_only',current_setting('transaction_read_only'),
 'readiness',rm_private.workshop_ownership_readiness_v1()) report;
commit;
