import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tz.initializeTimeZones();
  try {
    final currentTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(currentTimeZone.identifier));
  } catch (_) {
    // If detection fails, notifications still work but may use device's
    // default (UTC) reference â€” reminder time could be off in that case.
  }

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // PENTING: permission request (notifikasi biasa & exact alarm) SENGAJA
  // TIDAK dipanggil di sini. Kalau dipanggil sebelum runApp(), Activity
  // Android belum tentu siap nerima intent ke System Settings, jadi
  // requestExactAlarmsPermission() bisa gagal diam-diam tanpa error.
  // Diminta di HomePage.initState() setelah frame pertama selesai render.

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
  bool reminderEnabled;
  int reminderMinutes; // how many minutes before mint to notify (1-10)
  final DateTime createdAt;

  WlEntry({
    required this.id,
    required this.name,
    required this.type,
    this.mintDate,
    this.hasTime = false,
    this.quantity,
    this.twitterLink,
    this.reminderEnabled = false,
    this.reminderMinutes = 10,
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
        'reminderEnabled': reminderEnabled,
        'reminderMinutes': reminderMinutes,
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
      reminderEnabled: json['reminderEnabled'] as bool? ?? false,
      reminderMinutes: json['reminderMinutes'] as int? ?? 10,
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

/// Derives a stable 31-bit notification id from an entry's id so the same
/// entry always maps to the same notification (needed to cancel/replace it).
int notifIdFor(String entryId) => entryId.hashCode & 0x7FFFFFFF;

Future<void> cancelReminder(String entryId) async {
  await flutterLocalNotificationsPlugin.cancel(notifIdFor(entryId));
}

/// Result of trying to schedule a reminder, so the UI can tell the user
/// exactly why nothing was scheduled instead of failing silently.
enum ScheduleResult { scheduled, notEnabled, timeAlreadyPast }

/// Cancels any existing reminder for this entry, then schedules a new one
/// if the entry has a reminder enabled with a valid future fire time.
Future<ScheduleResult> scheduleReminder(WlEntry entry) async {
  await cancelReminder(entry.id);

  if (!entry.reminderEnabled || entry.mintDate == null || !entry.hasTime) {
    return ScheduleResult.notEnabled;
  }

  final fireTime =
      entry.mintDate!.subtract(Duration(minutes: entry.reminderMinutes));
  if (fireTime.isBefore(DateTime.now())) {
    debugPrint(
        'SKIP SCHEDULE: fireTime $fireTime already before now ${DateTime.now()}');
    return ScheduleResult.timeAlreadyPast; // don't schedule the past
  }

  final tzTime = tz.TZDateTime.from(fireTime, tz.local);
  debugPrint('SCHEDULING notif id=${notifIdFor(entry.id)} at $tzTime');

  await flutterLocalNotificationsPlugin.zonedSchedule(
    notifIdFor(entry.id),
    'Mint sebentar lagi! ðŸš¨',
    '${entry.name} (${entry.type.label}) mint dalam ${entry.reminderMinutes} menit',
    tzTime,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'mint_reminders',
        'Pengingat Mint NFT',
        channelDescription: 'Notifikasi pengingat sebelum waktu mint NFT',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
  );
  return ScheduleResult.scheduled;
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
    // Diminta SETELAH frame pertama selesai render, bukan di main() sebelum
    // runApp(). Ini penting: kalau diminta terlalu awal, intent ke System
    // Settings (buat exact alarm) bisa gagal diam-diam karena Activity-nya
    // belum sepenuhnya siap.
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissions());
  }

  Future<void> _requestPermissions() async {
    final androidImpl = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    final notifGranted = await androidImpl?.requestNotificationsPermission();
    debugPrint('NOTIF PERMISSION GRANTED: $notifGranted');

    // Wajib diminta terpisah dari izin notifikasi biasa. Tanpa ini,
    // zonedSchedule dengan AndroidScheduleMode.exactAllowWhileIdle akan
    // gagal/di-downgrade diam-diam di Android 12+ (termasuk semua HP
    // berbasis OriginOS/FuntouchOS/MIUI/ColorOS).
    final exactGranted = await androidImpl?.requestExactAlarmsPermission();
    debugPrint('EXACT ALARM PERMISSION GRANTED: $exactGranted');
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

    // Defensive resync: make sure every entry's reminder is (re)scheduled,
    // in case something changed since the app was last opened.
    for (final e in loaded) {
      await scheduleReminder(e); // ScheduleResult ignored here on purpose
    }
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

    if (result.deleted && entry != null) {
      await cancelReminder(entry.id);
    } else if (result.entry != null) {
      final scheduleResult = await scheduleReminder(result.entry!);
      if (scheduleResult == ScheduleResult.timeAlreadyPast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Waktu reminder sudah lewat, notifikasi tidak dijadwalkan. '
              'Coba pilih waktu mint yang lebih jauh dari sekarang.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _delete(WlEntry entry) async {
    setState(() => _entries.removeWhere((e) => e.id == entry.id));
    await _save();
    await cancelReminder(entry.id);
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
    final gtdCount = _entries.where((e) => e.type == WlType.gtd).length;
    final fcfsCount = _entries.where((e) => e.type == WlType.fcfs).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NFT WL Tracker',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          // TODO: hapus tombol ini setelah notifikasi dikonfirmasi jalan.
          // Menekannya harus langsung menampilkan notifikasi (tanpa
          // menunggu jadwal), untuk memisahkan masalah "notif dasar
          // gak jalan" dari masalah "scheduling/exact alarm gak jalan".
          IconButton(
            tooltip: 'Test Notif',
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: () async {
              await flutterLocalNotificationsPlugin.show(
                999999,
                'Test Notifikasi',
                'Kalau ini muncul, notifikasi dasar sudah OK.',
                const NotificationDetails(
                  android: AndroidNotificationDetails(
                    'mint_reminders',
                    'Pengingat Mint NFT',
                    importance: Importance.high,
                    priority: Priority.high,
                  ),
                ),
              );
            },
          ),
          // TODO: hapus tombol ini juga setelah selesai debug. Nampilin
          // status izin langsung di layar, gak perlu ADB/laptop.
          IconButton(
            tooltip: 'Cek Izin',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () async {
              final androidImpl = flutterLocalNotificationsPlugin
                  .resolvePlatformSpecificImplementation<
                      AndroidFlutterLocalNotificationsPlugin>();

              final notifEnabled =
                  await androidImpl?.areNotificationsEnabled();
              final exactAllowed =
                  await androidImpl?.canScheduleExactNotifications();
              final now = DateTime.now();
              final tzNow = tz.TZDateTime.now(tz.local);

              if (!context.mounted) return;
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Status Izin & Waktu'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Izin notifikasi: ${notifEnabled ?? "null (error)"}'),
                      const SizedBox(height: 6),
                      Text('Izin exact alarm: ${exactAllowed ?? "null (error)"}'),
                      const SizedBox(height: 6),
                      Text('Waktu device (lokal): $now'),
                      const SizedBox(height: 6),
                      Text('Waktu tz.local: $tzNow'),
                      const SizedBox(height: 6),
                      Text('Zona waktu terdeteksi: ${tz.local.name}'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Tutup'),
                    ),
                  ],
                ),
              );
            },
          ),
          // TODO: hapus tombol ini juga setelah selesai debug. Nge-tes
          // jalur zonedSchedule yang PERSIS sama kayak reminder beneran,
          // tapi 15 detik dari sekarang, biar cepet ketauan exact alarm
          // delivery-nya jalan atau enggak, terlepas dari logic tanggal
          // di form Add/Edit WL.
          IconButton(
            tooltip: 'Test Terjadwal 15 detik',
            icon: const Icon(Icons.timer_outlined),
            onPressed: () async {
              final fireAt =
                  tz.TZDateTime.now(tz.local).add(const Duration(seconds: 15));
              await flutterLocalNotificationsPlugin.zonedSchedule(
                999998,
                'Test Terjadwal',
                'Kalau ini muncul ~15 detik setelah kamu pencet tombol, zonedSchedule OK.',
                fireAt,
                const NotificationDetails(
                  android: AndroidNotificationDetails(
                    'mint_reminders',
                    'Pengingat Mint NFT',
                    importance: Importance.high,
                    priority: Priority.high,
                  ),
                ),
                androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
                uiLocalNotificationDateInterpretation:
                    UILocalNotificationDateInterpretation.absoluteTime,
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Dijadwalkan buat $fireAt. Minimize app (jangan force-close), tunggu 15 detik.'),
                  duration: const Duration(seconds: 4),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_entries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _SummaryChip(
                    label: 'GTD',
                    count: gtdCount,
                    color: WlType.gtd.color,
                  ),
                  const SizedBox(width: 10),
                  _SummaryChip(
                    label: 'FCFS',
                    count: fcfsCount,
                    color: WlType.fcfs.color,
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
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
          ),
        ],
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

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '= $count',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
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
                            ? formatDateTime(date, entry.hasTime) +
                                (isPast ? ' (lewat)' : '')
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
                          const Text('ðŸ”—', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 5),
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
                  if (entry.reminderEnabled &&
                      entry.hasTime &&
                      date != null &&
                      !isPast) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('ðŸ””', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        Text(
                          'Diingatkan ${entry.reminderMinutes} menit sebelum mint',
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.grey.shade500),
                        ),
                      ],
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
  TimeOfDay? _mintTime;
  bool _reminderEnabled = false;
  int _reminderMinutes = 10;

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
    if (e != null && e.hasTime && e.mintDate != null) {
      _mintTime = TimeOfDay(hour: e.mintDate!.hour, minute: e.mintDate!.minute);
    }
    _reminderEnabled = e?.reminderEnabled ?? false;
    _reminderMinutes = e?.reminderMinutes ?? 10;
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
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: const Color(0xFF9B5DE5),
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _mintTime = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final quantityText = _quantityCtrl.text.trim();
    final twitterText = _twitterCtrl.text.trim();

    DateTime? combinedDate = _mintDate;
    final hasTime = _mintDate != null && _mintTime != null;
    if (hasTime) {
      combinedDate = DateTime(
        _mintDate!.year,
        _mintDate!.month,
        _mintDate!.day,
        _mintTime!.hour,
        _mintTime!.minute,
      );
    }

    final entry = WlEntry(
      id: widget.entry?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim(),
      type: _type,
      mintDate: combinedDate,
      hasTime: hasTime,
      quantity: quantityText.isEmpty ? null : int.tryParse(quantityText),
      twitterLink: twitterText.isEmpty ? null : twitterText,
      reminderEnabled: _reminderEnabled && hasTime,
      reminderMinutes: _reminderMinutes,
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
            if (_mintDate != null && _mintTime != null) ...[
              const SizedBox(height: 20),
              const Text('Notifikasi Pengingat',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF161222),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Ingatkan sebelum mint',
                            style: TextStyle(fontSize: 14.5),
                          ),
                        ),
                        Switch(
                          value: _reminderEnabled,
                          activeColor: const Color(0xFF9B5DE5),
                          onChanged: (v) =>
                              setState(() => _reminderEnabled = v),
                        ),
                      ],
                    ),
                    if (_reminderEnabled) ...[
                      const SizedBox(height: 4),
                      Text(
                        '$_reminderMinutes menit sebelum waktu mint',
                        style: const TextStyle(
                          color: Color(0xFF9B5DE5),
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      Slider(
                        value: _reminderMinutes.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        activeColor: const Color(0xFF9B5DE5),
                        label: '$_reminderMinutes menit',
                        onChanged: (v) =>
                            setState(() => _reminderMinutes = v.round()),
                      ),
                    ],
                  ],
                ),
              ),
            ],
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
