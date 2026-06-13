import 'package:flutter/foundation.dart';

class MultiSelectController<T> extends ChangeNotifier {
  final Set<T> _selectedItems = {};
  bool _isMultiSelectMode = false;
  T? _lastSelectedItem;

  bool get isMultiSelectMode => _isMultiSelectMode;
  Set<T> get selectedItems => Set.unmodifiable(_selectedItems);
  int get selectedCount => _selectedItems.length;
  bool get hasSelection => _selectedItems.isNotEmpty;

  bool isSelected(T item) => _selectedItems.contains(item);

  void enterMultiSelectMode() {
    _isMultiSelectMode = true;
    notifyListeners();
  }

  void exitMultiSelectMode() {
    _isMultiSelectMode = false;
    _selectedItems.clear();
    _lastSelectedItem = null;
    notifyListeners();
  }

  void toggleSelection(T item) {
    if (!_isMultiSelectMode) {
      enterMultiSelectMode();
    }
    if (_selectedItems.contains(item)) {
      _selectedItems.remove(item);
    } else {
      _selectedItems.add(item);
    }
    _lastSelectedItem = item;
    notifyListeners();
  }

  void selectRange(T fromItem, List<T> allItems) {
    if (!_isMultiSelectMode) {
      enterMultiSelectMode();
    }
    final fromIndex = allItems.indexOf(fromItem);
    final lastSelected = _lastSelectedItem;
    final toIndex = lastSelected != null
        ? allItems.indexOf(lastSelected)
        : fromIndex;

    if (fromIndex < 0 || toIndex < 0) return;

    final start = fromIndex < toIndex ? fromIndex : toIndex;
    final end = fromIndex < toIndex ? toIndex : fromIndex;

    for (int i = start; i <= end; i++) {
      _selectedItems.add(allItems[i]);
    }
    _lastSelectedItem = fromItem;
    notifyListeners();
  }

  void selectAll(List<T> items) {
    if (!_isMultiSelectMode) {
      enterMultiSelectMode();
    }
    _selectedItems.addAll(items);
    notifyListeners();
  }

  void invertSelection(List<T> pageItems) {
    if (!_isMultiSelectMode) {
      enterMultiSelectMode();
    }
    for (final item in pageItems) {
      if (_selectedItems.contains(item)) {
        _selectedItems.remove(item);
      } else {
        _selectedItems.add(item);
      }
    }
    notifyListeners();
  }
}
