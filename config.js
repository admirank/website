/* AdmiRank public frontend configuration.
   The Supabase publishable/anon key is designed for browser use.
   NEVER put a service_role key in this file. */
window.ADMIRANK_CONFIG = {
  SUPABASE_URL: "https://lpsetyytfggpfmbdwefe.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_zW0zHUUih81Paxp4Q8_lEQ_3p2ffrGi",
  BRAND_NAME: "AdmiRank",
  CURRENCY: "৳",
  // Replace these placeholders with the official AdmiRank payment numbers.
  PAYMENT_ACCOUNTS: {
    bKash: "",
    Nagad: "",
    Rocket: ""
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