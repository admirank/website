-- AdmiRank v27: phone-number / email login without email verification.
-- Run once in Supabase SQL Editor.
--
-- ALSO REQUIRED (dashboard, cannot be done in SQL):
--   Authentication -> Providers -> Email -> turn OFF "Confirm email"  (then Save)

-- 1) Where login IDs are kept for admins to search (passwords stay hashed in Supabase Auth, never in this table)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS login_id text;
CREATE INDEX IF NOT EXISTS profiles_login_id_idx ON public.profiles (login_id);
CREATE INDEX IF NOT EXISTS profiles_phone_idx ON public.profiles (phone);

-- 2) New-user trigger now also saves phone + login_id
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, student_id, full_name, phone, login_id)
  VALUES (
    NEW.id,
    public.generate_student_id(),
    NEW.raw_user_meta_data ->> 'full_name',
    NULLIF(NEW.raw_user_meta_data ->> 'phone', ''),
    CASE WHEN lower(NEW.email) LIKE '%@phone.admirank.app'
         THEN split_part(NEW.email, '@', 1)   -- phone login: store the phone number
         ELSE lower(NEW.email) END            -- email login
  );

  -- Every new registration starts as a student. Admin privileges must be granted manually.
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'student');
  RETURN NEW;
END;
$$;

-- 3) Back-fill login_id for existing students
UPDATE public.profiles p
SET login_id = CASE WHEN lower(u.email) LIKE '%@phone.admirank.app'
                    THEN split_part(u.email, '@', 1) ELSE lower(u.email) END
FROM auth.users u
WHERE u.id = p.id AND p.login_id IS NULL;

-- 4) Admin-only: set a new password for a student who contacted the WhatsApp helpline.
--    Usage (as a logged-in admin, or from SQL editor with the admin check bypassed below):
--      select public.admin_reset_user_password('01712345678', 'newpass123');
CREATE OR REPLACE FUNCTION public.admin_reset_user_password(p_login_id text, p_new_password text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
  v_email text;
  v_digits text;
  v_n int;
BEGIN
  -- auth.uid() is NULL in the SQL editor (service role) -> allowed; in the app only admins pass.
  IF auth.uid() IS NOT NULL AND NOT public.is_admirank_admin() THEN
    RAISE EXCEPTION 'Admins only';
  END IF;
  IF length(coalesce(p_new_password, '')) < 6 THEN
    RAISE EXCEPTION 'Password must be at least 6 characters';
  END IF;

  v_email := lower(trim(p_login_id));
  IF position('@' in v_email) = 0 THEN
    v_digits := regexp_replace(v_email, '\D', '', 'g');
    v_digits := regexp_replace(v_digits, '^88', '');
    IF v_digits !~ '^0' THEN v_digits := '0' || v_digits; END IF;
    v_email := v_digits || '@phone.admirank.app';
  END IF;

  UPDATE auth.users
  SET encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
      updated_at = now()
  WHERE lower(email) = v_email;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RAISE EXCEPTION 'No account found for %', p_login_id; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_reset_user_password(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reset_user_password(text, text) TO authenticated;
