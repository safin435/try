"use client";
import { Suspense } from "react";
import { useSearchParams } from "next/navigation";
function ResultInner() {
  const status = useSearchParams().get("status");
  const success = status === "success", review = status === "review";
  return <main className="container section"><div className="panel" style={{maxWidth:620,margin:"40px auto",textAlign:"center"}}>
    <div style={{fontSize:48,color:success?"var(--green)":"#ff8585"}}>{success?"✓":"!"}</div>
    <h1 style={{fontSize:34}}>{success?"Booking confirmed":review?"Payment received — under review":"Payment not confirmed"}</h1>
    <p className="muted">{success?"Your payment has been verified. Please keep your booking reference.":review?"We received your payment but could not auto-confirm the slot. Our team will contact you or refund you. Please keep your bKash transaction ID.":"Your booking is not confirmed yet. Please contact the arena if money was deducted."}</p>
    <a className="btn" href="/">Back to home</a>
  </div></main>;
}
export default function Result() { return <Suspense><ResultInner /></Suspense>; }
