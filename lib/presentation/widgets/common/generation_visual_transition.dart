import 'package:flutter/material.dart';

import '../../themes/theme_extension.dart';

class GenerationVisualTransition extends StatelessWidget {
  const GenerationVisualTransition({
    super.key,
    required this.stage,
    required this.child,
  });

  final Object stage;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = Theme.of(context).appTheme;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : motion.slowDuration,
      switchInCurve: motion.standardCurve,
      switchOutCurve: motion.standardCurve,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          for (final outgoing in previous)
            IgnorePointer(child: ExcludeSemantics(child: outgoing)),
          if (current != null) current,
        ],
      ),
      child: KeyedSubtree(key: ValueKey(stage), child: child),
    );
  }
}
