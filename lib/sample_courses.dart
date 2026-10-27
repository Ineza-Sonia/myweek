import 'package:myweek/time_utils.dart';
import 'course.dart';

List<Course> sampleCourses() {
  return [
    Course(name: 'INSY 8413 Big Data', day: 1,
        start: parseTime('08:00')!, end: parseTime('11:00')!),
    Course(name: 'Work at school', day: 1,
        start: parseTime('09:00')!, end: parseTime('17:00')!),
    Course(name: 'INSY 8211 Computer Networks', day: 3,
        start: parseTime('18:00')!, end: parseTime('22:00')!),
    Course(name: 'ENGL 8221 English', day: 4,
        start: parseTime('08:30')!, end: parseTime('11:30')!),
    Course(name: 'INSY 8321 Data Structures', day: 4,
        start: parseTime('13:30')!, end: parseTime('17:30')!),
    Course(name: 'ACCT 8224 Accounting II', day: 6,
        start: parseTime('18:00')!, end: parseTime('21:00')!),
  ];
}