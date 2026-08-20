create or replace function public.record_expense(
  p_title text, p_category public.expense_category, p_amount_minor bigint, p_date date,
  p_paid_by text, p_description text default null, p_bill_path text default null, p_notes text default null
)
returns table(expense_id uuid) language plpgsql security definer set search_path = '' as $$
declare v_user public.users%rowtype; v_expense_id uuid;
begin
  select * into v_user from public.users where id=auth.uid() and active=true;
  if not found or v_user.role not in ('SUPER_ADMIN','ACCOUNT_MANAGER') then raise exception using errcode='42501',message='You are not authorized to record expenses'; end if;
  p_title:=btrim(coalesce(p_title,'')); p_paid_by:=btrim(coalesce(p_paid_by,''));
  p_description:=nullif(btrim(coalesce(p_description,'')),''); p_notes:=nullif(btrim(coalesce(p_notes,'')),''); p_bill_path:=nullif(btrim(coalesce(p_bill_path,'')),'');
  if char_length(p_title) not between 2 and 160 then raise exception using errcode='22023',message='Enter a valid expense title'; end if;
  if char_length(p_paid_by) not between 2 and 120 then raise exception using errcode='22023',message='Enter who paid the expense'; end if;
  if p_amount_minor < 100 or p_amount_minor > 1000000000 then raise exception using errcode='22023',message='Enter a valid expense amount'; end if;
  if p_date is null or p_date > current_date or p_date < current_date-366 then raise exception using errcode='22023',message='Enter a valid expense date'; end if;
  if char_length(coalesce(p_description,''))>2000 or char_length(coalesce(p_notes,''))>1000 then raise exception using errcode='22023',message='Expense details are too long'; end if;
  if p_bill_path is not null and (char_length(p_bill_path)>500 or p_bill_path not like v_user.mandal_id::text||'/expenses/%') then raise exception using errcode='22023',message='Invalid bill file path'; end if;
  insert into public.expenses(mandal_id,title,category,amount_minor,expense_date,paid_by,description,bill_path,notes,created_by)
  values(v_user.mandal_id,p_title,p_category,p_amount_minor,p_date,p_paid_by,p_description,p_bill_path,p_notes,v_user.id) returning id into v_expense_id;
  insert into public.transactions(mandal_id,external_id,type,description,income_minor,expense_minor,status,source_entity_type,source_entity_id,created_by)
  values(v_user.mandal_id,'EXP-'||v_expense_id::text,'EXPENSE',p_title,0,p_amount_minor,'ACTIVE','expense',v_expense_id,v_user.id);
  insert into public.audit_logs(mandal_id,user_id,action,entity_type,entity_id,new_data) values(v_user.mandal_id,v_user.id,'CREATE_EXPENSE','expense',v_expense_id,jsonb_build_object('title',p_title,'category',p_category,'amount_minor',p_amount_minor,'expense_date',p_date,'bill_attached',p_bill_path is not null));
  return query select v_expense_id;
end; $$;
revoke all on function public.record_expense(text,public.expense_category,bigint,date,text,text,text,text) from public,anon;
grant execute on function public.record_expense(text,public.expense_category,bigint,date,text,text,text,text) to authenticated;
drop policy if exists documents_delete on storage.objects;
create policy documents_delete on storage.objects for delete to authenticated using (bucket_id='mandal-documents' and (storage.foldername(name))[1]=(select private.current_mandal_id())::text and (select private.current_role()) in ('SUPER_ADMIN','ACCOUNT_MANAGER'));
