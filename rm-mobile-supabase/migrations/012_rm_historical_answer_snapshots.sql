-- Bubble retains submitted answer snapshots after their Questao link is removed.
-- Preserve those exact historical rows; never invent a replacement template link.
begin;
alter table public.rm_respostas alter column questao_id drop not null;
alter table public.rm_respostas add constraint rm_respostas_unlinked_history_only
  check(questao_id is not null or (bubble_id is not null and sync_source in ('bubble','etl')));
comment on constraint rm_respostas_unlinked_history_only on public.rm_respostas is
  'Only identified legacy answer snapshots may lack a question. New mobile submissions and revisions still validate real template question IDs.';
-- validate_form_answers already rejects missing/unknown questao_id for both new
-- submissions and corrections. Unlinked snapshots therefore remain read-only.
notify pgrst,'reload schema';
commit;
