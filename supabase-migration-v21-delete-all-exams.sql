-- AdmiRank v21: let an ADMIN wipe ALL exams and everything attached to them.
-- Deletes: exams, exam questions/options (the exam copies), student attempts, answers,
--          evaluations/marks, script annotations, activity logs, results, ranks, result
--          publications, evaluator assignments, rubrics and manual leaderboard entries.
-- KEEPS:   the question bank (qb_questions, subjects/courses/sources), the live questions
--          tables, courses, batches, enrollments, payments, users, and the *_backup tables.
-- Uploaded answer images are removed by the "Delete all exams" button in the admin page
-- (it uses the Storage API; deleting storage.objects from SQL does not free the files).
-- Run once in the Supabase SQL Editor. Safe to re-run.

CREATE OR REPLACE FUNCTION public.admin_delete_all_exams(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    n jsonb := '{}'::jsonb;
    c bigint;
BEGIN
    IF auth.uid() IS NULL OR NOT public.has_role('admin') THEN
        RAISE EXCEPTION 'Admin permission required';
    END IF;
    IF p_confirm IS DISTINCT FROM 'DELETE ALL EXAMS' THEN
        RAISE EXCEPTION 'Confirmation text did not match';
    END IF;

    DELETE FROM public.answer_annotations WHERE true;           GET DIAGNOSTICS c = ROW_COUNT; n := n || jsonb_build_object('answer_annotations', c);
    DELETE FROM public.answer_evaluations WHERE true;           GET DIAGNOSTICS c = ROW_COUNT; n := n || jsonb_build_object('answer_evaluations', c);
    DELETE FROM public.student_answers WHERE true;              GET DIAGNOSTICS c = ROW_COUNT; n := n || jsonb_build_object('student_answers', c);
    DELETE FROM public.exam_activity_logs WHERE true;           GET DIAGNOSTICS c = ROW_COUNT; n := n || jsonb_build_object('exam_activity_logs', c);
    DELETE FROM public.exam_results WHERE true;                 GET DIAGNOSTICS c = ROW_COUNT; n := n || jsonb_build_object('exam_results', c);
    DELETE FROM public.exam_result_publications WHERE true;     GET DIAGNOSTICS c = ROW_COUNT; n := n || jsonb_build_object('exam_result_publications', c);
    DELETE FROM public.exam_attempts WHERE true;                GET DIAGNOSTICS c = ROW_COUNT; n := n || jsonb_build_object('exam_attempts', c);
    DELETE FROM public.evaluation_rubrics WHERE true;           GET DIAGNOSTICS c = ROW_COUNT; n := n || jsonb_build_object('evaluation_rubrics', c);
    DELETE FROM public.exam_question_options WHERE true;        GET DIAGNOSTICS c = ROW_COUNT; n := n || jsonb_build_object('exam_question_options', c);
    DELETE FROM public.exam_questions WHERE true;               GET DIAGNOSTICS c = ROW_COUNT; n := n || jsonb_build_object('exam_questions', c);
    DELETE FROM public.evaluator_assignments WHERE true;        GET DIAGNOSTICS c = ROW_COUNT; n := n || jsonb_build_object('evaluator_assignments', c);
    DELETE FROM public.leaderboard_manual_entries WHERE true;   GET DIAGNOSTICS c = ROW_COUNT; n := n || jsonb_build_object('leaderboard_manual_entries', c);
    DELETE FROM public.exams WHERE true;                        GET DIAGNOSTICS c = ROW_COUNT; n := n || jsonb_build_object('exams', c);

    RETURN jsonb_build_object('success', true, 'deleted', n);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_delete_all_exams(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_all_exams(text) TO authenticated, service_role;
NOTIFY pgrst, 'reload schema';
