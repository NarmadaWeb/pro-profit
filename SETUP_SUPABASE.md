# Panduan Setup Supabase - Pro Profit

Dokumen ini berisi langkah-langkah untuk membersihkan dan menyiapkan ulang database Supabase Anda agar sesuai dengan arsitektur **Multi-Tenancy** aplikasi Pro Profit.

---

## 1. Cleanup & Reset (Hapus Semua)

Jika Anda ingin membersihkan database dari konfigurasi lama, jalankan script SQL berikut di **SQL Editor** Supabase Anda **SEBELUM** melakukan setup baru. Script ini akan menghapus semua tabel, fungsi, dan kebijakan yang ada.

```sql
-- ==========================================
-- HAPUS SEMUA (RESET)
-- ==========================================

-- 1. Hapus Trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- 2. Hapus Fungsi (Gunakan CASCADE untuk menghapus kebijakan yang bergantung padanya)
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.get_my_tenant_id() CASCADE;
DROP FUNCTION IF EXISTS public.get_user_tenant_id() CASCADE;

-- 3. Hapus Tabel (Urutan penting karena foreign key)
DROP TABLE IF EXISTS public.sales_logs;
DROP TABLE IF EXISTS public.recipe_ingredients;
DROP TABLE IF EXISTS public.recipes;
DROP TABLE IF EXISTS public.overhead_costs;
DROP TABLE IF EXISTS public.assets;
DROP TABLE IF EXISTS public.raw_materials;
DROP TABLE IF EXISTS public.user_profiles;
DROP TABLE IF EXISTS public.tenants;

-- 4. (Opsional) Hapus Ekstensi
-- DROP EXTENSION IF EXISTS "uuid-ossp";
```

---

## 2. Persiapan Proyek

1.  Buka [Supabase Dashboard](https://supabase.com/).
2.  Dapatkan **Project URL** dan **anon public key** dari menu **Settings -> API**.
3.  Pastikan provider **Email** aktif di menu **Authentication -> Providers**.

---

## 3. Setup Database Lengkap (SQL Editor)

Jalankan script SQL berikut untuk membangun seluruh struktur database yang diperlukan:

```sql
-- ==========================================
-- 1. PERSIAPAN AWAL
-- ==========================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ==========================================
-- 2. DEFINISI TABEL
-- ==========================================

-- Tabel: Tenants (Data Toko)
CREATE TABLE public.tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabel: User Profiles
CREATE TABLE public.user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE SET NULL,
    full_name TEXT,
    photo_url TEXT,
    role TEXT DEFAULT 'owner',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabel: Raw Materials (Bahan Baku)
CREATE TABLE public.raw_materials (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    price_per_unit NUMERIC NOT NULL DEFAULT 0,
    current_stock NUMERIC DEFAULT 0,
    max_stock NUMERIC DEFAULT 0,
    unit_measure TEXT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabel: Assets (Aset & Penyusutan)
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

-- Tabel: Overhead Costs (Biaya Operasional)
CREATE TABLE public.overhead_costs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    monthly_amount NUMERIC NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabel: Recipes (Menu)
CREATE TABLE public.recipes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'Umum',
    description TEXT,
    selling_price NUMERIC NOT NULL DEFAULT 0,
    target_margin_percent NUMERIC NOT NULL DEFAULT 0,
    calculated_hpp NUMERIC NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabel: Recipe Ingredients (Bahan Resep)
CREATE TABLE public.recipe_ingredients (
    recipe_id UUID REFERENCES public.recipes(id) ON DELETE CASCADE,
    raw_material_id UUID REFERENCES public.raw_materials(id) ON DELETE CASCADE,
    quantity_used NUMERIC NOT NULL,
    PRIMARY KEY (recipe_id, raw_material_id)
);

-- Tabel: Sales Log (Riwayat Penjualan)
CREATE TABLE public.sales_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    recipe_id UUID REFERENCES public.recipes(id) ON DELETE SET NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    subtotal NUMERIC NOT NULL DEFAULT 0,
    note TEXT,
    sale_timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ==========================================
-- 3. FUNGSI & TRIGGER
-- ==========================================

-- Auto-create profile on signup
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

-- Helper untuk mendapatkan tenant_id user aktif
CREATE OR REPLACE FUNCTION get_my_tenant_id()
RETURNS UUID AS $$
  SELECT tenant_id FROM public.user_profiles WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER;

-- ==========================================
-- 4. KEAMANAN (RLS POLICIES)
-- ==========================================

ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.raw_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.overhead_costs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recipe_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_logs ENABLE ROW LEVEL SECURITY;

-- Tenants
CREATE POLICY "View own tenant" ON public.tenants FOR SELECT USING (id = get_my_tenant_id());
CREATE POLICY "Allow create tenant" ON public.tenants FOR INSERT WITH CHECK (true);

-- User Profiles
CREATE POLICY "View own profile" ON public.user_profiles FOR SELECT USING (id = auth.uid());
CREATE POLICY "Update own profile" ON public.user_profiles FOR UPDATE USING (id = auth.uid());

-- Multi-Tenant Isolation (CRUD)
CREATE POLICY "Tenant Isolation - raw_materials" ON public.raw_materials FOR ALL USING (tenant_id = get_my_tenant_id()) WITH CHECK (tenant_id = get_my_tenant_id());
CREATE POLICY "Tenant Isolation - assets" ON public.assets FOR ALL USING (tenant_id = get_my_tenant_id()) WITH CHECK (tenant_id = get_my_tenant_id());
CREATE POLICY "Tenant Isolation - overhead_costs" ON public.overhead_costs FOR ALL USING (tenant_id = get_my_tenant_id()) WITH CHECK (tenant_id = get_my_tenant_id());
CREATE POLICY "Tenant Isolation - recipes" ON public.recipes FOR ALL USING (tenant_id = get_my_tenant_id()) WITH CHECK (tenant_id = get_my_tenant_id());
CREATE POLICY "Tenant Isolation - sales_logs" ON public.sales_logs FOR ALL USING (tenant_id = get_my_tenant_id()) WITH CHECK (tenant_id = get_my_tenant_id());

-- Recipe Ingredients (Nested isolation)
CREATE POLICY "Tenant Isolation - recipe_ingredients" ON public.recipe_ingredients
    FOR ALL USING (recipe_id IN (SELECT id FROM public.recipes WHERE tenant_id = get_my_tenant_id()));
```

---

## 4. Konfigurasi Flutter

1.  Perbarui file `.env`:
    ```env
    SUPABASE_URL=YOUR_PROJECT_URL
    SUPABASE_ANON_KEY=YOUR_ANON_KEY
    ```
2.  Pastikan `.env` terdaftar di `assets` pada `pubspec.yaml`.
3.  Aplikasi akan menangani pemilihan toko secara otomatis jika profil belum memiliki `tenant_id`.
