import { CashDonationForm } from "@/components/cash-donation-form";

export default function NewCashDonationPage() {
  return (
    <div className="p-5 md:p-8">
      <p className="text-sm font-bold text-orange-700">COLLECTION DESK</p>
      <h1 className="mt-1 text-4xl">Record cash donation</h1>
      <p className="mt-2 max-w-2xl text-stone-500">
        Creates a verified cash donation, receipt, ledger entry, and audit record in one secure transaction.
      </p>
      <CashDonationForm />
    </div>
  );
}
