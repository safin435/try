"use client";
import { useEffect, useMemo, useState } from "react";
import { SLOT_TIMES, SLOT_PRICE, ADVANCE_PRICE } from "@/lib/config";

type Slot = { start_time: string; end_time: string; status: string };
const labels = (s: string) => {
  const [h,m] = s.split(":").map(Number);
  const ap = h < 12 ? "AM" : "PM";
  const hour = h % 12 || 12;
  return `${String(hour).padStart(2,"0")}:${String(m).padStart(2,"0")} ${ap}`;
};

export default function BookingWidget() {
  const [date,setDate] = useState(new Date(Date.now()-new Date().getTimezoneOffset()*60000).toISOString().slice(0,10));
  const [slots,setSlots] = useState<Slot[]>([]);
  const [selected,setSelected] = useState<number|null>(null);
  const [loading,setLoading] = useState(false);
  const [error,setError] = useState("");
  const [form,setForm] = useState({name:"",phone:"",email:"",payment:"advance",provider:"bkash"});
  const [message,setMessage] = useState("");
  const minDate = useMemo(()=>new Date().toISOString().slice(0,10),[]);
  async function load() {
    setLoading(true); setError("");
    try {
      const r = await fetch(`/api/slots?date=${date}`,{cache:"no-store"});
      const j = await r.json(); if(!r.ok) throw new Error(j.error || "Could not load slots");
      setSlots(j.slots || []); setSelected(null);
    } catch(e:any) { setError(e.message); }
    finally { setLoading(false); }
  }
  useEffect(()=>{load();},[date]);
  async function book() {
    setError(""); setMessage("");
    if(selected===null) return setError("Please choose an available slot.");
    if(!form.name.trim() || !form.phone.trim()) return setError("Name and mobile number are required.");
    setLoading(true);
    try {
      const slot = SLOT_TIMES[selected];
      const r = await fetch("/api/bookings",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({
        date, startTime:slot[0], endTime:slot[1], customerName:form.name, phone:form.phone,
        email:form.email || null, paymentType:form.payment, provider:form.provider
      })});
      const j = await r.json(); if(!r.ok) throw new Error(j.error || "Booking could not be created");
      if(j.checkoutUrl) window.location.href = j.checkoutUrl;
      else setMessage(`Booking created: ${j.bookingCode}. Payment setup is not complete for this provider.`);
      await load();
    } catch(e:any) { setError(e.message); }
    finally { setLoading(false); }
  }
  return <div className="panel" style={{marginTop:24}}>
    <div className="row between"><strong>Select date / তারিখ</strong><span className="badge">2 HOUR SLOTS</span></div>
    <div className="field"><input aria-label="Booking date" type="date" min={minDate} value={date} onChange={e=>setDate(e.target.value)}/></div>
    <div className="row between" style={{margin:"18px 0 12px"}}><strong>Available times</strong><span className="muted" style={{fontSize:12}}>08:00 AM – 12:00 AM</span></div>
    {loading?<p className="muted">Loading availability…</p>:<div className="grid">{SLOT_TIMES.map((s,i)=>{
      const slot = slots.find(x=>x.start_time===s[0]);
      const booked = slot?.status==="confirmed" || slot?.status==="held" || slot?.status==="blocked";
      return <button key={s[0]} disabled={booked} onClick={()=>setSelected(i)} className={`slot ${booked?"booked":"available"} ${selected===i?"selected":""}`}>
        <strong>{labels(s[0])} – {labels(s[1]==="24:00"?"00:00":s[1])}</strong>
        <small>{booked ? (slot?.status==="blocked"?"Unavailable":"Booked") : selected===i?"Selected":"Available"}</small>
      </button>;
    })}</div>}
    <div className="row between" style={{marginTop:20}}><span className="muted">Slot price</span><strong>৳{SLOT_PRICE.toLocaleString("en-BD")}</strong></div>
    <div className="field"><label>Full name / নাম</label><input value={form.name} onChange={e=>setForm({...form,name:e.target.value})} placeholder="Your full name"/></div>
    <div className="field"><label>Mobile number / মোবাইল</label><input value={form.phone} onChange={e=>setForm({...form,phone:e.target.value})} placeholder="01XXXXXXXXX"/></div>
    <div className="field"><label>Email (optional)</label><input type="email" value={form.email} onChange={e=>setForm({...form,email:e.target.value})} placeholder="you@example.com"/></div>
    <div className="grid" style={{gridTemplateColumns:"repeat(2,1fr)"}}>
      <div className="field"><label>Payment option</label><select value={form.payment} onChange={e=>setForm({...form,payment:e.target.value})}><option value="advance">Advance ৳{ADVANCE_PRICE}</option><option value="full">Full ৳{SLOT_PRICE}</option></select></div>
      <div className="field"><label>Payment provider</label><select value={form.provider} onChange={e=>setForm({...form,provider:e.target.value})}><option value="bkash">bKash</option><option value="nagad">Nagad</option></select></div>
    </div>
    {error&&<p style={{color:"#ff8585"}}>{error}</p>}{message&&<p style={{color:"var(--green)"}}>{message}</p>}
    <button className="btn" disabled={loading} onClick={book} style={{width:"100%",marginTop:8}}>{loading?"PLEASE WAIT…":"CONTINUE TO BOOKING →"}</button>
    <p className="muted" style={{fontSize:12,marginTop:12}}>A slot is held only after the server creates a booking. Payment confirmation is verified server-side.</p>
  </div>;
}
