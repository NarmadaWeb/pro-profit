# Supabase Setup Guide for Pro Profit

This document outlines the necessary steps to configure your Supabase project for the **Pro Profit** application, specifically focusing on its **Multi-Tenant Architecture** ensuring data isolation per tenant (coffee shop/UMKM).

## Prerequisites
1. Create an account at [Supabase](https://supabase.com/).
2. Create a new project. Keep the database password secure.
3. Once created, go to Project Settings -> API to find your `Project URL` and `anon public` API key.

## 1. Authentication Configuration
Pro Profit uses Supabase Auth.
* Ensure **Email/Password** login is enabled in your Supabase Auth settings (Authentication -> Providers).
* Disable "Confirm email" if you want users to log in immediately without verifying their email during development.
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

## 3. Database Triggers
To automate the creation of a user profile when a user registers, run the following SQL:

```sql
-- Function to automatically handle new user sign-ups
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.user_profiles (id, full_name, role)
  VALUES (new.id, new.raw_user_meta_data->>'full_name', 'owner');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function on sign-up
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
```
*(Note: A new tenant will need to be created and linked to the user_profile. You can manage this logic in your application code or via another trigger).*

## 4. Row Level Security (RLS) Policies

To enforce multi-tenancy, Row Level Security MUST be enabled on all tables. These policies ensure that a user can only read, insert, update, or delete rows where the `tenant_id` matches their profile's `tenant_id`.

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

-- Apply RLS Policies for user_profiles
CREATE POLICY "Users can view their own profile" ON public.user_profiles
    FOR SELECT USING (id = auth.uid());
CREATE POLICY "Users can update their own profile" ON public.user_profiles
    FOR UPDATE USING (id = auth.uid());

-- Apply RLS Policies for raw_materials
CREATE POLICY "Tenant Isolation - Select raw_materials" ON public.raw_materials
    FOR SELECT USING (tenant_id = get_user_tenant_id());
CREATE POLICY "Tenant Isolation - Insert raw_materials" ON public.raw_materials
    FOR INSERT WITH CHECK (tenant_id = get_user_tenant_id());
CREATE POLICY "Tenant Isolation - Update raw_materials" ON public.raw_materials
    FOR UPDATE USING (tenant_id = get_user_tenant_id());
CREATE POLICY "Tenant Isolation - Delete raw_materials" ON public.raw_materials
    FOR DELETE USING (tenant_id = get_user_tenant_id());

-- Apply RLS Policies for assets
CREATE POLICY "Tenant Isolation - Select assets" ON public.assets
    FOR SELECT USING (tenant_id = get_user_tenant_id());
CREATE POLICY "Tenant Isolation - Insert assets" ON public.assets
    FOR INSERT WITH CHECK (tenant_id = get_user_tenant_id());
CREATE POLICY "Tenant Isolation - Update assets" ON public.assets
    FOR UPDATE USING (tenant_id = get_user_tenant_id());
CREATE POLICY "Tenant Isolation - Delete assets" ON public.assets
    FOR DELETE USING (tenant_id = get_user_tenant_id());

-- Apply RLS Policies for overhead_costs
CREATE POLICY "Tenant Isolation - Select overhead_costs" ON public.overhead_costs
    FOR SELECT USING (tenant_id = get_user_tenant_id());
CREATE POLICY "Tenant Isolation - Insert overhead_costs" ON public.overhead_costs
    FOR INSERT WITH CHECK (tenant_id = get_user_tenant_id());
CREATE POLICY "Tenant Isolation - Update overhead_costs" ON public.overhead_costs
    FOR UPDATE USING (tenant_id = get_user_tenant_id());
CREATE POLICY "Tenant Isolation - Delete overhead_costs" ON public.overhead_costs
    FOR DELETE USING (tenant_id = get_user_tenant_id());

-- Apply RLS Policies for recipes
CREATE POLICY "Tenant Isolation - Select recipes" ON public.recipes
    FOR SELECT USING (tenant_id = get_user_tenant_id());
CREATE POLICY "Tenant Isolation - Insert recipes" ON public.recipes
    FOR INSERT WITH CHECK (tenant_id = get_user_tenant_id());
CREATE POLICY "Tenant Isolation - Update recipes" ON public.recipes
    FOR UPDATE USING (tenant_id = get_user_tenant_id());
CREATE POLICY "Tenant Isolation - Delete recipes" ON public.recipes
    FOR DELETE USING (tenant_id = get_user_tenant_id());

-- Apply RLS Policies for recipe_ingredients
-- Assuming users can only access recipe_ingredients if they have access to the parent recipe
CREATE POLICY "Tenant Isolation - Select recipe_ingredients" ON public.recipe_ingredients
    FOR SELECT USING (recipe_id IN (SELECT id FROM public.recipes WHERE tenant_id = get_user_tenant_id()));
CREATE POLICY "Tenant Isolation - Insert recipe_ingredients" ON public.recipe_ingredients
    FOR INSERT WITH CHECK (recipe_id IN (SELECT id FROM public.recipes WHERE tenant_id = get_user_tenant_id()));
CREATE POLICY "Tenant Isolation - Update recipe_ingredients" ON public.recipe_ingredients
    FOR UPDATE USING (recipe_id IN (SELECT id FROM public.recipes WHERE tenant_id = get_user_tenant_id()));
CREATE POLICY "Tenant Isolation - Delete recipe_ingredients" ON public.recipe_ingredients
    FOR DELETE USING (recipe_id IN (SELECT id FROM public.recipes WHERE tenant_id = get_user_tenant_id()));

-- Apply RLS Policies for sales_logs
CREATE POLICY "Tenant Isolation - Select sales_logs" ON public.sales_logs
    FOR SELECT USING (tenant_id = get_user_tenant_id());
CREATE POLICY "Tenant Isolation - Insert sales_logs" ON public.sales_logs
    FOR INSERT WITH CHECK (tenant_id = get_user_tenant_id());
CREATE POLICY "Tenant Isolation - Update sales_logs" ON public.sales_logs
    FOR UPDATE USING (tenant_id = get_user_tenant_id());
CREATE POLICY "Tenant Isolation - Delete sales_logs" ON public.sales_logs
    FOR DELETE USING (tenant_id = get_user_tenant_id());
```

## 5. Storage (Optional for Images)
If Pro Profit needs to store images (e.g., recipe photos or user avatars):
1. Go to the **Storage** section in your Supabase dashboard.
2. Create a new bucket, e.g., `app-images`.
3. Set the bucket to **Public** if the images should be accessible by anyone with the URL, or keep it private and use RLS.
4. Apply RLS policies for storage:

```sql
-- Allow users to upload files to app-images bucket
CREATE POLICY "Allow authenticated uploads" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'app-images');

-- Allow users to view files
CREATE POLICY "Allow public read" ON storage.objects
  FOR SELECT USING (bucket_id = 'app-images');
```

## 6. Flutter Integration
In your Flutter app, use `flutter_dotenv` to securely manage your Supabase keys instead of hardcoding them.

### Step 1: Install Dependencies
Run the following command to add the necessary packages:
```bash
flutter pub add supabase_flutter flutter_dotenv
```

### Step 2: Create a `.env` file
Create a file named `.env` in the root directory of your project and add your Supabase credentials:
```env
SUPABASE_URL=YOUR_SUPABASE_URL
SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

Make sure to add `.env` to your `.gitignore` to prevent committing sensitive keys to version control.

### Step 3: Add `.env` to assets
In your `pubspec.yaml`, add the `.env` file to the assets block:
```yaml
flutter:
  assets:
    - .env
```

### Step 4: Initialize Supabase
Update your `main.dart` to initialize dotenv and Supabase:
```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Initialize Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const ProProfitApp());
}

class ProProfitApp extends StatelessWidget {
  const ProProfitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pro Profit',
      home: Scaffold(
        appBar: AppBar(title: const Text('Pro Profit')),
        body: const Center(child: Text('Supabase Initialized Successfully!')),
      ),
    );
  }
}
```
