alter table public.settings add column if not exists next_receipt_number bigint not null default 1 check (next_receipt_number > 0);
alter table public.donations add column if not exists donation_date date not null default current_date;
alter table public.donations add column if not exists collector_name text;
alter table public.donations add column if not exists notes text;

create or replace function public.record_cash_donation(
  p_name text, p_mobile text, p_amount_minor bigint, p_date date,
  p_collector text, p_notes text, p_idempotency_key text
) returns table(donation_id uuid, receipt_number text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_user public.users%rowtype;
  v_existing public.donations%rowtype;
  v_donor_id uuid;
  v_donation_id uuid;
  v_receipt_number text;
  v_sequence bigint;
  v_prefix text;
  v_year integer;
begin
  if (select auth.uid()) is null then
    raise exception using errcode='42501', message='Authentication required';
  end if;

  select * into v_user from public.users
  where id=(select auth.uid()) and active for share;
  if not found or v_user.role not in ('SUPER_ADMIN','COLLECTION_MANAGER') then
    raise exception using errcode='42501', message='Not authorized to record cash donations';
  end if;

  p_name := btrim(coalesce(p_name,''));
  p_mobile := regexp_replace(coalesce(p_mobile,''),'[^0-9]','','g');
  p_collector := btrim(coalesce(p_collector,''));
  p_notes := nullif(btrim(coalesce(p_notes,'')),'');
  p_idempotency_key := btrim(coalesce(p_idempotency_key,''));

  if char_length(p_name) < 2 or char_length(p_name) > 120 then
    raise exception using errcode='22023', message='Enter a valid donor name';
  end if;
  if p_mobile !~ '^[0-9]{10}$' then
    raise exception using errcode='22023', message='Enter a valid 10-digit mobile number';
  end if;
  if p_amount_minor < 100 or p_amount_minor > 1000000000 then
    raise exception using errcode='22023', message='Amount must be between ₹1 and ₹1,00,00,000';
  end if;
  if p_date is null or p_date > current_date or p_date < current_date - 366 then
    raise exception using errcode='22023', message='Enter a valid donation date';
  end if;
  if char_length(p_collector) < 2 or char_length(p_collector) > 120 then
    raise exception using errcode='22023', message='Enter a valid collector name';
  end if;
  if char_length(coalesce(p_notes,'')) > 1000 then
    raise exception using errcode='22023', message='Notes are too long';
  end if;
  if char_length(p_idempotency_key) < 16 or char_length(p_idempotency_key) > 100 then
    raise exception using errcode='22023', message='Invalid submission identifier';
  end if;

  select * into v_existing from public.donations
  where mandal_id=v_user.mandal_id and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.payment_method='CASH' and v_existing.status='VERIFIED' then
      return query select v_existing.id,v_existing.receipt_number;
      return;
    end if;
    raise exception using errcode='23505', message='Duplicate submission';
  end if;

  select s.receipt_prefix,m.festival_year into v_prefix,v_year
  from public.settings s join public.mandals m on m.id=s.mandal_id
  where s.mandal_id=v_user.mandal_id for update of s;
  if not found then
    raise exception using errcode='P0001', message='Mandal settings are incomplete';
  end if;

  update public.settings set next_receipt_number=next_receipt_number+1,
    updated_at=now(),updated_by=v_user.id
  where mandal_id=v_user.mandal_id
  returning next_receipt_number-1 into v_sequence;
  v_receipt_number := v_prefix||'-'||v_year::text||'-'||lpad(v_sequence::text,6,'0');

  insert into public.donors(mandal_id,full_name,mobile)
  values(v_user.mandal_id,p_name,p_mobile) returning id into v_donor_id;

  insert into public.donations(
    mandal_id,donor_id,receipt_number,amount_minor,currency,payment_method,
    payment_provider,transaction_id,idempotency_key,status,donor_name_snapshot,
    donor_mobile_snapshot,donation_date,collector_name,notes,verified_at,verified_by
  ) values(
    v_user.mandal_id,v_donor_id,v_receipt_number,p_amount_minor,'INR','CASH',
    'MANUAL',null,p_idempotency_key,'VERIFIED',p_name,p_mobile,p_date,
    p_collector,p_notes,now(),v_user.id
  ) returning id into v_donation_id;

  insert into public.receipts(mandal_id,donation_id,receipt_number)
  values(v_user.mandal_id,v_donation_id,v_receipt_number);
  insert into public.transactions(
    mandal_id,external_id,type,description,income_minor,expense_minor,status,
    source_entity_type,source_entity_id,created_by
  ) values(
    v_user.mandal_id,'CASH-'||v_donation_id::text,'CASH_DONATION',
    'Cash donation receipt '||v_receipt_number,p_amount_minor,0,'ACTIVE',
    'donation',v_donation_id,v_user.id
  );
  insert into public.audit_logs(mandal_id,user_id,action,entity_type,entity_id,new_data)
  values(v_user.mandal_id,v_user.id,'CREATE_CASH_DONATION','donation',v_donation_id,
    jsonb_build_object('receipt_number',v_receipt_number,'amount_minor',p_amount_minor,'payment_method','CASH'));

  return query select v_donation_id,v_receipt_number;
end;
$$;

revoke all on function public.record_cash_donation(text,text,bigint,date,text,text,text) from public,anon;
grant execute on function public.record_cash_donation(text,text,bigint,date,text,text,text) to authenticated;
