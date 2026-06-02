import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_logo.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _nameController = TextEditingController();
  final _photoUrlController = TextEditingController();
  bool _isLoading = true;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase
          .from('user_profiles')
          .select()
          .eq('id', user.id)
          .single();

      setState(() {
        _nameController.text = data['full_name'] ?? '';
        _photoUrl = data['photo_url']; // Assuming this field might exist or be added
        _photoUrlController.text = _photoUrl ?? '';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase.from('user_profiles').update({
        'full_name': _nameController.text.trim(),
        'photo_url': _photoUrlController.text.trim(),
      }).eq('id', user.id);

      setState(() {
        _photoUrl = _photoUrlController.text.trim();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil berhasil diperbarui!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memperbarui profil: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppLogo(),
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront),
            onPressed: () {
              Navigator.pushNamed(context, '/store-selection');
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth > 800) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: _buildBusinessInfoColumn(context),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 7,
                              child: _buildSettingsColumn(context),
                            ),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            _buildBusinessInfoColumn(context),
                            const SizedBox(height: 24),
                            _buildSettingsColumn(context),
                          ],
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBusinessInfoColumn(BuildContext context) {
    return Column(
      children: [
        _buildProfileCard(context),
        const SizedBox(height: 24),
        _buildEditProfileCard(context),
      ],
    );
  }

  Widget _buildProfileCard(BuildContext context) {
    final user = _supabase.auth.currentUser;
    final email = user?.email ?? 'Belum ada email';
    final fullName = _nameController.text.isEmpty ? 'Pemilik Bisnis' : _nameController.text;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
              image: _photoUrl != null && _photoUrl!.isNotEmpty
                  ? DecorationImage(image: NetworkImage(_photoUrl!), fit: BoxFit.cover)
                  : null,
            ),
            child: _photoUrl == null || _photoUrl!.isEmpty
                ? const Icon(Icons.store, size: 48)
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            fullName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Pemilik Bisnis',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          _buildInfoRow(context, Icons.location_on, 'Lokasi Utama', 'Indonesia'),
          const SizedBox(height: 16),
          _buildInfoRow(context, Icons.mail, 'Email Bisnis', email),
        ],
      ),
    );
  }

  Widget _buildEditProfileCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Edit Profil',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Nama Lengkap',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _photoUrlController,
            decoration: const InputDecoration(
              labelText: 'URL Foto Profil',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.image),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _updateProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Simpan Perubahan'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsColumn(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              try {
                await Supabase.instance.client.auth.signOut();
                // AuthWrapper will handle the navigation to LoginScreen
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Gagal keluar akun. Silakan coba lagi.')),
                  );
                }
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Keluar Akun'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              backgroundColor: Colors.white,
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fitur Hapus Akun akan segera hadir!')),
            );
          },
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Hapus Akun Bisnis', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

}
