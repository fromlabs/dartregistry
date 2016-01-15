import "dart:async";

@GlobalQuantifyCapability(
    r"^dart.async.Future$", injectable)
import 'package:reflectable/reflectable.dart';

class Injectable extends Reflectable {
  const Injectable()
      : super.fromList(const [
//          instanceInvokeCapability,
//          staticInvokeCapability,
//          topLevelInvokeCapability,
//          newInstanceCapability,
//          nameCapability,
//          classifyCapability,
          metadataCapability,
//          typeCapability,
//          typeRelationsCapability,
//          reflectedTypeCapability,
//          libraryCapability,
          declarationsCapability,
//          uriCapability,
//          libraryDependenciesCapability,
          invokingCapability,
//          typingCapability,
//          delegateCapability,
//          subtypeQuantifyCapability,
//          superclassQuantifyCapability,
          typeAnnotationQuantifyCapability,
//          typeAnnotationDeepQuantifyCapability,
//          correspondingSetterQuantifyCapability,
//          admitSubtypeCapability
        ]);
}

const Injectable injectable = const Injectable();

class Inject {
  const Inject();
}

const Inject inject = const Inject();

@injectable
abstract class Provider<T> {
  T get();
}

@injectable
class A {

  String a0;

  int a1;

  Provider<String> a2;

  Provider<List> a3;

  Provider<List<String>> a4;

  Provider<Future> a5;

  Future a6;

  // File a7;
}

main() {
  A x = new A();

  InstanceMirror instanceMirror = injectable.reflect(x);

  print(instanceMirror);

  VariableMirror mirror = instanceMirror.type.declarations["a5"];
  print(mirror);

  print(mirror.location);

  ClassMirror variableType = mirror.type;
  print(variableType);

  print(variableType.declarations);

  print(variableType.typeArguments);
}
