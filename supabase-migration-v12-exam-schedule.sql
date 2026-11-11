-- AdmiRank v12: optional exam SCHEDULE (opening time + expiry time) for exams made from the question bank.
-- Since v8 every exam is an always-open practice exam. This keeps that as the default, but lets an admin
-- give an exam an opening time and/or an expiry time when creating it ("Make exam from selected").
--   * Exams created WITHOUT a schedule behave exactly as before (always open, unlimited attempts).
--   * Exams created WITH a schedule cannot be STARTED before they open or after they expire.
--     A student who already started can finish within their own time limit.
-- Run once in the Supabase SQL Editor, after v8 / v9. Safe to re-run.

ALTER TABLE public.exams
    ADD COLUMN IF NOT EXISTS enforce_schedule boolean NOT NULL DEFAULT false;

-- Checked every time a NEW attempt is created (start_exam inserts into exam_attempts).
-- Resuming an attempt that is already in progress does not create a new row, so it is never blocked.
CREATE OR REPLACE FUNCTION public.admirank_enforce_exam_schedule()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    ex public.exams;
BEGIN
    SELECT * INTO ex FROM public.exams WHERE id = NEW.exam_id;

    IF FOUND AND ex.enforce_schedule THEN
        IF ex.start_time > now() THEN
            RAISE EXCEPTION 'This exam has not opened yet. It opens on %.',
                to_char(ex.start_time AT TIME ZONE 'Asia/Dhaka', 'DD Mon YYYY, HH12:MI AM');
        END IF;
        IF ex.end_time <= now() THEN
            RAISE EXCEPTION 'This exam has expired. It closed on %.',
                to_char(ex.end_time AT TIME ZONE 'Asia/Dhaka', 'DD Mon YYYY, HH12:MI AM');
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS exam_attempts_schedule_check ON public.exam_attempts;
CREATE TRIGGER exam_attempts_schedule_check
    BEFORE INSERT ON public.exam_attempts
    FOR EACH ROW EXECUTE FUNCTION public.admirank_enforce_exam_schedule();
