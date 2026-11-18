-- Owner-only diagnostic. Ownership is not user authorization or full isolation.
begin isolation level repeatable read read only;
set local statement_timeout='30s';
set local search_path='';
select jsonb_build_object('format_version',1,'source','postgresql_catalog_ownership',
 'captured_at',clock_timestamp(),'transaction_read_only',current_setting('transaction_read_only'),
 'readiness',rm_private.workshop_catalog_readiness_v1()) report;
commit;
