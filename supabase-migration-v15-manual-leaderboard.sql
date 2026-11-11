-- v15: Manual (fake/placeholder) leaderboard entries.
-- These rows live ONLY in this table and appear ONLY on the leaderboard.
-- They are not users, not attempts, not results.

CREATE TABLE IF NOT EXISTS public.leaderboard_manual_entries (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  exam_id       uuid NOT NULL REFERENCES public.exams(id) ON DELETE CASCADE,
  student_name  text NOT NULL CHECK (length(btrim(student_name)) > 0),
  total_marks   numeric NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS leaderboard_manual_entries_exam_idx
  ON public.leaderboard_manual_entries(exam_id);

ALTER TABLE public.leaderboard_manual_entries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage manual leaderboard entries" ON public.leaderboard_manual_entries;
CREATE POLICY "Admins manage manual leaderboard entries"
  ON public.leaderboard_manual_entries
  FOR ALL TO authenticated
  USING (public.has_role('admin'))
  WITH CHECK (public.has_role('admin'));

-- Leaderboard RPC: real published results + manual entries, ranked together by marks.
-- Return type changed (entry_id, is_manual added), so the old function must be dropped.
DROP FUNCTION IF EXISTS public.public_exam_leaderboard(uuid);

CREATE FUNCTION public.public_exam_leaderboard(p_exam_id uuid)
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
