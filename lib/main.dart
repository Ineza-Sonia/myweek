import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

// ============================================================
// MODELS (saved in Firestore under users/{uid}/...)
// ============================================================

class Course {
  Course({
    this.id = '',
    required this.name,
    required this.day,
    required this.start,
    required this.end,
    this.category = 'Class',
  });

  final String id; // the Firestore document id
  final String name;
  final int day; // 0 = Monday ... 6 = Sunday
  final int start; // minutes since midnight
  final int end;
  final String category;

  Map<String, dynamic> toMap() => {
    'name': name,
    'day': day,
    'start': start,
    'end': end,
    'category': category,
  };

  factory Course.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Course(
      id: doc.id,
      name: data['name'] as String,
      day: (data['day'] as num).toInt(),
      start: (data['start'] as num).toInt(),
      end: (data['end'] as num).toInt(),
      category: (data['category'] as String?) ?? 'Class',
    );
  }
}

class Task {
  Task({
    this.id = '',
    required this.title,
    this.daily = false,
    this.doneDate,
    this.order = 0,
  });

  final String id;
  final String title;
  final bool daily; // true = comes back every day
  final String? doneDate; // the day it was ticked, e.g. "2026-10-31"
  final int order; // to keep the list in the order it was created

  Map<String, dynamic> toMap() => {
    'title': title,
    'daily': daily,
    'doneDate': doneDate,
    'order': order,
  };

  factory Task.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Task(
      id: doc.id,
      title: data['title'] as String,
      daily: (data['daily'] as bool?) ?? false,
      doneDate: data['doneDate'] as String?,
      order: ((data['order'] as num?) ?? 0).toInt(),
    );
  }
}

class Research {
  Research({
    this.id = '',
    required this.topic,
    required this.detail,
    this.status = 'To find out',
    this.order = 0,
  });

  final String id;
  final String topic;
  final String detail;
  final String status;
  final int order;

  Map<String, dynamic> toMap() => {
    'topic': topic,
    'detail': detail,
    'status': status,
    'order': order,
  };

  factory Research.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Research(
      id: doc.id,
      topic: data['topic'] as String,
      detail: (data['detail'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'To find out',
      order: ((data['order'] as num?) ?? 0).toInt(),
    );
  }
}

/// The signed-in user's collection: users/{uid}/{name}
CollectionReference<Map<String, dynamic>> userCol(String name) {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection(name);
}

// ============================================================
// LOOKS
// ============================================================

final Map<String, Color> categoryColors = {
  'Class': Colors.teal,
  'Work': Colors.blueGrey,
  'Revision': Colors.indigo,
  'Project': Colors.deepPurple,
  'Money': Colors.green,
  'Health': Colors.orange,
  'Me time': Colors.cyan,
  'Sabbath': Colors.amber,
  'Together': Colors.pink,
};

final Map<String, IconData> categoryIcons = {
  'Class': Icons.school,
  'Work': Icons.work,
  'Revision': Icons.menu_book,
  'Project': Icons.code,
  'Money': Icons.savings,
  'Health': Icons.fitness_center,
  'Me time': Icons.spa,
  'Sabbath': Icons.wb_twilight,
  'Together': Icons.favorite,
};

const statuses = ['To find out', 'Asked', 'Done'];

final Map<String, Color> statusColors = {
  'To find out': Colors.orange.shade100,
  'Asked': Colors.blue.shade100,
  'Done': Colors.green.shade100,
};

// ============================================================
// TIME HELPERS
// ============================================================

const dayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday',
  'Friday', 'Saturday', 'Sunday',
];

/// "08:30" -> 510. Returns null if the text is not a valid HH:MM time.
int? parseTime(String text) {
  final parts = text.trim().split(':');
  if (parts.length != 2) return null;
  if (parts[0].isEmpty || parts[0].length > 2) return null;
  if (parts[1].length != 2) return null;

  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;

  return h * 60 + m;
}

String formatTime(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

String formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

String todayKey() {
  final n = DateTime.now();
  return '${n.year}-${n.month}-${n.day}';
}

// ============================================================
// RULES (functions outside build)
// ============================================================

/// "<" and not "<=": 11:00 end and 11:00 start do NOT clash.
bool clashes(Course a, Course b) {
  return a.day == b.day && a.start < b.end && b.start < a.end;
}

List<Course> clashingWith(Course course, List<Course> all) {
  return all.where((c) => c.id != course.id && clashes(course, c)).toList();
}

List<Course> coursesForDay(int day, List<Course> all) {
  final list = all.where((c) => c.day == day).toList();
  list.sort((a, b) => a.start.compareTo(b.start));
  return list;
}

int totalMinutes(List<Course> list) {
  int total = 0;
  for (final c in list) {
    total += c.end - c.start;
  }
  return total;
}

int classMinutes(List<Course> list) {
  int total = 0;
  for (final c in list) {
    if (c.category == 'Class') {
      total += c.end - c.start;
    }
  }
  return total;
}

/// Work yields to class: work blocks that overlap the class are shortened,
/// split or deleted in Firestore (all in one batch). Returns true if
/// something changed.
Future<bool> makeRoomForClass(Course cls, List<Course> all) async {
  final col = userCol('courses');
  final batch = FirebaseFirestore.instance.batch();
  bool changed = false;

  for (final w in all) {
    if (w.category != 'Work' || !clashes(cls, w)) continue;
    changed = true;
    final ref = col.doc(w.id);
    if (cls.start <= w.start && cls.end >= w.end) {
      batch.delete(ref); // the class covers all the work
    } else if (cls.start <= w.start) {
      batch.update(ref, {'start': cls.end}); // class cuts the beginning
    } else if (cls.end >= w.end) {
      batch.update(ref, {'end': cls.start}); // class cuts the end
    } else {
      // class in the middle: work before + a new work block after
      batch.update(ref, {'end': cls.start});
      batch.set(
        col.doc(),
        Course(
          name: w.name,
          category: 'Work',
          day: w.day,
          start: cls.end,
          end: w.end,
        ).toMap(),
      );
    }
  }

  if (changed) {
    await batch.commit();
  }
  return changed;
}

/// 0 or 1: which half of its column a clashing block takes in the grid.
int clashSlot(Course c, List<Course> all) {
  final before = clashingWith(c, all).where((o) =>
  o.start < c.start ||
      (o.start == c.start && all.indexOf(o) < all.indexOf(c)));
  return before.length % 2;
}

// ============================================================
// SMALL HELPERS (messages, dialogs, error handling)
// ============================================================

void say(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(text)));
}

void sayWithUndo(BuildContext context, String text, VoidCallback onUndo) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      action: SnackBarAction(label: 'Undo', onPressed: onUndo),
    ),
  );
}

Future<bool> askSure(BuildContext context, String title, String content) async {
  final sure = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return sure == true;
}

/// Runs a Firestore action and shows a message if the server refuses.
Future<void> run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on FirebaseException catch (e) {
    if (context.mounted) {
      say(context, 'Something went wrong (${e.code})');
    }
  }
}

/// The "loading" and "error" states of every screen that reads Firestore.
/// Returns null when the data has arrived.
Widget? loadingOrError(AsyncSnapshot snapshot, String what) {
  if (snapshot.hasError) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Could not load $what.\n${snapshot.error}',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
  if (!snapshot.hasData) {
    return const Center(child: CircularProgressIndicator());
  }
  return null;
}

// ============================================================
// SAMPLE DATA: written once when a new account is created
// ============================================================

Course block(String name, String category, int day, String start, String end) {
  return Course(
    name: name,
    category: category,
    day: day,
    start: parseTime(start)!,
    end: parseTime(end)!,
  );
}

List<Course> sampleCourses() {
  return [
    // ---------- Monday ----------
    block('Work at school', 'Work', 0, '09:00', '17:00'),
    block('Exercise', 'Health', 0, '17:30', '18:30'),
    block('Course revision', 'Revision', 0, '19:00', '21:00'),
    block('Call my man', 'Together', 0, '21:30', '22:00'),

    // ---------- Tuesday ----------
    block('INSY 8413 Big Data', 'Class', 1, '08:00', '11:00'),
    block('Work at school', 'Work', 1, '11:00', '17:00'),
    block('Personal project', 'Project', 1, '18:00', '20:00'),
    block('Call my man', 'Together', 1, '21:30', '22:00'),

    // ---------- Wednesday ----------
    block('Work at school', 'Work', 2, '09:00', '17:00'),
    block('Budget check', 'Money', 2, '18:00', '18:30'),
    block('Course revision', 'Revision', 2, '19:00', '21:00'),
    block('Call my man', 'Together', 2, '21:30', '22:00'),

    // ---------- Thursday ----------
    block('Work at school', 'Work', 3, '09:00', '17:00'),
    block('INSY 8211 Computer Networks', 'Class', 3, '18:00', '22:00'),
    block('Call my man', 'Together', 3, '22:15', '22:45'),

    // ---------- Friday ----------
    block('ENGL 8221 English', 'Class', 4, '08:30', '11:30'),
    block('Work at school', 'Work', 4, '11:30', '13:30'),
    block('INSY 8321 Data Structures', 'Class', 4, '13:30', '17:30'),
    block('Time with my man', 'Together', 4, '19:00', '21:00'),

    // ---------- Saturday ----------
    block('Sabbath rest', 'Sabbath', 5, '08:00', '18:00'),
    block('ME time', 'Me time', 5, '19:00', '21:00'),
    block('Call my man', 'Together', 5, '21:30', '22:00'),

    // ---------- Sunday ----------
    block('Personal project', 'Project', 6, '09:00', '12:00'),
    block('ME time', 'Me time', 6, '12:30', '14:00'),
    // DEMO CLASH (the brief needs one): overlaps ME time by 30 minutes.
    block('Budget and savings', 'Money', 6, '13:30', '14:30'),
    block('Exam preparation', 'Revision', 6, '15:30', '17:30'),
    block('ACCT 8224 Accounting II', 'Class', 6, '18:00', '21:00'),
    block('Call my man', 'Together', 6, '21:30', '22:00'),
  ];
}

Future<void> addSampleData() async {
  final batch = FirebaseFirestore.instance.batch();

  for (final c in sampleCourses()) {
    batch.set(userCol('courses').doc(), c.toMap());
  }

  final base = DateTime.now().millisecondsSinceEpoch;

  const taskTitles = [
    'Revise my courses',
    'Work on my personal project',
    'Check my budget / save money',
    'Check my body and mind',
    'Take some ME time',
    'Talk to my man before bed',
  ];
  for (int i = 0; i < taskTitles.length; i++) {
    batch.set(
      userCol('tasks').doc(),
      Task(title: taskTitles[i], daily: true, order: base + i).toMap(),
    );
  }

  const topics = [
    ['Masoro: own card printer', 'How is Masoro going to get its own card printer?'],
    ['Nursing emails', 'Write what exactly I must find out.'],
    ['Admission emails', 'Write what exactly I must find out.'],
    ['Gym information', 'Write what exactly I must find out.'],
    ['Student cards', 'Write what exactly I must find out.'],
  ];
  for (int i = 0; i < topics.length; i++) {
    batch.set(
      userCol('research').doc(),
      Research(topic: topics[i][0], detail: topics[i][1], order: base + i)
          .toMap(),
    );
  }

  await batch.commit();
}

// ============================================================
// APP + GATE
// ============================================================

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Week',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const AuthGate(),
    );
  }
}

/// Shows the login screen, or the app when someone is logged in.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data == null) {
          return const LoginScreen();
        }
        return const HomeShell();
      },
    );
  }
}

// ============================================================
// LOGIN SCREEN
// ============================================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool newAccount}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (newAccount) {
        await auth.createUserWithEmailAndPassword(
            email: _email.text.trim(), password: _password.text);
        await addSampleData();
      } else {
        await auth.signInWithEmailAndPassword(
            email: _email.text.trim(), password: _password.text);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _message(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'An account with this email already exists. Log in instead.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Wrong email or password.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'network-request-failed':
        return 'No internet connection.';
      default:
        return 'Something went wrong ($code).';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'My Week',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final email = (v ?? '').trim();
                      if (email.isEmpty) return 'Enter your email';
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(email)) {
                        return 'Enter a valid email, like aline@gmail.com';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                    (v ?? '').length < 6 ? 'At least 6 characters' : null,
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : () => _submit(newAccount: false),
                    child: const Text('Log in'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _submit(newAccount: true),
                    child: const Text('Create account'),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BOTTOM NAVIGATION
// ============================================================

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: tab,
        children: const [
          WeekScreen(),
          TasksScreen(),
          ResearchScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: tab,
        onTap: (i) {
          setState(() {
            tab = i;
          });
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_view_week), label: 'Week'),
          BottomNavigationBarItem(icon: Icon(Icons.task_alt), label: 'Today'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Research'),
        ],
      ),
    );
  }
}

// ============================================================
// SCREEN 1: WEEK (list + grid)
// ============================================================

class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key});

  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  // The live stream from Firestore, created once. The server sorts by start.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> coursesStream =
  userCol('courses').orderBy('start').snapshots();

  List<Course> latest = []; // the last list received, for the + button
  int selectedDay = DateTime.now().weekday - 1;
  bool gridView = false;

  void openCourse(Course? existing) {
    Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (context) => CourseScreen(
          course: existing,
          all: latest,
          initialDay: selectedDay,
        ),
      ),
    ).then((result) {
      if (!mounted || result is! Map) return;

      if (result['day'] is int) {
        setState(() {
          selectedDay = result['day'] as int;
        });
      }
      if (result['trimmed'] == true) {
        say(context, 'Work was shortened around your class');
      }
      final deleted = result['deleted'];
      if (deleted is Course) {
        sayWithUndo(context, '${deleted.name} deleted', () {
          // Undo = write the same data back with the same id
          userCol('courses').doc(deleted.id).set(deleted.toMap());
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Week'),
        actions: [
          IconButton(
            tooltip: gridView ? 'Show as list' : 'Show as grid',
            icon: Icon(gridView ? Icons.view_list : Icons.grid_view),
            onPressed: () {
              setState(() {
                gridView = !gridView;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => openCourse(null),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: coursesStream,
        builder: (context, snapshot) {
          final problem = loadingOrError(snapshot, 'your week');
          if (problem != null) return problem;

          final courses = snapshot.data!.docs.map(Course.fromDoc).toList();
          latest = courses;

          if (courses.isEmpty) {
            return const Center(
              child: Text(
                'Your week is empty.\nTap + to add your first block.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Week class time: ${formatDuration(classMinutes(courses))}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: gridView ? buildGrid(courses) : buildList(courses),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------- LIST VIEW ----------------
  Widget buildList(List<Course> courses) {
    final todays = coursesForDay(selectedDay, courses);
    final dayName = dayNames[selectedDay];
    final hasClass = todays.any((c) => c.category == 'Class');

    return Column(
      children: [
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (int i = 0; i < 7; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(dayNames[i].substring(0, 3)),
                    selected: selectedDay == i,
                    onSelected: (_) {
                      setState(() {
                        selectedDay = i;
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            '$dayName · Classes ${formatDuration(classMinutes(todays))}'
                ' · All ${formatDuration(totalMinutes(todays))}',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        if (!hasClass && todays.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('No classes on $dayName'),
          ),
        Expanded(
          child: todays.isEmpty
              ? Center(
            child: Text(
              'No classes on $dayName\nTap + to plan something',
              textAlign: TextAlign.center,
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: todays.length,
            itemBuilder: (context, index) {
              final course = todays[index];
              final others = clashingWith(course, courses);
              final hasClash = others.isNotEmpty;
              final color = categoryColors[course.category] ?? Colors.grey;
              final icon = categoryIcons[course.category] ?? Icons.event;

              String subtitle = '${course.category} · '
                  '${formatTime(course.start)} – ${formatTime(course.end)}';
              if (hasClash) {
                final names = others.map((c) => c.name).join(', ');
                subtitle += '\nClashes with $names';
              }

              return Card(
                color: hasClash ? Colors.red.shade100 : null,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color,
                    child: Icon(icon, color: Colors.white),
                  ),
                  title: Text(
                    course.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: hasClash ? Colors.red.shade900 : null,
                    ),
                  ),
                  subtitle: Text(subtitle),
                  isThreeLine: hasClash,
                  onTap: () => openCourse(course),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------- GRID VIEW ----------------
  Widget buildGrid(List<Course> courses) {
    const startHour = 7;
    const endHour = 23;
    const hourHeight = 48.0;
    const timeColWidth = 38.0;
    const totalHeight = (endHour - startHour) * hourHeight;
    final todayIndex = DateTime.now().weekday - 1;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 2,
            children: categoryColors.entries.map((e) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 10, color: e.value),
                  const SizedBox(width: 3),
                  Text(e.key, style: const TextStyle(fontSize: 10)),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final colWidth = (constraints.maxWidth - timeColWidth) / 7;

              return Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: timeColWidth),
                      for (int d = 0; d < 7; d++)
                        Container(
                          width: colWidth,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          alignment: Alignment.center,
                          color: d == todayIndex
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          child: Text(
                            dayNames[d].substring(0, 3),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 80),
                      child: SizedBox(
                        height: totalHeight,
                        child: Stack(
                          children: [
                            for (int h = startHour; h < endHour; h++)
                              Positioned(
                                top: (h - startHour) * hourHeight,
                                left: 0,
                                right: 0,
                                height: hourHeight,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: timeColWidth,
                                      child: Text(
                                        '${h.toString().padLeft(2, '0')}:00',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border(
                                            top: BorderSide(
                                              color: Colors.grey.shade300,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            for (int d = 0; d <= 7; d++)
                              Positioned(
                                left: timeColWidth + d * colWidth,
                                top: 0,
                                bottom: 0,
                                width: 1,
                                child: Container(color: Colors.grey.shade300),
                              ),
                            ...courses.map<Widget>((c) {
                              final s = c.start
                                  .clamp(startHour * 60, endHour * 60)
                                  .toInt();
                              final e = c.end
                                  .clamp(startHour * 60, endHour * 60)
                                  .toInt();
                              if (e <= s) return const SizedBox.shrink();

                              final hasClash =
                                  clashingWith(c, courses).isNotEmpty;
                              final color =
                                  categoryColors[c.category] ?? Colors.grey;
                              final textColor = color.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white;

                              final slot = hasClash ? clashSlot(c, courses) : 0;
                              final width =
                              hasClash ? colWidth / 2 - 1 : colWidth - 2;
                              final left = timeColWidth +
                                  c.day * colWidth +
                                  1 +
                                  slot * (colWidth / 2);

                              return Positioned(
                                left: left,
                                top: (s - startHour * 60) / 60 * hourHeight,
                                width: width,
                                height: (e - s) / 60 * hourHeight - 1,
                                child: GestureDetector(
                                  onTap: () => openCourse(c),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(4),
                                      border: hasClash
                                          ? Border.all(
                                          color: Colors.red, width: 2)
                                          : null,
                                    ),
                                    child: ClipRect(
                                      child: Text(
                                        c.name,
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================
// SCREEN 2: ADD / EDIT A BLOCK
// ============================================================

class CourseScreen extends StatefulWidget {
  const CourseScreen({
    super.key,
    this.course,
    required this.all,
    required this.initialDay,
  });

  final Course? course; // null = adding a new one
  final List<Course> all;
  final int initialDay;

  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  final nameController = TextEditingController();
  final startController = TextEditingController();
  final endController = TextEditingController();
  int day = 0;
  String category = 'Class';
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    if (c == null) {
      day = widget.initialDay;
    } else {
      nameController.text = c.name;
      startController.text = formatTime(c.start);
      endController.text = formatTime(c.end);
      day = c.day;
      category = c.category;
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    startController.dispose();
    endController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final name = nameController.text.trim();
    final start = parseTime(startController.text);
    final end = parseTime(endController.text);

    if (name.isEmpty) {
      say(context, 'Write the name first');
      return;
    }
    if (start == null) {
      say(context, 'Start time must look like 08:00 (hours 00-23, minutes 00-59)');
      return;
    }
    if (end == null) {
      say(context, 'End time must look like 10:30 (hours 00-23, minutes 00-59)');
      return;
    }
    if (end <= start) {
      say(context, 'The end time must be after the start time');
      return;
    }

    // Work never overlaps a class
    if (category == 'Work') {
      final hit = widget.all.where((c) =>
      c.id != widget.course?.id &&
          c.category == 'Class' &&
          c.day == day &&
          start < c.end &&
          c.start < end);
      if (hit.isNotEmpty) {
        say(context,
            'You have ${hit.first.name} then. You do not work during class.');
        return;
      }
    }

    setState(() {
      saving = true;
    });

    final block = Course(
      id: widget.course?.id ?? '',
      name: name,
      day: day,
      start: start,
      end: end,
      category: category,
    );

    bool trimmed = false;
    try {
      final col = userCol('courses');
      if (widget.course == null) {
        await col.add(block.toMap());
      } else {
        await col.doc(widget.course!.id).update(block.toMap());
      }
      if (category == 'Class') {
        trimmed = await makeRoomForClass(block, widget.all);
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
        });
        say(context, 'Could not save (${e.code})');
      }
      return;
    }

    if (mounted) {
      Navigator.pop(context, {'trimmed': trimmed, 'day': day});
    }
  }

  Future<void> deleteIt() async {
    final course = widget.course!;
    final sure = await askSure(context, 'Delete this block?', course.name);
    if (!sure || !mounted) return;

    try {
      await userCol('courses').doc(course.id).delete();
    } on FirebaseException catch (e) {
      if (mounted) say(context, 'Could not delete (${e.code})');
      return;
    }
    if (mounted) {
      Navigator.pop(context, {'deleted': course});
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.course != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit block' : 'Add to my week'),
        actions: [
          if (editing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete),
              onPressed: deleteIt,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Name (course or activity)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Day', style: TextStyle(fontWeight: FontWeight.bold)),
          Wrap(
            spacing: 6,
            children: [
              for (int i = 0; i < 7; i++)
                ChoiceChip(
                  label: Text(dayNames[i].substring(0, 3)),
                  selected: day == i,
                  onSelected: (_) {
                    setState(() {
                      day = i;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Category', style: TextStyle(fontWeight: FontWeight.bold)),
          Wrap(
            spacing: 6,
            children: [
              for (final name in categoryColors.keys)
                ChoiceChip(
                  avatar: Icon(categoryIcons[name], size: 16),
                  label: Text(name),
                  selected: category == name,
                  onSelected: (_) {
                    setState(() {
                      category = name;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: startController,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(
                    labelText: 'Start (08:00)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: endController,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(
                    labelText: 'End (10:30)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SCREEN 3: TODAY'S TASKS (daily checklist, saved in Firestore)
// ============================================================

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> tasksStream =
  userCol('tasks').snapshots();

  List<Task> latest = [];
  final controller = TextEditingController();
  bool repeatDaily = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> addTask() async {
    final title = controller.text.trim();
    if (title.isEmpty) {
      say(context, 'Write the task first');
      return;
    }
    if (latest.any((t) => t.title.toLowerCase() == title.toLowerCase())) {
      say(context, '"$title" is already on your list');
      return;
    }
    controller.clear();
    await run(
      context,
          () => userCol('tasks').add(Task(
        title: title,
        daily: repeatDaily,
        order: DateTime.now().millisecondsSinceEpoch,
      ).toMap()),
    );
  }

  Future<void> toggle(Task task, bool done) async {
    await run(
      context,
          () => userCol('tasks')
          .doc(task.id)
          .update({'doneDate': done ? todayKey() : null}),
    );
  }

  Future<void> deleteTask(Task task) async {
    final sure = await askSure(context, 'Delete this task?', task.title);
    if (!sure || !mounted) return;
    await run(context, () => userCol('tasks').doc(task.id).delete());
    if (!mounted) return;
    sayWithUndo(context, '"${task.title}" deleted', () {
      userCol('tasks').doc(task.id).set(task.toMap());
    });
  }

  @override
  Widget build(BuildContext context) {
    final dayName = dayNames[DateTime.now().weekday - 1];

    return Scaffold(
      appBar: AppBar(title: Text('Today · $dayName')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: tasksStream,
              builder: (context, snapshot) {
                final problem = loadingOrError(snapshot, 'your tasks');
                if (problem != null) return problem;

                final tasks = snapshot.data!.docs.map(Task.fromDoc).toList();
                tasks.sort((a, b) => a.order.compareTo(b.order));
                latest = tasks;

                final today = todayKey();
                // Daily tasks always show. One-time tasks show until done,
                // and stay for the rest of the day they were ticked.
                final shown = tasks
                    .where((t) =>
                t.daily || t.doneDate == null || t.doneDate == today)
                    .toList();
                final doneCount =
                    shown.where((t) => t.doneDate == today).length;
                final double progress =
                shown.isEmpty ? 0.0 : doneCount / shown.length;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$doneCount of ${shown.length} done',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                              value: progress, minHeight: 12),
                          if (shown.isNotEmpty && doneCount == shown.length)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('All done today. Rest well!'),
                            ),
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Tap to tick. Long press to delete.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: shown.isEmpty
                          ? const Center(
                        child: Text('No tasks for today. Add one below.'),
                      )
                          : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, index) {
                          final task = shown[index];
                          final done = task.doneDate == today;

                          return ListTile(
                            leading: Checkbox(
                              value: done,
                              onChanged: (v) => toggle(task, v ?? false),
                            ),
                            title: Text(
                              task.title,
                              style: TextStyle(
                                decoration: done
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle:
                            task.daily ? const Text('Every day') : null,
                            trailing: task.daily
                                ? const Icon(Icons.repeat)
                                : null,
                            onTap: () => toggle(task, !done),
                            onLongPress: () => deleteTask(task),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'Add a task',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => addTask(),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Every day'),
                  selected: repeatDaily,
                  onSelected: (value) {
                    setState(() {
                      repeatDaily = value;
                    });
                  },
                ),
                IconButton(
                  onPressed: addTask,
                  icon: const Icon(Icons.add_circle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SCREEN 4: RESEARCH BOARD (saved in Firestore)
// ============================================================

class ResearchScreen extends StatefulWidget {
  const ResearchScreen({super.key});

  @override
  State<ResearchScreen> createState() => _ResearchScreenState();
}

class _ResearchScreenState extends State<ResearchScreen> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> researchStream =
  userCol('research').snapshots();

  List<Research> latest = [];
  final topicController = TextEditingController();
  final detailController = TextEditingController();
  String filter = 'Open'; // Open, All or Done

  @override
  void dispose() {
    topicController.dispose();
    detailController.dispose();
    super.dispose();
  }

  bool matchesFilter(Research item) {
    if (filter == 'All') return true;
    if (filter == 'Done') return item.status == 'Done';
    return item.status != 'Done'; // Open
  }

  Future<void> addItem() async {
    final topic = topicController.text.trim();
    final detail = detailController.text.trim();
    if (topic.isEmpty) {
      say(context, 'Write the topic first');
      return;
    }
    if (latest.any((i) => i.topic.toLowerCase() == topic.toLowerCase())) {
      say(context, '"$topic" is already on the board');
      return;
    }
    topicController.clear();
    detailController.clear();
    await run(
      context,
          () => userCol('research').add(Research(
        topic: topic,
        detail: detail.isEmpty ? 'Write what exactly I must find out.' : detail,
        order: DateTime.now().millisecondsSinceEpoch,
      ).toMap()),
    );
  }

  Future<void> nextStatus(Research item) async {
    final next = statuses[(statuses.indexOf(item.status) + 1) % statuses.length];
    await run(
      context,
          () => userCol('research').doc(item.id).update({'status': next}),
    );
  }

  Future<void> deleteItem(Research item) async {
    final sure = await askSure(context, 'Delete this item?', item.topic);
    if (!sure || !mounted) return;
    await run(context, () => userCol('research').doc(item.id).delete());
    if (!mounted) return;
    sayWithUndo(context, '"${item.topic}" deleted', () {
      userCol('research').doc(item.id).set(item.toMap());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('To research')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: researchStream,
              builder: (context, snapshot) {
                final problem = loadingOrError(snapshot, 'your research list');
                if (problem != null) return problem;

                final items =
                snapshot.data!.docs.map(Research.fromDoc).toList();
                items.sort((a, b) => a.order.compareTo(b.order));
                latest = items;

                // Shown in status order: To find out, Asked, Done
                final shown = [
                  for (final s in statuses)
                    ...items.where((i) => i.status == s && matchesFilter(i)),
                ];
                final openCount =
                    items.where((i) => i.status != 'Done').length;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$openCount still open',
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                          for (final f in ['Open', 'All', 'Done'])
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: ChoiceChip(
                                label: Text(f),
                                selected: filter == f,
                                onSelected: (_) {
                                  setState(() {
                                    filter = f;
                                  });
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Tap an item to move it to the next status. Long press to delete.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    Expanded(
                      child: shown.isEmpty
                          ? Center(
                        child: Text(
                          filter == 'Open'
                              ? 'Nothing left to find out. Well done!'
                              : 'Nothing here yet.',
                        ),
                      )
                          : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, index) {
                          final item = shown[index];

                          return Card(
                            child: ListTile(
                              title: Text(
                                item.topic,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(item.detail),
                              trailing: Chip(
                                label: Text(item.status),
                                backgroundColor: statusColors[item.status],
                              ),
                              onTap: () => nextStatus(item),
                              onLongPress: () => deleteItem(item),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: topicController,
                  decoration: const InputDecoration(
                    hintText: 'Topic (e.g. Gym fees)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: detailController,
                        decoration: const InputDecoration(
                          hintText: 'What exactly must I find out?',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => addItem(),
                      ),
                    ),
                    IconButton(
                      onPressed: addItem,
                      icon: const Icon(Icons.add_circle),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}