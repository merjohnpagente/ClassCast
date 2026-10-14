import 'package:flutter/foundation.dart';

import '../models/doc_types.dart';
import '../models/shared_document.dart';
import '../services/document_service.dart';

/// Teacher document library: pick, search, filter, share-target.
class LibraryProvider extends ChangeNotifier {
  final DocumentService _docs = DocumentService();

  List<SharedDocument> _items = [];
  List<SharedDocument> get items => List.unmodifiable(_items);

  String _query = '';
  String get query => _query;

  DocKind? _filter;
  DocKind? get filter => _filter;

  SharedDocument? _selected;
  SharedDocument? get selected => _selected;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  String? _error;
  String? get error => _error;

  /// Start with an empty library; real files arrive via the file picker.
  void load() {
    _items = [];
    _loaded = true;
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void setFilter(DocKind? kind) {
    _filter = kind;
    notifyListeners();
  }

  void select(SharedDocument doc) {
    _selected = doc;
    notifyListeners();
  }

  void clearSelection() {
    _selected = null;
    notifyListeners();
  }

  void updateStatus(String id, DocStatus status) {
    _items = _items
        .map((d) => d.id == id ? d.copyWith(status: status) : d)
        .toList();
    if (_selected?.id == id) {
      _selected = _selected!.copyWith(status: status);
    }
    notifyListeners();
  }

  Future<bool> pickAndAdd() async {
    _error = null;
    final doc = await _docs.pickSingle();
    if (doc == null) return false;
    if (doc.kind == DocKind.unknown) {
      _error = 'Unsupported file format.';
      notifyListeners();
      return false;
    }
    _items = [doc, ..._items];
    _selected = doc;
    notifyListeners();
    return true;
  }

  Future<int> pickManyAndAdd() async {
    _error = null;
    final docs = await _docs.pickMultiple();
    final good = docs.where((d) => d.kind != DocKind.unknown).toList();
    if (good.isEmpty && docs.isNotEmpty) {
      _error = 'Unsupported file format.';
      notifyListeners();
      return 0;
    }
    _items = [...good, ..._items];
    notifyListeners();
    return good.length;
  }

  void remove(String id) {
    _items = _items.where((d) => d.id != id).toList();
    if (_selected?.id == id) _selected = null;
    notifyListeners();
  }

  List<SharedDocument> get visible {
    Iterable<SharedDocument> out = _items;
    if (_filter != null) {
      out = out.where((d) => d.kind == _filter);
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((d) =>
          d.name.toLowerCase().contains(q) ||
          d.extension.toLowerCase().contains(q));
    }
    return out.toList();
  }
}
