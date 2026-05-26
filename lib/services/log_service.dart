import 'dart:async';

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
    _lines.add('[${_ts()}] $line');
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    if (!_controller.isClosed) _controller.add(List.unmodifiable(_lines));
    _autoClear();
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
