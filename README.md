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

## 4. Add your existing image assets

Copy the following files from your existing repository into `assets/`:

- `admirank-logo.jpg`
- `du-a-banner.png`
- `du-a-course-poster.png`

If a file is missing, the interface uses a fallback. Replace these images later without changing application code.

## 5. Important configuration items to complete

Search for `Enter your` in the source and replace placeholders before launch. In particular, configure the bKash/Nagad/Rocket receiving account details and confirm the payment instructions.

## 6. Implementation notes and known backend dependencies

This frontend deliberately does not create tables, functions, policies or enum types. It calls the RPC functions named in the supplied database metadata and uses the existing table names.

Before production:
- The exam runner is mapped to the supplied RPC response shape. Still test start/resume, saved answers, auto-submit and expiry against the live project.
- **Storage policy mismatch found in supplied metadata:** `save_exam_answer` expects `student-<auth-user-UUID>/attempt-<attempt-UUID>/<filename>`, while the live Storage INSERT policy expression compares path segments 1 and 2 directly to the bare auth UUID and attempt UUID. These expressions conflict, so answer uploads are likely to be rejected by Storage before the RPC can save the path. Align the policy with the RPC's expected path (or change both consistently) in Supabase before relying on written-script uploads. The frontend uses the RPC-expected `student-.../attempt-...` path and does not weaken security.
- Confirm evaluator script access. The schema describes private storage access for assigned evaluators; signed/authenticated preview URLs are not yet implemented in this first frontend pass.
- The supplied policies expose students' own results, not a general public leaderboard. The leaderboard page explains this rather than exposing other students' personal results.
- Question option/image records and exam-question/option snapshots are exposed as admin table-management tabs; the administrator must create the snapshot rows and correct-option flags consistently. Evaluator assignments can be reviewed in the user section; the actual assignment creation workflow should be completed/tested against live constraints before production.
- The schema metadata includes function definitions, and the exam runner follows the supplied `start_exam` and `load_exam_questions` JSON response keys (`attempt_id`, `expires_at`, `questions`, `saved_answer`).

## 7. Security checklist

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
