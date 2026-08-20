"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { CheckCircle2, Loader2, ReceiptIndianRupee } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

type CashDonationResult = {
  donation_id: string;
  receipt_number: string;
};

function today() {
  const date = new Date();
  const offset = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 10);
}

export function CashDonationForm() {
  const router = useRouter();
  const submissionId = useRef(crypto.randomUUID());
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [savedReceipt, setSavedReceipt] = useState("");

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;

    const form = event.currentTarget;
    const values = new FormData(form);
    const amountRupees = Number(values.get("amount"));

    if (!Number.isFinite(amountRupees) || amountRupees < 1) {
      setError("Enter a valid donation amount.");
      return;
    }

    setBusy(true);
    setError("");

    const supabase = createClient();
    const { data, error: rpcError } = await supabase.rpc("record_cash_donation", {
      p_name: String(values.get("name") ?? ""),
      p_mobile: String(values.get("mobile") ?? ""),
      p_amount_minor: Math.round(amountRupees * 100),
      p_date: String(values.get("date") ?? ""),
      p_collector: String(values.get("collector") ?? ""),
      p_notes: String(values.get("notes") ?? ""),
      p_idempotency_key: submissionId.current,
    });

    if (rpcError) {
      setError(
        rpcError.code === "42501"
          ? "Your session expired or you are not authorized. Sign in again."
          : rpcError.message || "The donation could not be saved. Please try again.",
      );
      setBusy(false);
      return;
    }

    const result = (data as CashDonationResult[] | null)?.[0];
    if (!result?.receipt_number) {
      setError("The donation was saved, but its receipt could not be opened.");
      setBusy(false);
      return;
    }

    setSavedReceipt(result.receipt_number);
    submissionId.current = crypto.randomUUID();
    form.reset();
    window.setTimeout(
      () => router.push(`/receipt/${encodeURIComponent(result.receipt_number)}`),
      700,
    );
  }

  return (
    <form onSubmit={submit} className="card mt-7 max-w-4xl p-5 md:p-7">
      <div className="grid gap-5 sm:grid-cols-2">
        <label>
          <span className="label">Donor name</span>
          <input className="input" name="name" minLength={2} maxLength={120} required />
        </label>
        <label>
          <span className="label">Mobile number</span>
          <input
            className="input"
            name="mobile"
            inputMode="numeric"
            pattern="[0-9]{10}"
            maxLength={10}
            placeholder="10-digit number"
            required
          />
        </label>
        <label>
          <span className="label">Amount (₹)</span>
          <input className="input" name="amount" type="number" min="1" max="10000000" step="0.01" required />
        </label>
        <label>
          <span className="label">Donation date</span>
          <input className="input" name="date" type="date" defaultValue={today()} max={today()} required />
        </label>
        <label className="sm:col-span-2">
          <span className="label">Collector</span>
          <input className="input" name="collector" minLength={2} maxLength={120} required />
        </label>
        <label className="sm:col-span-2">
          <span className="label">Notes (optional)</span>
          <textarea className="input" name="notes" maxLength={1000} rows={3} />
        </label>
      </div>

      {error && (
        <p role="alert" className="mt-5 rounded-xl bg-red-50 p-3 text-sm font-semibold text-red-800">
          {error}
        </p>
      )}
      {savedReceipt && (
        <p className="mt-5 flex items-center gap-2 rounded-xl bg-emerald-50 p-3 text-sm font-semibold text-emerald-800">
          <CheckCircle2 size={18} /> Saved as {savedReceipt}. Opening receipt…
        </p>
      )}

      <button disabled={busy} className="btn btn-primary mt-6 w-full sm:w-auto" type="submit">
        {busy ? <Loader2 className="animate-spin" size={18} /> : <ReceiptIndianRupee size={18} />}
        {busy ? "Saving donation…" : "Save and generate receipt"}
      </button>
      <p className="mt-3 text-xs text-stone-500">
        Duplicate clicks are safely ignored. Financial records cannot be permanently deleted.
      </p>
    </form>
  );
}
