-- AdmiRank v11: fix the error shown when a student submits the MCQ part of a two-part exam:
--   new row for relation "exam_activity_logs" violates check constraint "exam_activity_logs_event_type_check"
-- Cause: when the MCQ part is locked, the database writes an activity-log row of type 'mcq_locked',
-- but that type was never allowed by the table's CHECK constraint. This adds it (all old types stay).
-- Run once in the Supabase SQL Editor. Safe to re-run.

ALTER TABLE public.exam_activity_logs
    DROP CONSTRAINT IF EXISTS exam_activity_logs_event_type_check;

ALTER TABLE public.exam_activity_logs
    ADD CONSTRAINT exam_activity_logs_event_type_check CHECK (event_type = ANY (ARRAY[
        'tab_switch', 'tab_return', 'fullscreen_exit', 'copy_attempt', 'paste_attempt',
        'context_menu', 'focus_lost', 'focus_returned', 'exam_started', 'answer_saved',
        'exam_submitted', 'connection_lost', 'connection_restored',
        'mcq_locked',
        'other'
    ]));
