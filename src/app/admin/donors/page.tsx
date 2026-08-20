import Link from "next/link";
import { Search, Users } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { CancelDonationButton } from "@/components/cancel-donation-button";

type DonationRow = {
  id: string;
  receipt_number: string | null;
  donor_name_snapshot: string;
  donor_mobile_snapshot: string;
  amount_minor: number;
  payment_method: string;
  status: string;
  donation_date: string;
  created_at: string;
  transaction_id: string | null;
};

const money = (minor: number) =>
  new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 2,
  }).format(minor / 100);

export default async function DonorsPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; status?: string }>;
}) {
  const params = await searchParams;
  const query = (params.q ?? "").trim().toLowerCase();
  const status = params.status ?? "ALL";
  const supabase = await createClient();

  const [{ data: donations, error }, { data: userData }] = await Promise.all([
    supabase
      .from("donations")
      .select(
        "id,receipt_number,donor_name_snapshot,donor_mobile_snapshot,amount_minor,payment_method,status,donation_date,created_at,transaction_id",
      )
      .order("created_at", { ascending: false })
      .limit(500),
    supabase.from("users").select("role").single(),
  ]);

  const rows = ((donations ?? []) as DonationRow[]).filter((row) => {
    const matchesStatus = status === "ALL" || row.status === status;
    const haystack = [
      row.donor_name_snapshot,
      row.donor_mobile_snapshot,
      row.receipt_number,
      row.transaction_id,
    ]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();
    return matchesStatus && (!query || haystack.includes(query));
  });

  return (
    <div className="p-5 md:p-8">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-end">
        <div>
          <p className="text-sm font-bold text-orange-700">COLLECTION REGISTER</p>
          <h1 className="mt-1 text-4xl">Donations & donors</h1>
          <p className="mt-2 text-stone-500">Search donors, open receipts, and reverse incorrect cash entries.</p>
        </div>
        <Link href="/admin/donations/new" className="btn btn-primary">Record cash donation</Link>
      </div>

      <form className="card mt-7 grid gap-3 p-4 sm:grid-cols-[1fr_190px_auto]">
        <label className="relative">
          <Search className="absolute left-3 top-3.5 text-stone-400" size={18} />
          <input
            className="input pl-10"
            name="q"
            defaultValue={params.q}
            placeholder="Name, mobile, receipt or transaction"
          />
        </label>
        <select className="input" name="status" defaultValue={status}>
          <option value="ALL">All statuses</option>
          <option value="VERIFIED">Verified</option>
          <option value="PENDING">Pending</option>
          <option value="FAILED">Failed</option>
          <option value="REFUNDED">Refunded</option>
          <option value="CANCELLED">Cancelled</option>
        </select>
        <button className="btn border border-stone-300 bg-white" type="submit">Apply</button>
      </form>

      {error ? (
        <div className="card mt-5 p-6 text-red-700">Donations could not be loaded. Please refresh.</div>
      ) : rows.length === 0 ? (
        <div className="card mt-5 py-16 text-center">
          <Users className="mx-auto text-stone-300" size={40} />
          <p className="mt-3 font-bold">No matching donations</p>
          <p className="mt-1 text-sm text-stone-500">New cash donations will appear here immediately.</p>
        </div>
      ) : (
        <div className="card mt-5 overflow-hidden">
          <div className="hidden overflow-x-auto md:block">
            <table className="w-full text-left text-sm">
              <thead className="bg-stone-50 text-xs uppercase text-stone-500">
                <tr>
                  {["Receipt","Donor","Mobile","Amount","Method","Status","Date","Actions"].map((heading) => (
                    <th className="px-4 py-3" key={heading}>{heading}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-stone-100">
                {rows.map((row) => (
                  <tr key={row.id}>
                    <td className="px-4 py-4 font-semibold">{row.receipt_number ?? "Pending"}</td>
                    <td className="px-4 py-4">{row.donor_name_snapshot}</td>
                    <td className="px-4 py-4">{row.donor_mobile_snapshot}</td>
                    <td className="px-4 py-4 font-bold">{money(row.amount_minor)}</td>
                    <td className="px-4 py-4">{row.payment_method}</td>
                    <td className="px-4 py-4">
                      <span className="rounded-full bg-stone-100 px-2 py-1 text-xs font-bold">{row.status}</span>
                    </td>
                    <td className="px-4 py-4">{new Date(row.donation_date).toLocaleDateString("en-IN")}</td>
                    <td className="px-4 py-4">
                      <div className="flex gap-2">
                        {row.receipt_number && row.status === "VERIFIED" && (
                          <Link className="font-bold text-orange-700" href={`/receipt/${row.receipt_number}`}>Receipt</Link>
                        )}
                        {userData?.role === "SUPER_ADMIN" && row.payment_method === "CASH" && row.status === "VERIFIED" && (
                          <CancelDonationButton donationId={row.id} receiptNumber={row.receipt_number ?? ""} />
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="divide-y md:hidden">
            {rows.map((row) => (
              <article className="p-4" key={row.id}>
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-bold">{row.donor_name_snapshot}</p>
                    <p className="text-sm text-stone-500">{row.donor_mobile_snapshot}</p>
                  </div>
                  <p className="font-bold">{money(row.amount_minor)}</p>
                </div>
                <div className="mt-3 flex items-center justify-between text-xs">
                  <span>{row.receipt_number ?? "Pending receipt"} · {row.payment_method}</span>
                  <span className="rounded-full bg-stone-100 px-2 py-1 font-bold">{row.status}</span>
                </div>
                <div className="mt-4 flex gap-4 text-sm">
                  {row.receipt_number && row.status === "VERIFIED" && (
                    <Link className="font-bold text-orange-700" href={`/receipt/${row.receipt_number}`}>View receipt</Link>
                  )}
                  {userData?.role === "SUPER_ADMIN" && row.payment_method === "CASH" && row.status === "VERIFIED" && (
                    <CancelDonationButton donationId={row.id} receiptNumber={row.receipt_number ?? ""} />
                  )}
                </div>
              </article>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
