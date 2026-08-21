import { ExpenseForm } from "@/components/expense-form";
import { CancelExpenseButton } from "@/components/cancel-expense-button";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const revalidate = 0;
const money=(n:number)=>new Intl.NumberFormat("en-IN",{style:"currency",currency:"INR"}).format(n/100);
const category=(v:string)=>v.replaceAll("_"," ").toLowerCase().replace(/\b\w/g,c=>c.toUpperCase());
type Row={id:string;title:string;category:string;amount_minor:number;expense_date:string;paid_by:string;bill_path:string|null;cancelled_at:string|null;cancellation_reason:string|null};

export default async function Page(){
 const sb=await createClient();
 const[{data,error},{data:user}]=await Promise.all([
  sb.from("expenses").select("id,title,category,amount_minor,expense_date,paid_by,bill_path,cancelled_at,cancellation_reason").order("expense_date",{ascending:false}).limit(200),
  sb.from("users").select("role").single(),
 ]);
 const all=(data??[]) as Row[],active=all.filter(x=>!x.cancelled_at),cancelled=all.filter(x=>x.cancelled_at),total=active.reduce((s,x)=>s+x.amount_minor,0),isSuper=user?.role==="SUPER_ADMIN";
 return <div className="p-5 md:p-8">
  <p className="text-sm font-bold text-orange-700">ACCOUNTS</p><h1 className="mt-1 text-4xl">Expenses</h1>
  <p className="mt-2 max-w-2xl text-stone-500">Record expenses with a private bill, immutable ledger entry, and audit trail.</p>
  <div className="card mt-6 p-5"><p className="text-sm text-stone-500">Total active expenses</p><p className="mt-1 text-3xl font-bold">{money(total)}</p></div>
  <ExpenseForm/>
  {error?<p role="alert" className="mt-6 rounded-xl bg-red-50 p-4 font-semibold text-red-800">Expenses could not be loaded.</p>:<>
   <ExpenseTable title="Recent expenses" rows={active} isSuper={isSuper}/>
   {cancelled.length>0&&<section className="card mt-7 overflow-hidden"><div className="border-b p-5"><h2 className="text-2xl">Cancelled expenses</h2><p className="text-sm text-stone-500">Preserved for audit history; reversal entries restore these amounts.</p></div><div className="divide-y">{cancelled.map(x=><article className="p-5" key={x.id}><div className="flex flex-col justify-between gap-2 sm:flex-row"><div><p className="font-bold line-through text-stone-500">{x.title}</p><p className="text-sm text-stone-500">{category(x.category)} · {new Date(x.expense_date+"T00:00:00").toLocaleDateString("en-IN")}</p></div><div className="sm:text-right"><span className="rounded-full bg-red-50 px-3 py-1 text-xs font-bold text-red-700">CANCELLED</span><p className="mt-2 font-bold text-stone-500 line-through">{money(x.amount_minor)}</p></div></div><p className="mt-3 rounded-xl bg-stone-50 p-3 text-sm"><span className="font-bold">Reason:</span> {x.cancellation_reason??"Not recorded"}</p><p className="mt-2 text-xs text-stone-500">Cancelled {x.cancelled_at?new Date(x.cancelled_at).toLocaleString("en-IN"):""}</p></article>)}</div></section>}
  </>}
 </div>;
}

function ExpenseTable({title,rows,isSuper}:{title:string;rows:Row[];isSuper:boolean}){return <section className="card mt-7 overflow-hidden"><div className="border-b p-5"><h2 className="text-2xl">{title}</h2></div>{rows.length===0?<p className="p-6 text-stone-500">No active expenses recorded.</p>:<div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead className="bg-stone-50 text-stone-500"><tr>{["Date","Title","Category","Paid by","Bill","Amount","Action"].map(h=><th className="px-4 py-3" key={h}>{h}</th>)}</tr></thead><tbody>{rows.map(x=><tr className="border-t" key={x.id}><td className="whitespace-nowrap px-4 py-4">{new Date(x.expense_date+"T00:00:00").toLocaleDateString("en-IN")}</td><td className="px-4 py-4 font-semibold">{x.title}</td><td className="px-4 py-4">{category(x.category)}</td><td className="px-4 py-4">{x.paid_by}</td><td className="px-4 py-4">{x.bill_path?"Attached":"—"}</td><td className="px-4 py-4 font-bold">{money(x.amount_minor)}</td><td className="whitespace-nowrap px-4 py-4">{isSuper?<CancelExpenseButton expenseId={x.id} title={x.title}/>:<span className="text-xs text-stone-400">Super Admin only</span>}</td></tr>)}</tbody></table></div>}</section>}
