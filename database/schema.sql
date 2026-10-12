-- EzyIntern HRMS PostgreSQL starter schema.
-- Apply only to a newly provisioned PostgreSQL database after reviewing permissions and migrations.
-- This schema is a scaffold; production row-level authorization and migrations are required.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_name text NOT NULL,
  slug text NOT NULL UNIQUE,
  timezone text NOT NULL DEFAULT 'Asia/Kolkata',
  currency char(3) NOT NULL DEFAULT 'INR',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS app_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  auth_provider text NOT NULL,
  auth_subject text NOT NULL,
  email text NOT NULL,
  display_name text NOT NULL,
  role text NOT NULL CHECK (role IN ('super_admin','hr_manager','finance_manager','department_manager','team_leader','employee')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (auth_provider, auth_subject),
  UNIQUE (company_id, email)
);

CREATE TABLE IF NOT EXISTS departments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  name text NOT NULL,
  code text,
  manager_employee_id uuid,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, name),
  UNIQUE (company_id, code)
);

CREATE TABLE IF NOT EXISTS employees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  user_id uuid REFERENCES app_users(id),
  employee_code text NOT NULL,
  legal_name text NOT NULL,
  preferred_name text,
  official_email text NOT NULL,
  personal_email text,
  phone text,
  department_id uuid REFERENCES departments(id),
  designation text NOT NULL,
  manager_employee_id uuid REFERENCES employees(id),
  employment_type text NOT NULL DEFAULT 'full_time',
  employment_status text NOT NULL DEFAULT 'active'
    CHECK (employment_status IN ('preboarding','active','probation','notice_period','suspended','exited','archived')),
  work_location text,
  joining_date date NOT NULL,
  probation_end_date date,
  last_working_date date,
  timezone text NOT NULL DEFAULT 'Asia/Kolkata',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, employee_code),
  UNIQUE (company_id, official_email)
);
ALTER TABLE departments DROP CONSTRAINT IF EXISTS departments_manager_employee_id_fkey;
ALTER TABLE departments ADD CONSTRAINT departments_manager_employee_id_fkey
  FOREIGN KEY (manager_employee_id) REFERENCES employees(id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE IF NOT EXISTS shifts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  name text NOT NULL,
  start_time time NOT NULL,
  end_time time NOT NULL,
  break_minutes integer NOT NULL DEFAULT 0 CHECK (break_minutes >= 0),
  grace_minutes integer NOT NULL DEFAULT 0 CHECK (grace_minutes >= 0),
  crosses_midnight boolean NOT NULL DEFAULT false,
  timezone text NOT NULL DEFAULT 'Asia/Kolkata',
  effective_from date NOT NULL DEFAULT CURRENT_DATE,
  effective_until date,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, name, effective_from)
);

CREATE TABLE IF NOT EXISTS employee_shifts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  employee_id uuid NOT NULL REFERENCES employees(id),
  shift_id uuid NOT NULL REFERENCES shifts(id),
  effective_from date NOT NULL,
  effective_until date,
  assigned_by uuid REFERENCES app_users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (effective_until IS NULL OR effective_until >= effective_from)
);

CREATE TABLE IF NOT EXISTS attendance_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  employee_id uuid NOT NULL REFERENCES employees(id),
  work_date date NOT NULL,
  checked_in_at timestamptz,
  checked_out_at timestamptz,
  break_minutes integer NOT NULL DEFAULT 0 CHECK (break_minutes >= 0),
  recorded_source text NOT NULL DEFAULT 'web',
  status text NOT NULL DEFAULT 'present'
    CHECK (status IN ('present','late','absent','half_day','work_from_home','on_leave','missed_punch','regularized')),
  approved_work_minutes integer CHECK (approved_work_minutes IS NULL OR approved_work_minutes >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (checked_out_at IS NULL OR checked_in_at IS NULL OR checked_out_at >= checked_in_at),
  UNIQUE (company_id, employee_id, work_date)
);
CREATE INDEX IF NOT EXISTS idx_attendance_company_date ON attendance_sessions(company_id, work_date);
CREATE INDEX IF NOT EXISTS idx_attendance_employee_date ON attendance_sessions(employee_id, work_date DESC);

CREATE TABLE IF NOT EXISTS attendance_corrections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  attendance_id uuid NOT NULL REFERENCES attendance_sessions(id),
  requested_by uuid NOT NULL REFERENCES app_users(id),
  reviewed_by uuid REFERENCES app_users(id),
  requested_check_in timestamptz,
  requested_check_out timestamptz,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  reviewer_comment text,
  decided_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS leave_types (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  name text NOT NULL,
  is_paid boolean NOT NULL DEFAULT true,
  annual_entitlement numeric(7,2) NOT NULL DEFAULT 0 CHECK (annual_entitlement >= 0),
  carry_forward_limit numeric(7,2) NOT NULL DEFAULT 0 CHECK (carry_forward_limit >= 0),
  requires_document boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, name)
);

CREATE TABLE IF NOT EXISTS leave_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  employee_id uuid NOT NULL REFERENCES employees(id),
  leave_type_id uuid NOT NULL REFERENCES leave_types(id),
  start_date date NOT NULL,
  end_date date NOT NULL,
  units numeric(6,2) NOT NULL CHECK (units > 0),
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','cancelled')),
  decided_by uuid REFERENCES app_users(id),
  decision_comment text,
  decided_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (end_date >= start_date)
);
CREATE INDEX IF NOT EXISTS idx_leave_company_status ON leave_requests(company_id, status, start_date);
CREATE INDEX IF NOT EXISTS idx_leave_employee_dates ON leave_requests(employee_id, start_date, end_date);

CREATE TABLE IF NOT EXISTS leave_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  employee_id uuid NOT NULL REFERENCES employees(id),
  leave_type_id uuid NOT NULL REFERENCES leave_types(id),
  entry_type text NOT NULL CHECK (entry_type IN ('opening','accrual','usage','reversal','adjustment','carry_forward','encashment')),
  units numeric(7,2) NOT NULL,
  effective_date date NOT NULL,
  reference_request_id uuid REFERENCES leave_requests(id),
  note text,
  created_by uuid REFERENCES app_users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_leave_ledger_balance ON leave_ledger(company_id, employee_id, leave_type_id, effective_date);

CREATE TABLE IF NOT EXISTS salary_structures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  employee_id uuid NOT NULL REFERENCES employees(id),
  annual_ctc numeric(14,2) NOT NULL CHECK (annual_ctc >= 0),
  monthly_gross numeric(14,2) NOT NULL CHECK (monthly_gross >= 0),
  components jsonb NOT NULL DEFAULT '[]'::jsonb,
  effective_from date NOT NULL,
  effective_until date,
  approved_by uuid REFERENCES app_users(id),
  approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (effective_until IS NULL OR effective_until >= effective_from)
);
CREATE INDEX IF NOT EXISTS idx_salary_employee_effective ON salary_structures(company_id, employee_id, effective_from DESC);

CREATE TABLE IF NOT EXISTS payroll_periods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  period_start date NOT NULL,
  period_end date NOT NULL,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','review','approved','released','locked','cancelled')),
  created_by uuid REFERENCES app_users(id),
  approved_by uuid REFERENCES app_users(id),
  approved_at timestamptz,
  locked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (period_end >= period_start),
  UNIQUE (company_id, period_start, period_end)
);

CREATE TABLE IF NOT EXISTS payroll_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  payroll_period_id uuid NOT NULL REFERENCES payroll_periods(id),
  employee_id uuid NOT NULL REFERENCES employees(id),
  gross_earnings numeric(14,2) NOT NULL DEFAULT 0,
  employee_deductions numeric(14,2) NOT NULL DEFAULT 0,
  employer_contributions numeric(14,2) NOT NULL DEFAULT 0,
  reimbursements numeric(14,2) NOT NULL DEFAULT 0,
  net_pay numeric(14,2) NOT NULL DEFAULT 0,
  component_breakdown jsonb NOT NULL DEFAULT '{}'::jsonb,
  exception_notes jsonb NOT NULL DEFAULT '[]'::jsonb,
  payment_status text NOT NULL DEFAULT 'not_initiated'
    CHECK (payment_status IN ('not_initiated','pending','processing','paid','failed','cancelled','reversed')),
  payment_reference text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, payroll_period_id, employee_id)
);

CREATE TABLE IF NOT EXISTS tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  title text NOT NULL,
  description text,
  assigned_to uuid REFERENCES employees(id),
  assigned_by uuid REFERENCES app_users(id),
  due_at timestamptz,
  priority text NOT NULL DEFAULT 'medium' CHECK (priority IN ('low','medium','high','urgent')),
  status text NOT NULL DEFAULT 'todo' CHECK (status IN ('backlog','todo','in_progress','under_review','blocked','completed','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tasks_company_status_due ON tasks(company_id, status, due_at);

CREATE TABLE IF NOT EXISTS documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  employee_id uuid REFERENCES employees(id),
  title text NOT NULL,
  document_type text NOT NULL,
  s3_bucket text NOT NULL,
  s3_key text NOT NULL,
  content_type text,
  size_bytes bigint CHECK (size_bytes IS NULL OR size_bytes >= 0),
  access_classification text NOT NULL DEFAULT 'restricted',
  uploaded_by uuid REFERENCES app_users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, s3_bucket, s3_key)
);

CREATE TABLE IF NOT EXISTS audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  actor_user_id uuid REFERENCES app_users(id),
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  detail jsonb NOT NULL DEFAULT '{}'::jsonb,
  request_id text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_company_time ON audit_events(company_id, created_at DESC);

-- IMPORTANT: Add and test backend tenant isolation / RLS policies before production.
-- Do not expose payroll, employee, document, or audit tables through an unauthenticated API.
COMMIT;
