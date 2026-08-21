alter table public.withdrawals add column if not exists cancelled_at timestamptz;
alter table public.withdrawals add column if not exists cancelled_by uuid references public.users(id);
alter table public.withdrawals add column if not exists cancellation_reason text;

create or replace function public.cancel_withdrawal_request(p_withdrawal_id uuid,p_reason text) returns table(withdrawal_id uuid)
language plpgsql security definer set search_path='' as $$
declare v_user public.users%rowtype;v_row public.withdrawals%rowtype;
begin
 if (select auth.uid()) is null then raise exception using errcode='42501',message='Authentication required';end if;
 select * into v_user from public.users where id=(select auth.uid()) and active for share;
 if not found or v_user.role<>'SUPER_ADMIN' then raise exception using errcode='42501',message='Only a Super Admin can cancel withdrawal requests';end if;
 p_reason:=btrim(coalesce(p_reason,''));
 if char_length(p_reason) not between 5 and 500 then raise exception using errcode='22023',message='Enter a cancellation reason of 5 to 500 characters';end if;
 select * into v_row from public.withdrawals where id=p_withdrawal_id and mandal_id=v_user.mandal_id for update;
 if not found then raise exception using errcode='P0002',message='Withdrawal request not found';end if;
 if v_row.cancelled_at is not null then return query select v_row.id;return;end if;
 if v_row.status not in ('REQUESTED','APPROVED') then raise exception using errcode='22023',message='Only requested or approved withdrawals can be cancelled';end if;
 update public.withdrawals set status='REJECTED',cancelled_at=now(),cancelled_by=v_user.id,cancellation_reason=p_reason where id=v_row.id;
 insert into public.audit_logs(mandal_id,user_id,action,entity_type,entity_id,old_data,new_data,reason)
 values(v_user.mandal_id,v_user.id,'CANCEL_WITHDRAWAL_REQUEST','withdrawal',v_row.id,jsonb_build_object('status',v_row.status),jsonb_build_object('status','CANCELLED','amount_minor',v_row.amount_minor),p_reason);
 return query select v_row.id;
end;$$;
revoke all on function public.cancel_withdrawal_request(uuid,text) from public,anon;
grant execute on function public.cancel_withdrawal_request(uuid,text) to authenticated;
