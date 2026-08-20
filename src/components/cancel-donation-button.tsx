"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function CancelDonationButton({
  donationId,
  receiptNumber,
}: {
  donationId: string;
  receiptNumber: string;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function cancel() {
    if (reason.trim().length < 5) {
      setError("Enter a reason of at least 5 characters.");
      return;
    }
    setBusy(true);
    setError("");
    const { error: rpcError } = await createClient().rpc("cancel_and_redact_cash_donation", {
      p_donation_id: donationId,
      p_reason: reason,
    });
    if (rpcError) {
      setError(rpcError.message || "The donation could not be cancelled.");
      setBusy(false);
      return;
    }
    setOpen(false);
    router.refresh();
  }

  return (
    <>
      <button className="font-bold text-red-700" type="button" onClick={() => setOpen(true)}>
        Cancel & remove details
      </button>
      {open && (
        <div className="fixed inset-0 z-50 grid place-items-center bg-black/50 p-4">
          <div className="card w-full max-w-md p-6">
            <h2 className="text-2xl">Cancel {receiptNumber}?</h2>
            <p className="mt-2 text-sm text-stone-600">
              Donor personal details will be redacted, the public receipt disabled, and a reversal added to the ledger. This cannot be undone.
            </p>
            <label className="mt-5 block">
              <span className="label">Reason</span>
              <textarea
                className="input"
                value={reason}
                onChange={(event) => setReason(event.target.value)}
                maxLength={500}
                rows={3}
                placeholder="Explain why this entry is being cancelled"
              />
            </label>
            {error && <p className="mt-3 text-sm font-semibold text-red-700">{error}</p>}
            <div className="mt-5 flex justify-end gap-2">
              <button className="btn border bg-white" type="button" onClick={() => setOpen(false)} disabled={busy}>Keep donation</button>
              <button className="btn bg-red-700 text-white" type="button" onClick={cancel} disabled={busy}>
                {busy ? "Cancelling…" : "Confirm cancellation"}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
