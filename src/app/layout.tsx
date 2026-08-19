import type { Metadata } from "next";
import { Inter, Playfair_Display } from "next/font/google";
import "./globals.css";
const inter=Inter({variable:"--font-sans",subsets:["latin"]});
const playfair=Playfair_Display({variable:"--font-display",subsets:["latin"]});
export const metadata:Metadata={title:"Ganpati Chanda Manager",description:"Transparent festival donation management",manifest:"/manifest.webmanifest"};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="en" className={`${inter.variable} ${playfair.variable}`}><body>{children}</body></html>}
