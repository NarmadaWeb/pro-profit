import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../widgets/app_logo.dart';

class HppCalculatorScreen extends StatefulWidget {
  const HppCalculatorScreen({super.key});

  @override
  State<HppCalculatorScreen> createState() => _HppCalculatorScreenState();
}

class _HppCalculatorScreenState extends State<HppCalculatorScreen> {
  bool _isCalculating = false;
  bool _isLoading = true;
  String? _tenantId;
  int _currentStep = 0;

  // Calculation State
  final _recipeNameController = TextEditingController();
  final _batchSizeController = TextEditingController(text: '1');
  final _productionTimeController = TextEditingController(text: '1');

  double _batchSize = 1.0;
  double _productionTimeHours = 1.0;

  final List<Map<String, dynamic>> _rawMaterials = [];
  final List<Map<String, dynamic>> _laborDetails = [];
  final List<Map<String, dynamic>> _equipmentDetails = [];

  double _electricityRate = 1500.0;
  double _waterRate = 0.0;
  double _wifiRate = 0.0;
  double _rentRate = 0.0;

  double _hppPerUnit = 0;
  double _totalHpp = 0;
  double _safetyMargin = 0;
  double _subtotalHpp = 0;
  double _marginPercentage = 30.0;
  double _recommendedPrice = 0;

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

      final ratesData = await Supabase.instance.client
          .from('utility_rates')
          .select()
          .eq('tenant_id', _tenantId as Object);

      setState(() {
        for (var rate in ratesData) {
          switch (rate['name'].toString().toLowerCase()) {
            case 'listrik':
              _electricityRate = (rate['rate'] as num).toDouble();
              break;
            case 'air':
              _waterRate = (rate['rate'] as num).toDouble();
              break;
            case 'wifi':
              _wifiRate = (rate['rate'] as num).toDouble();
              break;
            case 'sewa':
              _rentRate = (rate['rate'] as num).toDouble();
              break;
          }
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching HPP data: $e');
      setState(() => _isLoading = false);
    }
  }

  void _resetCalculator() {
    setState(() {
      _isCalculating = true;
      _currentStep = 0;
      _recipeNameController.clear();
      _batchSizeController.text = '1';
      _productionTimeController.text = '1';
      _batchSize = 1.0;
      _productionTimeHours = 1.0;
      _rawMaterials.clear();
      _laborDetails.clear();
      _equipmentDetails.clear();
      _hppPerUnit = 0;
      _totalHpp = 0;
      _subtotalHpp = 0;
      _safetyMargin = 0;
      _marginPercentage = 30.0;
      _recommendedPrice = 0;
    });
  }

  void _showInitialPurchaseModal() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final qtyController = TextEditingController();
    final noteController = TextEditingController();
    String selectedUnit = 'gram';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Input Bahan Baru', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTextField(
                      label: 'Nama Bahan',
                      hint: 'Biji Kopi',
                      controller: nameController,
                      icon: Icons.inventory_2,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: 'Harga Beli (Awal)',
                      hint: '100000',
                      controller: priceController,
                      icon: Icons.payments,
                      prefixText: 'Rp ',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            label: 'Jumlah Beli',
                            hint: '1',
                            controller: qtyController,
                            icon: Icons.shopping_cart,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Satuan', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: selectedUnit,
                                isDense: true,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                items: ['Kg', 'ml', 'gram', 'pcs', 'ons', 'L']
                                    .map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 12))))
                                    .toList(),
                                onChanged: (val) => setModalState(() => selectedUnit = val!),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: 'Keterangan Tambahan',
                      hint: 'Beli di Toko Maju',
                      controller: noteController,
                      icon: Icons.note,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
                ElevatedButton(
                  onPressed: () {
                    if (nameController.text.isEmpty) return;
                    setState(() {
                      _rawMaterials.add({
                        'name': nameController.text,
                        'purchase_price': double.tryParse(priceController.text) ?? 0.0,
                        'purchase_qty': double.tryParse(qtyController.text) ?? 1.0,
                        'purchase_unit': selectedUnit,
                        'purchase_note': noteController.text,
                        'usage_qty': 0.0,
                        'usage_unit': selectedUnit,
                        'usage_note': '',
                        'subtotal': 0.0,
                      });
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Tambah'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _addRawMaterial() {
    _showInitialPurchaseModal();
  }

  void _removeRawMaterial(int index) {
    setState(() {
      _rawMaterials.removeAt(index);
    });
  }

  void _calculateMaterialSubtotal(Map<String, dynamic> material) {
    double purchasePrice = material['purchase_price'] ?? 0.0;
    double purchaseQty = material['purchase_qty'] ?? 1.0;
    String purchaseUnit = material['purchase_unit'] ?? 'gram';
    double usageQty = material['usage_qty'] ?? 0.0;
    String usageUnit = material['usage_unit'] ?? 'gram';

    // Base everything to 'gram' or 'ml' or 'pcs'
    double normalizedPurchaseQty = _normalizeQty(purchaseQty, purchaseUnit);
    double normalizedUsageQty = _normalizeQty(usageQty, usageUnit);

    if (normalizedPurchaseQty > 0) {
      material['subtotal'] = (normalizedUsageQty / normalizedPurchaseQty) * purchasePrice;
    } else {
      material['subtotal'] = 0.0;
    }
  }

  double _normalizeQty(double qty, String unit) {
    switch (unit.toLowerCase()) {
      case 'kg':
      case 'l':
        return qty * 1000;
      case 'ons':
        return qty * 100;
      default:
        return qty;
    }
  }

  Future<void> _generatePdfReport() async {
    final pdf = pw.Document();
    final String productName = _recipeNameController.text.isEmpty ? "Produk Tanpa Nama" : _recipeNameController.text;
    final String dateStr = DateFormat('dd MMMM yyyy').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Laporan Kalkulasi HPP', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Text(dateStr),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Informasi Produk', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Nama Produk:'),
                pw.Text(productName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Jumlah Produksi:'),
                pw.Text('${_batchSize.toStringAsFixed(0)} pcs'),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Waktu Produksi:'),
                pw.Text('${_productionTimeHours.toStringAsFixed(1)} jam'),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Text('Rincian Biaya Bahan Baku', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.TableHelper.fromTextArray(
              headers: ['Nama Bahan', 'Pemakaian', 'Subtotal'],
              data: _rawMaterials.map((m) => [
                m['name'],
                '${m['usage_qty']} ${m['usage_unit']}',
                'Rp ${((m['subtotal'] ?? 0) as double).toStringAsFixed(0)}'
              ]).toList(),
            ),
            pw.SizedBox(height: 10),
            pw.Text('Rincian Biaya Tenaga Kerja', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.TableHelper.fromTextArray(
              headers: ['Posisi', 'Orang', 'Upah/Jam', 'Subtotal'],
              data: _laborDetails.map((l) => [
                l['name'],
                '${l['count']}',
                'Rp ${l['wage_per_hour']}',
                'Rp ${((l['subtotal'] ?? 0) as double).toStringAsFixed(0)}'
              ]).toList(),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Ringkasan HPP', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Subtotal HPP (Bahan + Tenaga Kerja + Overhead):'),
                pw.Text('Rp ${_subtotalHpp.toStringAsFixed(0)}'),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Safety Margin (5%):'),
                pw.Text('Rp ${_safetyMargin.toStringAsFixed(0)}'),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('TOTAL HPP (1 BATCH):', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text('Rp ${_totalHpp.toStringAsFixed(0)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.Divider(),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              color: PdfColors.grey200,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('HPP PER UNIT:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Rp ${_hppPerUnit.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Simulasi Harga Jual', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Margin Keuntungan:'),
                pw.Text('${_marginPercentage.toStringAsFixed(0)}%'),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Rekomendasi Harga Jual:', style: const pw.TextStyle(color: PdfColors.green)),
                pw.Text('Rp ${_recommendedPrice.toStringAsFixed(0)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.green)),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Laporan_HPP_${productName.replaceAll(' ', '_')}.pdf',
    );
  }

  void _addLabor() {
    setState(() {
      _laborDetails.add({
        'name': 'Pekerja ${_laborDetails.length + 1}',
        'wage_per_hour': 15000.0,
        'count': 1,
        'subtotal': 15000.0 * _productionTimeHours,
      });
    });
  }

  void _removeLabor(int index) {
    setState(() {
      _laborDetails.removeAt(index);
    });
  }

  void _addEquipment() {
    setState(() {
      _equipmentDetails.add({
        'name': 'Alat ${_equipmentDetails.length + 1}',
        'power_watts': 500.0,
        'usage_hours': _productionTimeHours,
        'subtotal': (500.0 / 1000.0) * _productionTimeHours * _electricityRate,
      });
    });
  }

  void _removeEquipment(int index) {
    setState(() {
      _equipmentDetails.removeAt(index);
    });
  }

  void _calculateFullCosting() {
    double materialTotal = 0;
    for (var m in _rawMaterials) {
      materialTotal += m['subtotal'] ?? 0;
    }

    double laborTotal = 0;
    for (var l in _laborDetails) {
      laborTotal += l['subtotal'] ?? 0;
    }

    double equipmentTotal = 0;
    for (var eq in _equipmentDetails) {
      equipmentTotal += eq['subtotal'] ?? 0;
    }

    double allocatedRent = (_rentRate / 720) * _productionTimeHours;
    double allocatedWater = (_waterRate / 720) * _productionTimeHours;
    double allocatedWifi = (_wifiRate / 720) * _productionTimeHours;

    double overheadTotal = equipmentTotal + allocatedRent + allocatedWater + allocatedWifi;

    _subtotalHpp = materialTotal + laborTotal + overheadTotal;
    _safetyMargin = _subtotalHpp * 0.05;
    _totalHpp = _subtotalHpp + _safetyMargin;

    _hppPerUnit = _totalHpp / (_batchSize > 0 ? _batchSize : 1);

    _updateMarginSimulation();
  }

  void _updateMarginSimulation() {
    if (_marginPercentage >= 100) _marginPercentage = 99.0;
    _recommendedPrice = _hppPerUnit / (1 - (_marginPercentage / 100));
  }

  Future<void> _saveCalculation() async {
    if (_tenantId == null) return;

    setState(() => _isLoading = true);

    try {
      double matTotal = 0;
      for (var m in _rawMaterials) {
        matTotal += m['subtotal'] ?? 0;
      }
      double laborTotal = 0;
      for (var l in _laborDetails) {
        laborTotal += l['subtotal'] ?? 0;
      }
      double overheadTotal = _subtotalHpp - matTotal - laborTotal;

      final details = {
        'raw_materials': _rawMaterials,
        'labor': _laborDetails,
        'equipment': _equipmentDetails,
        'utility_rates': {
          'electricity': _electricityRate,
          'water': _waterRate,
          'wifi': _wifiRate,
          'rent': _rentRate,
        },
        'safety_margin': _safetyMargin,
        'subtotal_hpp': _subtotalHpp,
      };

      await Supabase.instance.client.from('hpp_calculations').insert({
        'tenant_id': _tenantId,
        'product_name': _recipeNameController.text.trim().isEmpty ? 'Produk Tanpa Nama' : _recipeNameController.text.trim(),
        'batch_size': _batchSize,
        'production_time_hours': _productionTimeHours,
        'raw_material_cost': matTotal,
        'labor_cost': laborTotal,
        'overhead_cost': overheadTotal + _safetyMargin, // overhead + buffer
        'total_hpp': _totalHpp,
        'hpp_per_unit': _hppPerUnit,
        'details': details,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Riwayat perhitungan berhasil disimpan!')),
        );
        setState(() {
          _isCalculating = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan riwayat: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const AppLogo(),
        leading: _isCalculating
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _isCalculating = false),
            )
          : null,
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
      body: _isCalculating ? _buildCalculator(context) : _buildDashboard(context),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
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
              Text(
                'Tentukan harga jual produk Anda dengan akurat menggunakan metode Full Costing.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 32),

              InkWell(
                onTap: _resetCalculator,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.secondary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.calculate, size: 64, color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        'Mulai Hitung HPP Baru',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Langkah demi langkah menghitung biaya produksi',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              Text(
                'Menu Utama',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),

              _buildMenuGrid(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuGrid(BuildContext context) {
    final List<Map<String, dynamic>> menus = [
      {'title': 'Riwayat Perhitungan', 'icon': Icons.history, 'color': Colors.blue, 'route': '/history'},
      {'title': 'Daftar Bahan Baku', 'icon': Icons.inventory_2, 'color': Colors.orange, 'route': '/raw-materials'},
      {'title': 'Tarif Listrik', 'icon': Icons.electric_bolt, 'color': Colors.yellow.shade800, 'route': '/utility-rates'},
      {'title': 'Tarif Sewa', 'icon': Icons.home, 'color': Colors.purple, 'route': '/utility-rates'},
      {'title': 'Tarif Air', 'icon': Icons.water_drop, 'color': Colors.cyan, 'route': '/utility-rates'},
      {'title': 'Tarif Wifi', 'icon': Icons.wifi, 'color': Colors.green, 'route': '/utility-rates'},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.5,
      ),
      itemCount: menus.length,
      itemBuilder: (context, index) {
        final menu = menus[index];
        return InkWell(
          onTap: () {
            if (menu['route'] != null) {
              Navigator.pushNamed(context, menu['route']);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Fitur ${menu['title']} akan segera hadir!')),
              );
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(menu['icon'], color: menu['color'], size: 32),
                const SizedBox(height: 8),
                Text(
                  menu['title'],
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCalculator(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(5, (index) {
              bool isCompleted = index < _currentStep;
              bool isActive = index == _currentStep;
              return Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isActive
                    ? Theme.of(context).colorScheme.primary
                    : isCompleted
                      ? Theme.of(context).colorScheme.secondary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isCompleted
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isActive || isCompleted ? Colors.white : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                ),
              );
            }),
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: _buildStepContent(),
              ),
            ),
          ),
        ),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (_currentStep > 0)
                TextButton(
                  onPressed: () => setState(() => _currentStep--),
                  child: const Text('Kembali'),
                )
              else
                const SizedBox.shrink(),

              ElevatedButton(
                onPressed: () {
                  if (_currentStep < 4) {
                    setState(() {
                      _calculateFullCosting();
                      _currentStep++;
                    });
                  } else {
                    _saveCalculation();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                child: Text(_currentStep < 4 ? 'Lanjut' : 'Simpan Perhitungan'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildProductDataStep();
      case 1:
        return _buildRawMaterialsStep();
      case 2:
        return _buildLaborStep();
      case 3:
        return _buildOverheadStep();
      case 4:
        return _buildSimulationStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildProductDataStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Data Produk',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Informasi dasar mengenai produk yang akan diproduksi.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),

        _buildTextField(
          label: 'Nama Produk',
          hint: 'Contoh: Americano, Kopi Susu Gula Aren',
          controller: _recipeNameController,
          icon: Icons.inventory_2,
        ),
      ],
    );
  }

  Widget _buildRawMaterialsStep() {
    double totalMaterials = 0;
    for (var m in _rawMaterials) {
      totalMaterials += m['subtotal'] ?? 0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Biaya Bahan Baku',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Daftar semua bahan yang digunakan per batch.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: _addRawMaterial,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Tambah'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        if (_rawMaterials.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40.0),
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('Belum ada bahan baku ditambahkan.'),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _rawMaterials.length,
            itemBuilder: (context, index) {
              final material = _rawMaterials[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              material['name'] ?? '',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _removeRawMaterial(index),
                            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                          ),
                        ],
                      ),
                      const Divider(),
                      const Text(
                        'Informasi Pembelian:',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Harga: Rp ${material['purchase_price']} / ${material['purchase_qty']} ${material['purchase_unit']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (material['purchase_note']?.isNotEmpty == true)
                        Text('Note: ${material['purchase_note']}', style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 12),
                      const Text(
                        'Pemakaian Bahan:',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSmallTextField(
                              label: 'Jumlah Pakai',
                              hint: '10',
                              initialValue: material['usage_qty'].toString(),
                              keyboardType: TextInputType.number,
                              onChanged: (val) {
                                setState(() {
                                  material['usage_qty'] = double.tryParse(val) ?? 0;
                                  _calculateMaterialSubtotal(material);
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Satuan', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                DropdownButtonFormField<String>(
                                  initialValue: material['usage_unit'],
                                  isDense: true,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  items: ['Kg', 'ml', 'gram', 'pcs', 'ons', 'L']
                                      .map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 10))))
                                      .toList(),
                                  onChanged: (val) {
                                    setState(() {
                                      material['usage_unit'] = val!;
                                      _calculateMaterialSubtotal(material);
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSmallTextField(
                              label: 'Keterangan',
                              hint: 'Opsional',
                              initialValue: material['usage_note'],
                              onChanged: (val) => material['usage_note'] = val,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Biaya Pemakaian', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                            Text(
                              'Rp ${(material['subtotal'] ?? 0).toStringAsFixed(0)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

        const Divider(height: 40),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Biaya Bahan Baku:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                'Rp ${totalMaterials.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLaborStep() {
    double totalLabor = 0;
    for (var l in _laborDetails) {
      totalLabor += l['subtotal'] ?? 0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Biaya Tenaga Kerja',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hitung biaya upah pekerja per batch.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: _addLabor,
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('Tambah'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        if (_laborDetails.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40.0),
              child: Column(
                children: [
                  Icon(Icons.people_outline, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('Belum ada tenaga kerja ditambahkan.'),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _laborDetails.length,
            itemBuilder: (context, index) {
              final labor = _laborDetails[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildSmallTextField(
                              label: 'Posisi/Nama',
                              hint: 'Barista',
                              initialValue: labor['name'],
                              onChanged: (val) => labor['name'] = val,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _removeLabor(index),
                            icon: const Icon(Icons.delete, color: Colors.red),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSmallTextField(
                              label: 'Upah / Jam',
                              hint: '15000',
                              initialValue: labor['wage_per_hour'].toString(),
                              keyboardType: TextInputType.number,
                              prefix: 'Rp',
                              onChanged: (val) {
                                setState(() {
                                  labor['wage_per_hour'] = double.tryParse(val) ?? 0;
                                  labor['subtotal'] = labor['wage_per_hour'] * labor['count'] * _productionTimeHours;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSmallTextField(
                              label: 'Jumlah Orang',
                              hint: '1',
                              initialValue: labor['count'].toString(),
                              keyboardType: TextInputType.number,
                              onChanged: (val) {
                                setState(() {
                                  labor['count'] = int.tryParse(val) ?? 1;
                                  labor['subtotal'] = labor['wage_per_hour'] * labor['count'] * _productionTimeHours;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('Subtotal', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                Text(
                                  'Rp ${(labor['subtotal'] ?? 0).toStringAsFixed(0)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

        const Divider(height: 40),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Biaya Tenaga Kerja:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                'Rp ${totalLabor.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverheadStep() {
    double totalEquipment = 0;
    for (var eq in _equipmentDetails) {
      totalEquipment += eq['subtotal'] ?? 0;
    }

    double allocatedRent = (_rentRate / 720) * _productionTimeHours;
    double allocatedWater = (_waterRate / 720) * _productionTimeHours;
    double allocatedWifi = (_wifiRate / 720) * _productionTimeHours;

    double totalOverhead = totalEquipment + allocatedRent + allocatedWater + allocatedWifi;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Konfigurasi Produksi',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                label: 'Jumlah Produksi',
                hint: '50',
                controller: _batchSizeController,
                icon: Icons.shopping_basket,
                suffix: 'pcs',
                keyboardType: TextInputType.number,
                onChanged: (val) {
                  setState(() {
                    _batchSize = double.tryParse(val) ?? 1;
                  });
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                label: 'Waktu Produksi',
                hint: '2',
                controller: _productionTimeController,
                icon: Icons.timer,
                suffix: 'jam',
                keyboardType: TextInputType.number,
                onChanged: (val) {
                  setState(() {
                    _productionTimeHours = double.tryParse(val) ?? 1;
                    for (var labor in _laborDetails) {
                      labor['subtotal'] = labor['wage_per_hour'] * labor['count'] * _productionTimeHours;
                    }
                    for (var eq in _equipmentDetails) {
                      eq['usage_hours'] = _productionTimeHours;
                      eq['subtotal'] = (eq['power_watts'] / 1000.0) * eq['usage_hours'] * _electricityRate;
                    }
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Biaya Overhead',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Listrik, Sewa, Air, dan Wifi.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: _addEquipment,
              icon: const Icon(Icons.bolt, size: 18),
              label: const Text('Tambah Alat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        Text(
          'Biaya Listrik (Detail per Alat)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        if (_equipmentDetails.isEmpty)
          const Text('Belum ada alat listrik ditambahkan.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _equipmentDetails.length,
            itemBuilder: (context, index) {
              final eq = _equipmentDetails[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildSmallTextField(
                              label: 'Nama Alat',
                              hint: 'Mesin Espresso',
                              initialValue: eq['name'],
                              onChanged: (val) => eq['name'] = val,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _removeEquipment(index),
                            icon: const Icon(Icons.delete, color: Colors.red),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSmallTextField(
                              label: 'Daya (Watt)',
                              hint: '1000',
                              initialValue: eq['power_watts'].toString(),
                              keyboardType: TextInputType.number,
                              onChanged: (val) {
                                setState(() {
                                  eq['power_watts'] = double.tryParse(val) ?? 0;
                                  eq['subtotal'] = (eq['power_watts'] / 1000.0) * eq['usage_hours'] * _electricityRate;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSmallTextField(
                              label: 'Waktu Pakai (Jam)',
                              hint: '2',
                              initialValue: eq['usage_hours'].toString(),
                              keyboardType: TextInputType.number,
                              onChanged: (val) {
                                setState(() {
                                  eq['usage_hours'] = double.tryParse(val) ?? _productionTimeHours;
                                  eq['subtotal'] = (eq['power_watts'] / 1000.0) * eq['usage_hours'] * _electricityRate;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('Subtotal', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                Text(
                                  'Rp ${(eq['subtotal'] ?? 0).toStringAsFixed(0)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

        const Divider(height: 40),

        Text(
          'Biaya Utilitas Lainnya',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _buildSmallTextField(
                label: 'Tarif Sewa/Bulan',
                hint: '2000000',
                initialValue: _rentRate.toString(),
                keyboardType: TextInputType.number,
                prefix: 'Rp',
                onChanged: (val) => setState(() => _rentRate = double.tryParse(val) ?? 0),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Alokasi Batch', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  Text('Rp ${allocatedRent.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSmallTextField(
                label: 'Tarif Air/Bulan',
                hint: '100000',
                initialValue: _waterRate.toString(),
                keyboardType: TextInputType.number,
                prefix: 'Rp',
                onChanged: (val) => setState(() => _waterRate = double.tryParse(val) ?? 0),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Alokasi Batch', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  Text('Rp ${allocatedWater.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSmallTextField(
                label: 'Tarif Wifi/Bulan',
                hint: '300000',
                initialValue: _wifiRate.toString(),
                keyboardType: TextInputType.number,
                prefix: 'Rp',
                onChanged: (val) => setState(() => _wifiRate = double.tryParse(val) ?? 0),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Alokasi Batch', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  Text('Rp ${allocatedWifi.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),

        const Divider(height: 40),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Biaya Overhead:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                'Rp ${totalOverhead.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSimulationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hasil & Simulasi Harga',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primaryContainer,
                Theme.of(context).colorScheme.primary,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Text(
                'HPP PER UNIT',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                      letterSpacing: 2.0,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Rp ${_hppPerUnit.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Divider(color: Colors.white24, height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSummaryItem('Total HPP', 'Rp ${_totalHpp.toStringAsFixed(0)}'),
                  _buildSummaryItem('Batch Size', '${_batchSize.toStringAsFixed(0)} pcs'),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        Text(
          'Simulasi Profit Margin',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Ingin ambil margin berapa?'),
            Text(
              '${_marginPercentage.toStringAsFixed(0)}%',
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        Slider(
          value: _marginPercentage,
          min: 5,
          max: 95,
          activeColor: Theme.of(context).colorScheme.secondary,
          onChanged: (val) {
            setState(() {
              _marginPercentage = val;
              _updateMarginSimulation();
            });
          },
        ),

        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              _buildSimulationRow('Rekomendasi Harga Jual', 'Rp ${_recommendedPrice.toStringAsFixed(0)}', isHighlight: true),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Divider(),
              ),
              _buildSimulationRow('Profit per Unit', 'Rp ${(_recommendedPrice - _hppPerUnit).toStringAsFixed(0)}'),
              const SizedBox(height: 8),
              _buildSimulationRow('Estimasi Profit per Batch', 'Rp ${((_recommendedPrice - _hppPerUnit) * _batchSize).toStringAsFixed(0)}'),
            ],
          ),
        ),

        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveAsMenu,
                icon: const Icon(Icons.restaurant_menu),
                label: const Text('Simpan Menu'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _generatePdfReport,
                icon: const Icon(Icons.download),
                label: const Text('Unduh PDF'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: Theme.of(context).colorScheme.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 32),

        Text(
          'Rincian Biaya (Metode Full Costing)',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildCostBreakdown(),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
        ),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSimulationRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
            color: isHighlight ? Theme.of(context).colorScheme.primary : Colors.black54,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isHighlight ? 20 : 14,
            color: isHighlight ? Theme.of(context).colorScheme.secondary : Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildCostBreakdown() {
    double matTotal = 0;
    for (var m in _rawMaterials) {
      matTotal += m['subtotal'] ?? 0;
    }
    double laborTotal = 0;
    for (var l in _laborDetails) {
      laborTotal += l['subtotal'] ?? 0;
    }
    double overheadTotal = _subtotalHpp - matTotal - laborTotal;

    return Column(
      children: [
        _buildBreakdownItem('Biaya Bahan Baku', matTotal, Colors.orange),
        _buildBreakdownItem('Biaya Tenaga Kerja', laborTotal, Colors.blue),
        _buildBreakdownItem('Biaya Overhead', overheadTotal, Colors.purple),
        _buildBreakdownItem('Safety Margin (5%)', _safetyMargin, Colors.green),
      ],
    );
  }

  Widget _buildBreakdownItem(String label, double amount, Color color) {
    double percentage = _totalHpp > 0 ? (amount / _totalHpp) * 100 : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(label, style: const TextStyle(fontSize: 14)),
                ],
              ),
              Text('Rp ${amount.toStringAsFixed(0)} (${percentage.toStringAsFixed(1)}%)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: color.withValues(alpha: 0.1),
            color: color,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAsMenu() async {
    if (_tenantId == null) return;

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.from('recipes').insert({
        'tenant_id': _tenantId,
        'name': _recipeNameController.text.trim().isEmpty ? 'Produk Tanpa Nama' : _recipeNameController.text.trim(),
        'category': 'Hasil Kalkulator',
        'selling_price': _recommendedPrice,
        'target_margin_percent': _marginPercentage,
        'calculated_hpp': _hppPerUnit,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Produk berhasil ditambahkan ke daftar menu!')),
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan menu: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    String? suffix,
    String? prefixText,
    TextInputType? keyboardType,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
            prefixText: prefixText,
            suffixText: suffix,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildSmallTextField({
    required String label,
    required String hint,
    String? initialValue,
    String? prefix,
    TextInputType? keyboardType,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: initialValue,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix != null ? '$prefix ' : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
        ),
      ],
    );
  }
}
