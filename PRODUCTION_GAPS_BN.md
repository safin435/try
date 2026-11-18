# Live launch blockers — CHORBAKOR ARENA

এই মুহূর্তে কোডে:
- Website + booking form + database RPC + slot conflict protection আছে।
- bKash Tokenized Checkout flow-এর server-side skeleton আছে; merchant credentials ও bKash-এর exact approved API version/base URL দিয়ে sandbox test আবশ্যক।
- Supabase phone/email OTP flow আছে; SMS provider ও SMTP configuration ছাড়া OTP delivery হবে না।
- Nagad live adapter ইচ্ছাকৃতভাবে বন্ধ; Nagad-এর official merchant API package ছাড়া secure signature/encryption implementation অনুমান করা যাবে না।
- Admin page role check করে; প্রথম admin profile SQL থেকে assign করতে হবে।

অতএব এই ZIP এখনই “সব gateway-সহ production-ready” নয়। Real money নেওয়ার আগে payment provider-এ sandbox + live validation, database/RLS audit, refund/reconciliation, notification, expiry cron এবং security review শেষ করতে হবে।

## আপডেট ১ (নিরাপত্তা)
- `supabase/migrations/002_security_fixes.sql` চালান (schema.sql-এর পরে): booking RPC শুধু সার্ভার, টাকার অঙ্ক/কারেন্সি যাচাই, paid_amount, payment_events, rate limit।
- bKash finalize এখন amount, currency ও invoice মেলায়; টাকা কাটা কিন্তু স্লট নেই হলে `needs_review` হয়ে অ্যাডমিনের জন্য চিহ্নিত থাকে।
- এখনও বাকি: QR টিকিট, সব পেজ ও বাংলা/ইংরেজি সুইচার, অ্যাডমিন প্যানেল, রিফান্ড, নোটিফিকেশন, টেস্ট।

## Update 1 (নিরাপত্তা সংশোধন)
- supabase/migrations/002_security_fixes.sql চালান (schema.sql-এর পরে)।
- ঠিক হয়েছে: RPC শুধু সার্ভারের জন্য, bKash amount/currency/invoice যাচাই, মেয়াদোত্তীর্ণ হোল্ডে পেমেন্ট হলে needs_refund, paid_amount, ব্লক স্লট, রেট লিমিট, নিরাপদ এরর মেসেজ।
- এখনও বাকি: QR টিকিট, ড্যাশবোর্ড, অ্যাডমিন টুল, বাংলা/ইংরেজি সুইচার, বাকি পেজ, নোটিফিকেশন, টেস্ট।
