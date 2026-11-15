-- Lets students see the evaluator's pen marks on their own scripts once results are published.
-- Run once in the Supabase SQL Editor.

DROP POLICY IF EXISTS "Students view own annotations after publication" ON public.answer_annotations;
CREATE POLICY "Students view own annotations after publication" ON public.answer_annotations
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.student_answers sa
    JOIN public.exam_attempts ea ON ea.id = sa.attempt_id
    JOIN public.exam_result_publications rp ON rp.exam_id = ea.exam_id
    WHERE sa.id = answer_annotations.student_answer_id
      AND ea.student_id = (SELECT auth.uid())
      AND rp.is_published = true
  )
);

-- Safety net: make sure evaluators can read/write their own pen marks (idempotent).
GRANT SELECT, INSERT, UPDATE ON public.answer_annotations TO authenticated;
