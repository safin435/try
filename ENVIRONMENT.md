# Environment variable checklist

| Variable | Where from | Secret? |
|---|---|---|
| NEXT_PUBLIC_SUPABASE_URL | Supabase project | No |
| NEXT_PUBLIC_SUPABASE_ANON_KEY | Supabase project | No |
| SUPABASE_SERVICE_ROLE_KEY | Supabase project API settings | YES |
| BKASH_USERNAME/PASSWORD | bKash merchant onboarding | YES |
| BKASH_APP_KEY/SECRET | bKash merchant onboarding | YES |
| Nagad keys/certs | Official Nagad merchant onboarding | YES |
| NEXT_PUBLIC_SITE_URL | Your deployed domain | No |

Never place secret values in browser code or public NEXT_PUBLIC variables.
