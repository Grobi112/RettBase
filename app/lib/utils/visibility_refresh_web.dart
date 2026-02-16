import 'dart:html' as html;

final List<void Function()> _visibleCallbacks = [];
bool _listenerAdded = false;

void setOnVisible(void Function() callback) {
  if (!_visibleCallbacks.contains(callback)) _visibleCallbacks.add(callback);
  if (!_listenerAdded) {
    _listenerAdded = true;
    html.document.addEventListener('visibilitychange', (_) {
      if (html.document.visibilityState == 'visible') {
        for (final cb in List<void Function()>.from(_visibleCallbacks)) {
          try {
            cb();
          } catch (_) {}
        }
      }
    });
  }
}

void removeOnVisible(void Function() callback) {
  _visibleCallbacks.remove(callback);
}
