create or replace function public.cancel_expense(p_expense_id uuid,p_reason text) returns table(expense_id uuid)
language plpgsql security definer set search_path='' as $$
declare v_user public.users%rowtype;v_expense public.expenses%rowtype;
begin
 if (select auth.uid()) is null then raise exception using errcode='42501',message='Authentication required';end if;
 select * into v_user from public.users where id=(select auth.uid()) and active for share;
 if not found or v_user.role<>'SUPER_ADMIN' then raise exception using errcode='42501',message='Only a Super Admin can cancel an expense';end if;
 p_reason:=btrim(coalesce(p_reason,''));
 if char_length(p_reason) not between 5 and 500 then raise exception using errcode='22023',message='Enter a cancellation reason of 5 to 500 characters';end if;
 select * into v_expense from public.expenses where id=p_expense_id and mandal_id=v_user.mandal_id for update;
 if not found then raise exception using errcode='P0002',message='Expense not found';end if;
 if v_expense.cancelled_at is not null then return query select v_expense.id;return;end if;
 update public.expenses set cancelled_at=now(),cancellation_reason=p_reason where id=v_expense.id;
 insert into public.transactions(mandal_id,external_id,type,description,income_minor,expense_minor,status,source_entity_type,source_entity_id,created_by,reason)
 values(v_user.mandal_id,'REV-EXP-'||v_expense.id::text,'ADJUSTMENT','Reversal of cancelled expense: '||v_expense.title,v_expense.amount_minor,0,'ACTIVE','expense_reversal',v_expense.id,v_user.id,p_reason);
 insert into public.audit_logs(mandal_id,user_id,action,entity_type,entity_id,old_data,new_data,reason)
 values(v_user.mandal_id,v_user.id,'CANCEL_EXPENSE','expense',v_expense.id,jsonb_build_object('cancelled_at',null,'amount_minor',v_expense.amount_minor),jsonb_build_object('cancelled_at',now(),'reversal_minor',v_expense.amount_minor),p_reason);
 return query select v_expense.id;
end;$$;
revoke all on function public.cancel_expense(uuid,text) from public,anon;
grant execute on function public.cancel_expense(uuid,text) to authenticated;
