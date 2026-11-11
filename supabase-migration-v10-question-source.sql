-- AdmiRank v10: question SOURCE for the question bank.
-- Every bank question can now say where it came from (e.g. "Udvash DU A QB Model Test - 01").
-- Sources are a small list of text names that admins manage and then pick when adding questions
-- one by one or uploading them in bulk.
-- Run AFTER supabase-migration-v9-question-bank.sql, once, in the Supabase SQL Editor.
-- Safe to re-run: every step is idempotent.

-- ---------------------------------------------------------------------------
-- 1. The list of sources (plain text names, unique ignoring case / extra spaces)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.qb_sources (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name          text NOT NULL CHECK (length(btrim(name)) > 0),
    display_order integer NOT NULL DEFAULT 0,
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS qb_sources_name_key ON public.qb_sources (lower(btrim(name)));

-- ---------------------------------------------------------------------------
-- 2. Each question points at one source (optional). A source that still has questions
--    cannot be deleted by accident (RESTRICT).
-- ---------------------------------------------------------------------------
ALTER TABLE public.qb_questions
    ADD COLUMN IF NOT EXISTS source_id uuid REFERENCES public.qb_sources(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS qb_questions_source_idx ON public.qb_questions (source_id);

-- ---------------------------------------------------------------------------
-- 3. First source + set it on ALL questions that are already in the bank
-- ---------------------------------------------------------------------------
INSERT INTO public.qb_sources (name, display_order)
SELECT 'Udvash DU A QB Model Test - 01', 1
WHERE NOT EXISTS (
    SELECT 1 FROM public.qb_sources
    WHERE lower(btrim(name)) = lower('Udvash DU A QB Model Test - 01')
);

UPDATE public.qb_questions
SET source_id = (
    SELECT id FROM public.qb_sources
    WHERE lower(btrim(name)) = lower('Udvash DU A QB Model Test - 01')
)
WHERE source_id IS NULL;

-- ---------------------------------------------------------------------------
-- 4. Security: same as the rest of the bank - admins only.
--    Uses public.is_admirank_admin() from supabase-migration-v4-course-exam-access.sql.
-- ---------------------------------------------------------------------------
ALTER TABLE public.qb_sources ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "AdmiRank admins manage qb_sources" ON public.qb_sources;
CREATE POLICY "AdmiRank admins manage qb_sources" ON public.qb_sources
    FOR ALL TO authenticated USING (public.is_admirank_admin()) WITH CHECK (public.is_admirank_admin());

REVOKE ALL ON public.qb_sources FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.qb_sources TO authenticated;

-- Quick check after running: every question should have a source.
--   SELECT s.name, count(*) FROM public.qb_questions q
--   LEFT JOIN public.qb_sources s ON s.id = q.source_id GROUP BY s.name;
