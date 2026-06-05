import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_logo.dart';

class RawMaterialListScreen extends StatefulWidget {
  const RawMaterialListScreen({super.key});

  @override
  State<RawMaterialListScreen> createState() => _RawMaterialListScreenState();
}

class _RawMaterialListScreenState extends State<RawMaterialListScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _materials = [];
  bool _isLoading = true;
  String? _tenantId;

  @override
  void initState() {
    super.initState();
    _fetchMaterials();
  }

  Future<void> _fetchMaterials() async {
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
          .from('raw_materials')
          .select()
          .eq('tenant_id', _tenantId as Object)
          .order('name');

      setState(() {
        _materials = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching materials: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addOrEditMaterial([Map<String, dynamic>? material]) async {
    final nameController = TextEditingController(text: material?['name']);
    final priceController = TextEditingController(text: material?['price_per_unit']?.toString());
    final stockController = TextEditingController(text: material?['current_stock']?.toString());
    final unitController = TextEditingController(text: material?['unit_measure'] ?? 'gram');
    final categoryController = TextEditingController(text: material?['category'] ?? 'Bahan');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(material == null ? 'Tambah Bahan' : 'Edit Bahan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nama Bahan')),
              TextField(controller: categoryController, decoration: const InputDecoration(labelText: 'Kategori')),
              TextField(controller: priceController, decoration: const InputDecoration(labelText: 'Harga Satuan'), keyboardType: TextInputType.number),
              TextField(controller: stockController, decoration: const InputDecoration(labelText: 'Stok Saat Ini'), keyboardType: TextInputType.number),
              TextField(controller: unitController, decoration: const InputDecoration(labelText: 'Satuan (Kg, gram, ml, dll)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;

              final data = {
                'tenant_id': _tenantId,
                'name': nameController.text,
                'category': categoryController.text,
                'price_per_unit': double.tryParse(priceController.text) ?? 0,
                'current_stock': double.tryParse(stockController.text) ?? 0,
                'unit_measure': unitController.text,
              };

              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);

              try {
                if (material == null) {
                  await _supabase.from('raw_materials').insert(data);
                } else {
                  await _supabase.from('raw_materials').update(data).eq('id', material['id']);
                }
                if (mounted) {
                  navigator.pop(true);
                }
              } catch (e) {
                debugPrint('Error saving material: $e');
                if (mounted) {
                  scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error saving: $e')));
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (result == true) {
      _fetchMaterials();
    }
  }

  Future<void> _deleteMaterial(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Bahan?'),
        content: const Text('Tindakan ini tidak dapat dibatalkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _supabase.from('raw_materials').delete().eq('id', id);
      _fetchMaterials();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppLogo(),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditMaterial(),
        child: const Icon(Icons.add),
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
                        'Daftar Bahan Baku',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _materials.isEmpty
                            ? const Center(child: Text('Belum ada bahan baku.'))
                            : ListView.builder(
                                itemCount: _materials.length,
                                itemBuilder: (context, index) {
                                  final m = _materials[index];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: ListTile(
                                      title: Text(m['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text('${m['current_stock']} ${m['unit_measure']} | Rp ${m['price_per_unit']}/${m['unit_measure']}'),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _addOrEditMaterial(m)),
                                          IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), onPressed: () => _deleteMaterial(m['id'])),
                                        ],
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
