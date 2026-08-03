import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
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
  DateTime? mintDate; // optional
  int? quantity; // optional
  String? twitterLink; // optional
  final DateTime createdAt;

  WlEntry({
    required this.id,
    required this.name,
    required this.type,
    this.mintDate,
    this.quantity,
    this.twitterLink,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'mintDate': mintDate?.toIso8601String(),
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

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await prefs.setString('wl_entries', encoded);
  }

  List<WlEntry> get _sorted {
    final withDate = _entries.where((e) => e.mintDate != null).toList()
      ..sort((a, b) => a.mintDate!.compareTo(b.mintDate!));
    final withoutDate = _entries.where((e) => e.mintDate == null).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return [...withDate, ...withoutDate];
  }

  Future<void> _openAddEdit({WlEntry? entry}) async {
    final result = await Navigator.push<_AddEditResult>(
      context,
      MaterialPageRoute(builder: (_) => AddEditPage(entry: entry)),
    );
    if (result == null) return;

    setState(() {
      if (result.deleted && entry != null) {
        _entries.removeWhere((e) => e.id == entry.id);
      } else if (result.entry != null) {
        final idx = _entries.indexWhere((e) => e.id == result.entry!.id);
        if (idx >= 0) {
          _entries[idx] = result.entry!;
        } else {
          _entries.add(result.entry!);
        }
      }
    });
    _save();
  }

  Future<void> _delete(WlEntry entry) async {
    setState(() => _entries.removeWhere((e) => e.id == entry.id));
    await _save();
  }

  Future<void> _openTwitter(String link) async {
    var url = link.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membuka link Twitter')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _sorted;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NFT WL Tracker',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final e = list[i];
                    return _WlCard(
                      entry: e,
                      onTap: () => _openAddEdit(entry: e),
                      onDelete: () => _delete(e),
                      onTwitterTap: e.twitterLink != null &&
                              e.twitterLink!.trim().isNotEmpty
                          ? () => _openTwitter(e.twitterLink!)
                          : null,
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah WL'),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.confirmation_number_outlined,
                size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Belum ada catatan WL',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap tombol "Tambah WL" untuk mulai mencatat whitelist NFT kamu.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400),
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
  final VoidCallback onDelete;
  final VoidCallback? onTwitterTap;

  const _WlCard({
    required this.entry,
    required this.onTap,
    required this.onDelete,
    this.onTwitterTap,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date = entry.mintDate;
    final isPast = date != null &&
        date.isBefore(DateTime(now.year, now.month, now.day));
    final isSoon = date != null &&
        !isPast &&
        date.difference(DateTime(now.year, now.month, now.day)).inDays <= 3;

    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1E1930),
                title: const Text('Hapus catatan?'),
                content: Text('"${entry.name}" akan dihapus permanen.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Hapus',
                        style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF161222),
          borderRadius: BorderRadius.circular(14),
          border: isSoon
              ? Border.all(color: const Color(0xFF9B5DE5), width: 1.2)
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: entry.type.color.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          entry.type.label,
                          style: TextStyle(
                            color: entry.type.color,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.event,
                          size: 15,
                          color: isPast
                              ? Colors.grey
                              : (isSoon
                                  ? const Color(0xFF9B5DE5)
                                  : Colors.grey.shade400)),
                      const SizedBox(width: 4),
                      Text(
                        date != null
                            ? formatDate(date) + (isPast ? ' (lewat)' : '')
                            : 'Tanggal belum ditentukan',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isPast
                              ? Colors.grey
                              : (isSoon
                                  ? const Color(0xFF9B5DE5)
                                  : Colors.grey.shade400),
                          fontWeight:
                              isSoon ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (entry.quantity != null) ...[
                        const SizedBox(width: 14),
                        Icon(Icons.confirmation_number,
                            size: 14, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text('${entry.quantity}',
                            style: TextStyle(
                                fontSize: 12.5, color: Colors.grey.shade400)),
                      ],
                    ],
                  ),
                  if (onTwitterTap != null && entry.twitterLink != null) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: onTwitterTap,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.alternate_email,
                              size: 14, color: Color(0xFF1DA1F2)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              entry.twitterLink!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF1DA1F2),
                                decoration: TextDecoration.underline,
                                decorationColor: Color(0xFF1DA1F2),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / Edit page
// ---------------------------------------------------------------------------

class _AddEditResult {
  final WlEntry? entry;
  final bool deleted;
  _AddEditResult({this.entry, this.deleted = false});
}

class AddEditPage extends StatefulWidget {
  final WlEntry? entry;
  const AddEditPage({super.key, this.entry});

  @override
  State<AddEditPage> createState() => _AddEditPageState();
}

class _AddEditPageState extends State<AddEditPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _quantityCtrl;
  late TextEditingController _twitterCtrl;
  WlType _type = WlType.gtd;
  DateTime? _mintDate;

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
      lastDate: DateTime(now.year + 3),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: const Color(0xFF9B5DE5),
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _mintDate = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final quantityText = _quantityCtrl.text.trim();
    final twitterText = _twitterCtrl.text.trim();

    final entry = WlEntry(
      id: widget.entry?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim(),
      type: _type,
      mintDate: _mintDate,
      quantity: quantityText.isEmpty ? null : int.tryParse(quantityText),
      twitterLink: twitterText.isEmpty ? null : twitterText,
      createdAt: widget.entry?.createdAt ?? DateTime.now(),
    );

    Navigator.pop(context, _AddEditResult(entry: entry));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1930),
        title: const Text('Hapus catatan?'),
        content: Text('"${widget.entry!.name}" akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Hapus', style: TextStyle(color: Colors.redAccent)),
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
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete_outline),
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
              decoration: _fieldDecoration('Contoh: Pudgy Penguins'),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nama wajib diisi' : null,
            ),
            const SizedBox(height: 20),
            const Text('Tipe',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
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
                        onPressed: () => setState(() => _mintDate = null),
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
