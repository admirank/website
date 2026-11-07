-- AdmiRank: homepage banner management
-- Run in Supabase SQL Editor AFTER supabase-migration-v4-course-exam-access.sql.
-- This reuses the existing public.banners table and the public-assets bucket.

-- Ensure the existing public-assets bucket can serve and store website images.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'public-assets',
  'public-assets',
  true,
  8388608,
  ARRAY['image/jpeg','image/png','image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = GREATEST(storage.buckets.file_size_limit, EXCLUDED.file_size_limit),
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Public visitors can view banner/course images. Only admins can upload, replace or delete.
DROP POLICY IF EXISTS "AdmiRank public-assets public read" ON storage.objects;
CREATE POLICY "AdmiRank public-assets public read"
ON storage.objects FOR SELECT TO public
USING (bucket_id = 'public-assets');

DROP POLICY IF EXISTS "AdmiRank admins upload public-assets" ON storage.objects;
CREATE POLICY "AdmiRank admins upload public-assets"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'public-assets' AND public.is_admirank_admin());

DROP POLICY IF EXISTS "AdmiRank admins update public-assets" ON storage.objects;
CREATE POLICY "AdmiRank admins update public-assets"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'public-assets' AND public.is_admirank_admin())
WITH CHECK (bucket_id = 'public-assets' AND public.is_admirank_admin());

DROP POLICY IF EXISTS "AdmiRank admins delete public-assets" ON storage.objects;
CREATE POLICY "AdmiRank admins delete public-assets"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'public-assets' AND public.is_admirank_admin());

-- Banner metadata is public (it contains only titles, image paths and display settings).
-- The homepage filters inactive banners; public reads must include inactive rows so a hidden
-- bundled banner is not accidentally shown again as a local-asset fallback.
ALTER TABLE public.banners ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "AdmiRank public active banners read" ON public.banners;
CREATE POLICY "AdmiRank public active banners read"
ON public.banners FOR SELECT TO anon, authenticated
USING (true);

DROP POLICY IF EXISTS "AdmiRank admins manage banners" ON public.banners;
CREATE POLICY "AdmiRank admins manage banners"
ON public.banners FOR ALL TO authenticated
USING (public.is_admirank_admin())
WITH CHECK (public.is_admirank_admin());

GRANT SELECT ON public.banners TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.banners TO authenticated;
