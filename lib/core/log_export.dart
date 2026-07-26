import 'dart:convert';
import 'dart:io';

/// Writes an easy-to-share, timestamped text snapshot of the in-app logs.
Future<File> writeLogExport({
  required Directory directory,
  required List<String> logs,
  DateTime? now,
}) async {
  final timestamp = now ?? DateTime.now();
  final stamp = '${timestamp.year.toString().padLeft(4, '0')}'
      '${timestamp.month.toString().padLeft(2, '0')}'
      '${timestamp.day.toString().padLeft(2, '0')}-'
      '${timestamp.hour.toString().padLeft(2, '0')}'
      '${timestamp.minute.toString().padLeft(2, '0')}'
      '${timestamp.second.toString().padLeft(2, '0')}';
  await directory.create(recursive: true);
  final file = File('${directory.path}${Platform.pathSeparator}ForgeVPN-$stamp.txt');
  final content = StringBuffer()
    ..writeln('Forge VPN 日志')
    ..writeln('导出时间：${timestamp.toIso8601String()}')
    ..writeln()
    ..write(logs.join('\n'));
  return file.writeAsString(content.toString(), encoding: utf8, flush: true);
}
