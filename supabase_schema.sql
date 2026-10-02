-- =========================================================================
-- IRONBLOOD GYM & FITNESS STUDIO - SUPABASE DATABASE SCHEMA
-- Execute this script in your Supabase Dashboard -> SQL Editor -> Run
-- =========================================================================

-- 1. Enable pgcrypto extension for secure bcrypt password hashing
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Create Members Table
CREATE TABLE IF NOT EXISTS public.members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id TEXT UNIQUE NOT NULL,             -- Unique Member ID (e.g. 'MB-001')
    password_hash TEXT NOT NULL,                 -- Secure Bcrypt hash (protected)
    full_name TEXT NOT NULL,                     -- Member Name
    phone TEXT,                                  -- Contact Number (+91)
    emergency_phone TEXT,                        -- Emergency Contact Number (+91)
    photo_url TEXT,                              -- Profile Picture URL / Base64
    email TEXT,                                  -- Email Address
    aadhar_number TEXT,                          -- 12-digit Aadhar Card Number
    address TEXT,                                -- Residential / Street Address
    medical_history TEXT,                        -- Medical History / Health Conditions / Allergies / Notes
    plan TEXT DEFAULT 'Monthly',                 -- Membership Plan ('Monthly', '3 Months', '6 Months', 'Annual')
    membership_start_date DATE DEFAULT CURRENT_DATE, -- Membership Start Date
    membership_expiry_date DATE DEFAULT (CURRENT_DATE + INTERVAL '30 days'), -- Expiry Date (1 Month = 30 Days)
    assigned_trainer TEXT DEFAULT 'Unassigned',  -- General Floor Trainer
    has_pt BOOLEAN DEFAULT FALSE,                -- Has Active Personal Training
    pt_plan TEXT DEFAULT 'None',                 -- PT Plan ('Monthly PT', '3 Months PT', '6 Months PT', 'Annual PT')
    pt_start_date DATE,                          -- PT Start Date
    pt_expiry_date DATE,                         -- PT Expiry Date
    pt_trainer TEXT DEFAULT 'Unassigned',        -- Assigned Personal Coach
    renewal_status TEXT DEFAULT 'Active',        -- 'Active', 'Expiring Soon', 'Pending Renewal', 'Expired'
    pt_status TEXT DEFAULT 'None',               -- 'Active', 'Expiring Soon', 'Pending PT Renewal', 'Expired', 'None'
    is_active BOOLEAN DEFAULT TRUE,              -- Active Membership Status
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ensure columns exist if table was previously created
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS emergency_phone TEXT;
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS photo_url TEXT;
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS aadhar_number TEXT;
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS medical_history TEXT;
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS membership_start_date DATE DEFAULT CURRENT_DATE;
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS membership_expiry_date DATE DEFAULT (CURRENT_DATE + INTERVAL '30 days');
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS assigned_trainer TEXT DEFAULT 'Unassigned';
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS has_pt BOOLEAN DEFAULT FALSE;
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS pt_plan TEXT DEFAULT 'None';
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS pt_start_date DATE;
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS pt_expiry_date DATE;
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS pt_trainer TEXT DEFAULT 'Unassigned';
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS renewal_status TEXT DEFAULT 'Active';
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS pt_status TEXT DEFAULT 'None';
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS requested_renewal_plan TEXT;
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS requested_pt_plan TEXT;
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS requested_pt_trainer TEXT;

-- 3. Create Trainers Table
CREATE TABLE IF NOT EXISTS public.trainers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trainer_id TEXT UNIQUE NOT NULL,            -- Unique Trainer ID (e.g. 'TR-01')
    password_hash TEXT NOT NULL,                 -- Secure Bcrypt hash (protected)
    full_name TEXT NOT NULL,                     -- Trainer Full Name
    phone TEXT NOT NULL,                         -- Contact Number (+91)
    photo_url TEXT,                              -- Profile Picture URL / Base64
    email TEXT,                                  -- Email Address
    aadhar_number TEXT,                          -- 12-digit Aadhar Card Number
    address TEXT,                                -- Residential / Street Address
    experience TEXT DEFAULT '3+ Years',          -- Experience
    clients_count INT DEFAULT 0,                 -- Current active clients
    is_active BOOLEAN DEFAULT TRUE,              -- Active Status
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.trainers ADD COLUMN IF NOT EXISTS photo_url TEXT;
ALTER TABLE public.trainers ADD COLUMN IF NOT EXISTS aadhar_number TEXT;
ALTER TABLE public.trainers ADD COLUMN IF NOT EXISTS address TEXT;

-- 4. Enable Row Level Security (RLS)
ALTER TABLE public.members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trainers ENABLE ROW LEVEL SECURITY;

-- Allow read/write policies for public / authenticated clients
CREATE POLICY "Allow all on members" ON public.members FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on trainers" ON public.trainers FOR ALL USING (true) WITH CHECK (true);

-- 5. Secure PostgreSQL RPC Function: Verify Member Login
CREATE OR REPLACE FUNCTION verify_member_login(
    p_member_id TEXT,
    p_password TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_member RECORD;
    v_member_json JSONB;
BEGIN
    SELECT *
    INTO v_member
    FROM public.members
    WHERE (LOWER(member_id) = LOWER(TRIM(p_member_id)) OR phone = TRIM(p_member_id) OR LOWER(email) = LOWER(TRIM(p_member_id)))
      AND password_hash = crypt(p_password, password_hash)
      AND (is_active IS NULL OR is_active = TRUE);

    IF FOUND THEN
        v_member_json := to_jsonb(v_member);
        -- Securely strip password hash from response payload
        v_member_json := v_member_json - 'password_hash';

        RETURN jsonb_build_object(
            'success', true,
            'message', 'Authentication successful',
            'member', v_member_json
        );
    ELSE
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Invalid Member ID or Password'
        );
    END IF;
END;
$$;

-- 6. Secure PostgreSQL RPC Function: First-Time Member Account Activation & Password Setup
CREATE OR REPLACE FUNCTION activate_member_account(
    p_member_id TEXT,
    p_new_password TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count INT;
BEGIN
    UPDATE public.members
    SET password_hash = crypt(p_new_password, gen_salt('bf', 10)),
        updated_at = NOW()
    WHERE (LOWER(member_id) = LOWER(TRIM(p_member_id)) OR phone = TRIM(p_member_id));

    GET DIAGNOSTICS v_count = ROW_COUNT;

    IF v_count > 0 THEN
        RETURN jsonb_build_object(
            'success', true,
            'message', 'Account activated successfully. You can now log in.'
        );
    ELSE
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Member ID or phone number not found. Please contact front desk.'
        );
    END IF;
END;
$$;

-- 7. Helper Function: Admin Register New Member
CREATE OR REPLACE FUNCTION admin_create_member(
    p_member_id TEXT,
    p_full_name TEXT,
    p_initial_password TEXT,
    p_phone TEXT DEFAULT NULL,
    p_email TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.members (member_id, full_name, password_hash, phone, email)
    VALUES (
        TRIM(p_member_id),
        TRIM(p_full_name),
        crypt(p_initial_password, gen_salt('bf', 10)),
        TRIM(p_phone),
        TRIM(p_email)
    );

    RETURN jsonb_build_object('success', true, 'message', 'Member created successfully');
EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('success', false, 'message', 'Member ID already exists');
END;
$$;

-- 8. Secure PostgreSQL RPC Function: Verify Trainer Login
CREATE OR REPLACE FUNCTION verify_trainer_login(
    p_trainer_id TEXT,
    p_password TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_trainer RECORD;
BEGIN
    SELECT id, trainer_id, full_name, phone, photo_url, email, aadhar_number, address, experience, clients_count, is_active
    INTO v_trainer
    FROM public.trainers
    WHERE (LOWER(trainer_id) = LOWER(TRIM(p_trainer_id)) OR phone = TRIM(p_trainer_id) OR LOWER(email) = LOWER(TRIM(p_trainer_id)))
      AND password_hash = crypt(p_password, password_hash)
      AND is_active = TRUE;

    IF FOUND THEN
        RETURN jsonb_build_object(
            'success', true,
            'message', 'Authentication successful',
            'trainer', jsonb_build_object(
                'id', v_trainer.id,
                'trainer_id', v_trainer.trainer_id,
                'full_name', v_trainer.full_name,
                'phone', v_trainer.phone,
                'photo_url', v_trainer.photo_url,
                'email', v_trainer.email,
                'aadhar_number', v_trainer.aadhar_number,
                'address', v_trainer.address,
                'experience', v_trainer.experience,
                'clients_count', v_trainer.clients_count,
                'is_active', v_trainer.is_active
            )
        );
    ELSE
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Invalid Trainer ID or Password'
        );
    END IF;
END;
$$;

-- 9. Secure PostgreSQL RPC Function: First-Time Trainer Account Activation & Password Setup
CREATE OR REPLACE FUNCTION activate_trainer_account(
    p_trainer_id TEXT,
    p_new_password TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count INT;
BEGIN
    UPDATE public.trainers
    SET password_hash = crypt(p_new_password, gen_salt('bf', 10)),
        updated_at = NOW()
    WHERE (LOWER(trainer_id) = LOWER(TRIM(p_trainer_id)) OR phone = TRIM(p_trainer_id));

    GET DIAGNOSTICS v_count = ROW_COUNT;

    IF v_count > 0 THEN
        RETURN jsonb_build_object(
            'success', true,
            'message', 'Trainer account activated successfully! You can now log in.'
        );
    ELSE
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Trainer ID or phone number not found. Please contact Admin.'
        );
    END IF;
END;
$$;

-- 10. Helper Function: Admin Register New Trainer
CREATE OR REPLACE FUNCTION admin_create_trainer(
    p_trainer_id TEXT,
    p_full_name TEXT,
    p_initial_password TEXT,
    p_phone TEXT,
    p_email TEXT DEFAULT NULL,
    p_experience TEXT DEFAULT '3+ Years'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.trainers (trainer_id, full_name, password_hash, phone, email, experience)
    VALUES (
        TRIM(p_trainer_id),
        TRIM(p_full_name),
        crypt(p_initial_password, gen_salt('bf', 10)),
        TRIM(p_phone),
        TRIM(p_email),
        TRIM(p_experience)
    );

    RETURN jsonb_build_object('success', true, 'message', 'Trainer registered successfully');
EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('success', false, 'message', 'Trainer ID already exists');
END;
$$;

-- 11. RPC Function: Request Membership Renewal (Member Side)
CREATE OR REPLACE FUNCTION request_membership_renewal(
    p_member_id TEXT,
    p_plan TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.members
    SET renewal_status = 'Pending Approval',
        requested_renewal_plan = p_plan,
        updated_at = NOW()
    WHERE LOWER(member_id) = LOWER(TRIM(p_member_id));

    IF FOUND THEN
        RETURN jsonb_build_object(
            'success', true,
            'message', 'Membership renewal request submitted for ' || p_plan || '! Front desk / Admin will confirm shortly.'
        );
    ELSE
        RETURN jsonb_build_object('success', false, 'message', 'Member not found');
    END IF;
END;
$$;

-- 12. RPC Function: Request Personal Training (Member Side)
CREATE OR REPLACE FUNCTION request_personal_training(
    p_member_id TEXT,
    p_pt_plan TEXT,
    p_trainer_name TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.members
    SET pt_status = 'Requested',
        requested_pt_plan = p_pt_plan,
        requested_pt_trainer = p_trainer_name,
        updated_at = NOW()
    WHERE LOWER(member_id) = LOWER(TRIM(p_member_id));

    IF FOUND THEN
        RETURN jsonb_build_object(
            'success', true,
            'message', 'Personal Training request submitted with Coach ' || p_trainer_name || ' (' || p_pt_plan || ')!'
        );
    ELSE
        RETURN jsonb_build_object('success', false, 'message', 'Member not found');
    END IF;
END;
$$;

-- 13. RPC Function: Admin Confirm / Renew Membership
CREATE OR REPLACE FUNCTION admin_renew_membership(
    p_member_id TEXT,
    p_plan TEXT,
    p_months INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_new_expiry DATE;
BEGIN
    -- Calculate new expiry: 1 Year = full calendar year (365/366 days), other plans = 30 days per month
    IF COALESCE(p_months, 1) >= 12 OR LOWER(p_plan) LIKE '%annual%' OR LOWER(p_plan) LIKE '%year%' OR LOWER(p_plan) LIKE '%12 month%' THEN
        SELECT GREATEST(COALESCE(membership_expiry_date, CURRENT_DATE), CURRENT_DATE) + ((COALESCE(p_months, 12) / 12) || ' year')::INTERVAL
        INTO v_new_expiry
        FROM public.members
        WHERE LOWER(member_id) = LOWER(TRIM(p_member_id));
    ELSE
        SELECT GREATEST(COALESCE(membership_expiry_date, CURRENT_DATE), CURRENT_DATE) + ((COALESCE(p_months, 1) * 30) || ' days')::INTERVAL
        INTO v_new_expiry
        FROM public.members
        WHERE LOWER(member_id) = LOWER(TRIM(p_member_id));
    END IF;

    UPDATE public.members
    SET plan = p_plan,
        membership_expiry_date = v_new_expiry,
        renewal_status = 'Active',
        requested_renewal_plan = NULL,
        is_active = TRUE,
        updated_at = NOW()
    WHERE LOWER(member_id) = LOWER(TRIM(p_member_id));

    IF FOUND THEN
        RETURN jsonb_build_object(
            'success', true,
            'message', 'Membership renewed successfully until ' || v_new_expiry::TEXT
        );
    ELSE
        RETURN jsonb_build_object('success', false, 'message', 'Member not found');
    END IF;
END;
$$;

-- 14. RPC Function: Admin Assign / Activate Personal Training
CREATE OR REPLACE FUNCTION admin_assign_pt(
    p_member_id TEXT,
    p_pt_plan TEXT,
    p_trainer_name TEXT,
    p_months INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_new_pt_expiry DATE;
BEGIN
    -- Calculate new PT expiry: 1 Year = full calendar year (365/366 days), other plans = 30 days per month
    IF COALESCE(p_months, 1) >= 12 OR LOWER(p_pt_plan) LIKE '%annual%' OR LOWER(p_pt_plan) LIKE '%year%' OR LOWER(p_pt_plan) LIKE '%12 month%' THEN
        SELECT GREATEST(COALESCE(pt_expiry_date, CURRENT_DATE), CURRENT_DATE) + ((COALESCE(p_months, 12) / 12) || ' year')::INTERVAL
        INTO v_new_pt_expiry
        FROM public.members
        WHERE LOWER(member_id) = LOWER(TRIM(p_member_id));
    ELSE
        SELECT GREATEST(COALESCE(pt_expiry_date, CURRENT_DATE), CURRENT_DATE) + ((COALESCE(p_months, 1) * 30) || ' days')::INTERVAL
        INTO v_new_pt_expiry
        FROM public.members
        WHERE LOWER(member_id) = LOWER(TRIM(p_member_id));
    END IF;

    UPDATE public.members
    SET has_pt = TRUE,
        pt_plan = p_pt_plan,
        pt_trainer = p_trainer_name,
        pt_start_date = COALESCE(pt_start_date, CURRENT_DATE),
        pt_expiry_date = v_new_pt_expiry,
        pt_status = 'Active',
        requested_pt_plan = NULL,
        requested_pt_trainer = NULL,
        updated_at = NOW()
    WHERE LOWER(member_id) = LOWER(TRIM(p_member_id));

    -- Increment clients_count for the trainer if not unassigned
    IF LOWER(TRIM(p_trainer_name)) <> 'unassigned' THEN
        UPDATE public.trainers
        SET clients_count = clients_count + 1
        WHERE LOWER(full_name) = LOWER(TRIM(p_trainer_name));
    END IF;

    IF FOUND THEN
        RETURN jsonb_build_object(
            'success', true,
            'message', 'Personal Training assigned with ' || p_trainer_name || ' until ' || v_new_pt_expiry::TEXT
        );
    ELSE
        RETURN jsonb_build_object('success', false, 'message', 'Member not found');
    END IF;
END;
$$;

-- 14b. RPC Function: Admin Decline Membership Renewal Request
CREATE OR REPLACE FUNCTION admin_decline_renewal(
    p_member_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.members
    SET renewal_status = 'Active',
        requested_renewal_plan = NULL,
        updated_at = NOW()
    WHERE LOWER(member_id) = LOWER(TRIM(p_member_id));

    IF FOUND THEN
        RETURN jsonb_build_object('success', true, 'message', 'Renewal request declined.');
    ELSE
        RETURN jsonb_build_object('success', false, 'message', 'Member not found.');
    END IF;
END;
$$;

-- 14c. RPC Function: Admin Decline PT Request
CREATE OR REPLACE FUNCTION admin_decline_pt(
    p_member_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.members
    SET pt_status = 'None',
        requested_pt_plan = NULL,
        requested_pt_trainer = NULL,
        updated_at = NOW()
    WHERE LOWER(member_id) = LOWER(TRIM(p_member_id));

    IF FOUND THEN
        RETURN jsonb_build_object('success', true, 'message', 'Personal training request declined.');
    ELSE
        RETURN jsonb_build_object('success', false, 'message', 'Member not found.');
    END IF;
END;
$$;
-- 15. Create Membership Plans Table (Managed by Admin)
CREATE TABLE IF NOT EXISTS public.membership_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_name TEXT UNIQUE NOT NULL,             -- e.g. 'Admission Fee', 'Monthly', '3 Months', '6 Months', 'Yearly'
    duration_months INT DEFAULT 1,               -- Duration in months (0 for admission/registration fee)
    price NUMERIC NOT NULL,                      -- Plan fee in INR (e.g. 2000, 888, 3888, 4888, 8888)
    is_active BOOLEAN DEFAULT TRUE,              -- Visibility/active status
    display_order INT DEFAULT 1,                 -- Sorting order in UI
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Drop description column if table already exists
ALTER TABLE public.membership_plans DROP COLUMN IF EXISTS description;

-- 16. Create Personal Training (PT) Plans Table (Managed by Admin)
CREATE TABLE IF NOT EXISTS public.pt_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_name TEXT UNIQUE NOT NULL,             -- e.g. 'Monthly PT'
    duration_months INT DEFAULT 1,               -- Duration in months
    price NUMERIC NOT NULL,                      -- PT fee in INR (e.g. 3000)
    is_active BOOLEAN DEFAULT TRUE,
    display_order INT DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Drop description and sessions_info columns if table already exists
ALTER TABLE public.pt_plans DROP COLUMN IF EXISTS description;
ALTER TABLE public.pt_plans DROP COLUMN IF EXISTS sessions_info;

-- Enable RLS for Plans
ALTER TABLE public.membership_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pt_plans ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow all on membership_plans" ON public.membership_plans FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on pt_plans" ON public.pt_plans FOR ALL USING (true) WITH CHECK (true);

-- 17. Seed Initial Membership Plans & Pricing
INSERT INTO public.membership_plans (plan_name, duration_months, price, display_order)
VALUES
    ('Admission Fee', 0, 2000, 1),
    ('Monthly', 1, 888, 2),
    ('3 Months', 3, 3888, 3),
    ('6 Months', 6, 4888, 4),
    ('Yearly', 12, 8888, 5)
ON CONFLICT (plan_name) DO UPDATE SET
    price = EXCLUDED.price,
    duration_months = EXCLUDED.duration_months,
    display_order = EXCLUDED.display_order,
    updated_at = NOW();

-- 18. Seed Initial Personal Training (PT) Plans & Pricing
INSERT INTO public.pt_plans (plan_name, duration_months, price, display_order)
VALUES
    ('Monthly PT', 1, 3000, 1)
ON CONFLICT (plan_name) DO UPDATE SET
    price = EXCLUDED.price,
    duration_months = EXCLUDED.duration_months,
    display_order = EXCLUDED.display_order,
    updated_at = NOW();

-- 19. Admin Management Table (Stores Admin Name, Password & Metadata)
CREATE TABLE IF NOT EXISTS public.admin (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT UNIQUE NOT NULL DEFAULT 'ADMIN',
    password TEXT NOT NULL DEFAULT 'ADMIN123',
    full_name TEXT NOT NULL DEFAULT 'BAPI DAS',
    phone TEXT DEFAULT '+919876543210',
    email TEXT DEFAULT 'admin@ironblood.com',
    role TEXT DEFAULT 'GYM OWNER & FOUNDER',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.admin ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all on admin" ON public.admin FOR ALL USING (true) WITH CHECK (true);

INSERT INTO public.admin (username, password, full_name, phone, email, role)
VALUES ('ADMIN', 'ADMIN123', 'BAPI DAS', '+919876543210', 'admin@ironblood.com', 'GYM OWNER & FOUNDER')
ON CONFLICT (username) DO NOTHING;

-- 20. Studio Announcements & Notice Board Table
CREATE TABLE IF NOT EXISTS public.announcements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    target_audience TEXT NOT NULL DEFAULT 'ALL', -- 'ALL', 'MEMBERS', 'TRAINERS'
    duration_hours INT DEFAULT 36,               -- Notice Active Duration (default 36 Hours)
    expires_at TIMESTAMPTZ,                      -- Exact Expiration Timestamp
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all on announcements" ON public.announcements FOR ALL USING (true) WITH CHECK (true);

-- Seed initial welcome announcement
INSERT INTO public.announcements (title, message, target_audience, duration_hours, expires_at)
VALUES (
    'Welcome to IRONBLOOD Fitness Studio!',
    'Stay tuned here for official gym schedules, holiday notices, competition updates, and studio announcements.',
    'ALL',
    36,
    NOW() + INTERVAL '36 hours'
) ON CONFLICT DO NOTHING;

-- 21. Revenue Transactions & Official Payment Receipts Table
CREATE TABLE IF NOT EXISTS public.revenue_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.members(id) ON DELETE SET NULL,
    member_id TEXT NOT NULL,
    member_name TEXT NOT NULL,
    type TEXT NOT NULL,
    plan_name TEXT NOT NULL,
    amount NUMERIC(10,2) NOT NULL,
    base_amount NUMERIC(10,2) NOT NULL,
    discount_amount NUMERIC(10,2) DEFAULT 0.0,
    payment_mode TEXT DEFAULT 'UPI',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.revenue_transactions ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES public.members(id) ON DELETE SET NULL;

ALTER TABLE public.revenue_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all on revenue_transactions" ON public.revenue_transactions FOR ALL USING (true) WITH CHECK (true);
