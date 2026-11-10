-- AdmiRank v8: every exam is a PRACTICE exam.
-- Students can start any published exam of a batch they are actively enrolled in,
-- at any time (no opening/closing window) and any number of times.
-- Run once in Supabase SQL Editor.


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
            expires_at = lock_at + make_interval(mins => ex.written_duration_minutes),
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

    -- Practice exam: unlimited attempts.

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
