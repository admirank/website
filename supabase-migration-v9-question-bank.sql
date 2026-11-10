-- AdmiRank v9: central QUESTION BANK.
-- Admins upload questions once (by course + subject + type, each with its answer and a short solution),
-- then build exams by picking questions from the bank. Every exam question remembers which bank
-- question it came from, so the bank can show "used in <exam>" tags.
-- Run AFTER supabase-migration-v8-practice-exams.sql, once, in the Supabase SQL Editor.

-- ---------------------------------------------------------------------------
-- 1. Bank taxonomy: courses and their subjects
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.qb_courses (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name          text NOT NULL UNIQUE,
    display_order integer NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.qb_subjects (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id     uuid NOT NULL REFERENCES public.qb_courses(id) ON DELETE CASCADE,
    name          text NOT NULL,
    display_order integer NOT NULL DEFAULT 0,
    UNIQUE (course_id, name)
);

INSERT INTO public.qb_courses (name, display_order) VALUES
    ('DU A', 1),
    ('DU B', 2)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.qb_subjects (course_id, name, display_order)
SELECT c.id, s.name, s.ord
FROM public.qb_courses c
JOIN (VALUES
    ('DU A', 'Physics',   1),
    ('DU A', 'Chemistry', 2),
    ('DU A', 'Math',      3),
    ('DU A', 'Biology',   4),
    ('DU A', 'Bangla',    5),
    ('DU A', 'English',   6),
    ('DU B', 'Bangla',            1),
    ('DU B', 'English',           2),
    ('DU B', 'General Knowledge', 3)
) AS s(course_name, name, ord) ON s.course_name = c.name
ON CONFLICT (course_id, name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. The questions themselves (MCQ or written; answer + short solution always required)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.qb_questions (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id      uuid NOT NULL REFERENCES public.qb_courses(id)  ON DELETE RESTRICT,
    subject_id     uuid NOT NULL REFERENCES public.qb_subjects(id) ON DELETE RESTRICT,
    question_type  text NOT NULL CHECK (question_type IN ('mcq', 'written')),
    question_text  text NOT NULL CHECK (length(btrim(question_text)) > 0),
    option_a       text,
    option_b       text,
    option_c       text,
    option_d       text,
    correct_option text CHECK (correct_option IN ('A', 'B', 'C', 'D')),
    answer_text    text,                       -- written answer (MCQ: optional extra note)
    explanation    text NOT NULL CHECK (length(btrim(explanation)) > 0),  -- short solution
    marks          numeric NOT NULL DEFAULT 1 CHECK (marks >= 0),
    negative_marks numeric NOT NULL DEFAULT 0 CHECK (negative_marks >= 0),
    is_active      boolean NOT NULL DEFAULT true,
    created_by     uuid DEFAULT auth.uid(),
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT qb_mcq_complete CHECK (
        question_type <> 'mcq' OR (
            length(btrim(coalesce(option_a, ''))) > 0
            AND length(btrim(coalesce(option_b, ''))) > 0
            AND correct_option IS NOT NULL
            AND length(btrim(coalesce(CASE correct_option
                    WHEN 'A' THEN option_a WHEN 'B' THEN option_b
                    WHEN 'C' THEN option_c WHEN 'D' THEN option_d END, ''))) > 0
        )
    ),
    CONSTRAINT qb_written_has_answer CHECK (
        question_type <> 'written' OR length(btrim(coalesce(answer_text, ''))) > 0
    )
);

CREATE INDEX IF NOT EXISTS qb_questions_filter_idx ON public.qb_questions (course_id, subject_id, question_type);
CREATE INDEX IF NOT EXISTS qb_subjects_course_idx  ON public.qb_subjects (course_id);

CREATE OR REPLACE FUNCTION public.qb_touch_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS qb_questions_touch ON public.qb_questions;
CREATE TRIGGER qb_questions_touch BEFORE UPDATE ON public.qb_questions
FOR EACH ROW EXECUTE FUNCTION public.qb_touch_updated_at();

-- A question's subject must belong to the question's course.
CREATE OR REPLACE FUNCTION public.qb_check_subject_course()
RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.qb_subjects s
                   WHERE s.id = NEW.subject_id AND s.course_id = NEW.course_id) THEN
        RAISE EXCEPTION 'The selected subject does not belong to the selected course.';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS qb_questions_subject_check ON public.qb_questions;
CREATE TRIGGER qb_questions_subject_check BEFORE INSERT OR UPDATE OF course_id, subject_id ON public.qb_questions
FOR EACH ROW EXECUTE FUNCTION public.qb_check_subject_course();

-- ---------------------------------------------------------------------------
-- 3. Remember where each exam question came from (drives the "used in" tags).
--    Deleting a bank question never touches exams: the exam keeps its own snapshot.
-- ---------------------------------------------------------------------------
ALTER TABLE public.exam_questions
    ADD COLUMN IF NOT EXISTS bank_question_id uuid REFERENCES public.qb_questions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS exam_questions_bank_question_idx ON public.exam_questions (bank_question_id);

-- ---------------------------------------------------------------------------
-- 4. Security: the bank is admin-only (students never read it; they see exam snapshots).
--    Uses public.is_admirank_admin() from supabase-migration-v4-course-exam-access.sql.
-- ---------------------------------------------------------------------------
ALTER TABLE public.qb_courses   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qb_subjects  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qb_questions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "AdmiRank admins manage qb_courses" ON public.qb_courses;
CREATE POLICY "AdmiRank admins manage qb_courses" ON public.qb_courses
    FOR ALL TO authenticated USING (public.is_admirank_admin()) WITH CHECK (public.is_admirank_admin());

DROP POLICY IF EXISTS "AdmiRank admins manage qb_subjects" ON public.qb_subjects;
CREATE POLICY "AdmiRank admins manage qb_subjects" ON public.qb_subjects
    FOR ALL TO authenticated USING (public.is_admirank_admin()) WITH CHECK (public.is_admirank_admin());

DROP POLICY IF EXISTS "AdmiRank admins manage qb_questions" ON public.qb_questions;
CREATE POLICY "AdmiRank admins manage qb_questions" ON public.qb_questions
    FOR ALL TO authenticated USING (public.is_admirank_admin()) WITH CHECK (public.is_admirank_admin());

REVOKE ALL ON public.qb_courses, public.qb_subjects, public.qb_questions FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.qb_courses, public.qb_subjects, public.qb_questions TO authenticated;
