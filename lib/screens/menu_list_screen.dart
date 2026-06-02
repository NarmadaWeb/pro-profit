import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_logo.dart';

class MenuListScreen extends StatefulWidget {
  const MenuListScreen({super.key});

  @override
  State<MenuListScreen> createState() => _MenuListScreenState();
}

class _MenuListScreenState extends State<MenuListScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _menus = [];
  bool _isLoading = true;
  String? _tenantId;

  @override
  void initState() {
    super.initState();
    _fetchMenus();
  }

  Future<void> _fetchMenus() async {
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
          .from('recipes')
          .select()
          .eq('tenant_id', _tenantId as Object)
          .order('name');

      setState(() {
        _menus = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching menus: $e');
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
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daftar Menu',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _menus.isEmpty
                            ? const Center(child: Text('Belum ada menu yang dibuat.'))
                            : ListView.builder(
                                itemCount: _menus.length,
                                itemBuilder: (context, index) {
                                  final menu = _menus[index];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                        child: const Icon(Icons.restaurant_menu),
                                      ),
                                      title: Text(
                                        menu['name'],
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Text(
                                        'HPP: Rp ${menu['calculated_hpp'].toStringAsFixed(0)} | Margin: ${menu['target_margin_percent']}%',
                                      ),
                                      trailing: Text(
                                        'Rp ${menu['selling_price'].toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.primary,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  );
                                },
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
