import 'package:flutter/material.dart';

/// A tab stack that builds a tab the first time it is opened, and keeps it
/// alive after that.
///
/// An [IndexedStack] builds every child on the first frame, so entering the
/// shell ran `initState` on every screen at once: two database reads, two
/// network probes and the whole settings screen, before the teacher had tapped
/// anything. State is still preserved — that is what the [Offstage] is for —
/// the difference is only when a tab is first built.
class LazyTabStack extends StatefulWidget {
  final int index;

  /// One builder per tab, called the first time that tab is opened.
  final List<Widget Function()> builders;

  const LazyTabStack({
    super.key,
    required this.index,
    required this.builders,
  }) : assert(builders.length > 0);

  @override
  State<LazyTabStack> createState() => _LazyTabStackState();
}

class _LazyTabStackState extends State<LazyTabStack> {
  /// One slot per tab, filled the first time that tab is opened and never
  /// replaced.
  ///
  /// The builders were re-invoked on every build before. That sounds harmless
  /// until you notice who rebuilds: the student shell watches the whole
  /// `SyncProvider`, so every single socket frame — every page change, every
  /// raised hand — rebuilt the shell, which re-ran all three builders and gave
  /// the viewer a brand new widget instance. Four rebuilds per frame, one of
  /// them the document. Holding the instance means a parent rebuild hands the
  /// same widget down and `updateChild`'s identity check skips the subtree.
  final List<Widget?> _slots = [];

  @override
  void initState() {
    super.initState();
    _slots.length = widget.builders.length;
    _fill(widget.index);
  }

  @override
  void didUpdateWidget(LazyTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.builders.length != _slots.length) {
      _slots.length = widget.builders.length;
    }
    _fill(widget.index);
  }

  /// Builds [tab] if it has never been built. No `setState`: this runs from
  /// `build` and from `didUpdateWidget`, both of which are already rebuilding.
  void _fill(int tab) {
    if (tab < 0 || tab >= _slots.length) return;
    if (_slots[tab] != null) return;
    _slots[tab] = widget.builders[tab]();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var i = 0; i < _slots.length; i++)
          if (_slots[i] case final Widget child)
            Offstage(offstage: i != widget.index, child: child),
      ],
    );
  }
}
