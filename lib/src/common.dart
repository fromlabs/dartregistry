library dartregistry.common;

import "annotations.dart";

part "internal/common.dart";

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

  String toString() => id;
}

class ClassDescriptor {
  final Type type;

  final String simpleName;

  final String qualifiedName;

  List annotations;

  ClassDescriptor._(
      this.type, this.simpleName, this.qualifiedName, this.annotations);

  String toString() => qualifiedName;
}

class MethodDescriptor {
  final ClassDescriptor classDescriptor;

  final String name;

  final List annotations;

  final int parametersCount;

  MethodDescriptor._(
      this.classDescriptor, this.name, this.parametersCount, this.annotations);

  String toString() => "$classDescriptor.$name";
}
