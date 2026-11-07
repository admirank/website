-- AdmiRank: repair public course pages, exam detail pages and admin Excel imports.
-- Run AFTER supabase-migration-v2.sql and supabase-migration-v3-enrollment.sql.
-- This migration grants only the read/write access required by the frontend.

CREATE OR REPLACE FUNCTION public.is_admirank_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles ur
    WHERE ur.user_id = auth.uid()
      AND ur.role = 'admin'
  );
$$;

REVOKE ALL ON FUNCTION public.is_admirank_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admirank_admin() TO anon, authenticated;

-- Course detail pages must be readable by visitors; unpublished courses remain admin-only.
DROP POLICY IF EXISTS "AdmiRank public published courses read" ON public.courses;
CREATE POLICY "AdmiRank public published courses read"
ON public.courses FOR SELECT TO anon, authenticated
USING (status = 'published' OR public.is_admirank_admin());

DROP POLICY IF EXISTS "AdmiRank admins manage courses" ON public.courses;
CREATE POLICY "AdmiRank admins manage courses"
ON public.courses FOR ALL TO authenticated
USING (public.is_admirank_admin())
WITH CHECK (public.is_admirank_admin());

-- Students can see published/ongoing batches; admins can see and manage all batches.
DROP POLICY IF EXISTS "AdmiRank public active batches read" ON public.batches;
CREATE POLICY "AdmiRank public active batches read"
ON public.batches FOR SELECT TO anon, authenticated
USING (status IN ('published', 'ongoing') OR public.is_admirank_admin());

DROP POLICY IF EXISTS "AdmiRank admins manage batches" ON public.batches;
CREATE POLICY "AdmiRank admins manage batches"
ON public.batches FOR ALL TO authenticated
USING (public.is_admirank_admin())
WITH CHECK (public.is_admirank_admin());

-- Exam metadata is visible to admins and to students with an active enrollment
-- in the exam's batch. Students still start exams only through the secure RPC.
DROP POLICY IF EXISTS "AdmiRank admins manage exams" ON public.exams;
CREATE POLICY "AdmiRank admins manage exams"
ON public.exams FOR ALL TO authenticated
USING (public.is_admirank_admin())
WITH CHECK (public.is_admirank_admin());

DROP POLICY IF EXISTS "AdmiRank enrolled students read exam metadata" ON public.exams;
CREATE POLICY "AdmiRank enrolled students read exam metadata"
ON public.exams FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.batches b
    JOIN public.enrollments en ON en.batch_id = b.id
    WHERE b.id = exams.batch_id
      AND en.student_id = auth.uid()
      AND en.status = 'active'
  )
);

-- Only admins can directly inspect/edit question snapshots and answer keys.
-- Student question delivery remains through load_exam_questions().
DROP POLICY IF EXISTS "AdmiRank admins manage exam questions" ON public.exam_questions;
CREATE POLICY "AdmiRank admins manage exam questions"
ON public.exam_questions FOR ALL TO authenticated
USING (public.is_admirank_admin())
WITH CHECK (public.is_admirank_admin());

DROP POLICY IF EXISTS "AdmiRank admins manage exam question options" ON public.exam_question_options;
CREATE POLICY "AdmiRank admins manage exam question options"
ON public.exam_question_options FOR ALL TO authenticated
USING (public.is_admirank_admin())
WITH CHECK (public.is_admirank_admin());

-- Students can read their own enrollment rows; admins can read all enrollments.
DROP POLICY IF EXISTS "AdmiRank users read own enrollments" ON public.enrollments;
CREATE POLICY "AdmiRank users read own enrollments"
ON public.enrollments FOR SELECT TO authenticated
USING (student_id = auth.uid() OR public.is_admirank_admin());

-- Payment status and verification metadata are private to the payer and admins.
DROP POLICY IF EXISTS "AdmiRank users read own payments" ON public.payments;
CREATE POLICY "AdmiRank users read own payments"
ON public.payments FOR SELECT TO authenticated
USING (
  public.is_admirank_admin()
  OR EXISTS (
    SELECT 1 FROM public.enrollments en
    WHERE en.id = payments.enrollment_id
      AND en.student_id = auth.uid()
  )
);

-- Ensure the browser roles have the table privileges required for the policies.
GRANT SELECT ON public.courses, public.batches TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.courses, public.batches TO authenticated;
GRANT SELECT ON public.exams, public.enrollments, public.payments TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.exams TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.exam_questions, public.exam_question_options TO authenticated;

-- NOTE: Do not put the Supabase service_role/secret key in config.js or app.js.
