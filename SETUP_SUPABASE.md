# Supabase Setup Guide for Pro Profit

This document outlines the necessary steps to configure your Supabase project for the **Pro Profit** application, specifically focusing on its **Multi-Tenant Architecture** ensuring data isolation per tenant (coffee shop/UMKM).

## 1. Authentication Configuration
Pro Profit uses Supabase Auth.
* Ensure Email/Password login is enabled in your Supabase Auth settings.
* (Optional) Enable Google or Apple providers if social login is desired.

## 2. Database Schema (Multi-Tenant)
Execute the following SQL commands in your Supabase SQL Editor to create the necessary tables. Every primary table includes a `tenant_id` to separate data.

```sql
-- Create a table for tenants (Coffee Shops/UMKM)
CREATE TABLE public.tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Extend auth.users with a tenant reference
-- In a real production app, this might be a separate user_profiles table
CREATE TABLE public.user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
    full_name TEXT,
    role TEXT DEFAULT 'owner',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Table: Raw Materials (Bahan Baku)
CREATE TABLE public.raw_materials (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    price_per_unit NUMERIC NOT NULL,
    current_stock NUMERIC DEFAULT 0,
    max_stock NUMERIC DEFAULT 0,
    unit_measure TEXT NOT NULL, -- e.g., 'kg', 'L', 'pcs'
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Table: Assets (Aset & Penyusutan)
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

-- Table: Overhead Costs (Biaya Overhead)
CREATE TABLE public.overhead_costs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    monthly_amount NUMERIC NOT NULL
);

-- Table: Recipes/Menus (Resep Menu)
CREATE TABLE public.recipes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    description TEXT,
    selling_price NUMERIC NOT NULL,
    target_margin_percent NUMERIC NOT NULL DEFAULT 0,
    calculated_hpp NUMERIC DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Table: Recipe Ingredients (Bahan Resep)
CREATE TABLE public.recipe_ingredients (
    recipe_id UUID REFERENCES public.recipes(id) ON DELETE CASCADE,
    raw_material_id UUID REFERENCES public.raw_materials(id) ON DELETE CASCADE,
    quantity_used NUMERIC NOT NULL,
    PRIMARY KEY (recipe_id, raw_material_id)
);

-- Table: Sales Log (Log Penjualan)
CREATE TABLE public.sales_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    recipe_id UUID REFERENCES public.recipes(id) ON DELETE SET NULL,
    quantity INTEGER NOT NULL,
    subtotal NUMERIC NOT NULL,
    note TEXT,
    sale_timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

## 3. Row Level Security (RLS) Policies

To enforce multi-tenancy, Row Level Security MUST be enabled on all tables that contain a `tenant_id`. These policies ensure that a user can only read, insert, update, or delete rows where the `tenant_id` matches their profile's `tenant_id`.

```sql
-- Enable RLS on all tenant-specific tables
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.raw_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.overhead_costs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recipe_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_logs ENABLE ROW LEVEL SECURITY;

-- Create a helper function to get the current user's tenant_id
CREATE OR REPLACE FUNCTION get_user_tenant_id()
RETURNS UUID
LANGUAGE sql SECURITY DEFINER
AS $$
  SELECT tenant_id FROM public.user_profiles WHERE id = auth.uid();
$$;

-- Apply RLS Policies (Example for 'raw_materials' - repeat for others)
CREATE POLICY "Tenant Isolation - Select" ON public.raw_materials
    FOR SELECT USING (tenant_id = get_user_tenant_id());

CREATE POLICY "Tenant Isolation - Insert" ON public.raw_materials
    FOR INSERT WITH CHECK (tenant_id = get_user_tenant_id());

CREATE POLICY "Tenant Isolation - Update" ON public.raw_materials
    FOR UPDATE USING (tenant_id = get_user_tenant_id())
    WITH CHECK (tenant_id = get_user_tenant_id());

CREATE POLICY "Tenant Isolation - Delete" ON public.raw_materials
    FOR DELETE USING (tenant_id = get_user_tenant_id());

-- Apply similar policies to `assets`, `overhead_costs`, `recipes`, `sales_logs`
-- Note: recipe_ingredients can inherit security through recipe_id, but it's safer to add tenant_id to it as well or use complex joins for RLS.
```

## 4. Flutter Integration
In your Flutter app, initialize Supabase with your URL and Anon Key in `main.dart`.
Ensure you have added the `supabase_flutter` package to your `pubspec.yaml`.

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
  );

  runApp(const ProProfitApp());
}
```
