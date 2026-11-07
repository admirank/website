-- AdmiRank enrollment workflow and automatic admin access
-- Run this AFTER supabase-migration-v2.sql in Supabase SQL Editor.
-- Uses the existing public.enrollments, public.batches and public.user_roles tables.

-- Student-facing, secure RPC: creates a PENDING enrollment for a published batch.
-- Admins are given ACTIVE enrollment instead and do not need to pay.
CREATE OR REPLACE FUNCTION public.create_course_enrollment(p_batch_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_batch public.batches%ROWTYPE;
  v_enrollment_id uuid;
  v_is_admin boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'You must be logged in to enroll.';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.user_roles ur
    WHERE ur.user_id = v_user_id AND ur.role = 'admin'
  ) INTO v_is_admin;

  SELECT * INTO v_batch
  FROM public.batches
  WHERE id = p_batch_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Batch not found.';
  END IF;

  IF NOT v_is_admin THEN
    IF v_batch.status NOT IN ('published', 'ongoing') THEN
      RAISE EXCEPTION 'Enrollment is not open for this batch.';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.courses c
      WHERE c.id = v_batch.course_id AND c.status = 'published'
    ) THEN
      RAISE EXCEPTION 'This course is not currently available.';
    END IF;

    IF v_batch.enrollment_start IS NOT NULL AND now() < v_batch.enrollment_start THEN
      RAISE EXCEPTION 'Enrollment has not started yet.';
    END IF;
    IF v_batch.enrollment_end IS NOT NULL AND now() > v_batch.enrollment_end THEN
      RAISE EXCEPTION 'Enrollment has closed for this batch.';
    END IF;
  END IF;

  SELECT id INTO v_enrollment_id
  FROM public.enrollments
  WHERE student_id = v_user_id AND batch_id = p_batch_id
  LIMIT 1;

  IF v_enrollment_id IS NOT NULL THEN
    IF v_is_admin THEN
      UPDATE public.enrollments
      SET status = 'active'
      WHERE id = v_enrollment_id AND status <> 'active';
    ELSIF EXISTS (
      SELECT 1 FROM public.enrollments
      WHERE id = v_enrollment_id AND status IN ('pending', 'active')
    ) THEN
      RETURN v_enrollment_id;
    ELSE
      UPDATE public.enrollments
      SET status = 'pending'
      WHERE id = v_enrollment_id;
    END IF;
    RETURN v_enrollment_id;
  END IF;

  INSERT INTO public.enrollments (student_id, batch_id, status)
  VALUES (v_user_id, p_batch_id, CASE WHEN v_is_admin THEN 'active' ELSE 'pending' END)
  RETURNING id INTO v_enrollment_id;

  RETURN v_enrollment_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_course_enrollment(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_course_enrollment(uuid) TO authenticated;

-- Backfill ACTIVE enrollments for every existing admin and every existing batch.
INSERT INTO public.enrollments (student_id, batch_id, status)
SELECT ur.user_id, b.id, 'active'
FROM public.user_roles ur
CROSS JOIN public.batches b
WHERE ur.role = 'admin'
  AND NOT EXISTS (
    SELECT 1 FROM public.enrollments e
    WHERE e.student_id = ur.user_id AND e.batch_id = b.id
  );

-- When a new admin role is assigned, enroll that user in every existing batch.
CREATE OR REPLACE FUNCTION public.admirank_enroll_new_admin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.role = 'admin' THEN
    INSERT INTO public.enrollments (student_id, batch_id, status)
    SELECT NEW.user_id, b.id, 'active'
    FROM public.batches b
    WHERE NOT EXISTS (
      SELECT 1 FROM public.enrollments e
      WHERE e.student_id = NEW.user_id AND e.batch_id = b.id
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS admirank_auto_enroll_admin_role ON public.user_roles;
CREATE TRIGGER admirank_auto_enroll_admin_role
AFTER INSERT OR UPDATE OF role ON public.user_roles
FOR EACH ROW EXECUTE FUNCTION public.admirank_enroll_new_admin();

-- When a new batch is created, automatically enroll every existing admin.
CREATE OR REPLACE FUNCTION public.admirank_enroll_admins_in_new_batch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.enrollments (student_id, batch_id, status)
  SELECT ur.user_id, NEW.id, 'active'
  FROM public.user_roles ur
  WHERE ur.role = 'admin'
    AND NOT EXISTS (
      SELECT 1 FROM public.enrollments e
      WHERE e.student_id = ur.user_id AND e.batch_id = NEW.id
    );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS admirank_auto_enroll_admin_batch ON public.batches;
CREATE TRIGGER admirank_auto_enroll_admin_batch
AFTER INSERT ON public.batches
FOR EACH ROW EXECUTE FUNCTION public.admirank_enroll_admins_in_new_batch();
