"use client";

import { useRef, useState } from "react";
import { HandCoins, IndianRupee, Loader2, LockKeyhole } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

const presets = [101, 501, 1001, 2001];

export function DonationForm() {
  const [amount, setAmount] = useState(501);
  const [method, setMethod] = useState("UPI");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const submissionId = useRef(crypto.randomUUID());

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage("");

    if (method !== "CASH") {
      setMessage("Online payment is still in development mode. No real payment was charged.");
      return;
    }

    setBusy(true);
    const values = new FormData(event.currentTarget);
    const { data, error } = await createClient().rpc("submit_cash_pledge", {
      p_mandal_id: process.env.NEXT_PUBLIC_MANDAL_ID!,
      p_name: String(values.get("name") ?? ""),
      p_mobile: String(values.get("mobile") ?? ""),
      p_email: String(values.get("email") ?? ""),
      p_address: String(values.get("address") ?? ""),
      p_amount_minor: Math.round(amount * 100),
      p_idempotency_key: submissionId.current,
    });

    if (error) {
      setMessage(error.message || "Cash request could not be submitted.");
      setBusy(false);
      return;
    }

    const result = (data as { request_reference: string }[] | null)?.[0];
    setMessage(
      `Cash request ${result?.request_reference ?? ""} submitted. Pay an authorized Mandal collector. Your receipt will be issued only after the admin confirms receiving cash.`,
    );
    submissionId.current = crypto.randomUUID();
    setBusy(false);
  }

  return (
    <form onSubmit={submit} className="card p-5 md:p-8">
      <p className="text-sm font-bold text-orange-700">CHOOSE AN AMOUNT</p>
      <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-4">
        {presets.map((value) => (
          <button
            type="button"
            key={value}
            onClick={() => setAmount(value)}
            className={`rounded-xl border p-3 font-bold ${amount === value ? "border-orange-600 bg-orange-50" : "border-stone-200"}`}
          >
            ₹{value.toLocaleString("en-IN")}
          </button>
        ))}
      </div>
      <div className="mt-5">
        <label className="label">Custom amount</label>
        <div className="relative">
          <IndianRupee className="absolute left-3 top-3.5" size={17} />
          <input className="input pl-9" type="number" min="1" max="10000000" value={amount} onChange={(e) => setAmount(Number(e.target.value))} />
        </div>
      </div>
      <div className="mt-5 grid gap-4 sm:grid-cols-2">
        <label><span className="label">Full name</span><input className="input" name="name" required minLength={2} maxLength={120} /></label>
        <label><span className="label">Mobile number</span><input className="input" name="mobile" required inputMode="numeric" pattern="[0-9]{10}" maxLength={10} /></label>
        <label><span className="label">Email (optional)</span><input className="input" name="email" type="email" /></label>
        <label>
          <span className="label">Payment method</span>
          <select className="input" value={method} onChange={(e) => setMethod(e.target.value)}>
            <option value="CASH">Cash donation</option>
            <option value="UPI">UPI — development mode</option>
            <option value="CARD">Card — development mode</option>
            <option value="NETBANKING">Netbanking — development mode</option>
          </select>
        </label>
      </div>
      <label className="mt-4 block"><span className="label">Address (optional)</span><textarea className="input" name="address" maxLength={500} rows={2} /></label>

      {method === "CASH" && (
        <div className="mt-5 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
          <p className="flex items-center gap-2 font-bold"><HandCoins size={18} /> Cash donation process</p>
          <p className="mt-1">Submit your request, pay an authorized collector, and receive a verified receipt after the admin confirms the cash.</p>
        </div>
      )}

      <button className="btn btn-primary mt-6 w-full" type="submit" disabled={busy}>
        {busy ? <Loader2 className="animate-spin" size={17} /> : <LockKeyhole size={17} />}
        {method === "CASH" ? "Submit cash donation request" : `Continue securely · ₹${amount.toLocaleString("en-IN")}`}
      </button>
      {message && <p className="mt-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">{message}</p>}
      <p className="mt-4 text-center text-xs text-stone-500">A receipt is issued only after cash or online payment is verified.</p>
    </form>
  );
}
