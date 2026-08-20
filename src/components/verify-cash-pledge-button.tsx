"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function VerifyCashPledgeButton({ donationId }: { donationId: string }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [collector, setCollector] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function verify() {
    if (collector.trim().length < 2) {
      setError("Enter the collector name.");
      return;
    }
    setBusy(true);
    const { data, error: rpcError } = await createClient().rpc("verify_cash_pledge", {
      p_donation_id: donationId,
      p_collector: collector,
    });
    if (rpcError) {
      setError(rpcError.message || "Cash could not be verified.");
      setBusy(false);
      return;
    }
    const receipt = (data as { receipt_number: string }[] | null)?.[0]?.receipt_number;
    setOpen(false);
    if (receipt) router.push(`/receipt/${encodeURIComponent(receipt)}`);
    else router.refresh();
  }

  return (
    <>
      <button className="font-bold text-emerald-700" type="button" onClick={() => setOpen(true)}>Confirm cash received</button>
      {open && (
        <div className="fixed inset-0 z-50 grid place-items-center bg-black/50 p-4">
          <div className="card w-full max-w-md p-6">
            <h2 className="text-2xl">Confirm cash received</h2>
            <p className="mt-2 text-sm text-stone-600">Confirm only after the collector has physically received the donation. This will generate the verified receipt.</p>
            <label className="mt-5 block"><span className="label">Collector name</span><input className="input" value={collector} onChange={(e) => setCollector(e.target.value)} maxLength={120} /></label>
            {error && <p className="mt-3 text-sm font-semibold text-red-700">{error}</p>}
            <div className="mt-5 flex justify-end gap-2">
              <button className="btn border bg-white" type="button" onClick={() => setOpen(false)} disabled={busy}>Not received</button>
              <button className="btn bg-emerald-700 text-white" type="button" onClick={verify} disabled={busy}>{busy ? "Verifying…" : "Confirm and issue receipt"}</button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
