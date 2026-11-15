-- Lets a student review ALL options of their own published attempt (so the option they picked is visible),
-- without leaking which option is correct unless the admin enabled "show correct answers".
-- Run once in the Supabase SQL Editor.

CREATE OR REPLACE FUNCTION public.student_result_review(p_attempt_id uuid)
RETURNS TABLE (
  exam_question_id uuid,
  option_id uuid,
  option_label text,
  option_text text,
  option_image_path text,
  display_order integer,
  is_correct boolean
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_exam uuid;
  v_show boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'You must be logged in.'; END IF;

  SELECT ea.exam_id INTO v_exam
  FROM public.exam_attempts ea
  WHERE ea.id = p_attempt_id AND ea.student_id = auth.uid();
  IF v_exam IS NULL THEN RAISE EXCEPTION 'Attempt not found.'; END IF;

  SELECT rp.show_correct_answers INTO v_show
  FROM public.exam_result_publications rp
  WHERE rp.exam_id = v_exam AND rp.is_published = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Results are not published yet.'; END IF;

  RETURN QUERY
  SELECT o.exam_question_id, o.id, o.option_label, o.option_text, o.option_image_path, o.display_order,
         CASE WHEN COALESCE(v_show, false) THEN o.is_correct ELSE NULL END
  FROM public.exam_question_options o
  JOIN public.exam_questions q ON q.id = o.exam_question_id
  WHERE q.exam_id = v_exam
  ORDER BY o.exam_question_id, o.display_order;
END; $$;

REVOKE ALL ON FUNCTION public.student_result_review(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.student_result_review(uuid) TO authenticated;
