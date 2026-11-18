import { createAdminClient } from "@/lib/supabase/admin";
import { SITE_URL } from "@/lib/config";

const base = process.env.BKASH_BASE_URL;
const required = ["BKASH_USERNAME", "BKASH_PASSWORD", "BKASH_APP_KEY", "BKASH_APP_SECRET"] as const;

function credentials() {
  for (const k of required) if (!process.env[k]) throw new Error(`${k} is missing`);
  if (!base) throw new Error("BKASH_BASE_URL is missing");
  return {
    username: process.env.BKASH_USERNAME!,
    password: process.env.BKASH_PASSWORD!,
    appKey: process.env.BKASH_APP_KEY!,
    appSecret: process.env.BKASH_APP_SECRET!
  };
}

async function bkashFetch(path: string, init: RequestInit) {
  const res = await fetch(`${base}${path}`, { ...init, signal: AbortSignal.timeout(30000), cache: "no-store" });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.statusMessage || data.message || `bKash API error ${res.status}`);
  return data;
}

async function grantToken() {
  const c = credentials();
  return bkashFetch("/token/grant", {
    method: "POST",
    headers: {
      "Content-Type": "application/json", Accept: "application/json",
      username: c.username, password: c.password, "X-App-Key": c.appKey
    },
    body: JSON.stringify({ app_key: c.appKey, app_secret: c.appSecret })
  });
}

export async function createBkashPayment(bookingId: string, amount: number, payerReference: string) {
  const c = credentials();
  const token = await grantToken();
  if (!token.id_token) throw new Error("bKash did not return an access token");
  const created = await bkashFetch("/create", {
    method: "POST",
    headers: {
      "Content-Type": "application/json", Accept: "application/json",
      Authorization: token.id_token, "X-App-Key": c.appKey,
      username: c.username, password: c.password
    },
    body: JSON.stringify({
      mode: "0011", payerReference: payerReference.slice(0, 30),
      callbackURL: `${SITE_URL}/api/payments/bkash/callback`,
      amount: amount.toFixed(2), currency: "BDT", intent: "sale",
      merchantInvoiceNumber: bookingId.slice(0, 30)
    })
  });
  if (!created.paymentID || !created.bkashURL) throw new Error("Invalid bKash create-payment response");
  return { paymentId: created.paymentID as string, checkoutUrl: created.bkashURL as string };
}

export async function executeBkashPayment(paymentId: string) {
  const c = credentials();
  const token = await grantToken();
  return bkashFetch("/execute", {
    method: "POST",
    headers: {
      "Content-Type": "application/json", Accept: "application/json",
      Authorization: token.id_token, "X-App-Key": c.appKey,
      username: c.username, password: c.password
    },
    body: JSON.stringify({ paymentID: paymentId })
  });
}

export async function finalizeBkashPayment(paymentId: string) {
  const db = createAdminClient();
  const { data: payment } = await db.from("payments")
    .select("id,booking_id,amount,status").eq("provider_payment_id", paymentId).single();
  if (!payment) throw new Error("Payment record not found");
  if (payment.status === "paid") return payment;             // duplicate callback: do nothing
  const result = await executeBkashPayment(paymentId);
  await db.from("payment_events").insert({ payment_id: payment.id, event_type: "bkash_execute", payload: result });
  if (result.transactionStatus !== "Completed" || !result.trxID) {
    await db.from("payments").update({ status: "failed" }).eq("id", payment.id).eq("status", "pending");
    throw new Error(result.statusMessage || "bKash transaction is not completed");
  }
  // Server-side checks against OUR records, never the browser's word.
  if (result.merchantInvoiceNumber !== String(payment.booking_id).slice(0, 30)) throw new Error("Invoice mismatch");
  const { data: outcome, error } = await db.rpc("confirm_booking_payment", {
    p_payment_id: payment.id, p_provider_transaction_id: result.trxID, p_provider_payload: result,
    p_amount: Math.round(Number(result.amount)), p_currency: String(result.currency || "")
  });
  if (error) throw new Error(error.message);
  return { ...payment, outcome };
}
