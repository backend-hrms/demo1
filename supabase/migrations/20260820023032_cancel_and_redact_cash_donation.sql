create or replace function public.cancel_and_redact_cash_donation(p_donation_id uuid,p_reason text)
returns boolean language plpgsql security definer set search_path=''
as $$
declare
  v_user public.users%rowtype;
  v_donation public.donations%rowtype;
begin
  if (select auth.uid()) is null then
    raise exception using errcode='42501',message='Authentication required';
  end if;
  select * into v_user from public.users where id=(select auth.uid()) and active for share;
  if not found or v_user.role <> 'SUPER_ADMIN' then
    raise exception using errcode='42501',message='Only a super administrator can cancel donations';
  end if;
  p_reason:=btrim(coalesce(p_reason,''));
  if char_length(p_reason)<5 or char_length(p_reason)>500 then
    raise exception using errcode='22023',message='Enter a cancellation reason of at least 5 characters';
  end if;
  select * into v_donation from public.donations
  where id=p_donation_id and mandal_id=v_user.mandal_id for update;
  if not found then raise exception using errcode='P0002',message='Donation not found'; end if;
  if v_donation.payment_method<>'CASH' then
    raise exception using errcode='22023',message='Online donations require the provider refund workflow';
  end if;
  if v_donation.status='CANCELLED' then return true; end if;
  if v_donation.status<>'VERIFIED' then
    raise exception using errcode='22023',message='Only verified cash donations can be cancelled';
  end if;

  insert into public.transactions(
    mandal_id,external_id,type,description,income_minor,expense_minor,status,
    source_entity_type,source_entity_id,reversal_of,created_by,reason
  )
  select v_user.mandal_id,'REV-'||v_donation.id::text,'ADJUSTMENT',
    'Reversal of cash receipt '||v_donation.receipt_number,0,v_donation.amount_minor,
    'ACTIVE','donation_reversal',v_donation.id,t.id,v_user.id,p_reason
  from public.transactions t
  where t.source_entity_type='donation' and t.source_entity_id=v_donation.id
  order by t.created_at limit 1;

  if not found then
    raise exception using errcode='P0001',message='Original ledger entry was not found';
  end if;

  update public.donations set status='CANCELLED',cancelled_at=now(),
    cancellation_reason=p_reason,donor_name_snapshot='Deleted donor',
    donor_mobile_snapshot='**********',donor_email_snapshot=null,
    donor_address_snapshot=null,notes=null
  where id=v_donation.id;

  update public.donors set full_name='Deleted donor',mobile='0000000000',
    email=null,address=null,updated_at=now()
  where id=v_donation.donor_id;

  insert into public.audit_logs(mandal_id,user_id,action,entity_type,entity_id,old_data,new_data,reason)
  values(v_user.mandal_id,v_user.id,'CANCEL_AND_REDACT_CASH_DONATION','donation',v_donation.id,
    jsonb_build_object('receipt_number',v_donation.receipt_number,'status',v_donation.status,'amount_minor',v_donation.amount_minor),
    jsonb_build_object('receipt_number',v_donation.receipt_number,'status','CANCELLED','personal_details','REDACTED'),p_reason);
  return true;
end;
$$;
revoke all on function public.cancel_and_redact_cash_donation(uuid,text) from public,anon;
grant execute on function public.cancel_and_redact_cash_donation(uuid,text) to authenticated;
