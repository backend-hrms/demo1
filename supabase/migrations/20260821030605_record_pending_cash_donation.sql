create or replace function public.record_pending_cash_donation(p_name text,p_mobile text,p_amount_minor bigint,p_date date,p_notes text,p_idempotency_key text) returns table(donation_id uuid) language plpgsql security definer set search_path='' as $$
declare v_user public.users%rowtype;v_existing public.donations%rowtype;v_donor_id uuid;v_donation_id uuid;
begin
 if (select auth.uid()) is null then raise exception using errcode='42501',message='Authentication required';end if;
 select * into v_user from public.users where id=(select auth.uid()) and active for share;
 if not found or v_user.role not in ('SUPER_ADMIN','COLLECTION_MANAGER') then raise exception using errcode='42501',message='Not authorized to record pending donations';end if;
 p_name:=btrim(coalesce(p_name,''));p_mobile:=regexp_replace(coalesce(p_mobile,''),'[^0-9]','','g');p_notes:=nullif(btrim(coalesce(p_notes,'')),'');p_idempotency_key:=btrim(coalesce(p_idempotency_key,''));
 if char_length(p_name) not between 2 and 120 then raise exception using errcode='22023',message='Enter a valid donor name';end if;
 if p_mobile!~'^[0-9]{10}$' then raise exception using errcode='22023',message='Enter a valid 10-digit mobile number';end if;
 if p_amount_minor<100 or p_amount_minor>1000000000 then raise exception using errcode='22023',message='Enter a valid pending amount';end if;
 if p_date is null or p_date>current_date or p_date<current_date-366 then raise exception using errcode='22023',message='Enter a valid pledge date';end if;
 if char_length(coalesce(p_notes,''))>1000 then raise exception using errcode='22023',message='Notes are too long';end if;
 if char_length(p_idempotency_key) not between 16 and 100 then raise exception using errcode='22023',message='Invalid submission identifier';end if;
 select * into v_existing from public.donations where mandal_id=v_user.mandal_id and idempotency_key=p_idempotency_key;
 if found then return query select v_existing.id;return;end if;
 insert into public.donors(mandal_id,full_name,mobile) values(v_user.mandal_id,p_name,p_mobile) returning id into v_donor_id;
 insert into public.donations(mandal_id,donor_id,amount_minor,currency,payment_method,payment_provider,idempotency_key,status,donor_name_snapshot,donor_mobile_snapshot,donation_date,notes) values(v_user.mandal_id,v_donor_id,p_amount_minor,'INR','CASH','ADMIN_PAY_LATER',p_idempotency_key,'PENDING',p_name,p_mobile,p_date,p_notes) returning id into v_donation_id;
 insert into public.audit_logs(mandal_id,user_id,action,entity_type,entity_id,new_data) values(v_user.mandal_id,v_user.id,'CREATE_PENDING_CASH_DONATION','donation',v_donation_id,jsonb_build_object('amount_minor',p_amount_minor,'payment_method','CASH','status','PENDING','source','ADMIN_PAY_LATER'));
 return query select v_donation_id;
end;$$;
revoke all on function public.record_pending_cash_donation(text,text,bigint,date,text,text) from public,anon;
grant execute on function public.record_pending_cash_donation(text,text,bigint,date,text,text) to authenticated;
