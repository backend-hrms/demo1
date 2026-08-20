create or replace function public.request_withdrawal(p_amount_minor bigint,p_purpose text,p_payment_method public.payment_method,p_description text default null,p_document_path text default null)
returns table(withdrawal_id uuid) language plpgsql security definer set search_path='' as $$
declare v_user public.users%rowtype; v_id uuid;
begin
 select * into v_user from public.users where id=auth.uid() and active=true;
 if not found or v_user.role not in ('SUPER_ADMIN','ACCOUNT_MANAGER') then raise exception using errcode='42501',message='You are not authorized to request withdrawals'; end if;
 p_purpose:=btrim(coalesce(p_purpose,''));p_description:=nullif(btrim(coalesce(p_description,'')),'');p_document_path:=nullif(btrim(coalesce(p_document_path,'')),'');
 if p_amount_minor<100 or p_amount_minor>1000000000 then raise exception using errcode='22023',message='Enter a valid withdrawal amount';end if;
 if char_length(p_purpose) not between 3 and 200 then raise exception using errcode='22023',message='Enter a valid purpose';end if;
 if char_length(coalesce(p_description,''))>2000 then raise exception using errcode='22023',message='Description is too long';end if;
 if p_document_path is not null and (char_length(p_document_path)>500 or p_document_path not like v_user.mandal_id::text||'/withdrawals/%') then raise exception using errcode='22023',message='Invalid document path';end if;
 insert into public.withdrawals(mandal_id,amount_minor,purpose,status,requested_by,payment_method,description,supporting_document_path)
 values(v_user.mandal_id,p_amount_minor,p_purpose,'REQUESTED',v_user.id,p_payment_method,p_description,p_document_path) returning id into v_id;
 insert into public.audit_logs(mandal_id,user_id,action,entity_type,entity_id,new_data) values(v_user.mandal_id,v_user.id,'REQUEST_WITHDRAWAL','withdrawal',v_id,jsonb_build_object('amount_minor',p_amount_minor,'purpose',p_purpose,'status','REQUESTED'));
 return query select v_id;
end;$$;

create or replace function public.transition_withdrawal(p_withdrawal_id uuid,p_action text)
returns table(status public.withdrawal_status) language plpgsql security definer set search_path='' as $$
declare v_user public.users%rowtype;v_row public.withdrawals%rowtype;v_action text:=upper(btrim(coalesce(p_action,'')));
begin
 select * into v_user from public.users where id=auth.uid() and active=true;
 if not found or v_user.role<>'SUPER_ADMIN' then raise exception using errcode='42501',message='Only a Super Admin can approve or complete withdrawals';end if;
 select * into v_row from public.withdrawals where id=p_withdrawal_id and mandal_id=v_user.mandal_id for update;
 if not found then raise exception using errcode='P0002',message='Withdrawal not found';end if;
 if v_action='APPROVE' and v_row.status='REQUESTED' then
   update public.withdrawals set status='APPROVED',approved_by=v_user.id,approved_at=now() where id=v_row.id;
   insert into public.audit_logs(mandal_id,user_id,action,entity_type,entity_id,old_data,new_data) values(v_user.mandal_id,v_user.id,'APPROVE_WITHDRAWAL','withdrawal',v_row.id,jsonb_build_object('status','REQUESTED'),jsonb_build_object('status','APPROVED'));
   return query select 'APPROVED'::public.withdrawal_status;
 elsif v_action='REJECT' and v_row.status='REQUESTED' then
   update public.withdrawals set status='REJECTED',approved_by=v_user.id,approved_at=now() where id=v_row.id;
   insert into public.audit_logs(mandal_id,user_id,action,entity_type,entity_id,old_data,new_data) values(v_user.mandal_id,v_user.id,'REJECT_WITHDRAWAL','withdrawal',v_row.id,jsonb_build_object('status','REQUESTED'),jsonb_build_object('status','REJECTED'));
   return query select 'REJECTED'::public.withdrawal_status;
 elsif v_action='COMPLETE' and v_row.status='APPROVED' then
   update public.withdrawals set status='COMPLETED',completed_by=v_user.id,completed_at=now() where id=v_row.id;
   insert into public.transactions(mandal_id,external_id,type,description,income_minor,expense_minor,status,source_entity_type,source_entity_id,created_by)
   values(v_user.mandal_id,'WDL-'||v_row.id::text,'WITHDRAWAL',v_row.purpose,0,v_row.amount_minor,'ACTIVE','withdrawal',v_row.id,v_user.id);
   insert into public.audit_logs(mandal_id,user_id,action,entity_type,entity_id,old_data,new_data) values(v_user.mandal_id,v_user.id,'COMPLETE_WITHDRAWAL','withdrawal',v_row.id,jsonb_build_object('status','APPROVED'),jsonb_build_object('status','COMPLETED','amount_minor',v_row.amount_minor));
   return query select 'COMPLETED'::public.withdrawal_status;
 else raise exception using errcode='22023',message='This withdrawal cannot make that status change';end if;
end;$$;
revoke all on function public.request_withdrawal(bigint,text,public.payment_method,text,text) from public,anon;
grant execute on function public.request_withdrawal(bigint,text,public.payment_method,text,text) to authenticated;
revoke all on function public.transition_withdrawal(uuid,text) from public,anon;
grant execute on function public.transition_withdrawal(uuid,text) to authenticated;
