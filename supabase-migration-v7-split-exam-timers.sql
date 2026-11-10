-- AdmiRank v7: separate timers for MCQ and written sections
-- Run once in Supabase SQL Editor. Safe to re-run.

ALTER TABLE public.exams
  ADD COLUMN IF NOT EXISTS mcq_duration_minutes integer CHECK (mcq_duration_minutes IS NULL OR mcq_duration_minutes > 0),
  ADD COLUMN IF NOT EXISTS written_duration_minutes integer CHECK (written_duration_minutes IS NULL OR written_duration_minutes > 0);

ALTER TABLE public.exam_attempts
  ADD COLUMN IF NOT EXISTS current_phase text NOT NULL DEFAULT 'all' CHECK (current_phase IN ('all','mcq','written')),
  ADD COLUMN IF NOT EXISTS mcq_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS mcq_locked_at timestamptz;

-- Internal helper: moves an attempt from MCQ phase to written phase.
-- p_force = true  -> student submitted MCQ early
-- p_force = false -> only advances if MCQ time is over
CREATE OR REPLACE FUNCTION public.admirank_advance_exam_phase(p_attempt_id uuid, p_force boolean DEFAULT false)
RETURNS public.exam_attempts
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
    a public.exam_attempts;
    ex public.exams;
    lock_at timestamptz;
BEGIN
    SELECT * INTO a FROM public.exam_attempts WHERE id = p_attempt_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN a;
    END IF;

    IF a.status = 'in_progress' AND a.current_phase = 'mcq'
       AND (p_force OR now() >= a.mcq_expires_at) THEN
        SELECT * INTO ex FROM public.exams WHERE id = a.exam_id;
        lock_at := LEAST(now(), a.mcq_expires_at);

        UPDATE public.exam_attempts
        SET current_phase = 'written',
            mcq_locked_at = lock_at,
            expires_at = LEAST(lock_at + make_interval(mins => ex.written_duration_minutes), ex.end_time),
            updated_at = now()
        WHERE id = a.id
        RETURNING * INTO a;

        INSERT INTO public.exam_activity_logs (attempt_id, student_id, event_type, event_details)
        VALUES (a.id, a.student_id, 'mcq_locked',
                jsonb_build_object('forced', p_force, 'locked_at', lock_at));
    END IF;

    RETURN a;
END;
$function$;

REVOKE ALL ON FUNCTION public.admirank_advance_exam_phase(uuid, boolean) FROM PUBLIC, anon, authenticated;

-- Student-facing: submit the MCQ section early (also used by the auto-lock at timeout)
CREATE OR REPLACE FUNCTION public.lock_mcq_phase(p_attempt_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
    a public.exam_attempts;
BEGIN
    IF auth.uid() IS NULL OR NOT public.has_role('student') THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    SELECT * INTO a FROM public.exam_attempts WHERE id = p_attempt_id;
    IF NOT FOUND OR a.student_id <> auth.uid() THEN
        RAISE EXCEPTION 'Attempt not found';
    END IF;
    IF a.status <> 'in_progress' THEN
        RAISE EXCEPTION 'This exam attempt is not active.';
    END IF;
    IF a.expires_at <= now() THEN
        RAISE EXCEPTION 'Your exam time has expired.';
    END IF;

    SELECT * INTO a FROM public.admirank_advance_exam_phase(p_attempt_id, TRUE);

    RETURN jsonb_build_object(
        'success', TRUE,
        'current_phase', a.current_phase,
        'expires_at', a.expires_at,
        'server_time', now()
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.lock_mcq_phase(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.start_exam(p_exam_id uuid)
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

    IF NOW() < v_exam.start_time THEN
        RAISE EXCEPTION 'This exam has not started yet.';
    END IF;

    IF NOW() >= v_exam.end_time THEN
        RAISE EXCEPTION 'This exam has already ended.';
    END IF;

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
                'attempt_number', v_existing.attempt_number
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

    IF v_attempt_number >= v_exam.max_attempts THEN
        RAISE EXCEPTION 'You have reached the maximum number of attempts.';
    END IF;

    v_attempt_number := v_attempt_number + 1;

    -- 7. Ensure the exam contains questions
    SELECT COUNT(*)::INTEGER
    INTO v_question_count
    FROM public.exam_questions
    WHERE exam_id = p_exam_id;

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
    WHERE q.exam_id = p_exam_id;

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
    WHERE q.exam_id = p_exam_id;

    -- 10. Calculate attempt expiry
    SELECT bool_or(question_type = 'mcq'), bool_or(question_type <> 'mcq')
    INTO v_has_mcq, v_has_written
    FROM public.exam_questions
    WHERE exam_id = p_exam_id;

    IF COALESCE(v_has_mcq, FALSE) AND COALESCE(v_has_written, FALSE)
       AND v_exam.mcq_duration_minutes IS NOT NULL
       AND v_exam.written_duration_minutes IS NOT NULL THEN
        -- Two-phase exam: MCQ first (own timer), then written (own timer)
        v_phase := 'mcq';
        v_mcq_expires := LEAST(
            NOW() + make_interval(mins => v_exam.mcq_duration_minutes),
            v_exam.end_time
        );
        v_expires_at := LEAST(
            NOW() + make_interval(mins => v_exam.mcq_duration_minutes + v_exam.written_duration_minutes),
            v_exam.end_time
        );
    ELSE
        v_expires_at := LEAST(
            NOW() + make_interval(mins => v_exam.duration_minutes),
            v_exam.end_time
        );
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
        option_orders
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
        v_option_orders
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
        'attempt_number', v_attempt_number
    );
END;
$function$;

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
        'questions', v_questions
    );
END;
$function$;

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
