-- AdmiRank v23: prepare the leaderboard (fake/manual entries) BEFORE publishing.
-- Change: manual leaderboard entries are now shown to students only after the exam's
-- results are published. Admins always see them, so they can add/edit entries first and
-- then press "Publish results" to reveal real + manual entries together.
-- Run once in the Supabase SQL Editor. Safe to re-run.

CREATE OR REPLACE FUNCTION public.public_exam_leaderboard(p_exam_id uuid)
RETURNS TABLE (
  exam_id uuid,
  exam_title text,
  student_name text,
  profile_picture_path text,
  total_marks numeric,
  rank_position integer,
  entry_id uuid,
  is_manual boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH combined AS (
    SELECT
      er.exam_id,
      e.title AS exam_title,
      COALESCE(NULLIF(p.full_name, ''), 'Student') AS student_name,
      p.profile_picture_path,
      er.total_marks,
      NULL::uuid AS entry_id,
      false AS is_manual
    FROM public.exam_results er
    JOIN public.exams e ON e.id = er.exam_id
    JOIN public.exam_result_publications pub
      ON pub.exam_id = er.exam_id AND pub.is_published = true
    LEFT JOIN public.profiles p ON p.id = er.student_id
    WHERE er.exam_id = p_exam_id

    UNION ALL

    SELECT
      m.exam_id,
      e.title,
      m.student_name,
      NULL::text,
      m.total_marks,
      m.id,
      true
    FROM public.leaderboard_manual_entries m
    JOIN public.exams e ON e.id = m.exam_id
    WHERE m.exam_id = p_exam_id
      AND (
        COALESCE(public.has_role('admin'), false)
        OR EXISTS (
          SELECT 1 FROM public.exam_result_publications pub
          WHERE pub.exam_id = m.exam_id AND pub.is_published = true
        )
      )
  )
  SELECT
    c.exam_id, c.exam_title, c.student_name, c.profile_picture_path,
    c.total_marks,
    (RANK() OVER (ORDER BY c.total_marks DESC NULLS LAST))::integer AS rank_position,
    c.entry_id, c.is_manual
  FROM combined c
  ORDER BY c.total_marks DESC NULLS LAST, c.student_name;
$$;

REVOKE ALL ON FUNCTION public.public_exam_leaderboard(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.public_exam_leaderboard(uuid) TO anon, authenticated;
NOTIFY pgrst, 'reload schema';
