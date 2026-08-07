import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NftWlTrackerApp());
}

class NftWlTrackerApp extends StatelessWidget {
  const NftWlTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NFT WL Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0B14),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9B5DE5),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161222),
          elevation: 0,
        ),
        cardColor: const Color(0xFF161222),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

enum WlType { gtd, fcfs }

extension WlTypeX on WlType {
  String get label => this == WlType.gtd ? 'GTD' : 'FCFS';
  Color get color =>
      this == WlType.gtd ? const Color(0xFF2ECC71) : const Color(0xFFF39C12);
}

class WlEntry {
  final String id;
  String name;
  WlType type;
  DateTime? mintDate; // date portion always meaningful when non-null
  bool hasTime; // whether the time-of-day part of mintDate was set by user
  int? quantity; // optional
  String? twitterLink; // optional
  final DateTime createdAt;

  WlEntry({
    required this.id,
    required this.name,
    required this.type,
    this.mintDate,
    this.hasTime = false,
    this.quantity,
    this.twitterLink,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'mintDate': mintDate?.toIso8601String(),
        'hasTime': hasTime,
        'quantity': quantity,
        'twitterLink': twitterLink,
        'createdAt': createdAt.toIso8601String(),
      };

  factory WlEntry.fromJson(Map<String, dynamic> json) {
    return WlEntry(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      type: (json['type'] == 'fcfs') ? WlType.fcfs : WlType.gtd,
      mintDate: json['mintDate'] != null
          ? DateTime.tryParse(json['mintDate'] as String)
          : null,
      hasTime: json['hasTime'] as bool? ?? false,
      quantity: json['quantity'] as int?,
      twitterLink: json['twitterLink'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

const List<String> _monthNamesId = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

String formatDate(DateTime d) {
  return '${d.day} ${_monthNamesId[d.month - 1]} ${d.year}';
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');

String formatDateTime(DateTime d, bool hasTime) {
  final datePart = formatDate(d);
  if (!hasTime) return datePart;
  return '$datePart, ${_twoDigits(d.hour)}:${_twoDigits(d.minute)}';
}

// ---------------------------------------------------------------------------
// Home page
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<WlEntry> _entries = [];
  bool _loading = true;

  bool _searching = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('wl_entries');
    List<WlEntry> loaded = [];
    if (raw != null) {
      try {
        final List decoded = jsonDecode(raw);
        loaded = decoded
            .map((e) => WlEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        // ignore malformed data
      }
    }
    setState(() {
      _entries = loaded;
      _loading = false;
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await prefs.setString('wl_entries', raw);
  }

  List<WlEntry> get _visibleEntries {
    if (_query.isEmpty) return _entries;
    return _entries.where((e) {
      return e.name.toLowerCase().contains(_query) ||
          (e.twitterLink ?? '').toLowerCase().contains(_query);
    }).toList();
  }

  Future<void> _openAddEdit({WlEntry? entry}) async {
    final result = await Navigator.push<_AddEditResult>(
      context,
      MaterialPageRoute(builder: (_) => AddEditWlPage(entry: entry)),
    );
    if (result == null) return;

    setState(() {
      if (result.deleted && entry != null) {
        _entries.removeWhere((e) => e.id == entry.id);
      } else if (result.entry != null) {
        final idx = _entries.indexWhere((e) => e.id == result.entry!.id);
        if (idx == -1) {
          _entries.insert(0, result.entry!);
        } else {
          _entries[idx] = result.entry!;
        }
      }
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final gtdCount = _entries.where((e) => e.type == WlType.gtd).length;
    final fcfsCount = _entries.where((e) => e.type == WlType.fcfs).length;
    final visible = _visibleEntries;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 16, color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Cari nama WL atau link Twitter...',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                ),
              )
            : const Text('NFT WL Tracker',
                style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: _searching ? 'Tutup pencarian' : 'Cari WL',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_searching) {
                  _searching = false;
                  _searchCtrl.clear();
                } else {
                  _searching = true;
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_entries.isNotEmpty && !_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _SummaryChip(
                    label: 'GTD',
                    value: gtdCount,
                    color: WlType.gtd.color,
                  ),
                  const SizedBox(width: 12),
                  _SummaryChip(
                    label: 'FCFS',
                    value: fcfsCount,
                    color: WlType.fcfs.color,
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? _EmptyState(onAdd: () => _openAddEdit())
                    : visible.isEmpty
                        ? const _EmptyState(
                            icon: Icons.search_off,
                            title: 'Gak ketemu',
                            subtitle:
                                'Gak ada WL yang cocok sama pencarian kamu.',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                            itemCount: visible.length,
                            itemBuilder: (context, i) {
                              final entry = visible[i];
                              return _WlCard(
                                entry: entry,
                                onTap: () => _openAddEdit(entry: entry),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddEdit(),
        backgroundColor: const Color(0xFF9B5DE5),
        icon: const Icon(Icons.add),
        label: const Text('Tambah WL'),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          border: Border.all(color: color.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '$label = $value',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback? onAdd;
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    this.onAdd,
    this.icon = Icons.confirmation_number_outlined,
    this.title = 'Belum ada catatan WL',
    this.subtitle = 'Tap tombol "Tambah WL" untuk mulai mencatat\nwhitelist NFT kamu.',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade700),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _WlCard extends StatelessWidget {
  final WlEntry entry;
  final VoidCallback onTap;

  const _WlCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161222),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: entry.type.color.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: entry.type.color.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    entry.type.label,
                    style: TextStyle(
                      color: entry.type.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
            if (entry.mintDate != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today,
                      size: 15, color: Color(0xFF9B5DE5)),
                  const SizedBox(width: 6),
                  Text(
                    formatDateTime(entry.mintDate!, entry.hasTime),
                    style: const TextStyle(
                      color: Color(0xFF9B5DE5),
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ],
            if (entry.quantity != null) ...[
              const SizedBox(height: 6),
              Text('Jumlah: ${entry.quantity}',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
            ],
            if (entry.twitterLink != null &&
                entry.twitterLink!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('Link:',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        var link = entry.twitterLink!.trim();
                        if (!link.startsWith('http')) link = 'https://$link';
                        final uri = Uri.tryParse(link);
                        if (uri != null) {
                          final ok = await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Gagal membuka link Twitter')),
                            );
                          }
                        }
                      },
                      child: Text(
                        entry.twitterLink!,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.lightBlueAccent,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add/Edit page
// ---------------------------------------------------------------------------

class _AddEditResult {
  final WlEntry? entry;
  final bool deleted;
  _AddEditResult({this.entry, this.deleted = false});
}

class AddEditWlPage extends StatefulWidget {
  final WlEntry? entry;
  const AddEditWlPage({super.key, this.entry});

  @override
  State<AddEditWlPage> createState() => _AddEditWlPageState();
}

class _AddEditWlPageState extends State<AddEditWlPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _quantityCtrl;
  late final TextEditingController _twitterCtrl;

  WlType _type = WlType.gtd;
  DateTime? _mintDate;
  TimeOfDay? _mintTime;

  bool get _isEditing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _quantityCtrl =
        TextEditingController(text: e?.quantity?.toString() ?? '');
    _twitterCtrl = TextEditingController(text: e?.twitterLink ?? '');
    _type = e?.type ?? WlType.gtd;
    _mintDate = e?.mintDate;
    if (e?.mintDate != null && e!.hasTime) {
      _mintTime =
          TimeOfDay(hour: e.mintDate!.hour, minute: e.mintDate!.minute);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _quantityCtrl.dispose();
    _twitterCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _mintDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        _mintDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> _pickTime() async {
    if (_mintDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih tanggal mint dulu ya')),
      );
      return;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: _mintTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _mintTime = picked);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    DateTime? finalDate = _mintDate;
    bool hasTime = false;
    if (finalDate != null && _mintTime != null) {
      finalDate = DateTime(finalDate.year, finalDate.month, finalDate.day,
          _mintTime!.hour, _mintTime!.minute);
      hasTime = true;
    }

    final quantityText = _quantityCtrl.text.trim();
    final twitterText = _twitterCtrl.text.trim();

    final entry = WlEntry(
      id: widget.entry?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      type: _type,
      mintDate: finalDate,
      hasTime: hasTime,
      quantity: quantityText.isEmpty ? null : int.tryParse(quantityText),
      twitterLink: twitterText.isEmpty ? null : twitterText,
      createdAt: widget.entry?.createdAt ?? DateTime.now(),
    );

    Navigator.pop(context, _AddEditResult(entry: entry));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Catatan?'),
        content: Text('"${widget.entry!.name}" akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context, _AddEditResult(deleted: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Catatan WL' : 'Tambah Catatan WL'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Hapus',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Nama NFT',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameCtrl,
              style: const TextStyle(fontSize: 16),
              decoration: _fieldDecoration('Contoh: Lokal Pride'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nama wajib diisi' : null,
            ),
            const SizedBox(height: 20),
            const Text('Tipe', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _typeChip(WlType.gtd)),
                const SizedBox(width: 10),
                Expanded(child: _typeChip(WlType.fcfs)),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Tanggal Mint (opsional)',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF161222),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 18, color: Color(0xFF9B5DE5)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _mintDate != null
                            ? formatDate(_mintDate!)
                            : 'Belum tau tanggalnya',
                        style: TextStyle(
                          fontSize: 15,
                          color: _mintDate != null
                              ? Colors.white
                              : Colors.grey.shade500,
                        ),
                      ),
                    ),
                    if (_mintDate != null)
                      IconButton(
                        onPressed: () => setState(() {
                          _mintDate = null;
                          _mintTime = null;
                        }),
                        icon: const Icon(Icons.close, size: 18),
                        color: Colors.grey,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Jam Mint (opsional)',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF161222),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time,
                        size: 18, color: Color(0xFF9B5DE5)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _mintTime != null
                            ? '${_twoDigits(_mintTime!.hour)}:${_twoDigits(_mintTime!.minute)}'
                            : 'Belum tau jamnya',
                        style: TextStyle(
                          fontSize: 15,
                          color: _mintTime != null
                              ? Colors.white
                              : Colors.grey.shade500,
                        ),
                      ),
                    ),
                    if (_mintTime != null)
                      IconButton(
                        onPressed: () => setState(() => _mintTime = null),
                        icon: const Icon(Icons.close, size: 18),
                        color: Colors.grey,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Jumlah (opsional)',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _quantityCtrl,
              style: const TextStyle(fontSize: 16),
              keyboardType: TextInputType.number,
              decoration: _fieldDecoration('Contoh: 2'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                if (int.tryParse(v.trim()) == null) {
                  return 'Harus berupa angka';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            const Text('Link Twitter (opsional)',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _twitterCtrl,
              style: const TextStyle(fontSize: 16),
              keyboardType: TextInputType.url,
              decoration: _fieldDecoration('https://x.com/namaproject'),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9B5DE5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _isEditing ? 'Simpan Perubahan' : 'Simpan Catatan',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(WlType type) {
    final selected = _type == type;
    return InkWell(
      onTap: () => setState(() => _type = type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? type.color.withOpacity(0.20)
              : const Color(0xFF161222),
          border: Border.all(
            color: selected ? type.color : Colors.transparent,
            width: 1.4,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          type.label,
          style: TextStyle(
            color: selected ? type.color : Colors.grey.shade400,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade600),
      filled: true,
      fillColor: const Color(0xFF161222),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}
