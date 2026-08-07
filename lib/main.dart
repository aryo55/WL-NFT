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

enum WlChain { ethereum, solana, robinhood, lainnya }

extension WlChainX on WlChain {
  String get label {
    switch (this) {
      case WlChain.ethereum:
        return 'Ethereum';
      case WlChain.solana:
        return 'Solana';
      case WlChain.robinhood:
        return 'Robinhood';
      case WlChain.lainnya:
        return 'Lainnya';
    }
  }

  Color get color {
    switch (this) {
      case WlChain.ethereum:
        return const Color(0xFF627EEA);
      case WlChain.solana:
        return const Color(0xFF9945FF);
      case WlChain.robinhood:
        return const Color(0xFF00C805);
      case WlChain.lainnya:
        return const Color(0xFF9E9E9E);
    }
  }
}

/// Logo chain digambar manual (vector, bukan gambar dari internet) biar
/// app-nya tetap ringan & gak butuh koneksi buat nampilin logo.
class ChainLogo extends StatelessWidget {
  final WlChain chain;
  final double size;
  const ChainLogo({super.key, required this.chain, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ChainLogoPainter(chain),
      ),
    );
  }
}

class _ChainLogoPainter extends CustomPainter {
  final WlChain chain;
  _ChainLogoPainter(this.chain);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    switch (chain) {
      case WlChain.ethereum:
        // Bentuk diamond khas Ethereum: dua segitiga bertumpuk.
        final paintTop = Paint()..color = const Color(0xFF627EEA);
        final paintBottom = Paint()..color = const Color(0xFF8298EE);
        final top = Path()
          ..moveTo(w * 0.5, 0)
          ..lineTo(w * 0.92, h * 0.58)
          ..lineTo(w * 0.5, h * 0.78)
          ..lineTo(w * 0.08, h * 0.58)
          ..close();
        canvas.drawPath(top, paintTop);
        final bottom = Path()
          ..moveTo(w * 0.08, h * 0.68)
          ..lineTo(w * 0.5, h * 0.90)
          ..lineTo(w * 0.92, h * 0.68)
          ..lineTo(w * 0.5, h)
          ..close();
        canvas.drawPath(bottom, paintBottom);
        break;

      case WlChain.solana:
        // Tiga bar sejajar miring, gradasi ungu ke hijau.
        final gradient = const LinearGradient(
          colors: [Color(0xFF9945FF), Color(0xFF14F195)],
        );
        final rect = Rect.fromLTWH(0, 0, w, h);
        final paint = Paint()..shader = gradient.createShader(rect);
        final barH = h * 0.16;
        final skew = w * 0.14;
        for (final ty in [h * 0.12, h * 0.42, h * 0.72]) {
          final bar = Path()
            ..moveTo(skew, ty)
            ..lineTo(w, ty)
            ..lineTo(w - skew, ty + barH)
            ..lineTo(0, ty + barH)
            ..close();
          canvas.drawPath(bar, paint);
        }
        break;

      case WlChain.robinhood:
        // Bentuk daun/feather sederhana, warna hijau khas Robinhood.
        final paint = Paint()..color = const Color(0xFF00C805);
        final leaf = Path()
          ..moveTo(w * 0.5, 0)
          ..quadraticBezierTo(w * 0.95, h * 0.25, w * 0.5, h)
          ..quadraticBezierTo(w * 0.05, h * 0.25, w * 0.5, 0)
          ..close();
        canvas.drawPath(leaf, paint);
        final stem = Paint()
          ..color = Colors.white.withOpacity(0.85)
          ..strokeWidth = size.width * 0.06
          ..style = PaintingStyle.stroke;
        canvas.drawLine(
            Offset(w * 0.5, h * 0.15), Offset(w * 0.5, h * 0.92), stem);
        break;

      case WlChain.lainnya:
        final paint = Paint()..color = const Color(0xFF9E9E9E);
        canvas.drawCircle(Offset(w / 2, h / 2), w / 2, paint);
        final textPainter = TextPainter(
          text: const TextSpan(
            text: '?',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          Offset(w / 2 - textPainter.width / 2, h / 2 - textPainter.height / 2),
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ChainLogoPainter oldDelegate) =>
      oldDelegate.chain != chain;
}

class WlEntry {
  final String id;
  String name;
  WlType type;
  WlChain chain;
  String? walletAddress; // wallet mana yang dapat WL ini
  DateTime? mintDate; // date portion always meaningful when non-null
  bool hasTime; // whether the time-of-day part of mintDate was set by user
  int? quantity; // optional
  String? twitterLink; // optional
  final DateTime createdAt;

  WlEntry({
    required this.id,
    required this.name,
    required this.type,
    this.chain = WlChain.ethereum,
    this.walletAddress,
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
        'chain': chain.name,
        'walletAddress': walletAddress,
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
      chain: WlChain.values.firstWhere(
        (c) => c.name == json['chain'],
        orElse: () => WlChain.ethereum,
      ),
      walletAddress: json['walletAddress'] as String?,
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
          (e.twitterLink ?? '').toLowerCase().contains(_query) ||
          (e.walletAddress ?? '').toLowerCase().contains(_query) ||
          e.chain.label.toLowerCase().contains(_query);
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
                ChainLogo(chain: entry.chain, size: 22),
                const SizedBox(width: 8),
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
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(
                entry.chain.label,
                style: TextStyle(
                    color: entry.chain.color, fontSize: 12, fontWeight: FontWeight.w600),
              ),
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
            if (entry.walletAddress != null &&
                entry.walletAddress!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entry.walletAddress!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.grey.shade400, fontSize: 13),
                    ),
                  ),
                ],
              ),
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
  late final TextEditingController _walletCtrl;

  WlType _type = WlType.gtd;
  WlChain _chain = WlChain.ethereum;
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
    _walletCtrl = TextEditingController(text: e?.walletAddress ?? '');
    _type = e?.type ?? WlType.gtd;
    _chain = e?.chain ?? WlChain.ethereum;
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
    _walletCtrl.dispose();
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
    final walletText = _walletCtrl.text.trim();

    final entry = WlEntry(
      id: widget.entry?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      type: _type,
      chain: _chain,
      walletAddress: walletText.isEmpty ? null : walletText,
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
            const Text('Chain', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children:
                  WlChain.values.map((c) => _chainChip(c)).toList(),
            ),
            const SizedBox(height: 20),
            const Text('Wallet Yang Dapat WL (opsional)',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _walletCtrl,
              style: const TextStyle(fontSize: 15),
              decoration: _fieldDecoration('0x1234... atau alamat wallet'),
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

  Widget _chainChip(WlChain chain) {
    final selected = _chain == chain;
    return InkWell(
      onTap: () => setState(() => _chain = chain),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? chain.color.withOpacity(0.20)
              : const Color(0xFF161222),
          border: Border.all(
            color: selected ? chain.color : Colors.transparent,
            width: 1.4,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChainLogo(chain: chain, size: 18),
            const SizedBox(width: 8),
            Text(
              chain.label,
              style: TextStyle(
                color: selected ? chain.color : Colors.grey.shade400,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
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
