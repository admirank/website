-- AdmiRank v14: let an ADMIN delete one student's exam entry (attempt) so the student can take the exam again.
-- Removes the attempt together with its answers, evaluations, activity log and result row, then
-- re-ranks the remaining results of that exam. Uploaded answer files in storage are left untouched.
-- Run once in the Supabase SQL Editor. Safe to re-run.

CREATE OR REPLACE FUNCTION public.admin_delete_exam_attempt(p_attempt_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_exam_id uuid;
BEGIN
    IF auth.uid() IS NULL OR NOT public.has_role('admin') THEN
        RAISE EXCEPTION 'Admin permission required';
    END IF;

    SELECT exam_id INTO v_exam_id FROM public.exam_attempts WHERE id = p_attempt_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Entry not found';
    END IF;

    DELETE FROM public.answer_evaluations
    WHERE student_answer_id IN (SELECT id FROM public.student_answers WHERE attempt_id = p_attempt_id);
    DELETE FROM public.student_answers    WHERE attempt_id = p_attempt_id;
    DELETE FROM public.exam_activity_logs WHERE attempt_id = p_attempt_id;
    DELETE FROM public.exam_results       WHERE attempt_id = p_attempt_id;
    DELETE FROM public.exam_attempts      WHERE id = p_attempt_id;

    -- keep ranks correct for everyone who remains
    UPDATE public.exam_results er
    SET rank_position = rr.new_rank
    FROM (
        SELECT id, RANK() OVER (ORDER BY total_marks DESC)::INTEGER AS new_rank
        FROM public.exam_results WHERE exam_id = v_exam_id
    ) rr
    WHERE er.id = rr.id;

    RETURN jsonb_build_object('success', true, 'exam_id', v_exam_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_delete_exam_attempt(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_exam_attempt(uuid) TO authenticated, service_role;
NOTIFY pgrst, 'reload schema';
