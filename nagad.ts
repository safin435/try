/**
 * Nagad integration intentionally fails closed until the merchant supplies
 * the official integration package/API specification issued for their own
 * merchant account. Do not guess signature/encryption rules or use unofficial
 * endpoints. Once the official pack is available, implement create + verify
 * + callback signature validation here.
 */
export async function createNagadPayment(_bookingId: string, _amount: number) {
  if (process.env.NAGAD_ENABLED !== "true") {
    throw new Error("Nagad is not activated. Add the official Nagad merchant API integration pack and credentials first.");
  }
  throw new Error("Nagad adapter awaits the official merchant-specific API specification.");
}
