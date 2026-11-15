-- AdmiRank v28: working coupon codes (server-checked) + a default batch for every course.
-- Run once in Supabase SQL Editor. Safe to re-run.

-------------------------------------------------------------------------------
-- 1) Coupon price check (used by both the preview and the real payment)
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admirank_coupon_quote(p_student uuid, p_price numeric, p_code text, p_lock boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  c public.coupons%ROWTYPE;
  v_disc numeric;
  v_used int;
  v_user_used int;
BEGIN
  IF p_lock THEN
    SELECT * INTO c FROM public.coupons WHERE upper(trim(code)) = upper(trim(p_code)) LIMIT 1 FOR UPDATE;
  ELSE
    SELECT * INTO c FROM public.coupons WHERE upper(trim(code)) = upper(trim(p_code)) LIMIT 1;
  END IF;

  IF NOT FOUND OR COALESCE(c.is_active, true) = false THEN
    RETURN jsonb_build_object('valid', false, 'message', 'কুপন কোডটি সঠিক নয়।');
  END IF;
  IF c.starts_at IS NOT NULL AND now() < c.starts_at THEN
    RETURN jsonb_build_object('valid', false, 'message', 'এই কুপনটি এখনো চালু হয়নি।');
  END IF;
  IF c.expires_at IS NOT NULL AND now() > c.expires_at THEN
    RETURN jsonb_build_object('valid', false, 'message', 'এই কুপনের মেয়াদ শেষ হয়ে গেছে।');
  END IF;
  IF c.min_purchase IS NOT NULL AND p_price < c.min_purchase THEN
    RETURN jsonb_build_object('valid', false, 'message', 'এই কোর্সে কুপনটি প্রযোজ্য নয়।');
  END IF;
  IF c.usage_limit IS NOT NULL THEN
    SELECT count(*) INTO v_used FROM public.coupon_usages WHERE coupon_id = c.id;
    IF v_used >= c.usage_limit THEN
      RETURN jsonb_build_object('valid', false, 'message', 'এই কুপনের ব্যবহারের সীমা শেষ হয়ে গেছে।');
    END IF;
  END IF;
  SELECT count(*) INTO v_user_used FROM public.coupon_usages WHERE coupon_id = c.id AND student_id = p_student;
  IF v_user_used >= COALESCE(c.per_user_limit, 1) THEN
    RETURN jsonb_build_object('valid', false, 'message', 'আপনি এই কুপনটি আগেই ব্যবহার করেছেন।');
  END IF;

  IF lower(c.discount_type) LIKE '%percent%' THEN
    v_disc := round(p_price * c.discount_value / 100.0, 2);
    IF c.max_discount IS NOT NULL THEN v_disc := least(v_disc, c.max_discount); END IF;
  ELSE
    v_disc := c.discount_value;          -- fixed amount in taka
  END IF;
  v_disc := greatest(least(v_disc, p_price), 0);

  RETURN jsonb_build_object(
    'valid', true,
    'coupon_id', c.id,
    'code', upper(trim(c.code)),
    'original_amount', p_price,
    'discount_amount', v_disc,
    'final_amount', p_price - v_disc,
    'message', 'কুপন প্রয়োগ হয়েছে।'
  );
END; $$;
REVOKE ALL ON FUNCTION public.admirank_coupon_quote(uuid, numeric, text, boolean) FROM PUBLIC, anon, authenticated;

-------------------------------------------------------------------------------
-- 2) Preview (student presses "Apply") - changes nothing
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.preview_course_coupon(p_enrollment_id uuid, p_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_price numeric;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'You must be logged in.'; END IF;
  SELECT COALESCE(c.sale_price, c.price) INTO v_price
  FROM public.enrollments e
  JOIN public.batches b ON b.id = e.batch_id
  JOIN public.courses c ON c.id = b.course_id
  WHERE e.id = p_enrollment_id AND e.student_id = auth.uid() AND e.status = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'Pending enrollment not found for this student'; END IF;
  IF p_code IS NULL OR trim(p_code) = '' THEN
    RETURN jsonb_build_object('valid', false, 'message', 'কুপন কোড লিখুন।');
  END IF;
  RETURN public.admirank_coupon_quote(auth.uid(), v_price, p_code, false);
END; $$;
REVOKE ALL ON FUNCTION public.preview_course_coupon(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.preview_course_coupon(uuid, text) TO authenticated;

-------------------------------------------------------------------------------
-- 3) Submit payment: same checks as before, but the amount includes the coupon
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_course_payment_v2(
  p_enrollment_id uuid, p_payment_method text, p_transaction_id text,
  p_sender_phone_last2 text, p_coupon_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_price numeric; v_amount numeric; v_method text; v_payment_id uuid;
  v_quote jsonb; v_coupon_id uuid; v_disc numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role('student') THEN
    RAISE EXCEPTION 'Student authentication required';
  END IF;
  v_method := lower(trim(p_payment_method));
  IF v_method NOT IN ('bkash', 'nagad', 'rocket') THEN RAISE EXCEPTION 'Invalid payment method'; END IF;
  IF p_transaction_id IS NULL OR trim(p_transaction_id) = '' THEN RAISE EXCEPTION 'Transaction ID is required'; END IF;
  IF p_sender_phone_last2 IS NULL OR p_sender_phone_last2 !~ '^[0-9]{2}$' THEN
    RAISE EXCEPTION 'Enter exactly two sender phone digits';
  END IF;

  SELECT COALESCE(c.sale_price, c.price) INTO v_price
  FROM public.enrollments e
  JOIN public.batches b ON b.id = e.batch_id
  JOIN public.courses c ON c.id = b.course_id
  WHERE e.id = p_enrollment_id AND e.student_id = auth.uid() AND e.status = 'pending'
  FOR UPDATE OF e;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pending enrollment not found for this student'; END IF;
  IF v_price IS NULL OR v_price <= 0 THEN RAISE EXCEPTION 'This enrollment does not require a payment'; END IF;

  IF EXISTS (SELECT 1 FROM public.payments p WHERE p.enrollment_id = p_enrollment_id AND p.status = 'paid') THEN
    RAISE EXCEPTION 'This enrollment has already been paid';
  END IF;
  IF EXISTS (SELECT 1 FROM public.payments p WHERE p.enrollment_id = p_enrollment_id AND p.status = 'pending') THEN
    RAISE EXCEPTION 'A payment submission is already pending';
  END IF;

  v_amount := v_price;
  IF p_coupon_code IS NOT NULL AND trim(p_coupon_code) <> '' THEN
    v_quote := public.admirank_coupon_quote(auth.uid(), v_price, p_coupon_code, true);
    IF NOT (v_quote ->> 'valid')::boolean THEN RAISE EXCEPTION '%', v_quote ->> 'message'; END IF;
    v_coupon_id := (v_quote ->> 'coupon_id')::uuid;
    v_disc := (v_quote ->> 'discount_amount')::numeric;
    v_amount := (v_quote ->> 'final_amount')::numeric;
  END IF;
  IF v_amount <= 0 THEN RAISE EXCEPTION 'Invalid payable amount'; END IF;

  INSERT INTO public.payments (student_id, enrollment_id, amount, currency, payment_method, payment_provider,
                               transaction_id, sender_phone_last2, status, submitted_at)
  VALUES (auth.uid(), p_enrollment_id, v_amount, 'BDT', v_method, v_method,
          trim(p_transaction_id), p_sender_phone_last2, 'pending', now())
  RETURNING id INTO v_payment_id;

  IF v_coupon_id IS NOT NULL THEN
    INSERT INTO public.coupon_usages (coupon_id, student_id, enrollment_id, payment_id, discount_amount)
    VALUES (v_coupon_id, auth.uid(), p_enrollment_id, v_payment_id, v_disc);
  END IF;

  RETURN jsonb_build_object('success', true, 'payment_id', v_payment_id, 'amount', v_amount,
                            'discount', v_disc, 'status', 'pending',
                            'message', 'Payment submitted for admin verification');
END; $$;
REVOKE ALL ON FUNCTION public.submit_course_payment_v2(uuid, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_course_payment_v2(uuid, text, text, text, text) TO authenticated;

-------------------------------------------------------------------------------
-- 4) If an admin rejects a payment, give the coupon back to the student
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admirank_release_coupon_on_reject()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF OLD.status = 'pending' AND NEW.status NOT IN ('pending', 'paid') THEN
    DELETE FROM public.coupon_usages WHERE payment_id = NEW.id;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_release_coupon_on_reject ON public.payments;
CREATE TRIGGER trg_release_coupon_on_reject
AFTER UPDATE OF status ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.admirank_release_coupon_on_reject();

-------------------------------------------------------------------------------
-- 5) The SUNRISER coupon: 2000 -> 499  (fixed discount of 1501 taka)
--    Make sure the course price is exactly 2000, or change 1501 below.
-------------------------------------------------------------------------------
DELETE FROM public.coupons c
WHERE upper(trim(c.code)) = 'SUNRISER'
  AND NOT EXISTS (SELECT 1 FROM public.coupon_usages u WHERE u.coupon_id = c.id);

DO $$
DECLARE t text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.coupons WHERE upper(trim(code)) = 'SUNRISER') THEN
    RAISE NOTICE 'SUNRISER already exists and has been used - edit it in Admin > Coupons instead.';
    RETURN;
  END IF;
  FOREACH t IN ARRAY ARRAY['fixed', 'fixed_amount', 'amount', 'flat'] LOOP
    BEGIN
      INSERT INTO public.coupons (code, discount_type, discount_value, max_discount, min_purchase,
                                  usage_limit, per_user_limit, is_active)
      VALUES ('SUNRISER', t, 1501, NULL, 0, NULL, 1, true);
      EXIT;
    EXCEPTION WHEN check_violation THEN NULL;   -- try the next spelling
    END;
  END LOOP;
END $$;

-------------------------------------------------------------------------------
-- 6) Every course gets one default batch (existing batches are NOT touched)
-------------------------------------------------------------------------------
INSERT INTO public.batches (course_id, name, batch_code, status)
SELECT c.id, 'Main Batch', 'MAIN-' || left(c.id::text, 6), 'published'
FROM public.courses c
WHERE NOT EXISTS (SELECT 1 FROM public.batches b WHERE b.course_id = c.id);

CREATE OR REPLACE FUNCTION public.admirank_default_batch()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.batches b WHERE b.course_id = NEW.id) THEN
    INSERT INTO public.batches (course_id, name, batch_code, status)
    VALUES (NEW.id, 'Main Batch', 'MAIN-' || left(NEW.id::text, 6), 'published');
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_default_batch ON public.courses;
CREATE TRIGGER trg_default_batch
AFTER INSERT ON public.courses
FOR EACH ROW EXECUTE FUNCTION public.admirank_default_batch();

-- Check:  select code, discount_type, discount_value, is_active from public.coupons;
