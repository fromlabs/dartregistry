import 'package:reflectable/reflectable.dart';

// Annotate with this class to enable reflection.
class Reflector extends Reflectable {
  const Reflector()
      : super(invokingCapability); // Request the capability to invoke methods.
}

const reflector = const Reflector();

@reflector // This annotation enables reflection on A.
class A {
  final int a;
  A(this.a);
  greater(int x) => x > a;
  lessEqual(int x) => x <= a;
}

main() {
  A x = new A(10);
  // Reflect upon [x] using the const instance of the reflector:
  InstanceMirror instanceMirror = reflector.reflect(x);
  int weekday = new DateTime.now().weekday;
  // On Fridays we test if 3 is greater than 10, on other days if it is less
  // than or equal.
  String methodName = weekday == DateTime.FRIDAY ? "greater" : "lessEqual";
  // Reflectable invocation:
  print(instanceMirror.invoke(methodName, [3]));
}
