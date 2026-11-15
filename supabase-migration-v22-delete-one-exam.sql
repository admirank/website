-- AdmiRank v22: let an ADMIN delete ONE exam with everything attached to it
-- (entries/attempts, answers, marks, annotations, logs, results, ranks, publication,
-- evaluator assignments, rubrics, manual leaderboard rows and the exam's question copies).
-- Question-bank questions are NOT touched. Uploaded answer images are removed by the
-- admin page button through the Storage API.
-- Run once in the Supabase SQL Editor. Safe to re-run.

CREATE OR REPLACE FUNCTION public.admin_delete_exam(p_exam_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_attempts bigint;
BEGIN
    IF auth.uid() IS NULL OR NOT public.has_role('admin') THEN
        RAISE EXCEPTION 'Admin permission required';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.exams WHERE id = p_exam_id) THEN
        RAISE EXCEPTION 'Exam not found';
    END IF;

    SELECT count(*) INTO v_attempts FROM public.exam_attempts WHERE exam_id = p_exam_id;

    DELETE FROM public.answer_annotations WHERE student_answer_id IN (
        SELECT sa.id FROM public.student_answers sa JOIN public.exam_attempts ea ON ea.id = sa.attempt_id WHERE ea.exam_id = p_exam_id);
    DELETE FROM public.answer_evaluations WHERE student_answer_id IN (
        SELECT sa.id FROM public.student_answers sa JOIN public.exam_attempts ea ON ea.id = sa.attempt_id WHERE ea.exam_id = p_exam_id);
    DELETE FROM public.student_answers WHERE attempt_id IN (SELECT id FROM public.exam_attempts WHERE exam_id = p_exam_id);
    DELETE FROM public.exam_activity_logs WHERE attempt_id IN (SELECT id FROM public.exam_attempts WHERE exam_id = p_exam_id);
    DELETE FROM public.exam_results WHERE exam_id = p_exam_id;
    DELETE FROM public.exam_result_publications WHERE exam_id = p_exam_id;
    DELETE FROM public.exam_attempts WHERE exam_id = p_exam_id;
    DELETE FROM public.evaluation_rubrics WHERE exam_question_id IN (SELECT id FROM public.exam_questions WHERE exam_id = p_exam_id);
    DELETE FROM public.exam_question_options WHERE exam_question_id IN (SELECT id FROM public.exam_questions WHERE exam_id = p_exam_id);
    DELETE FROM public.exam_questions WHERE exam_id = p_exam_id;
    DELETE FROM public.evaluator_assignments WHERE exam_id = p_exam_id;
    DELETE FROM public.leaderboard_manual_entries WHERE exam_id = p_exam_id;
    DELETE FROM public.exams WHERE id = p_exam_id;

    RETURN jsonb_build_object('success', true, 'exam_id', p_exam_id, 'attempts_deleted', v_attempts);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_delete_exam(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_exam(uuid) TO authenticated, service_role;
NOTIFY pgrst, 'reload schema';
