library dartregistry.common;

import "annotations.dart";

typedef ScopeRunnable();

typedef T ProvideFunction<T>();

@injectable
abstract class Provider<T> {
  T get();
}

class Scope {
  static const Scope NONE = const Scope("NONE");
  static const Scope ISOLATE = const Scope("ISOLATE");

  final String id;

  const Scope(this.id);

  String toString() => this.id;
}
