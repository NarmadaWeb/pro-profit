import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_logo.dart';

class UtilityRatesScreen extends StatefulWidget {
  const UtilityRatesScreen({super.key});

  @override
  State<UtilityRatesScreen> createState() => _UtilityRatesScreenState();
}

class _UtilityRatesScreenState extends State<UtilityRatesScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _tenantId;

  final Map<String, TextEditingController> _controllers = {
    'Listrik': TextEditingController(),
    'Air': TextEditingController(),
    'Wifi': TextEditingController(),
    'Sewa': TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _fetchRates();
  }

  Future<void> _fetchRates() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profileData = await _supabase
          .from('user_profiles')
          .select('tenant_id')
          .eq('id', user.id)
          .single();

      _tenantId = profileData['tenant_id'];
      if (_tenantId == null) return;

      final data = await _supabase
          .from('utility_rates')
          .select()
          .eq('tenant_id', _tenantId as Object);

      setState(() {
        for (var rate in data) {
          final name = rate['name'].toString();
          if (_controllers.containsKey(name)) {
            _controllers[name]!.text = rate['rate'].toString();
          }
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching rates: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveRates() async {
    setState(() => _isLoading = true);
    try {
      for (var entry in _controllers.entries) {
        final name = entry.key;
        final rate = double.tryParse(entry.value.text) ?? 0;

        // Check if exists
        final existing = await _supabase
            .from('utility_rates')
            .select()
            .eq('tenant_id', _tenantId as Object)
            .eq('name', name);

        if (existing.isEmpty) {
          await _supabase.from('utility_rates').insert({
            'tenant_id': _tenantId,
            'name': name,
            'rate': rate,
            'unit': name == 'Listrik' ? 'kWh' : 'Bulan',
          });
        } else {
          await _supabase.from('utility_rates').update({
            'rate': rate,
          }).eq('tenant_id', _tenantId as Object).eq('name', name);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tarif berhasil diperbarui!')),
        );
      }
    } catch (e) {
      debugPrint('Error saving rates: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: $e')),
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
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pengaturan Tarif Utilitas',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tarif ini digunakan sebagai dasar perhitungan biaya overhead pada kalkulator HPP.',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 32),
                      ..._controllers.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: TextFormField(
                            controller: entry.value,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Tarif ${entry.key}',
                              prefixText: 'Rp ',
                              suffixText: entry.key == 'Listrik' ? '/ kWh' : '/ Bulan',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saveRates,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Simpan Perubahan', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
