import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_logo.dart';

class HppCalculatorScreen extends StatefulWidget {
  const HppCalculatorScreen({super.key});

  @override
  State<HppCalculatorScreen> createState() => _HppCalculatorScreenState();
}

class _HppCalculatorScreenState extends State<HppCalculatorScreen> {
  final List<Map<String, dynamic>> _rawMaterials = [];

  double _cupLidCost = 0.0;
  double _strawCarrierCost = 0.0;

  double _electricityCost = 0.0;
  double _rentCost = 0.0;
  double _salaryCost = 0.0;
  double _monthlyTarget = 1.0;

  double _hppPerUnit = 0;
  double _subtotal = 0;
  double _safetyMargin = 0;
  double _marginPercentage = 30.0;
  double _recommendedPrice = 0;

  String? _tenantId;
  bool _isLoading = true;
  final _recipeNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final profileData = await Supabase.instance.client
          .from('user_profiles')
          .select('tenant_id')
          .eq('id', user.id)
          .single();

      _tenantId = profileData['tenant_id'];
      if (_tenantId == null) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/store-selection');
        }
        return;
      }

      // Fetch existing materials and overhead if any
      final materialsData = await Supabase.instance.client
          .from('raw_materials')
          .select()
          .eq('tenant_id', _tenantId as Object);

      final overheadData = await Supabase.instance.client
          .from('overhead_costs')
          .select()
          .eq('tenant_id', _tenantId as Object);

      setState(() {
        if (materialsData.isNotEmpty) {
          _rawMaterials.clear();
          for (var m in materialsData) {
            _rawMaterials.add({
              'id': m['id'],
              'name': m['name'],
              'price': (m['price_per_unit'] as num).toDouble(),
              'qty': 1.0, // default qty for calculation
            });
          }
        } else {
          _rawMaterials.add({'name': 'Biji Kopi Arabika', 'price': 150000.0, 'qty': 1.0});
        }

        if (overheadData.isNotEmpty) {
          for (var o in overheadData) {
            if (o['name'].toString().toLowerCase().contains('listrik')) {
              _electricityCost = (o['monthly_amount'] as num).toDouble();
            } else if (o['name'].toString().toLowerCase().contains('sewa')) {
              _rentCost = (o['monthly_amount'] as num).toDouble();
            } else if (o['name'].toString().toLowerCase().contains('gaji')) {
              _salaryCost = (o['monthly_amount'] as num).toDouble();
            }
          }
        } else {
          _electricityCost = 500000.0;
          _rentCost = 2000000.0;
          _salaryCost = 3000000.0;
        }

        _isLoading = false;
        _calculateHPP();
      });
    } catch (e) {
      debugPrint('Error fetching HPP data: $e');
      setState(() => _isLoading = false);
    }
  }

  void _calculateHPP() {
    double rawTotal = 0;
    for (var material in _rawMaterials) {
      rawTotal += (material['price'] as double) * (material['qty'] as double);
    }

    double totalPack = _cupLidCost + _strawCarrierCost;
    double overheadPerUnit = (_electricityCost + _rentCost + _salaryCost) / (_monthlyTarget > 0 ? _monthlyTarget : 1);

    _subtotal = rawTotal + totalPack + overheadPerUnit;
    _safetyMargin = _subtotal * 0.05;
    _hppPerUnit = _subtotal + _safetyMargin;

    _updateMarginSimulation();
    setState(() {});
  }

  void _updateMarginSimulation() {
    if (_marginPercentage >= 100) _marginPercentage = 99.0;
    _recommendedPrice = _hppPerUnit / (1 - (_marginPercentage / 100));
  }

  Future<void> _saveAsMenu() async {
    if (_tenantId == null) return;
    if (_recipeNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan nama menu terlebih dahulu')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 1. Insert into recipes
      await Supabase.instance.client.from('recipes').insert({
        'tenant_id': _tenantId,
        'name': _recipeNameController.text.trim(),
        'category': 'Coffee', // default
        'selling_price': _recommendedPrice,
        'target_margin_percent': _marginPercentage,
        'calculated_hpp': _hppPerUnit,
      }).select().single();

      // 2. Optional: Save materials as raw_materials if they don't have ID
      // For simplicity, we just save the recipe for now.

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Menu berhasil disimpan!')),
        );
        _recipeNameController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan menu: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _addRawMaterial() {
    setState(() {
      _rawMaterials.add({'name': '', 'price': 0.0, 'qty': 1.0});
    });
    _calculateHPP();
  }

  void _removeRawMaterial(int index) {
    setState(() {
      _rawMaterials.removeAt(index);
    });
    _calculateHPP();
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kalkulator HPP',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    'Metode: Full Costing',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 800) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildInputsSection(context),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 1,
                        child: _buildSummarySection(context),
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      _buildInputsSection(context),
                      const SizedBox(height: 24),
                      _buildSummarySection(context),
                    ],
                  );
                }
              },
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputsSection(BuildContext context) {
    return Column(
      children: [
        _buildSectionCard(
          context,
          title: 'Bahan Baku',
          icon: Icons.inventory_2,
          action: TextButton.icon(
            onPressed: _addRawMaterial,
            icon: const Icon(Icons.add_circle, size: 16),
            label: const Text('Tambah Bahan'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.secondary,
              textStyle: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          child: Column(
            children: [
              ..._rawMaterials.asMap().entries.map((entry) {
                int idx = entry.key;
                Map<String, dynamic> material = entry.value;
                double subtotal = material['price'] * material['qty'];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          initialValue: material['name'],
                          decoration: const InputDecoration(labelText: 'Nama Bahan', isDense: true),
                          onChanged: (val) => material['name'] = val,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          initialValue: material['price'].toString(),
                          decoration: const InputDecoration(labelText: 'Harga', isDense: true),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            material['price'] = double.tryParse(val) ?? 0;
                            _calculateHPP();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          initialValue: material['qty'].toString(),
                          decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            material['qty'] = double.tryParse(val) ?? 0;
                            _calculateHPP();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Rp ${subtotal.toStringAsFixed(0)}',
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                        onPressed: () => _removeRawMaterial(idx),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          context,
          title: 'Biaya Kemasan',
          icon: Icons.unarchive,
          child: Row(
            children: [
              Expanded(
                child: _buildInputField(
                  context,
                  label: 'Cup & Lid',
                  initialValue: _cupLidCost.toString(),
                  onChanged: (val) {
                    _cupLidCost = double.tryParse(val) ?? 0;
                    _calculateHPP();
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildInputField(
                  context,
                  label: 'Sedotan & Carrier',
                  initialValue: _strawCarrierCost.toString(),
                  onChanged: (val) {
                    _strawCarrierCost = double.tryParse(val) ?? 0;
                    _calculateHPP();
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          context,
          title: 'Overhead & Penyusutan',
          icon: Icons.account_balance_wallet,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      context,
                      label: 'Listrik/Bulan',
                      initialValue: _electricityCost.toString(),
                      onChanged: (val) {
                        _electricityCost = double.tryParse(val) ?? 0;
                        _calculateHPP();
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInputField(
                      context,
                      label: 'Sewa/Bulan',
                      initialValue: _rentCost.toString(),
                      onChanged: (val) {
                        _rentCost = double.tryParse(val) ?? 0;
                        _calculateHPP();
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInputField(
                      context,
                      label: 'Gaji/Bulan',
                      initialValue: _salaryCost.toString(),
                      onChanged: (val) {
                        _salaryCost = double.tryParse(val) ?? 0;
                        _calculateHPP();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Target Produksi',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                        ),
                        Text(
                          'Estimasi unit terjual per bulan',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                    SizedBox(
                      width: 100,
                      child: TextFormField(
                        initialValue: _monthlyTarget.toString(),
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (val) {
                          _monthlyTarget = double.tryParse(val) ?? 1;
                          _calculateHPP();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard(BuildContext context, {required String title, required IconData icon, Widget? action, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _buildInputField(BuildContext context, {required String label, required String initialValue, required Function(String) onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 1.0,
              ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: initialValue,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            prefixText: 'Rp ',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildSummarySection(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).colorScheme.primary),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ESTIMASI HPP PER UNIT',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      letterSpacing: 2.0,
                    ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rp',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _hppPerUnit.toStringAsFixed(0),
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimary,
                            height: 1.0,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Divider(color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.2)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Subtotal Biaya',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                  Text(
                    'Rp ${_subtotal.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Safety Margin (5%)',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                  Text(
                    'Rp ${_safetyMargin.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF6BD8CB), // secondary-fixed-dim
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _calculateHPP,
                  icon: const Icon(Icons.calculate),
                  label: const Text('Hitung HPP'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Theme.of(context).colorScheme.primaryContainer,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'SIMPAN SEBAGAI MENU',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      letterSpacing: 2.0,
                    ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _recipeNameController,
                decoration: InputDecoration(
                  hintText: 'Nama Menu (contoh: Kopi Susu Gula Aren)',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saveAsMenu,
                  icon: const Icon(Icons.save),
                  label: const Text('Simpan Ke Menu'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.trending_up, color: Theme.of(context).colorScheme.onSecondaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Simulasi Margin',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Berapa laba yang ingin Anda ambil?',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Margin Laba',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        Text(
                          '${_marginPercentage.toStringAsFixed(0)}%',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _marginPercentage,
                      min: 5,
                      max: 80,
                      activeColor: Theme.of(context).colorScheme.secondary,
                      onChanged: (val) {
                        setState(() {
                          _marginPercentage = val;
                          _updateMarginSimulation();
                        });
                      },
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rekomendasi Harga Jual:',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Rp ${_recommendedPrice.toStringAsFixed(0)}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.secondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
