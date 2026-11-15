-- AdmiRank v24: admin-only usage report (storage buckets + database tables, in bytes).
-- Used by the admin "Storage usage" page. Run once in the Supabase SQL Editor. Safe to re-run.

CREATE OR REPLACE FUNCTION public.admin_usage_report()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_buckets jsonb;
    v_tables  jsonb;
BEGIN
    IF auth.uid() IS NULL OR NOT public.has_role('admin') THEN
        RAISE EXCEPTION 'Admin permission required';
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object('bucket', b.id, 'files', COALESCE(o.files, 0), 'bytes', COALESCE(o.bytes, 0)) ORDER BY COALESCE(o.bytes, 0) DESC), '[]'::jsonb)
    INTO v_buckets
    FROM storage.buckets b
    LEFT JOIN (
        SELECT bucket_id, count(*) AS files, sum(COALESCE((metadata->>'size')::bigint, 0)) AS bytes
        FROM storage.objects GROUP BY bucket_id
    ) o ON o.bucket_id = b.id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object('name', c.relname, 'rows', COALESCE(s.n_live_tup, 0), 'bytes', pg_total_relation_size(c.oid)) ORDER BY pg_total_relation_size(c.oid) DESC), '[]'::jsonb)
    INTO v_tables
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
    WHERE c.relkind = 'r';

    RETURN jsonb_build_object(
        'buckets', v_buckets,
        'tables', v_tables,
        'database_bytes', pg_database_size(current_database())
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_usage_report() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_usage_report() TO authenticated, service_role;
NOTIFY pgrst, 'reload schema';
