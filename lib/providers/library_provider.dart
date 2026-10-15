import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/doc_types.dart';
import '../models/shared_document.dart';
import '../services/document_service.dart';
import '../services/library_store.dart';

/// Teacher document library: pick, search, filter, share-target.
class LibraryProvider extends ChangeNotifier {
  final DocumentService _docs = DocumentService();
  final LibraryStore _store = LibraryStore();

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

  /// Restore the library saved on this device.
  ///
  /// Was empty on every start, which meant a session could not be revived
  /// "with its document" and the teacher had to re-pick the file each lesson.
  /// Entries whose file has been cleared from the cache are pruned here rather
  /// than left in the list to fail when tapped.
  Future<void> load() async {
    try {
      _items = await _store.pruneMissing();
      _error = null;
    } on LibraryReadException {
      // A store that cannot be read is not an empty library. Say so, so the
      // teacher does not re-pick files they already have.
      _error = 'The saved library could not be read on this device.';
    }
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
    final SharedDocument? doc;
    try {
      doc = await _docs.pickSingle();
    } on FilePickException catch (e) {
      // Silent before: the teacher tapped Add, nothing happened, and a denied
      // storage permission looked exactly like a cancelled picker.
      _error = e.message;
      notifyListeners();
      return false;
    }
    if (doc == null) return false;
    if (doc.kind == DocKind.unknown) {
      _error = 'Unsupported file format.';
      notifyListeners();
      return false;
    }
    _items = [doc, ..._items];
    _selected = doc;
    notifyListeners();
    try {
      await _store.save(doc);
    } catch (e) {
      // It is in the list but not on disk, so it will not survive a restart.
      _error = 'Added, but could not be saved: it may be gone after restart.';
      notifyListeners();
    }
    return true;
  }

  Future<int> pickManyAndAdd() async {
    _error = null;
    final List<SharedDocument> docs;
    try {
      docs = await _docs.pickMultiple();
    } on FilePickException catch (e) {
      _error = e.message;
      notifyListeners();
      return 0;
    }
    final good = docs.where((d) => d.kind != DocKind.unknown).toList();
    if (good.isEmpty && docs.isNotEmpty) {
      _error = 'Unsupported file format.';
      notifyListeners();
      return 0;
    }
    _items = [...good, ..._items];
    notifyListeners();
    try {
      await _store.saveAll(good);
    } catch (e) {
      _error = 'Added, but could not be saved: they may be gone after '
          'restart.';
      notifyListeners();
    }
    return good.length;
  }

  void remove(String id) {
    _items = _items.where((d) => d.id != id).toList();
    if (_selected?.id == id) _selected = null;
    notifyListeners();
    unawaited(_store.remove(id));
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
