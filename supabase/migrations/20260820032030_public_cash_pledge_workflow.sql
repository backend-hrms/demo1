create or replace function public.submit_cash_pledge(
  p_mandal_id uuid,p_name text,p_mobile text,p_email text,p_address text,
  p_amount_minor bigint,p_idempotency_key text
) returns table(donation_id uuid,request_reference text)
language plpgsql security definer set search_path=''
as $$
declare v_donor_id uuid; v_donation_id uuid;
begin
  p_name:=btrim(coalesce(p_name,''));
  p_mobile:=regexp_replace(coalesce(p_mobile,''),'[^0-9]','','g');
  p_email:=nullif(lower(btrim(coalesce(p_email,''))),'');
  p_address:=nullif(btrim(coalesce(p_address,'')),'');
  p_idempotency_key:=btrim(coalesce(p_idempotency_key,''));
  if not exists(select 1 from public.mandals where id=p_mandal_id) then raise exception using errcode='22023',message='Mandal not found'; end if;
  if char_length(p_name)<2 or char_length(p_name)>120 then raise exception using errcode='22023',message='Enter a valid donor name'; end if;
  if p_mobile!~'^[0-9]{10}$' then raise exception using errcode='22023',message='Enter a valid 10-digit mobile number'; end if;
  if p_email is not null and p_email!~'^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception using errcode='22023',message='Enter a valid email'; end if;
  if char_length(coalesce(p_address,''))>500 then raise exception using errcode='22023',message='Address is too long'; end if;
  if p_amount_minor<100 or p_amount_minor>1000000000 then raise exception using errcode='22023',message='Enter a valid amount'; end if;
  if char_length(p_idempotency_key)<16 or char_length(p_idempotency_key)>100 then raise exception using errcode='22023',message='Invalid submission identifier'; end if;
  if (select count(*) from public.donations where mandal_id=p_mandal_id and donor_mobile_snapshot=p_mobile and payment_method='CASH' and status='PENDING' and created_at>now()-interval '1 hour')>=3 then
    raise exception using errcode='P0001',message='Too many pending cash requests. Please contact the Mandal.';
  end if;
  select id into v_donation_id from public.donations where mandal_id=p_mandal_id and idempotency_key=p_idempotency_key;
  if found then return query select v_donation_id,'CASH-'||upper(left(replace(v_donation_id::text,'-',''),8)); return; end if;
  insert into public.donors(mandal_id,full_name,mobile,email,address)
  values(p_mandal_id,p_name,p_mobile,p_email,p_address) returning id into v_donor_id;
  insert into public.donations(mandal_id,donor_id,amount_minor,currency,payment_method,payment_provider,idempotency_key,status,
    donor_name_snapshot,donor_mobile_snapshot,donor_email_snapshot,donor_address_snapshot,donation_date)
  values(p_mandal_id,v_donor_id,p_amount_minor,'INR','CASH','PUBLIC_CASH_PLEDGE',p_idempotency_key,'PENDING',
    p_name,p_mobile,p_email,p_address,current_date) returning id into v_donation_id;
  insert into public.audit_logs(mandal_id,action,entity_type,entity_id,new_data)
  values(p_mandal_id,'SUBMIT_CASH_PLEDGE','donation',v_donation_id,jsonb_build_object('amount_minor',p_amount_minor,'payment_method','CASH','status','PENDING'));
  return query select v_donation_id,'CASH-'||upper(left(replace(v_donation_id::text,'-',''),8));
end;$$;
revoke all on function public.submit_cash_pledge(uuid,text,text,text,text,bigint,text) from public;
grant execute on function public.submit_cash_pledge(uuid,text,text,text,text,bigint,text) to anon,authenticated;

create or replace function public.verify_cash_pledge(p_donation_id uuid,p_collector text)
returns table(donation_id uuid,receipt_number text)
language plpgsql security definer set search_path=''
as $$
declare v_user public.users%rowtype; v_donation public.donations%rowtype; v_sequence bigint; v_prefix text; v_year integer; v_receipt text;
begin
  if (select auth.uid()) is null then raise exception using errcode='42501',message='Authentication required'; end if;
  select * into v_user from public.users where id=(select auth.uid()) and active for share;
  if not found or v_user.role not in ('SUPER_ADMIN','COLLECTION_MANAGER') then raise exception using errcode='42501',message='Not authorized to verify cash'; end if;
  p_collector:=btrim(coalesce(p_collector,''));
  if char_length(p_collector)<2 or char_length(p_collector)>120 then raise exception using errcode='22023',message='Enter a valid collector name'; end if;
  select * into v_donation from public.donations where id=p_donation_id and mandal_id=v_user.mandal_id for update;
  if not found then raise exception using errcode='P0002',message='Cash request not found'; end if;
  if v_donation.payment_method<>'CASH' or v_donation.status<>'PENDING' then raise exception using errcode='22023',message='This cash request cannot be verified'; end if;
  select s.receipt_prefix,m.festival_year into v_prefix,v_year from public.settings s join public.mandals m on m.id=s.mandal_id where s.mandal_id=v_user.mandal_id for update of s;
  update public.settings set next_receipt_number=next_receipt_number+1,updated_at=now(),updated_by=v_user.id where mandal_id=v_user.mandal_id returning next_receipt_number-1 into v_sequence;
  v_receipt:=v_prefix||'-'||v_year::text||'-'||lpad(v_sequence::text,6,'0');
  update public.donations set receipt_number=v_receipt,status='VERIFIED',verified_at=now(),verified_by=v_user.id,collector_name=p_collector where id=v_donation.id;
  insert into public.receipts(mandal_id,donation_id,receipt_number) values(v_user.mandal_id,v_donation.id,v_receipt);
  insert into public.transactions(mandal_id,external_id,type,description,income_minor,expense_minor,status,source_entity_type,source_entity_id,created_by)
  values(v_user.mandal_id,'CASH-'||v_donation.id::text,'CASH_DONATION','Cash donation receipt '||v_receipt,v_donation.amount_minor,0,'ACTIVE','donation',v_donation.id,v_user.id);
  insert into public.audit_logs(mandal_id,user_id,action,entity_type,entity_id,old_data,new_data)
  values(v_user.mandal_id,v_user.id,'VERIFY_CASH_PLEDGE','donation',v_donation.id,jsonb_build_object('status','PENDING'),jsonb_build_object('status','VERIFIED','receipt_number',v_receipt));
  return query select v_donation.id,v_receipt;
end;$$;
revoke all on function public.verify_cash_pledge(uuid,text) from public,anon;
grant execute on function public.verify_cash_pledge(uuid,text) to authenticated;
