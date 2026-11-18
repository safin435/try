# Payment test plan

1. Test bKash in sandbox only first.
2. Test successful payment and verify transaction ID, amount, currency, and booking ID server-side.
3. Test cancel/fail/timeout and ensure the slot does not become confirmed.
4. Replay the callback and ensure idempotency (no duplicate payment/booking).
5. Simulate a payment that is successful at provider but callback is delayed; reconcile with provider Query Payment.
6. Test partial/advance payment and remaining due amount.
7. For Nagad, do not test or enable until the official merchant integration pack is implemented and reviewed.
8. Before live mode, get provider approval and perform a low-value controlled transaction under the merchant's approved process.
