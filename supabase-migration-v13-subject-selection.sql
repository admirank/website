-- AdmiRank v13: COMPULSORY / OPTIONAL SUBJECT SELECTION for exams.
--
-- Example (DU A unit): Physics + Chemistry are compulsory, and each student must choose
-- any TWO of Bangla / English / Math / Biology. Each student then sees only the compulsory
-- questions plus the questions of the optional subjects they chose, and their marks are
-- calculated out of that set only.
--
--   exams.subject_rules              {"pick":2,"subjects":[{"id","name","kind":"compulsory|optional","marks","count"}]}
--                                    NULL = normal exam (every question for every student, exactly as before)
--   exam_questions.subject_id        subject of each copied question (+ subject_name_snapshot)
--   exam_attempts.selected_subject_ids  the optional subjects this attempt chose
--   exam_attempts.total_marks        the maximum marks of THIS attempt (compulsory + chosen optional)
--
-- start_exam(uuid) becomes start_exam(uuid, uuid[] DEFAULT NULL): old calls keep working for normal exams.
-- Run once in the Supabase SQL Editor, after v12. Safe to re-run.

ALTER TABLE public.exams          ADD COLUMN IF NOT EXISTS subject_rules jsonb;
ALTER TABLE public.exam_questions ADD COLUMN IF NOT EXISTS subject_id uuid;
ALTER TABLE public.exam_questions ADD COLUMN IF NOT EXISTS subject_name_snapshot text;
ALTER TABLE public.exam_attempts  ADD COLUMN IF NOT EXISTS selected_subject_ids uuid[];

-- Give already-created exams their subject (looked up from the question bank), so they can be
-- re-used / reported by subject. Harmless for exams without subject rules.
UPDATE public.exam_questions AS eq
SET subject_id = qb.subject_id,
    subject_name_snapshot = s.name
FROM public.qb_questions AS qb
JOIN public.qb_subjects AS s ON s.id = qb.subject_id
WHERE eq.bank_question_id = qb.id
  AND eq.subject_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_exam_questions_exam_subject ON public.exam_questions (exam_id, subject_id);

-- TRUE when a question belongs in an attempt: it has no subject, the exam has no optional subjects,
-- its subject is compulsory, or its subject is one of the optional subjects the student selected.
CREATE OR REPLACE FUNCTION public.admirank_question_included(
    p_subject uuid, p_optional uuid[], p_selected uuid[]
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
    SELECT p_subject IS NULL
        OR p_optional IS NULL
        OR NOT (p_subject = ANY(p_optional))
        OR (p_selected IS NOT NULL AND p_subject = ANY(p_selected));
$function$;

-- ---------------------------------------------------------------- start_exam
DROP FUNCTION IF EXISTS public.start_exam(uuid);
CREATE OR REPLACE FUNCTION public.start_exam(p_exam_id uuid, p_selected_subject_ids uuid[] DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_user_id UUID;
    v_exam public.exams%ROWTYPE;
    v_attempt_id UUID;
    v_attempt_number INTEGER;
    v_expires_at TIMESTAMPTZ;
    v_question_order JSONB;
    v_option_orders JSONB;
    v_existing public.exam_attempts%ROWTYPE;
    v_question_count INTEGER;
    v_phase TEXT := 'all';
    v_mcq_expires TIMESTAMPTZ := NULL;
    v_has_mcq BOOLEAN;
    v_has_written BOOLEAN;
    v_rules JSONB;
    v_pick INTEGER := 0;
    v_optional UUID[] := NULL;
    v_selected UUID[] := NULL;
    v_total_marks NUMERIC := 0;
BEGIN
    -- 1. Verify authentication
    v_user_id := (SELECT auth.uid());

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'You must be logged in to start an exam.';
    END IF;

    IF NOT public.has_role('student') THEN
        RAISE EXCEPTION 'Only student accounts can start exams.';
    END IF;

    -- 2. Lock the exam row to prevent simultaneous attempt creation
    SELECT *
    INTO v_exam
    FROM public.exams
    WHERE id = p_exam_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Exam not found.';
    END IF;

    -- 3. Verify exam availability
    IF v_exam.status <> 'published' THEN
        RAISE EXCEPTION 'This exam is not published.';
    END IF;

    -- Practice exam: no schedule window; always open once published.

    -- 4. Verify active enrollment in the exam batch
    IF NOT EXISTS (
        SELECT 1
        FROM public.batches b
        JOIN public.enrollments en
            ON en.batch_id = b.id
        WHERE b.id = v_exam.batch_id
          AND en.student_id = v_user_id
          AND en.status = 'active'
          AND (
              en.expires_at IS NULL
              OR en.expires_at > NOW()
          )
    ) THEN
        RAISE EXCEPTION 'You are not actively enrolled in this exam batch.';
    END IF;

    -- 5. Resume an existing attempt if allowed
    SELECT *
    INTO v_existing
    FROM public.exam_attempts
    WHERE exam_id = p_exam_id
      AND student_id = v_user_id
      AND status = 'in_progress'
    ORDER BY attempt_number DESC
    LIMIT 1;

    IF FOUND THEN
        IF v_exam.allow_resume
           AND v_existing.expires_at > NOW() THEN
            RETURN jsonb_build_object(
                'success', TRUE,
                'message', 'Existing exam attempt resumed.',
                'attempt_id', v_existing.id,
                'expires_at', v_existing.expires_at,
                'attempt_number', v_existing.attempt_number,
                'selected_subject_ids', to_jsonb(v_existing.selected_subject_ids),
                'total_marks', v_existing.total_marks
            );
        ELSE
            RAISE EXCEPTION 'You already have an unfinished attempt.';
        END IF;
    END IF;

    -- 6. Enforce maximum attempts
    SELECT COUNT(*)::INTEGER
    INTO v_attempt_number
    FROM public.exam_attempts
    WHERE exam_id = p_exam_id
      AND student_id = v_user_id;

    -- Practice exam: unlimited attempts.

    v_attempt_number := v_attempt_number + 1;

    -- 6b. Compulsory / optional subject rules (v13)
    v_rules := v_exam.subject_rules;
    IF v_rules IS NOT NULL AND jsonb_typeof(v_rules -> 'subjects') = 'array' THEN
        SELECT COALESCE(array_agg((sj ->> 'id')::UUID), ARRAY[]::UUID[])
        INTO v_optional
        FROM jsonb_array_elements(v_rules -> 'subjects') AS sj
        WHERE sj ->> 'kind' = 'optional';

        v_pick := COALESCE((v_rules ->> 'pick')::INTEGER, 0);

        IF cardinality(v_optional) > 0 AND v_pick > 0 THEN
            SELECT COALESCE(array_agg(DISTINCT x), ARRAY[]::UUID[])
            INTO v_selected
            FROM unnest(COALESCE(p_selected_subject_ids, ARRAY[]::UUID[])) AS x;

            IF cardinality(v_selected) <> v_pick THEN
                RAISE EXCEPTION 'Please choose exactly % optional subject(s) to start this exam.', v_pick;
            END IF;

            IF EXISTS (
                SELECT 1 FROM unnest(v_selected) AS x WHERE NOT (x = ANY(v_optional))
            ) THEN
                RAISE EXCEPTION 'You can only choose from the optional subjects of this exam.';
            END IF;
        ELSE
            v_optional := NULL;
            v_selected := NULL;
        END IF;
    END IF;

    -- 7. Ensure the exam contains questions
    SELECT COUNT(*)::INTEGER, COALESCE(SUM(marks), 0)
    INTO v_question_count, v_total_marks
    FROM public.exam_questions
    WHERE exam_id = p_exam_id
      AND public.admirank_question_included(subject_id, v_optional, v_selected);

    IF v_question_count = 0 THEN
        RAISE EXCEPTION 'This exam does not contain any questions.';
    END IF;

    -- 8. Generate question order
    SELECT COALESCE(
        jsonb_agg(q.id ORDER BY
            CASE WHEN v_exam.randomize_questions THEN random() END,
            CASE WHEN NOT v_exam.randomize_questions THEN q.question_order END
        ),
        '[]'::JSONB
    )
    INTO v_question_order
    FROM public.exam_questions q
    WHERE q.exam_id = p_exam_id
      AND public.admirank_question_included(q.subject_id, v_optional, v_selected);

    -- 9. Generate option order for each question
    SELECT COALESCE(
        jsonb_object_agg(
            q.id::TEXT,
            CASE
                WHEN v_exam.randomize_options THEN
                    COALESCE(
                        (
                            SELECT jsonb_agg(o.id ORDER BY random())
                            FROM public.exam_question_options o
                            WHERE o.exam_question_id = q.id
                        ),
                        '[]'::JSONB
                    )
                ELSE
                    COALESCE(
                        (
                            SELECT jsonb_agg(o.id ORDER BY o.display_order)
                            FROM public.exam_question_options o
                            WHERE o.exam_question_id = q.id
                        ),
                        '[]'::JSONB
                    )
            END
        ),
        '{}'::JSONB
    )
    INTO v_option_orders
    FROM public.exam_questions q
    WHERE q.exam_id = p_exam_id
      AND public.admirank_question_included(q.subject_id, v_optional, v_selected);

    -- 10. Calculate attempt expiry
    SELECT bool_or(question_type = 'mcq'), bool_or(question_type <> 'mcq')
    INTO v_has_mcq, v_has_written
    FROM public.exam_questions
    WHERE exam_id = p_exam_id
      AND public.admirank_question_included(subject_id, v_optional, v_selected);

    IF COALESCE(v_has_mcq, FALSE) AND COALESCE(v_has_written, FALSE)
       AND v_exam.mcq_duration_minutes IS NOT NULL
       AND v_exam.written_duration_minutes IS NOT NULL THEN
        -- Two-phase exam: MCQ first (own timer), then written (own timer)
        v_phase := 'mcq';
        v_mcq_expires := NOW() + make_interval(mins => v_exam.mcq_duration_minutes);
        v_expires_at := NOW() + make_interval(mins => v_exam.mcq_duration_minutes + v_exam.written_duration_minutes);
    ELSE
        v_expires_at := NOW() + make_interval(mins => v_exam.duration_minutes);
    END IF;

    -- 11. Create exam attempt
    INSERT INTO public.exam_attempts (
        exam_id,
        student_id,
        attempt_number,
        status,
        started_at,
        expires_at,
        current_phase,
        mcq_expires_at,
        question_order,
        option_orders,
        total_marks,
        selected_subject_ids
    )
    VALUES (
        p_exam_id,
        v_user_id,
        v_attempt_number,
        'in_progress',
        NOW(),
        v_expires_at,
        v_phase,
        v_mcq_expires,
        v_question_order,
        v_option_orders,
        v_total_marks,
        v_selected
    )
    RETURNING id INTO v_attempt_id;

    -- 12. Return safe attempt information
    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Exam started successfully.',
        'attempt_id', v_attempt_id,
        'expires_at', v_expires_at,
        'current_phase', v_phase,
        'mcq_expires_at', v_mcq_expires,
        'attempt_number', v_attempt_number,
        'selected_subject_ids', to_jsonb(v_selected),
        'total_marks', v_total_marks
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.start_exam(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_exam(uuid, uuid[]) TO authenticated, service_role;

-- ---------------------------------------------------------------- load_exam_questions
CREATE OR REPLACE FUNCTION public.load_exam_questions(p_attempt_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_user_id UUID;
    v_attempt public.exam_attempts%ROWTYPE;
    v_questions JSONB;
BEGIN
    -- 1. Verify authentication
    v_user_id := (SELECT auth.uid());

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'You must be logged in.';
    END IF;

    IF NOT public.has_role('student') THEN
        RAISE EXCEPTION 'Only students can load exam questions.';
    END IF;

    -- 2. Find the student's own attempt
    SELECT *
    INTO v_attempt
    FROM public.exam_attempts
    WHERE id = p_attempt_id
      AND student_id = v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Exam attempt not found.';
    END IF;

    -- 3. Verify attempt status
    IF v_attempt.status <> 'in_progress' THEN
        RAISE EXCEPTION 'This exam attempt is not active.';
    END IF;

    -- Move to the written phase automatically if MCQ time is over
    SELECT * INTO v_attempt FROM public.admirank_advance_exam_phase(p_attempt_id, FALSE);

    IF v_attempt.expires_at <= NOW() THEN
        RAISE EXCEPTION 'Your exam time has expired.';
    END IF;

    -- 4. Load questions in the student's assigned order
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', q.id,
                'question_order', qo.ordinality,
                'question_type', q.question_type,
                'question_text', q.question_text_snapshot,
                'image_paths', q.image_paths_snapshot,
                'marks', q.marks,
                'negative_marks', q.negative_marks,
                'subject_id', q.subject_id,
                'subject_name', q.subject_name_snapshot,

                -- Options are returned without correct-answer flags
                'options',
                CASE
                    WHEN q.question_type = 'mcq' THEN
                        (
                            SELECT COALESCE(
                                jsonb_agg(
                                    jsonb_build_object(
                                        'id', o.id,
                                        'option_label', o.option_label,
                                        'option_text', o.option_text,
                                        'option_image_path', o.option_image_path
                                    )
                                    ORDER BY oo.ordinality
                                ),
                                '[]'::JSONB
                            )
                            FROM jsonb_array_elements_text(
                                COALESCE(
                                    v_attempt.option_orders -> q.id::TEXT,
                                    '[]'::JSONB
                                )
                            ) WITH ORDINALITY AS oo(option_id, ordinality)
                            JOIN public.exam_question_options o
                                ON o.id = oo.option_id::UUID
                               AND o.exam_question_id = q.id
                        )
                    ELSE '[]'::JSONB
                END,

                -- Restore the student's own previously saved response
                'saved_answer',
                (
                    SELECT jsonb_build_object(
                        'selected_option_id', sa.selected_option_id,
                        'written_answer_text', sa.written_answer_text,
                        'answer_image_path', sa.answer_image_path
                    )
                    FROM public.student_answers sa
                    WHERE sa.attempt_id = v_attempt.id
                      AND sa.exam_question_id = q.id
                )
            )
            ORDER BY qo.ordinality
        ),
        '[]'::JSONB
    )
    INTO v_questions
    FROM jsonb_array_elements_text(
        v_attempt.question_order
    ) WITH ORDINALITY AS qo(question_id, ordinality)
    JOIN public.exam_questions q
        ON q.id = qo.question_id::UUID
       AND q.exam_id = v_attempt.exam_id
       AND (
            v_attempt.current_phase = 'all'
            OR (v_attempt.current_phase = 'mcq' AND q.question_type = 'mcq')
            OR (v_attempt.current_phase = 'written' AND q.question_type <> 'mcq')
       );

    -- 5. Return safe exam information
    RETURN jsonb_build_object(
        'success', TRUE,
        'attempt_id', v_attempt.id,
        'exam_id', v_attempt.exam_id,
        'started_at', v_attempt.started_at,
        'expires_at', v_attempt.expires_at,
        'current_phase', v_attempt.current_phase,
        'mcq_expires_at', v_attempt.mcq_expires_at,
        'server_time', NOW(),
        'attempt_number', v_attempt.attempt_number,
        'total_marks', v_attempt.total_marks,
        'selected_subject_ids', to_jsonb(v_attempt.selected_subject_ids),
        'questions', v_questions
    );
END;
$function$;

-- ---------------------------------------------------------------- save_exam_answer
CREATE OR REPLACE FUNCTION public.save_exam_answer(p_attempt_id uuid, p_exam_question_id uuid, p_selected_option_id uuid DEFAULT NULL::uuid, p_written_answer_text text DEFAULT NULL::text, p_answer_image_path text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_attempt RECORD;
    v_question_type TEXT;
    v_answer_id UUID;
    v_prefix TEXT;
BEGIN
    IF auth.uid() IS NULL OR NOT public.has_role('student') THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    SELECT *
    INTO v_attempt
    FROM public.admirank_advance_exam_phase(p_attempt_id, FALSE);

    IF v_attempt.id IS NULL OR v_attempt.student_id <> auth.uid() THEN
        RAISE EXCEPTION 'Attempt not found';
    END IF;

    IF v_attempt.status <> 'in_progress'
       OR v_attempt.expires_at <= now() THEN
        RAISE EXCEPTION 'Exam attempt is no longer active';
    END IF;

    SELECT question_type
    INTO v_question_type
    FROM public.exam_questions
    WHERE id = p_exam_question_id
      AND exam_id = v_attempt.exam_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Question does not belong to this exam';
    END IF;

    -- v13: a student may only answer the questions assigned to this attempt
    -- (compulsory subjects + the optional subjects they chose).
    IF NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements_text(v_attempt.question_order) AS qo(question_id)
        WHERE qo.question_id = p_exam_question_id::TEXT
    ) THEN
        RAISE EXCEPTION 'This question is not part of your selected subjects';
    END IF;

    -- Phase enforcement: MCQ is locked once its own timer ends / is submitted
    IF v_attempt.current_phase = 'mcq' AND v_question_type <> 'mcq' THEN
        RAISE EXCEPTION 'The written section has not started yet';
    END IF;
    IF v_attempt.current_phase = 'written' AND v_question_type = 'mcq' THEN
        RAISE EXCEPTION 'The MCQ section is closed and can no longer be edited';
    END IF;

    IF v_question_type = 'mcq' THEN
        IF p_selected_option_id IS NULL
           OR p_written_answer_text IS NOT NULL
           OR p_answer_image_path IS NOT NULL THEN
            RAISE EXCEPTION 'Invalid MCQ answer';
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM public.exam_question_options
            WHERE id = p_selected_option_id
              AND exam_question_id = p_exam_question_id
        ) THEN
            RAISE EXCEPTION 'Invalid MCQ option';
        END IF;

    ELSIF v_question_type = 'written' THEN
        IF p_selected_option_id IS NOT NULL THEN
            RAISE EXCEPTION 'Written questions cannot have MCQ options';
        END IF;

        IF NULLIF(trim(p_written_answer_text), '') IS NULL
           AND p_answer_image_path IS NULL THEN
            RAISE EXCEPTION 'Please provide a written answer';
        END IF;

        IF p_answer_image_path IS NOT NULL THEN
            v_prefix := auth.uid()::TEXT || '/' || p_attempt_id::TEXT || '/';

            IF p_answer_image_path NOT LIKE v_prefix || '%' THEN
                RAISE EXCEPTION 'Invalid answer image path';
            END IF;

            IF NOT EXISTS (
                SELECT 1
                FROM storage.objects
                WHERE bucket_id = 'answer-scripts'
                  AND name = p_answer_image_path
            ) THEN
                RAISE EXCEPTION 'Answer image not found in storage';
            END IF;
        END IF;

    ELSE
        RAISE EXCEPTION 'Unsupported question type';
    END IF;

    INSERT INTO public.student_answers (
        attempt_id,
        exam_question_id,
        selected_option_id,
        written_answer_text,
        answer_image_path,
        evaluation_status,
        answered_at,
        updated_at
    )
    VALUES (
        p_attempt_id,
        p_exam_question_id,
        p_selected_option_id,
        p_written_answer_text,
        p_answer_image_path,
        'pending',
        now(),
        now()
    )
    ON CONFLICT (attempt_id, exam_question_id)
    DO UPDATE SET
        selected_option_id = EXCLUDED.selected_option_id,
        written_answer_text = EXCLUDED.written_answer_text,
        answer_image_path = EXCLUDED.answer_image_path,
        obtained_marks = NULL,
        is_correct = NULL,
        evaluation_status = 'pending',
        answered_at = now(),
        updated_at = now()
    RETURNING id INTO v_answer_id;

    INSERT INTO public.exam_activity_logs (
        attempt_id,
        student_id,
        event_type,
        event_details
    )
    VALUES (
        p_attempt_id,
        auth.uid(),
        'answer_saved',
        jsonb_build_object('exam_question_id', p_exam_question_id)
    );

    RETURN jsonb_build_object(
        'success', true,
        'answer_id', v_answer_id,
        'message', 'Answer saved'
    );
END;
$function$;

NOTIFY pgrst, 'reload schema';
