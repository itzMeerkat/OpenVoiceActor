/// Base for controllers. Screens listen and rebuild; this package can't use
/// Flutter's ChangeNotifier, which is what keeps it free of UI code.
class Notifier {
  final _listeners = <void Function()>[];

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void notifyListeners() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}
