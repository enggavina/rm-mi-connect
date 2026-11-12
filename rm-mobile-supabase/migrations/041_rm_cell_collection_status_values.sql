-- Commit enum additions before operations may use the new values. Existing
-- values and their ordering remain intact; the new states have no terminal rule.
begin;
alter type public.rm_status_cel_proj_enum add value 'aguardando_coleta';
alter type public.rm_status_cel_proj_enum add value 'coletado';
commit;
