import 'dart:async';

// лог только в памяти (последние _maxLines строк) - в файл НЕ пишем: плейнтекст
// история соединений на диске для privacy-продукта неприемлема
class LogService {
  static final LogService _instance = LogService._();
  factory LogService() => _instance;
  LogService._() {
    Timer.periodic(const Duration(hours: 1), (_) => _autoClear());
  }

  static const _maxLines = 2000;

  final _lines = <String>[];
  final _controller = StreamController<List<String>>.broadcast();
  DateTime _lastClear = DateTime.now();

  Stream<List<String>> get stream => _controller.stream;
  List<String> get lines => List.unmodifiable(_lines);

  void add(String line) {
    if (line.isEmpty) return;
    final entry = '[${_ts()}] $line';
    _lines.add(entry);
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    if (!_controller.isClosed) _controller.add(List.unmodifiable(_lines));
  }

  void clear() {
    _lines.clear();
    _lastClear = DateTime.now();
    if (!_controller.isClosed) _controller.add(const []);
  }

  void _autoClear() {
    if (DateTime.now().difference(_lastClear).inHours >= 24) clear();
  }

  static String _ts() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:${n.second.toString().padLeft(2, '0')}';
  }
}
