# Panduan Setup Lengkap Supabase - Pro Profit

Dokumen ini menyediakan instruksi mendetail untuk mengonfigurasi backend Supabase, termasuk database, autentikasi, dan storage agar aplikasi Pro Profit dapat berjalan dengan lancar.

---

## 1. Cleanup & Reset (Hapus Semua)

Gunakan script ini di **SQL Editor** jika Anda ingin memulai dari awal atau membersihkan tabel yang error.

```sql
-- 1. Hapus Trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- 2. Hapus Fungsi (CASCADE menghapus kebijakan terkait)
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.get_my_tenant_id() CASCADE;
DROP FUNCTION IF EXISTS public.get_user_tenant_id() CASCADE;

-- 3. Hapus Tabel
DROP TABLE IF EXISTS public.sales_logs;
DROP TABLE IF EXISTS public.recipe_ingredients;
DROP TABLE IF EXISTS public.recipes;
DROP TABLE IF EXISTS public.overhead_costs;
DROP TABLE IF EXISTS public.assets;
DROP TABLE IF EXISTS public.raw_materials;
DROP TABLE IF EXISTS public.user_profiles;
DROP TABLE IF EXISTS public.tenants;
```

---

## 2. Setup Database & Multi-Tenancy

Jalankan script ini di **SQL Editor**. Perhatikan bagian **Policy** yang memungkinkan pengguna melihat daftar toko yang tersedia.

```sql
-- EKSTENSI
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- TABEL UTAMA
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
    sale_timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- FUNGSI & TRIGGER
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

CREATE OR REPLACE FUNCTION get_my_tenant_id()
RETURNS UUID AS $$
  SELECT tenant_id FROM public.user_profiles WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER;

-- ROW LEVEL SECURITY (RLS)
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.raw_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.overhead_costs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recipe_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_logs ENABLE ROW LEVEL SECURITY;

-- Polisi Spesifik: Agar user bisa melihat daftar toko saat memilih toko
CREATE POLICY "Allow view all tenants" ON public.tenants FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow create tenant" ON public.tenants FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "View own profile" ON public.user_profiles FOR SELECT USING (id = auth.uid());
CREATE POLICY "Update own profile" ON public.user_profiles FOR UPDATE USING (id = auth.uid());

-- Isolasi Tenant (Gunakan Helper Function)
CREATE POLICY "Tenant Isolation" ON public.raw_materials FOR ALL USING (tenant_id = get_my_tenant_id());
CREATE POLICY "Tenant Isolation" ON public.assets FOR ALL USING (tenant_id = get_my_tenant_id());
CREATE POLICY "Tenant Isolation" ON public.overhead_costs FOR ALL USING (tenant_id = get_my_tenant_id());
CREATE POLICY "Tenant Isolation" ON public.recipes FOR ALL USING (tenant_id = get_my_tenant_id());
CREATE POLICY "Tenant Isolation" ON public.sales_logs FOR ALL USING (tenant_id = get_my_tenant_id());
CREATE POLICY "Ingredient Isolation" ON public.recipe_ingredients FOR ALL USING (
    recipe_id IN (SELECT id FROM public.recipes WHERE tenant_id = get_my_tenant_id())
);
```

---

## 3. Setup Storage (Foto Profil)

1.  Buka menu **Storage** di dashboard Supabase.
2.  Klik **New Bucket**.
3.  Beri nama: `avatars`.
4.  Centang **Public bucket**.
5.  Klik **Save**.
6.  Buka tab **Policies** untuk bucket `avatars`.
7.  Tambahkan kebijakan (New Policy):
    *   **Select**: Pilih "Get Started quickly" -> "Give access to everyone".
    *   **Insert/Update**: Pilih "Give access to authenticated users" -> Pastikan kolom `owner` sesuai dengan `auth.uid()`.

---

## 4. Konfigurasi File `.env`

File `.env` harus berada di root folder project.

```env
SUPABASE_URL=https://xyz.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1Ni...
```

---

## 5. Troubleshooting (Masalah Umum)

*   **Aplikasi Stale/Hanya Loading**: Pastikan koneksi internet stabil dan kunci di `.env` sudah benar tanpa tanda kutip.
*   **Daftar Toko Kosong**: Jalankan script RLS di bagian `tenants` (Poin 2) agar `authenticated` user bisa melihat daftar toko.
*   **Error "Permission Denied"**: Pastikan Anda sudah menjalankan `ENABLE ROW LEVEL SECURITY` pada setiap tabel.
*   **Gagal Upload Foto**: Pastikan bucket `avatars` sudah dibuat dan diset sebagai **Public**.
