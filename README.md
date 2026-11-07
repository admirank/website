# AdmiRank website
Static site (HTML/CSS/JS + supabase-js via CDN). Upload these files to the root of your GitHub repo (keep your existing `assets/` folder), then import the repo in Vercel (no build settings needed).
- Placeholders to fill: `js/config.js` (`payNumber`, `contact`), About text in `js/app.js`.
- Uses only the publishable key. Roles come from `user_roles`; RLS/RPCs enforce access.

## Gaps found in your database (not worked around, need your decision)
1. **No student self-enrollment**: `enrollments` has no student INSERT policy and no RPC. Admin creates a *pending* enrollment (Admin → enrollments); the student then sees "Submit payment".
2. **Leaderboard**: students can read only their own `exam_results`, so no public leaderboard.
3. **Result review**: students have no SELECT on `student_answers`, so submitted-vs-correct answers can't be shown.
4. **Admin student list**: `profiles` is readable only by its owner; admins can't list students.
5. **Question images**: students have no `question-media` policy, so snapshot images can't be shown during exams.
6. **Profile picture upload**: no student-writable bucket exists.
7. Exam-activity logging inserts may be rejected if no student INSERT policy exists (errors are ignored).
8. No "copy questions from bank into exam" function; use the exam_questions / exam_question_options tabs.
