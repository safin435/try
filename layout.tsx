import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "CHORBAKOR ARENA | Football Turf Booking",
  description: "Book your football turf slot online at CHORBAKOR ARENA.",
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL || "https://chorbakorarena.com")
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
