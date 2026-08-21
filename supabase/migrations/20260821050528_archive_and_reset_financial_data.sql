create schema if not exists private;

create table if not exists private.financial_archive_batches (
  id uuid primary key default gen_random_uuid(),
  mandal_id uuid not null,
  archived_at timestamptz not null default now(),
  reason text not null,
  source_counts jsonb not null,
  donors jsonb not null,
  donations jsonb not null,
  receipts jsonb not null,
  expenses jsonb not null,
  withdrawals jsonb not null,
  transactions jsonb not null,
  audit_logs jsonb not null,
  webhook_events jsonb not null
);

revoke all on schema private from public, anon, authenticated;
revoke all on table private.financial_archive_batches from public, anon, authenticated;

do $$
declare
  v_mandal_id uuid;
  v_mandal_count integer;
begin
  select count(*) into v_mandal_count from public.mandals;
  if v_mandal_count <> 1 then
    raise exception 'Fresh-start reset requires exactly one mandal; found %', v_mandal_count;
  end if;
  select id into strict v_mandal_id from public.mandals;

  lock table public.webhook_events, public.receipts, public.transactions,
    public.audit_logs, public.expenses, public.withdrawals, public.donations,
    public.donors, public.settings in share row exclusive mode;

  insert into private.financial_archive_batches (
    mandal_id, reason, source_counts, donors, donations, receipts,
    expenses, withdrawals, transactions, audit_logs, webhook_events
  )
  select
    v_mandal_id,
    'User-requested fresh start from 2026-08-21; operational balances reset to zero',
    jsonb_build_object(
      'donors', (select count(*) from public.donors where mandal_id = v_mandal_id),
      'donations', (select count(*) from public.donations where mandal_id = v_mandal_id),
      'receipts', (select count(*) from public.receipts where mandal_id = v_mandal_id),
      'expenses', (select count(*) from public.expenses where mandal_id = v_mandal_id),
      'withdrawals', (select count(*) from public.withdrawals where mandal_id = v_mandal_id),
      'transactions', (select count(*) from public.transactions where mandal_id = v_mandal_id),
      'audit_logs', (select count(*) from public.audit_logs where mandal_id = v_mandal_id),
      'webhook_events', (select count(*) from public.webhook_events we where exists (
        select 1 from public.donations d where d.id = we.donation_id and d.mandal_id = v_mandal_id
      ))
    ),
    coalesce((select jsonb_agg(to_jsonb(x)) from public.donors x where x.mandal_id = v_mandal_id), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(x)) from public.donations x where x.mandal_id = v_mandal_id), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(x)) from public.receipts x where x.mandal_id = v_mandal_id), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(x)) from public.expenses x where x.mandal_id = v_mandal_id), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(x)) from public.withdrawals x where x.mandal_id = v_mandal_id), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(x)) from public.transactions x where x.mandal_id = v_mandal_id), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(x)) from public.audit_logs x where x.mandal_id = v_mandal_id), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(x)) from public.webhook_events x where exists (
      select 1 from public.donations d where d.id = x.donation_id and d.mandal_id = v_mandal_id
    )), '[]'::jsonb);

  -- This one-time, archived reset is the only operation permitted to bypass
  -- the normal no-delete financial safeguards.
  alter table public.audit_logs disable trigger audit_logs_no_delete;
  alter table public.donations disable trigger donations_no_delete;
  alter table public.expenses disable trigger expenses_no_delete;
  alter table public.transactions disable trigger transactions_no_delete;
  alter table public.withdrawals disable trigger withdrawals_no_delete;

  delete from public.webhook_events we where exists (
    select 1 from public.donations d where d.id = we.donation_id and d.mandal_id = v_mandal_id
  );
  delete from public.receipts where mandal_id = v_mandal_id;
  delete from public.transactions where mandal_id = v_mandal_id;
  delete from public.audit_logs where mandal_id = v_mandal_id;
  delete from public.expenses where mandal_id = v_mandal_id;
  delete from public.withdrawals where mandal_id = v_mandal_id;
  delete from public.donations where mandal_id = v_mandal_id;
  delete from public.donors where mandal_id = v_mandal_id;

  update public.settings
  set next_receipt_number = 1, updated_at = now()
  where mandal_id = v_mandal_id;

  alter table public.audit_logs enable trigger audit_logs_no_delete;
  alter table public.donations enable trigger donations_no_delete;
  alter table public.expenses enable trigger expenses_no_delete;
  alter table public.transactions enable trigger transactions_no_delete;
  alter table public.withdrawals enable trigger withdrawals_no_delete;
end;
$$;
