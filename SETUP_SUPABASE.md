# Panduan Setup Lengkap Supabase - Pro Profit

Dokumen ini berisi instruksi lengkap untuk membersihkan dan menyiapkan ulang database Supabase Anda agar fitur **Multi-Tenancy** berjalan dengan benar tanpa error Row Level Security (RLS).

---

## 1. Cleanup & Reset (Hapus Semua)

Jalankan script ini di **SQL Editor** Supabase untuk menghapus semua pengaturan lama yang mungkin menyebabkan konflik.

```sql
-- 1. Hapus Trigger & Fungsi
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.get_my_tenant_id() CASCADE;
DROP FUNCTION IF EXISTS public.get_user_tenant_id() CASCADE;

-- 2. Hapus Tabel
DROP TABLE IF EXISTS public.sales_logs;
DROP TABLE IF EXISTS public.recipe_ingredients;
DROP TABLE IF EXISTS public.recipes;
DROP TABLE IF EXISTS public.hpp_calculations;
DROP TABLE IF EXISTS public.utility_rates;
DROP TABLE IF EXISTS public.overhead_costs;
DROP TABLE IF EXISTS public.assets;
DROP TABLE IF EXISTS public.raw_materials;
DROP TABLE IF EXISTS public.user_profiles;
DROP TABLE IF EXISTS public.tenants;

-- 3. (Opsional) Hapus Ekstensi
-- DROP EXTENSION IF EXISTS "uuid-ossp";
```

---

## 2. Setup Database & Multi-Tenancy (Lengkap)

Jalankan script ini secara keseluruhan di **SQL Editor**. Script ini mencakup pembuatan tabel dan kebijakan keamanan (RLS) yang sudah diperbaiki agar Anda bisa membuat toko tanpa error.

```sql
-- ==========================================
-- 1. PERSIAPAN & TABEL
-- ==========================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE public.tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE SET NULL,
    full_name TEXT,
    photo_url TEXT,
    role TEXT DEFAULT 'owner',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.raw_materials (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    price_per_unit NUMERIC NOT NULL DEFAULT 0,
    current_stock NUMERIC DEFAULT 0,
    unit_measure TEXT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.assets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    purchase_price NUMERIC NOT NULL,
    economic_life_years INTEGER NOT NULL,
    purchase_date DATE NOT NULL,
    monthly_depreciation NUMERIC GENERATED ALWAYS AS (purchase_price / (economic_life_years * 12)) STORED
);

CREATE TABLE public.overhead_costs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    monthly_amount NUMERIC NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.recipes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'Umum',
    selling_price NUMERIC NOT NULL DEFAULT 0,
    target_margin_percent NUMERIC NOT NULL DEFAULT 0,
    calculated_hpp NUMERIC NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.recipe_ingredients (
    recipe_id UUID REFERENCES public.recipes(id) ON DELETE CASCADE,
    raw_material_id UUID REFERENCES public.raw_materials(id) ON DELETE CASCADE,
    quantity_used NUMERIC NOT NULL,
    PRIMARY KEY (recipe_id, raw_material_id)
);

CREATE TABLE public.sales_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    recipe_id UUID REFERENCES public.recipes(id) ON DELETE SET NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    subtotal NUMERIC NOT NULL DEFAULT 0,
    note TEXT DEFAULT 'Input Manual',
    sale_timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.utility_rates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    rate NUMERIC NOT NULL DEFAULT 0,
    unit TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.hpp_calculations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    product_name TEXT NOT NULL,
    batch_size NUMERIC NOT NULL DEFAULT 1,
    production_time_hours NUMERIC NOT NULL DEFAULT 0,
    raw_material_cost NUMERIC NOT NULL DEFAULT 0,
    labor_cost NUMERIC NOT NULL DEFAULT 0,
    overhead_cost NUMERIC NOT NULL DEFAULT 0,
    total_hpp NUMERIC NOT NULL DEFAULT 0,
    hpp_per_unit NUMERIC NOT NULL DEFAULT 0,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ==========================================
-- 2. FUNGSI & TRIGGER
-- ==========================================

-- Trigger saat user baru mendaftar
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.user_profiles (id, full_name)
  VALUES (new.id, new.raw_user_meta_data->>'full_name');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Fungsi Helper Tenant (PENTING untuk RLS)
CREATE OR REPLACE FUNCTION get_my_tenant_id()
RETURNS UUID AS $$
  SELECT tenant_id FROM public.user_profiles WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER;

-- ==========================================
-- 3. KEAMANAN (ROW LEVEL SECURITY)
-- ==========================================

-- Aktifkan RLS di semua tabel
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.raw_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.overhead_costs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recipe_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.utility_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hpp_calculations ENABLE ROW LEVEL SECURITY;

-- BERSIHKAN POLISI LAMA (Jika ada)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public')
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON ' || quote_ident(r.tablename);
    END LOOP;
END $$;

-- POLISI BARU (DIPERBAIKI)

-- 1. Tenants: Izinkan user buat toko & lihat daftar toko
CREATE POLICY "Tenants - Select" ON public.tenants FOR SELECT TO authenticated USING (true);
CREATE POLICY "Tenants - Insert" ON public.tenants FOR INSERT TO authenticated WITH CHECK (true);

-- 2. User Profiles: Izinkan user kelola profil sendiri
CREATE POLICY "Profiles - Select" ON public.user_profiles FOR SELECT TO authenticated USING (id = auth.uid());
CREATE POLICY "Profiles - Update" ON public.user_profiles FOR UPDATE TO authenticated USING (id = auth.uid());

-- 3. Isolasi Tenant (Isolasi data antar toko)
-- Tabel dengan kolom tenant_id
CREATE POLICY "RLS - Raw Materials" ON public.raw_materials FOR ALL TO authenticated USING (tenant_id = get_my_tenant_id());
CREATE POLICY "RLS - Assets" ON public.assets FOR ALL TO authenticated USING (tenant_id = get_my_tenant_id());
CREATE POLICY "RLS - Overhead" ON public.overhead_costs FOR ALL TO authenticated USING (tenant_id = get_my_tenant_id());
CREATE POLICY "RLS - Recipes" ON public.recipes FOR ALL TO authenticated USING (tenant_id = get_my_tenant_id());
CREATE POLICY "RLS - Sales Logs" ON public.sales_logs FOR ALL TO authenticated USING (tenant_id = get_my_tenant_id());
CREATE POLICY "RLS - Utility Rates" ON public.utility_rates FOR ALL TO authenticated USING (tenant_id = get_my_tenant_id());
CREATE POLICY "RLS - HPP Calculations" ON public.hpp_calculations FOR ALL TO authenticated USING (tenant_id = get_my_tenant_id());

-- 4. Recipe Ingredients (Isolasi berdasarkan resep milik tenant)
CREATE POLICY "RLS - Ingredients" ON public.recipe_ingredients FOR ALL TO authenticated USING (
    recipe_id IN (SELECT id FROM public.recipes WHERE tenant_id = get_my_tenant_id())
);
```

---

## 3. Setup Storage (Bucket: avatars)

1.  Buka menu **Storage**.
2.  Buat bucket baru: `avatars`.
3.  Set sebagai **Public**.
4.  Di tab **Policies** untuk bucket `avatars`:
    *   **Select**: Izinkan untuk semua (Public).
    *   **Insert/Update**: Izinkan hanya untuk user terautentikasi.

---

## 4. Tips Troubleshooting

*   **Error "New row violates RLS"**: Pastikan Anda sudah menjalankan script di Poin 2 secara lengkap, terutama bagian polisi `Tenants - Insert`.
*   **Daftar Toko Tidak Muncul**: Pastikan tabel `tenants` sudah memiliki polisi `Tenants - Select`.
*   **Gagal Login/Daftar**: Periksa file `.env` di root folder project Anda. Pastikan URL dan Key sudah benar.
