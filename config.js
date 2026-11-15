/* AdmiRank public frontend configuration.
   The Supabase publishable/anon key is designed for browser use.
   NEVER put a service_role key in this file. */
window.ADMIRANK_CONFIG = {
  SUPABASE_URL: "https://lpsetyytfggpfmbdwefe.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_zW0zHUUih81Paxp4Q8_lEQ_3p2ffrGi",
  BRAND_NAME: "AdmiRank",
  // Phone-number logins are mapped to a hidden email: <phone>@LOGIN_EMAIL_DOMAIN (no email is ever sent).
  // If you change this, change the same domain in supabase-migration-v27-phone-login.sql too.
  LOGIN_EMAIL_DOMAIN: "phone.admirank.app",
  HELPLINE_WHATSAPP: "8801411422809",   // international format, no +
  HELPLINE_LABEL: "01411422809",
  CURRENCY: "৳",
  // Replace these placeholders with the official AdmiRank payment numbers.
  PAYMENT_ACCOUNTS: {
    bKash: "01717146962",
    Nagad: "01712108137",
    Rocket: "Currently Unavailable"
  },
  // Landing page content. Leave a value empty to use the built-in default / hide the block.
  LANDING: {
    about: "",   // ENTER YOUR ABOUT-US PARAGRAPH HERE (Bengali or English)
    facebook: "https://facebook.com/AdmiRank",
    stats: [     // ENTER YOUR NUMBERS HERE, e.g. { value: "1,200+", label: "Students" } (hidden until filled)
      // { value: "", label: "" },
    ],
    faqs: [      // ENTER EXTRA FAQ HERE, e.g. { q: "Question?", a: "Answer." }
      // { q: "", a: "" },
    ]
  },
  ASSET_PATHS: {
    logo: "./assets/admirank-logo.jpg",
    banner: "./assets/du-a-banner.png",
    coursePoster: "./assets/du-a-course-poster.png"
  }
};
