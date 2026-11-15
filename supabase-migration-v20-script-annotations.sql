-- Stores the evaluator's pen marks (underlines etc.) for each written script.
-- The student's original answer image is never modified; marks are a separate layer.
-- Run once in the Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS public.answer_annotations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_answer_id uuid NOT NULL REFERENCES public.student_answers(id) ON DELETE CASCADE,
  evaluator_id uuid NOT NULL,
  strokes jsonb NOT NULL DEFAULT '[]'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (student_answer_id, evaluator_id)
);

ALTER TABLE public.answer_annotations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage answer annotations" ON public.answer_annotations;
CREATE POLICY "Admins manage answer annotations" ON public.answer_annotations
FOR ALL TO authenticated USING (public.has_role('admin'::text)) WITH CHECK (public.has_role('admin'::text));

DROP POLICY IF EXISTS "Evaluators view own annotations" ON public.answer_annotations;
CREATE POLICY "Evaluators view own annotations" ON public.answer_annotations
FOR SELECT TO authenticated
USING (evaluator_id = (SELECT auth.uid()) AND public.has_role('evaluator'::text));

DROP POLICY IF EXISTS "Evaluators insert own annotations" ON public.answer_annotations;
CREATE POLICY "Evaluators insert own annotations" ON public.answer_annotations
FOR INSERT TO authenticated
WITH CHECK (
  evaluator_id = (SELECT auth.uid()) AND public.has_role('evaluator'::text)
  AND EXISTS (
    SELECT 1 FROM public.student_answers sa
    JOIN public.exam_attempts ea ON ea.id = sa.attempt_id
    JOIN public.evaluator_assignments ass ON ass.exam_id = ea.exam_id
    WHERE sa.id = answer_annotations.student_answer_id
      AND ass.evaluator_id = (SELECT auth.uid()) AND ass.status = 'active'
  )
);

DROP POLICY IF EXISTS "Evaluators update own annotations" ON public.answer_annotations;
CREATE POLICY "Evaluators update own annotations" ON public.answer_annotations
FOR UPDATE TO authenticated
USING (evaluator_id = (SELECT auth.uid()) AND public.has_role('evaluator'::text))
WITH CHECK (evaluator_id = (SELECT auth.uid()) AND public.has_role('evaluator'::text));
