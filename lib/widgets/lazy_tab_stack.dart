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
  late final Set<int> _built = {widget.index};

  @override
  void didUpdateWidget(LazyTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_built.add(widget.index)) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final order = _built.toList()..sort();
    return Stack(
      children: [
        for (final i in order)
          Offstage(
            offstage: i != widget.index,
            child: widget.builders[i](),
          ),
      ],
    );
  }
}
