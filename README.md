# CHORBAKOR ARENA — Full-stack production codebase

এই প্যাকেজটি একটি বাস্তব Full-stack Next.js + Supabase প্রজেক্টের সোর্স কোড। শুধু ZIP upload করলেই লাইভ পেমেন্ট/OTP কাজ করবে না। Hosting, Supabase project, SMS/Email provider এবং merchant API credentials কনফিগার করতে হবে।

## 1) Requirements
- Node.js 20.9+ (recommended)
- Supabase project with PostgreSQL + Auth
- Hosting that supports Next.js (Vercel recommended)
- Domain DNS access for `chorbakorarena.com`
- bKash Tokenized Checkout live merchant API credentials
- Nagad-issued official merchant integration package/credentials
- SMS provider configured in Supabase Auth for phone OTP
- SMTP configured in Supabase Auth for email OTP

## 2) Install
```bash
npm install
cp .env.example .env.local
```
Fill `.env.local`. Never commit `.env.local` or expose service-role/payment secrets.

## 3) Database
Supabase Dashboard → SQL Editor → run `supabase/schema.sql`.

Create a user by signing up through the app, then assign that user as admin from SQL Editor:
```sql
update public.profiles set role='admin'
where id = 'AUTH_USER_UUID';
```
The `profiles` row must be created for the user. You can insert it:
```sql
insert into public.profiles(id, full_name, role)
values ('AUTH_USER_UUID','Arena Owner','admin')
on conflict (id) do update set role='admin';
```
Do not make role updates available to public users.

## 4) Auth / OTP
In Supabase → Authentication → Providers:
- Enable Phone provider and configure a supported SMS provider.
- Enable Email provider and configure SMTP + email OTP template.
- Set allowed redirect URLs to `https://chorbakorarena.com/**`.
- Enable CAPTCHA and tune OTP rate limits before public launch.
Phone OTP will not deliver until an SMS provider is connected.

## 5) bKash
Set the four bKash credentials from your own merchant onboarding pack:
- `BKASH_USERNAME`
- `BKASH_PASSWORD`
- `BKASH_APP_KEY`
- `BKASH_APP_SECRET`
Use the exact production base URL and API version supplied by bKash. The default is the common Tokenized Checkout v1.2.0-beta URL; verify with your merchant pack before production. Test in sandbox first. Never share these secrets in chat or source control.

The current implementation uses grant-token → create-payment → customer redirect → execute-payment on callback. Production review should also add the provider's Query Payment reconciliation job and refund API workflow before enabling real customers.

## 6) Nagad — activation blocked pending official merchant pack
Nagad's merchant integrations can vary by onboarding/API version. This project intentionally fails closed for Nagad rather than guessing cryptographic signing, encryption, endpoint paths, or callback validation. Add the official merchant-specific API documentation and credentials issued to your Nagad merchant account, then implement `src/lib/payments/nagad.ts` with:
- payment initialization,
- signed callback validation,
- server-side payment verification,
- transaction ID / amount / currency / merchant validation,
- idempotent booking confirmation.
Do not switch `NAGAD_ENABLED=true` until this code is completed and tested. Do not use unofficial API code copied from unknown sources.

## 7) Booking rules
- 8 fixed slots per day, 08:00–24:00 Bangladesh time.
- Two-hour slot duration.
- Default slot price BDT 2,200 and advance BDT 500.
- Hold default 10 minutes.
- A PostgreSQL partial unique index prevents two active bookings for the same date + start time.
- Payment is confirmed server-side only.

## 8) Deploy
1. Push project to a private Git repository.
2. Import into Vercel.
3. Add every `.env.example` variable in Vercel Project Settings → Environment Variables.
4. Set `NEXT_PUBLIC_SITE_URL=https://chorbakorarena.com`.
5. Connect domain and configure DNS as instructed by hosting.
6. Deploy and test all flows on sandbox/staging.
7. Switch to live merchant credentials only after bKash/Nagad provider approval and end-to-end test.

## 9) Important production work still required
- Nagad adapter (official merchant-specific spec required).
- Admin booking actions (manual booking, block slot, pricing editor, cancellation/refund UI).
- Automated expiry worker/cron for held bookings (the unique slot is released during next booking request; configure scheduled cleanup for reporting).
- Email/SMS notification templates and delivery provider.
- QR ticket generation and downloadable PDF.
- Query-payment reconciliation and refund workflow.
- Rate limiting/CAPTCHA on booking and auth endpoints.
- Security review, privacy policy, terms, cancellation/refund policy, backups, monitoring.
- Legal/merchant approval and test transactions.

**This is deployable source code, not a claim that merchant accounts have already been connected or verified.**
