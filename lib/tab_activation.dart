// The home shell keeps every tab alive in an IndexedStack, so a tab's
// stores go stale while it is hidden. Becoming the visible tab again — not
// being rebuilt — is the reload signal. This mixin owns that rising-edge
// check once, so each tab screen only states WHAT to reload and the rule
// cannot drift between tabs.

import 'package:flutter/widgets.dart';

mixin TabActivationAware<T extends StatefulWidget> on State<T> {
  /// Reads [widget]'s isActive flag — the mixin cannot name the field on a
  /// generic widget, so each screen points it there in one line.
  bool isActiveOf(T widget);

  /// The tab just became the visible one; reload whatever another tab's
  /// flows may have changed.
  void onTabActivated();

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (isActiveOf(widget) && !isActiveOf(oldWidget)) {
      onTabActivated();
    }
  }
}
