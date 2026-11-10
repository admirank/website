# AdmiRank Website

A responsive, multi-page admission-preparation platform frontend built with HTML, CSS, vanilla JavaScript and the existing Supabase backend.

## 1. Run locally

No build step is required.

```bash
python -m http.server 5500
```

Open `http://localhost:5500`.

You can also use the VS Code Live Server extension. Opening `index.html` directly with `file://` may interfere with authentication redirects; use a local HTTP server.

## 2. Deploy to GitHub + Vercel

1. Upload the contents of this folder to the root of your GitHub repository.
2. Confirm `index.html`, `config.js`, `app.js`, `styles.css`, and `vercel.json` are in the repository root.
3. Import the repository into Vercel.
4. Select **Other** as the framework preset. No build command is required; output directory is `.`.
5. Deploy.

The included `vercel.json` rewrites app routes to `index.html`.

## 3. Supabase configuration

Edit `config.js`:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

The supplied publishable key is prefilled. It is intended for browser use. **Never add a Supabase `service_role` key to frontend code or GitHub.**

The app uses the existing tables and RPC functions from the supplied metadata:
- Auth: Supabase Auth, `profiles`, `user_roles`
- Courses and payments: `courses`, `batches`, `enrollments`, `payments`, `submit_course_payment`, `admin_verify_payment`, `admin_reject_payment`
- Exam engine: `exams`, `exam_attempts`, `exam_questions`, `exam_question_options`, `student_answers`, `start_exam`, `load_exam_questions`, `save_exam_answer`, `submit_exam_attempt`
- Evaluation/results: `answer_evaluations`, `evaluation_rubrics`, `evaluator_assignments`, `exam_results`, `exam_result_publications`
- Content: `banners`, `announcements`, `site_settings`, `coupons`

All authorization remains dependent on Supabase Auth, RLS and backend function checks. Frontend route checks are only navigation/UI, not a security boundary.

## 4. Homepage hero assets

The homepage now uses one fixed, responsive cinematic hero instead of the previous two stacked banners. Its campus artwork is stored at `assets/admirank-hero-campus.jpg`; the headline and the “কোর্সসমূহ দেখুন” button are live HTML, and the button smoothly scrolls to `আমাদের কোর্সসমূহ`.

The previous admin banner-upload/management interface has been disabled. Existing rows in the Supabase `banners` table are left untouched but are no longer rendered on the homepage. The supplied AdmiRank logo and course-poster fallback remain in `assets/`.

## 5. Important configuration items to complete

Search for `Enter your` in the source and replace placeholders before launch. In particular, configure the bKash/Nagad/Rocket receiving account details and confirm the payment instructions.

## 6. New features and database migration

Before deploying this version, run `supabase-migration-v2.sql` in Supabase SQL Editor. It adds course routine/details fields, creates the profile-pictures storage bucket and its owner-only upload policies, and adds a safe published-leaderboard RPC.

The admin exam form now asks for a course, opening/closing date and time, duration, exam title and an Excel question file. To preserve the existing `start_exam()` enrollment security, it internally reuses a batch for that course or creates a system-managed published batch. You do not need to enter or manage a batch ID in the exam form.

Excel question columns: `question_type`, `question_text`, `option_a`, `option_b`, `option_c`, `option_d`, `correct_option`, `answer_text`, `explanation`, `marks`, `negative_marks`. Use `mcq` for multiple choice and `written` for written answers. For MCQ, `correct_option` must be A, B, C or D.

## 7. Implementation notes and known backend dependencies

This frontend deliberately does not create tables, functions, policies or enum types. It calls the RPC functions named in the supplied database metadata and uses the existing table names.

Before production:
- The exam runner is mapped to the supplied RPC response shape. Still test start/resume, saved answers, auto-submit and expiry against the live project.
- **Storage policy mismatch found in supplied metadata:** `save_exam_answer` expects `student-<auth-user-UUID>/attempt-<attempt-UUID>/<filename>`, while the live Storage INSERT policy expression compares path segments 1 and 2 directly to the bare auth UUID and attempt UUID. These expressions conflict, so answer uploads are likely to be rejected by Storage before the RPC can save the path. Align the policy with the RPC's expected path (or change both consistently) in Supabase before relying on written-script uploads. The frontend uses the RPC-expected `student-.../attempt-...` path and does not weaken security.
- Confirm evaluator script access. The schema describes private storage access for assigned evaluators; signed/authenticated preview URLs are not yet implemented in this first frontend pass.
- The supplied policies expose students' own results, not a general public leaderboard. The leaderboard page explains this rather than exposing other students' personal results.
- Question option/image records and exam-question/option snapshots are exposed as admin table-management tabs; the administrator must create the snapshot rows and correct-option flags consistently. Evaluator assignments can be reviewed in the user section; the actual assignment creation workflow should be completed/tested against live constraints before production.
- The schema metadata includes function definitions, and the exam runner follows the supplied `start_exam` and `load_exam_questions` JSON response keys (`attempt_id`, `expires_at`, `questions`, `saved_answer`).

## 8. Security checklist

- Keep service-role credentials off the client.
- Never trust prices, marks, roles, payment status or enrollment status sent from the browser.
- Verify payments in the real provider account before approving them.
- Do not collect payment PINs, OTPs, passwords or CVVs.
- Keep `question-media` and `answer-scripts` private.
- Do not expose correct answers during active attempts.
- Test student, admin and evaluator roles independently.

## Backend gaps found in the supplied metadata

1. **Student enrollment creation is missing:** the listed RLS policies only allow students to select their own enrollment rows; no student INSERT policy or enrollment-creation RPC is listed. The course enrollment screen therefore does not attempt a browser insert. Admin must create a pending enrollment, after which the student can submit payment using the existing secure RPC.
2. **Answer-script storage path policy conflict:** see the storage note above. Align the Storage INSERT/SELECT policies with the exact `save_exam_answer` RPC path convention before enabling written file uploads.
3. **Public leaderboard:** no policy allows students to read other students' results. The leaderboard is intentionally not populated from private `exam_results`.

## Course enrollment and admin access update (v3)

1. Run `supabase-migration-v3-enrollment.sql` in the Supabase SQL Editor after the earlier v2 migration. It adds the secure `create_course_enrollment(p_batch_id)` RPC and automatically enrolls admin-role users in every existing and future batch.
2. In `config.js`, set the `PAYMENT_ACCOUNTS` values to the official AdmiRank bKash, Nagad and Rocket receiving numbers. Leave a value blank only while that provider is not being used.
3. Keep the favicon files in `assets/` with these exact names: `favicon.ico`, `favicon-16x16.png`, and `favicon-32x32.png`. `index.html` references those names.
4. Students can create a pending enrollment from a published batch, submit a provider, TrxID and sender phone last two digits, and wait for an admin to approve or reject the payment. Approval is still performed by the existing `admin_verify_payment` RPC and activates the enrollment.

The payment provider account numbers are intentionally left blank in `config.js`; replace them before accepting payments. Never collect payment PINs or OTPs, and verify each transaction in the actual provider account before approving it.


## November 2026 repair: course details, exam routes and Excel validation

1. Replace the deployed `app.js` with the `app.js` in this package.
2. Keep `index.html`, `styles.css`, `config.js`, and the `assets/` directory in the same deployment root.
3. In Supabase SQL Editor, run `supabase-migration-v4-course-exam-access.sql` after migrations v2 and v3. This enables public reading of published courses/batches and the required authenticated admin/exam access.
4. In `config.js`, fill in the official AdmiRank bKash, Nagad and Rocket receiving numbers before accepting payments. Do not put any PIN, OTP, service-role key or secret key in the frontend.
5. Redeploy the complete project to Vercel (not just the `app.js` file if your deployment root differs).

The course details route now resolves by course ID, slug, or legacy title links and displays the routine, exam schedule, batch enrollment and payment entry point. Exam detail routes preserve their destination through login. Excel import accepts `.xlsx` only, validates the workbook headers and every question before creating an exam, and attempts to remove a partially imported exam if a database write fails.

Important: the frontend and SQL migration can be syntax-checked here, but live payment approval and database permissions still require the migration to be applied to your Supabase project and the receiving numbers to be configured.


## 9. Question bank (v9)

Run `supabase-migration-v9-question-bank.sql` once in the Supabase SQL Editor (after v8).

- **Admin → Question bank** is now where all questions are uploaded. Courses and subjects are fixed: **DU A** (Physics, Chemistry, Math, Biology, Bangla, English) and **DU B** (Bangla, English, General Knowledge).
- Two question types, kept separate: **MCQ** (4 options + correct option) and **Written** (model answer). Every question must also have a **short solution**.
- Add one question at a time (“Save & add another” speeds this up) or use **Bulk upload (Excel)** with `AdmiRank-Question-Template.xlsx` (`subject` column is optional if you choose a default subject).
- Each question shows **Used in** tags with the (shortened) name of every exam it was added to; filter by used / not used.
- **Exams are built from the bank:** tick questions (selection stays while you change filters) → “Make exam from selected”. Questions are copied into the exam as snapshots, so editing or deleting a bank question never changes an existing exam. The old “upload Excel inside Create exam” form was removed.
