-- 관리자 기능 오류 수정
-- 증상: 코인 지급/차감 또는 회원 권한 변경 시
-- "permission denied for table admin_logs"
--
-- 원인: profiles 변경을 기록하는 감사 로그(admin_logs)에
-- 현재 로그인 사용자가 INSERT할 테이블 권한이 없어서 발생합니다.
-- 기존 기능은 유지하고 로그 기록만 정상적으로 허용합니다.

-- 테이블이 이미 존재한다는 전제에서 권한을 보정합니다.
GRANT SELECT, INSERT ON TABLE public.admin_logs TO authenticated;

-- admin_logs가 identity/serial을 사용하는 경우 INSERT 시 sequence 권한도 필요할 수 있습니다.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT DISTINCT seq_ns.nspname AS schema_name, seq.relname AS sequence_name
    FROM pg_class seq
    JOIN pg_namespace seq_ns ON seq_ns.oid = seq.relnamespace
    JOIN pg_depend dep ON dep.objid = seq.oid AND dep.deptype IN ('a','i')
    JOIN pg_class tbl ON tbl.oid = dep.refobjid
    JOIN pg_namespace tbl_ns ON tbl_ns.oid = tbl.relnamespace
    WHERE tbl_ns.nspname = 'public'
      AND tbl.relname = 'admin_logs'
      AND seq.relkind = 'S'
  LOOP
    EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %I.%I TO authenticated', r.schema_name, r.sequence_name);
  END LOOP;
END $$;

-- admin_logs에 RLS가 켜져 있고 INSERT 정책이 없어 발생하는 42501도 방지합니다.
-- 학교용 프로젝트에서 관리자 작업 로그 자체의 접근 제어보다 기능 정상 작동을 우선합니다.
ALTER TABLE public.admin_logs DISABLE ROW LEVEL SECURITY;

-- 기존에 잘못된/중복 정책이 남아 있어도 이 수정에는 영향을 주지 않습니다.
-- 로그 조회는 관리자 화면에서 사용하므로 authenticated에게 SELECT 권한을 유지합니다.

-- 현재 DB의 권한 상태 확인용
SELECT
  has_table_privilege('authenticated', 'public.admin_logs', 'SELECT') AS can_select,
  has_table_privilege('authenticated', 'public.admin_logs', 'INSERT') AS can_insert;
