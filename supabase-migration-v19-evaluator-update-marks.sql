-- Lets evaluators change a mark they already gave (re-click a different mark).
-- Run once in the Supabase SQL Editor.

DROP POLICY IF EXISTS "Evaluators update own evaluations" ON public.answer_evaluations;
CREATE POLICY "Evaluators update own evaluations"
ON public.answer_evaluations FOR UPDATE TO authenticated
USING (evaluator_id = (SELECT auth.uid()) AND public.has_role('evaluator'::text))
WITH CHECK (evaluator_id = (SELECT auth.uid()) AND public.has_role('evaluator'::text));

CREATE OR REPLACE FUNCTION public.admirank_sync_evaluation_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_max NUMERIC;
BEGIN
  SELECT eq.marks INTO v_max
  FROM public.student_answers sa
  JOIN public.exam_questions eq ON eq.id = sa.exam_question_id
  WHERE sa.id = NEW.student_answer_id;
  IF v_max IS NULL THEN RAISE EXCEPTION 'Answer not found'; END IF;
  IF NEW.marks_awarded < 0 OR NEW.marks_awarded > v_max THEN
    RAISE EXCEPTION 'Marks must be between 0 and %', v_max;
  END IF;
  UPDATE public.student_answers
  SET obtained_marks = NEW.marks_awarded, evaluation_status = 'manual_evaluated', updated_at = now()
  WHERE id = NEW.student_answer_id;
  RETURN NULL;
END; $$;

DROP TRIGGER IF EXISTS trg_admirank_sync_evaluation_update ON public.answer_evaluations;
CREATE TRIGGER trg_admirank_sync_evaluation_update
AFTER UPDATE OF marks_awarded ON public.answer_evaluations
FOR EACH ROW EXECUTE FUNCTION public.admirank_sync_evaluation_update();
