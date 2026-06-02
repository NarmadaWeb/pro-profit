import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../widgets/app_logo.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  double _totalOmzet = 0;
  double _labaBersih = 0;
  double _avgHpp = 0;
  List<Map<String, dynamic>> _dailyOmzet = [];
  List<Map<String, dynamic>> _topMenus = [];
  String? _tenantId;
  String _userName = 'Pemilik Toko';

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profileData = await _supabase
          .from('user_profiles')
          .select('tenant_id, full_name')
          .eq('id', user.id)
          .single();

      _tenantId = profileData['tenant_id'];
      _userName = profileData['full_name'] ?? 'Pemilik Toko';

      if (_tenantId == null) {
        setState(() => _isLoading = false);
        return;
      }

      // 1. Fetch Sales Logs for metrics and trend
      final salesData = await _supabase
          .from('sales_logs')
          .select('subtotal, sale_timestamp')
          .eq('tenant_id', _tenantId as Object);

      double totalOmzet = 0;
      Map<String, double> dailyMap = {};

      // Initialize last 7 days
      for (int i = 6; i >= 0; i--) {
        final date = DateTime.now().subtract(Duration(days: i));
        final label = DateFormat('EEE').format(date);
        dailyMap[label] = 0;
      }

      for (var sale in salesData) {
        final double subtotal = (sale['subtotal'] as num).toDouble();
        totalOmzet += subtotal;

        final timestamp = DateTime.parse(sale['sale_timestamp']).toLocal();
        final label = DateFormat('EEE').format(timestamp);
        if (dailyMap.containsKey(label)) {
          dailyMap[label] = (dailyMap[label] ?? 0) + subtotal;
        }
      }

      _dailyOmzet = dailyMap.entries.map((e) => {'label': e.key, 'value': e.value}).toList();

      // 2. Fetch Recipes for HPP and Laba calculation
      final recipesData = await _supabase
          .from('recipes')
          .select('calculated_hpp, selling_price, target_margin_percent, name')
          .eq('tenant_id', _tenantId as Object);

      double totalHpp = 0;
      if (recipesData.isNotEmpty) {
        for (var recipe in recipesData) {
          totalHpp += (recipe['calculated_hpp'] as num).toDouble();
        }
        _avgHpp = (totalHpp / recipesData.length) / 100; // Simplified for display as % if needed, or keep as value
        // Let's use the average margin instead
        double totalMarginPercent = 0;
        for (var recipe in recipesData) {
           totalMarginPercent += (recipe['target_margin_percent'] as num).toDouble();
        }
        _avgHpp = totalMarginPercent / recipesData.length;
      }

      _totalOmzet = totalOmzet;
      // Rough estimation of Laba Bersih
      _labaBersih = totalOmzet * (_avgHpp / 100);

      // 3. Top Menus (by margin)
      final topMenusData = await _supabase
          .from('recipes')
          .select('name, target_margin_percent')
          .eq('tenant_id', _tenantId as Object)
          .order('target_margin_percent', ascending: false)
          .limit(3);

      _topMenus = List<Map<String, dynamic>>.from(topMenusData);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching dashboard data: $e');
      setState(() => _isLoading = false);
    }
  }

  String _formatCurrency(double value) {
    if (value >= 1000000) {
      return 'Rp ${(value / 1000000).toStringAsFixed(1)}Jt';
    } else if (value >= 1000) {
      return 'Rp ${(value / 1000).toStringAsFixed(1)}Rb';
    }
    return 'Rp ${value.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fitur Tambah Cepat akan segera hadir!')),
          );
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        child: const Icon(Icons.add),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Halo, $_userName',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Berikut ringkasan performa bisnis Anda minggu ini.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            _buildMetricsGrid(context),
            const SizedBox(height: 24),
            _buildTrenOmzet(context),
            const SizedBox(height: 24),
                _buildTopMenu(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: constraints.maxWidth > 600
                  ? (constraints.maxWidth - 32) / 3
                  : constraints.maxWidth,
              child: _buildMetricCard(
                context,
                title: 'OMZET TOTAL',
                icon: Icons.payments,
                iconColor: Theme.of(context).colorScheme.primary,
                value: _formatCurrency(_totalOmzet),
                changeIcon: Icons.trending_up,
                changeText: 'Total akumulasi',
                changeColor: Theme.of(context).colorScheme.secondary,
                isDark: false,
              ),
            ),
            SizedBox(
              width: constraints.maxWidth > 600
                  ? (constraints.maxWidth - 32) / 3
                  : constraints.maxWidth,
              child: _buildMetricCard(
                context,
                title: 'ESTIMASI LABA',
                icon: Icons.account_balance_wallet,
                iconColor: const Color(0xFF6BD8CB), // secondary-fixed-dim
                value: _formatCurrency(_labaBersih),
                changeIcon: Icons.verified,
                changeText: 'Berdasarkan margin',
                changeColor: const Color(0xFF4AE176), // tertiary-fixed-dim
                isDark: true,
              ),
            ),
            SizedBox(
              width: constraints.maxWidth > 600
                  ? (constraints.maxWidth - 32) / 3
                  : constraints.maxWidth,
              child: _buildMetricCard(
                context,
                title: 'MARGIN RATA-RATA',
                icon: Icons.inventory_2,
                iconColor: Theme.of(context).colorScheme.error,
                value: '${_avgHpp.toStringAsFixed(1)}%',
                changeIcon: Icons.info,
                changeText: 'Dari semua menu',
                changeColor: Theme.of(context).colorScheme.onSurfaceVariant,
                isDark: false,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color iconColor,
    required String value,
    required IconData changeIcon,
    required String changeText,
    required Color changeColor,
    required bool isDark,
  }) {
    final bgColor = isDark
        ? Theme.of(context).colorScheme.primary
        : Colors.white.withValues(alpha: 0.8);
    final titleColor = isDark
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final valueColor =
        isDark ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: titleColor,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                  fontSize: 32,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(changeIcon, size: 16, color: changeColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  changeText,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: changeColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrenOmzet(BuildContext context) {
    double maxVal = 0;
    for (var d in _dailyOmzet) {
      if ((d['value'] as double) > maxVal) maxVal = d['value'];
    }
    if (maxVal == 0) maxVal = 1;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tren Omzet Mingguan',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '7 Hari',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '30 Hari',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: _dailyOmzet.isEmpty
                ? const Center(child: Text('Belum ada data penjualan.'))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _dailyOmzet.map((d) {
                      return _buildBar(
                        context,
                        d['label'],
                        (d['value'] as double) / maxVal,
                        d['label'] == DateFormat('EEE').format(DateTime.now()),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBar(BuildContext context, String label, double heightRatio, bool isHighlight) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: heightRatio,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isHighlight
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isHighlight
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopMenu(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Menu Margin Tertinggi',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 16),
          if (_topMenus.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Text('Belum ada data menu.'),
            )
          else
            ..._topMenus.map((m) => _buildMenuItem(
                context,
                m['name'],
                'Margin ${m['target_margin_percent']}%',
                Icons.restaurant_menu,
              )),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/menu-list');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Lihat Semua Menu'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, String title, String subtitle, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Detail Menu akan segera hadir!')),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
