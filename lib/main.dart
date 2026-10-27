import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

// ============================================================
// MODELS (the data, separate from the widgets)
// ============================================================

class Course {
  Course({
    required this.name,
    required this.day,
    required this.start,
    required this.end,
    this.category = 'Class',
  });

  String name;
  int day; // 0 = Monday ... 6 = Sunday
  int start; // minutes since midnight
  int end;
  String category;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'day': day,
      'start': start,
      'end': end,
      'category': category,
    };
  }

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      name: json['name'] as String,
      day: json['day'] as int,
      start: json['start'] as int,
      end: json['end'] as int,
      category: json['category'] as String,
    );
  }
}

class Task {
  Task({required this.title, this.daily = false, this.doneDate});

  String title;
  bool daily; // true = comes back every day
  String? doneDate; // the day it was ticked, e.g. "2026-10-14"

  Map<String, dynamic> toJson() {
    return {'title': title, 'daily': daily, 'doneDate': doneDate};
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      title: json['title'] as String,
      daily: json['daily'] as bool,
      doneDate: json['doneDate'] as String?,
    );
  }
}

class Research {
  Research({
    required this.topic,
    required this.detail,
    this.status = 'To find out',
  });

  String topic;
  String detail;
  String status;

  Map<String, dynamic> toJson() {
    return {'topic': topic, 'detail': detail, 'status': status};
  }

  factory Research.fromJson(Map<String, dynamic> json) {
    return Research(
      topic: json['topic'] as String,
      detail: json['detail'] as String,
      status: json['status'] as String,
    );
  }
}

// ============================================================
// SAVING (Part 2): one key per list, stored as JSON text
// ============================================================

Future<void> saveList(String key, List<Map<String, dynamic>> list) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(key, jsonEncode(list));
}

/// Returns the saved list, or null the very first time (nothing saved yet).
Future<List<Map<String, dynamic>>?> readList(String key) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(key);
  if (saved == null) return null;
  final list = jsonDecode(saved) as List;
  return list.map((x) => x as Map<String, dynamic>).toList();
}

// ============================================================
// LOOKS: colours and icons of each category / status
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
  if (parts.length != 2) return null; // "8h" has no colon
  if (parts[0].isEmpty || parts[0].length > 2) return null;
  if (parts[1].length != 2) return null; // minutes need 2 digits

  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null; // letters instead of numbers
  if (h < 0 || h > 23 || m < 0 || m > 59) return null; // "25:00", "10:75"

  return h * 60 + m;
}

/// 510 -> "08:30"
String formatTime(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// 210 -> "3h 30m", 120 -> "2h", 45 -> "45m"
String formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// A text for "today", used to know which tasks are ticked today.
String todayKey() {
  final n = DateTime.now();
  return '${n.year}-${n.month}-${n.day}';
}

// ============================================================
// RULES (functions outside build)
// ============================================================

/// Two blocks clash if they are on the same day and each starts
/// before the other ends. "<" and not "<=", so 11:00 end and
/// 11:00 start do NOT clash.
bool clashes(Course a, Course b) {
  return a.day == b.day && a.start < b.end && b.start < a.end;
}

/// Every other block that clashes with this one.
List<Course> clashingWith(Course course, List<Course> all) {
  return all.where((c) => c != course && clashes(course, c)).toList();
}

/// The blocks of one day, sorted by start time.
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

/// Work yields to class: when a class is added or moved, any work block
/// that overlaps it is shortened, split or removed. Returns true if
/// something changed.
bool makeRoomForClass(Course cls, List<Course> all) {
  bool changed = false;
  for (final w in List<Course>.from(all)) {
    if (w.category != 'Work' || !clashes(cls, w)) continue;
    changed = true;
    if (cls.start <= w.start && cls.end >= w.end) {
      all.remove(w); // the class covers all the work
    } else if (cls.start <= w.start) {
      w.start = cls.end; // the class cuts the beginning of the work
    } else if (cls.end >= w.end) {
      w.end = cls.start; // the class cuts the end of the work
    } else {
      // the class is in the middle: work before + work after
      all.add(Course(
        name: w.name,
        category: 'Work',
        day: w.day,
        start: cls.end,
        end: w.end,
      ));
      w.end = cls.start;
    }
  }
  return changed;
}

/// 0 or 1: which half of its column a clashing block takes in the grid,
/// so two clashing blocks sit side by side.
int clashSlot(Course c, List<Course> all) {
  final before = clashingWith(c, all).where((o) =>
  o.start < c.start ||
      (o.start == c.start && all.indexOf(o) < all.indexOf(c)));
  return before.length % 2;
}

// Small helpers to show messages
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

// ============================================================
// SAMPLE DATA (so the app is never empty on its first run)
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
    block('Work at school', 'Work', 1, '11:00', '17:00'), // after class
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
    block('Work at school', 'Work', 4, '11:30', '13:30'), // between classes
    block('INSY 8321 Data Structures', 'Class', 4, '13:30', '17:30'),
    block('Time with my man', 'Together', 4, '19:00', '21:00'),

    // ---------- Saturday ----------
    block('Sabbath rest', 'Sabbath', 5, '08:00', '18:00'),
    block('ME time', 'Me time', 5, '19:00', '21:00'),
    block('Call my man', 'Together', 5, '21:30', '22:00'),

    // ---------- Sunday ----------
    block('Personal project', 'Project', 6, '09:00', '12:00'),
    block('ME time', 'Me time', 6, '12:30', '14:00'),
    // DEMO CLASH (the brief needs one): this overlaps ME time by 30 min.
    // Edit ME time to end at 13:30 and the red disappears on both.
    block('Budget and savings', 'Money', 6, '13:30', '14:30'),
    block('Exam preparation', 'Revision', 6, '15:30', '17:30'),
    block('ACCT 8224 Accounting II', 'Class', 6, '18:00', '21:00'),
    block('Call my man', 'Together', 6, '21:30', '22:00'),
  ];
}

// ============================================================
// APP + BOTTOM NAVIGATION
// ============================================================

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Week',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps each tab alive, so nothing is lost when you switch.
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
  final List<Course> courses = sampleCourses();
  int selectedDay = DateTime.now().weekday - 1; // Monday is 1 in Dart
  bool gridView = false;

  @override
  void initState() {
    super.initState();
    loadCourses();
  }

  Future<void> saveCourses() {
    return saveList('courses', courses.map((c) => c.toJson()).toList());
  }

  Future<void> loadCourses() async {
    final saved = await readList('courses');
    if (saved == null || !mounted) return; // first time: keep the sample data
    setState(() {
      courses.clear();
      courses.addAll(saved.map(Course.fromJson));
    });
  }

  /// Opens the add/edit screen. existing == null means "add".
  void openCourse(Course? existing) {
    Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (context) => CourseScreen(
          course: existing,
          all: courses,
          initialDay: selectedDay,
        ),
      ),
    ).then((result) {
      if (result == null || !mounted) return; // back arrow pressed

      if (result == 'delete') {
        final removed = existing!;
        final position = courses.indexOf(removed);
        setState(() {
          courses.remove(removed);
        });
        saveCourses();
        sayWithUndo(context, '${removed.name} deleted', () {
          setState(() {
            courses.insert(position, removed);
          });
          saveCourses();
        });
        return;
      }

      if (result is Course) {
        bool trimmed = false;
        setState(() {
          if (existing == null) {
            courses.add(result);
          }
          if (result.category == 'Class') {
            trimmed = makeRoomForClass(result, courses);
          }
          selectedDay = result.day;
        });
        saveCourses();
        if (trimmed) {
          say(context, 'Work was shortened around your class');
        }
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
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => openCourse(null),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Week class time: ${formatDuration(classMinutes(courses))}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: gridView ? buildGrid() : buildList()),
        ],
      ),
    );
  }

  // ---------------- LIST VIEW ----------------
  Widget buildList() {
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
  Widget buildGrid() {
    const startHour = 7;
    const endHour = 23;
    const hourHeight = 48.0;
    const timeColWidth = 38.0;
    const totalHeight = (endHour - startHour) * hourHeight;
    final todayIndex = DateTime.now().weekday - 1;

    return Column(
      children: [
        // Legend: what each colour means
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
                  // Day names row
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
                  // The scrollable grid
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 80),
                      child: SizedBox(
                        height: totalHeight,
                        child: Stack(
                          children: [
                            // hour lines + hour labels
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
                            // vertical lines between days
                            for (int d = 0; d <= 7; d++)
                              Positioned(
                                left: timeColWidth + d * colWidth,
                                top: 0,
                                bottom: 0,
                                width: 1,
                                child: Container(color: Colors.grey.shade300),
                              ),
                            // the blocks
                            ...courses.map<Widget>((c) {
                              final s = c.start
                                  .clamp(startHour * 60, endHour * 60)
                                  .toInt();
                              final e = c.end
                                  .clamp(startHour * 60, endHour * 60)
                                  .toInt();
                              if (e <= s) return const SizedBox.shrink();

                              final hasClash = clashingWith(c, courses).isNotEmpty;
                              final color =
                                  categoryColors[c.category] ?? Colors.grey;
                              final textColor = color.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white;

                              // clashing blocks share the column (half each)
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
                                          ? Border.all(color: Colors.red, width: 2)
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

  void save() {
    final name = nameController.text.trim();
    final start = parseTime(startController.text);
    final end = parseTime(endController.text);

    // Every input is checked first. A refusal changes nothing.
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

    // Work never overlaps a class: when there is class, you do not work.
    if (category == 'Work') {
      final hit = widget.all.where((c) =>
      c != widget.course &&
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

    // Edit: change the same object. Add: make a new one.
    final result = widget.course ??
        Course(name: name, day: day, start: start, end: end, category: category);
    result.name = name;
    result.day = day;
    result.start = start;
    result.end = end;
    result.category = category;

    Navigator.pop(context, result);
  }

  void confirmDelete() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete this block?'),
          content: Text(widget.course!.name),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext); // close the dialog
                Navigator.pop(context, 'delete'); // go back with "delete"
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
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
              onPressed: confirmDelete,
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
          FilledButton(onPressed: save, child: const Text('Save')),
        ],
      ),
    );
  }
}

// ============================================================
// SCREEN 3: TODAY'S TASKS (daily checklist)
// ============================================================

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final List<Task> tasks = [
    Task(title: 'Revise my courses', daily: true),
    Task(title: 'Work on my personal project', daily: true),
    Task(title: 'Check my budget / save money', daily: true),
    Task(title: 'Check my body and mind', daily: true),
    Task(title: 'Take some ME time', daily: true),
    Task(title: 'Talk to my man before bed', daily: true),
  ];
  final controller = TextEditingController();
  bool repeatDaily = false;

  @override
  void initState() {
    super.initState();
    loadTasks();
  }

  Future<void> saveTasks() {
    return saveList('tasks', tasks.map((t) => t.toJson()).toList());
  }

  Future<void> loadTasks() async {
    final saved = await readList('tasks');
    if (saved == null || !mounted) return; // first time: keep the sample tasks
    setState(() {
      tasks.clear();
      tasks.addAll(saved.map(Task.fromJson));
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void addTask() {
    final title = controller.text.trim();
    if (title.isEmpty) {
      say(context, 'Write the task first');
      return;
    }
    if (tasks.any((t) => t.title.toLowerCase() == title.toLowerCase())) {
      say(context, '"$title" is already on your list');
      return;
    }
    setState(() {
      tasks.add(Task(title: title, daily: repeatDaily));
    });
    saveTasks();
    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final today = todayKey();
    final dayName = dayNames[DateTime.now().weekday - 1];

    // Daily tasks always show. One-time tasks show until they are done,
    // and stay for the rest of the day they were ticked.
    final shown = tasks
        .where((t) => t.daily || t.doneDate == null || t.doneDate == today)
        .toList();
    final doneCount = shown.where((t) => t.doneDate == today).length;
    final double progress = shown.isEmpty ? 0.0 : doneCount / shown.length;

    return Scaffold(
      appBar: AppBar(title: Text('Today · $dayName')),
      body: Column(
        children: [
          const KigaliWeatherTile(),
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
                LinearProgressIndicator(value: progress, minHeight: 12),
                if (shown.isNotEmpty && doneCount == shown.length)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('All done today. Rest well!'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('No tasks for today. Add one below.'))
                : ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final task = shown[index];
                final done = task.doneDate == today;

                return Dismissible(
                  key: ObjectKey(task),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red.shade200,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete),
                  ),
                  onDismissed: (_) {
                    final position = tasks.indexOf(task);
                    setState(() {
                      tasks.remove(task);
                    });
                    saveTasks();
                    sayWithUndo(context, '"${task.title}" deleted', () {
                      setState(() {
                        tasks.insert(position, task);
                      });
                      saveTasks();
                    });
                  },
                  child: CheckboxListTile(
                    value: done,
                    onChanged: (value) {
                      setState(() {
                        task.doneDate = (value ?? false) ? today : null;
                      });
                      saveTasks();
                    },
                    title: Text(
                      task.title,
                      style: TextStyle(
                        decoration:
                        done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: task.daily ? const Text('Every day') : null,
                    secondary: task.daily ? const Icon(Icons.repeat) : null,
                  ),
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
                IconButton(onPressed: addTask, icon: const Icon(Icons.add_circle)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SCREEN 4: RESEARCH BOARD (what I still have to find out)
// ============================================================

class ResearchScreen extends StatefulWidget {
  const ResearchScreen({super.key});

  @override
  State<ResearchScreen> createState() => _ResearchScreenState();
}

class _ResearchScreenState extends State<ResearchScreen> {
  final List<Research> items = [
    Research(
      topic: 'Masoro: own card printer',
      detail: 'How is Masoro going to get its own card printer?',
    ),
    Research(
      topic: 'Nursing emails',
      detail: 'Write what exactly I must find out.',
    ),
    Research(
      topic: 'Admission emails',
      detail: 'Write what exactly I must find out.',
    ),
    Research(
      topic: 'Gym information',
      detail: 'Write what exactly I must find out.',
    ),
    Research(
      topic: 'Student cards',
      detail: 'Write what exactly I must find out.',
    ),
  ];
  final topicController = TextEditingController();
  final detailController = TextEditingController();
  String filter = 'Open'; // Open, All or Done

  @override
  void initState() {
    super.initState();
    loadItems();
  }

  Future<void> saveItems() {
    return saveList('research', items.map((i) => i.toJson()).toList());
  }

  Future<void> loadItems() async {
    final saved = await readList('research');
    if (saved == null || !mounted) return; // first time: keep the sample items
    setState(() {
      items.clear();
      items.addAll(saved.map(Research.fromJson));
    });
  }

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

  void addItem() {
    final topic = topicController.text.trim();
    final detail = detailController.text.trim();
    if (topic.isEmpty) {
      say(context, 'Write the topic first');
      return;
    }
    if (items.any((i) => i.topic.toLowerCase() == topic.toLowerCase())) {
      say(context, '"$topic" is already on the board');
      return;
    }
    setState(() {
      items.add(Research(
        topic: topic,
        detail: detail.isEmpty ? 'Write what exactly I must find out.' : detail,
      ));
    });
    saveItems();
    topicController.clear();
    detailController.clear();
  }

  @override
  Widget build(BuildContext context) {
    // Built in status order, never changing the real list.
    final shown = [
      for (final s in statuses) ...items.where((i) => i.status == s && matchesFilter(i)),
    ];
    final openCount = items.where((i) => i.status != 'Done').length;

    return Scaffold(
      appBar: AppBar(title: const Text('To research')),
      body: Column(
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
                'Tap an item to move it to the next status. Swipe left to delete.',
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

                return Dismissible(
                  key: ObjectKey(item),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red.shade200,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete),
                  ),
                  onDismissed: (_) {
                    final position = items.indexOf(item);
                    setState(() {
                      items.remove(item);
                    });
                    saveItems();
                    sayWithUndo(context, '"${item.topic}" deleted', () {
                      setState(() {
                        items.insert(position, item);
                      });
                      saveItems();
                    });
                  },
                  child: Card(
                    child: ListTile(
                      title: Text(
                        item.topic,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(item.detail),
                      trailing: Chip(
                        label: Text(item.status),
                        backgroundColor: statusColors[item.status],
                      ),
                      onTap: () {
                        setState(() {
                          final next =
                              (statuses.indexOf(item.status) + 1) %
                                  statuses.length;
                          item.status = statuses[next];
                        });
                        saveItems();
                      },
                    ),
                  ),
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
// ============================================================
// LIVE WEATHER FROM AN API (loading, error and data states)
// ============================================================

String weatherWords(int code) {
  if (code == 0) return 'Clear sky';
  if (code <= 2) return 'Partly cloudy';
  if (code == 3) return 'Cloudy';
  if (code == 45 || code == 48) return 'Fog';
  if (code >= 51 && code <= 57) return 'Drizzle';
  if (code >= 61 && code <= 67) return 'Rain';
  if (code >= 80 && code <= 82) return 'Rain showers';
  if (code >= 95) return 'Thunderstorm';
  return 'Unknown';
}

IconData weatherIcon(int code) {
  if (code == 0) return Icons.wb_sunny;
  if (code <= 3) return Icons.cloud;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 95) return Icons.thunderstorm;
  if (code >= 51) return Icons.water_drop;
  return Icons.help_outline;
}

class KigaliWeatherTile extends StatefulWidget {
  const KigaliWeatherTile({super.key});

  @override
  State<KigaliWeatherTile> createState() => _KigaliWeatherTileState();
}

class _KigaliWeatherTileState extends State<KigaliWeatherTile> {
  bool loading = true; // state 1: loading
  String? error; // state 2: error
  double? temperature; // state 3: data
  int? code;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
            '?latitude=-1.9441&longitude=30.0619'
            '&current=temperature_2m,weather_code'
            '&timezone=Africa%2FKigali',
      );
      final response = await http.get(url);
      if (response.statusCode != 200) {
        throw Exception('The weather server answered ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        temperature = (current['temperature_2m'] as num).toDouble();
        code = (current['weather_code'] as num).toInt();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'Could not load the weather.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (loading) {
      content = const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Loading Kigali weather...'),
        ],
      );
    } else if (error != null) {
      content = Row(
        children: [
          const Icon(Icons.wifi_off),
          const SizedBox(width: 12),
          Expanded(child: Text(error!)),
          TextButton(onPressed: load, child: const Text('Retry')),
        ],
      );
    } else {
      content = Row(
        children: [
          Icon(weatherIcon(code!)),
          const SizedBox(width: 12),
          Text(
            'Kigali now: ${temperature!.round()}°C, ${weatherWords(code!)}',
          ),
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(padding: const EdgeInsets.all(12), child: content),
    );
  }
}