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
  ASSET_PATHS: {
    logo: "./assets/admirank-logo.jpg",
    banner: "./assets/du-a-banner.png",
    coursePoster: "./assets/du-a-course-poster.png"
  }
};