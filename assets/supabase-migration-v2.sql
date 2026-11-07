-- AdmiRank website refresh migration
-- Run in Supabase SQL Editor as project owner.

-- 1) Extended course detail fields used by the public course page and admin form.
ALTER TABLE public.courses
  ADD COLUMN IF NOT EXISTS detailed_information text,
  ADD COLUMN IF NOT EXISTS routine text;

-- 2) Public profile-photo bucket. Each signed-in user may write only to their own folder.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('profile-pictures', 'profile-pictures', true, 3145728,
        ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Public can view profile pictures" ON storage.objects;
CREATE POLICY "Public can view profile pictures"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'profile-pictures');

DROP POLICY IF EXISTS "Users upload own profile pictures" ON storage.objects;
CREATE POLICY "Users upload own profile pictures"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'profile-pictures'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Users update own profile pictures" ON storage.objects;
CREATE POLICY "Users update own profile pictures"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'profile-pictures'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'profile-pictures'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Users delete own profile pictures" ON storage.objects;
CREATE POLICY "Users delete own profile pictures"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'profile-pictures'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- 3) A privacy-conscious leaderboard RPC: exposes only name, public avatar path,
--    marks and rank for exams whose results have explicitly been published.
CREATE OR REPLACE FUNCTION public.public_exam_leaderboard(p_exam_id uuid)
RETURNS TABLE (
  exam_id uuid,
  exam_title text,
  student_name text,
  profile_picture_path text,
  total_marks numeric,
  rank_position integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    er.exam_id,
    e.title,
    COALESCE(NULLIF(p.full_name, ''), 'Student'),
    p.profile_picture_path,
    er.total_marks,
    er.rank_position
  FROM public.exam_results er
  JOIN public.exams e ON e.id = er.exam_id
  JOIN public.exam_result_publications pub
    ON pub.exam_id = er.exam_id AND pub.is_published = true
  LEFT JOIN public.profiles p ON p.id = er.student_id
  WHERE er.exam_id = p_exam_id
  ORDER BY er.rank_position NULLS LAST, er.total_marks DESC;
$$;

REVOKE ALL ON FUNCTION public.public_exam_leaderboard(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.public_exam_leaderboard(uuid) TO anon, authenticated;

-- NOTE ABOUT EXAMS:
-- The existing exam engine's start_exam() RPC checks active enrollment through
-- exams.batch_id -> batches -> enrollments. To avoid breaking that secure check,
-- the new exam creator asks you for a COURSE only and automatically reuses an
-- existing batch for that course, or creates a system-managed published batch
-- when none exists. No batch ID is shown or required in the admin exam form.
