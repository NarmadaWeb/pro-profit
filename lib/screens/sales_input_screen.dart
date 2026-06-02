import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../widgets/app_logo.dart';

class SalesInputScreen extends StatefulWidget {
  const SalesInputScreen({super.key});

  @override
  State<SalesInputScreen> createState() => _SalesInputScreenState();
}

class _SalesInputScreenState extends State<SalesInputScreen> {
  int _qty = 1;
  String? _selectedMenuId;
  List<Map<String, dynamic>> _menuOptions = [];
  List<Map<String, dynamic>> _salesHistory = [];
  double _totalOmzet = 0;
  bool _isLoading = true;
  String? _tenantId;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // 1. Get tenant_id for the user
      final profileData = await Supabase.instance.client
          .from('user_profiles')
          .select('tenant_id')
          .eq('id', user.id)
          .single();

      _tenantId = profileData['tenant_id'];
      if (_tenantId == null) {
        throw Exception("Tenant ID not found. User profile may not be set up correctly.");
      }

      // 2. Fetch recipes (menus)
      final recipesData = await Supabase.instance.client
          .from('recipes')
          .select('id, name, selling_price')
          .eq('tenant_id', _tenantId as Object);

      setState(() {
        _menuOptions = List<Map<String, dynamic>>.from(recipesData);
      });

      // 3. Fetch today's sales history
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day).toIso8601String();

      final salesData = await Supabase.instance.client
          .from('sales_logs')
          .select('*, recipes(name)')
          .eq('tenant_id', _tenantId as Object)
          .gte('sale_timestamp', startOfDay)
          .order('sale_timestamp', ascending: false);

      double omzet = 0;
      final formattedSales = (salesData as List).map((sale) {
        omzet += sale['subtotal'] ?? 0;
        final timestamp = DateTime.parse(sale['sale_timestamp']).toLocal();
        return {
          'id': sale['id'],
          'menu': sale['recipes']?['name'] ?? 'Unknown Menu',
          'note': sale['note'] ?? '-',
          'qty': sale['quantity'],
          'subtotal': sale['subtotal'],
          'time': DateFormat('HH:mm').format(timestamp),
        };
      }).toList();

      setState(() {
        _salesHistory = formattedSales;
        _totalOmzet = omzet;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching data: $e'), backgroundColor: Colors.red),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _incrementQty() {
    setState(() {
      _qty++;
    });
  }

  void _decrementQty() {
    if (_qty > 1) {
      setState(() {
        _qty--;
      });
    }
  }

  Future<void> _submitSale() async {
    if (_selectedMenuId == null || _tenantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih menu terlebih dahulu.')),
      );
      return;
    }

    try {
      final selected = _menuOptions.firstWhere((element) => element['id'] == _selectedMenuId);
      final double price = (selected['selling_price'] as num).toDouble();
      final double subtotal = price * _qty;

      // Insert into Supabase
      final response = await Supabase.instance.client.from('sales_logs').insert({
        'tenant_id': _tenantId,
        'recipe_id': _selectedMenuId,
        'quantity': _qty,
        'subtotal': subtotal,
        'note': 'Input Manual',
      }).select('*, recipes(name)').single();

      final timestamp = DateTime.parse(response['sale_timestamp']).toLocal();

      setState(() {
        _salesHistory.insert(0, {
          'id': response['id'],
          'menu': response['recipes']?['name'] ?? 'Unknown Menu',
          'note': response['note'] ?? '-',
          'qty': response['quantity'],
          'subtotal': response['subtotal'],
          'time': DateFormat('HH:mm').format(timestamp),
        });
        _totalOmzet += subtotal;
        _qty = 1; // reset
        _selectedMenuId = null; // reset dropdown
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Berhasil Disimpan'),
              ],
            ),
            backgroundColor: Color(0xFF006A61), // secondary
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving sale: $e'), backgroundColor: Colors.red),
        );
      }
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
            onPressed: () {},
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
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
                    child: _buildInputSection(context),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 7,
                    child: _buildHistorySection(context),
                  ),
                ],
              );
            } else {
              return Column(
                children: [
                  _buildInputSection(context),
                  const SizedBox(height: 24),
                  _buildHistorySection(context),
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

  Widget _buildInputSection(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TOTAL OMZET HARI INI',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  Icon(Icons.trending_up, color: Theme.of(context).colorScheme.secondary),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'Rp',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _totalOmzet.toStringAsFixed(0), // Format simply for now
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: -1.0,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '+12.5%',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Vs. Kemarin',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.add_circle, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Input Log Penjualan',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'PILIH MENU PRODUK',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: 1.0,
                    ),
              ),
              const SizedBox(height: 8),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceBright,
                      ),
                      initialValue: _selectedMenuId,
                      items: _menuOptions.map((menu) {
                        return DropdownMenuItem<String>(
                          value: menu['id'].toString(),
                          child: Text('${menu['name']} - Rp ${menu['selling_price']}'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedMenuId = val;
                        });
                      },
                      hint: const Text('Pilih Menu'),
                    ),
              const SizedBox(height: 24),
              Text(
                'JUMLAH TERJUAL',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: 1.0,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  InkWell(
                    onTap: _decrementQty,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.remove),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 48,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$_qty',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _incrementQty,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitSale,
                  icon: const Icon(Icons.save),
                  label: const Text('Simpan Log Penjualan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHistorySection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceBright,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Riwayat Penjualan',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hari ini: ${DateFormat('dd MMMM yyyy').format(DateTime.now())}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Laporan PDF'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.secondary,
                    textStyle: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _salesHistory.length,
            itemBuilder: (context, index) {
              final sale = _salesHistory[index];
              return Container(
                decoration: BoxDecoration(
                  color: index.isOdd ? Theme.of(context).colorScheme.surfaceBright : Colors.white,
                  border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sale['menu'],
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          Text(
                            'Catatan: ${sale['note']}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                  fontSize: 11,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        sale['qty'].toString(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        sale['subtotal'].toString(),
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        sale['time'],
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
