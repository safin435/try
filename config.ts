export const SITE_NAME = process.env.NEXT_PUBLIC_SITE_NAME || "CHORBAKOR ARENA";
export const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";
export const SLOT_TIMES = [
  ["08:00", "10:00"], ["10:00", "12:00"], ["12:00", "14:00"], ["14:00", "16:00"],
  ["16:00", "18:00"], ["18:00", "20:00"], ["20:00", "22:00"], ["22:00", "24:00"]
] as const;
export const SLOT_PRICE = Number(process.env.BOOKING_PRICE_BDT || 2200);
export const ADVANCE_PRICE = Number(process.env.BOOKING_ADVANCE_BDT || 500);
export const HOLD_MINUTES = Number(process.env.BOOKING_HOLD_MINUTES || 10);
