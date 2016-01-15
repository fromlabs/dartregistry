import "dart:async";

@GlobalQuantifyCapability(
    r"^dart.async.Future$", injectable)
import 'package:reflectable/reflectable.dart';

class Injectable extends Reflectable {
  const Injectable()
      : super.fromList(const [
          metadataCapability,
          declarationsCapability,
          invokingCapability,
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
class B {
}

@injectable
class C {
}

@injectable
class D {
}

typedef T ProviderFunction<T>();

@injectable
class A {

  @inject
  Provider<B> a2;

  @inject
  Provider<Future<C>> a3;

  // @inject
  // ProviderFunction<D> a4;
}

main() {
  A x = new A();

  // print(injectable.annotatedClasses);
  // print(inject.annotatedClasses);

  InstanceMirror instanceMirror = injectable.reflect(x);

  print(instanceMirror);

  print(instanceMirror.type);

  print(instanceMirror.type.declarations);

  instanceMirror.type.declarations.forEach((name, DeclarationMirror mirror) {
    if (mirror is VariableMirror) {
      print(name);

      print("VariableMirror");

      print(mirror.metadata);

      if (mirror.metadata.contains(inject)) {
        print("Inject");

        var variableType = mirror.type;
        print(variableType);

        if (variableType is ClassMirror) {
          if (variableType.isSubclassOf(injectable.reflectType(Provider))) {
            print("Inject Provider");

            print(variableType.typeArguments);

            if (variableType.typeArguments.length == 1 &&
                variableType.typeArguments.first is ClassMirror) {
              ClassMirror typeMirror = variableType.typeArguments.first;

              if (typeMirror.isSubclassOf(injectable.reflectType(Future))) {
                print("Inject Provider<Future>");

                if (typeMirror.typeArguments.length == 1 &&
                    variableType.typeArguments.first is ClassMirror) {
                  typeMirror = typeMirror.typeArguments[0];
                } else {
                  throw new ArgumentError();
                }
              }

              print("---> ${typeMirror.simpleName}");
            } else {
              throw new ArgumentError();
            }
          } else {
            throw new UnimplementedError();
          }
        } else if (variableType is TypedefMirror) {
          throw new UnimplementedError();
        } else {
          throw new UnsupportedError("Injection not supported");
        }
      }
    }
  });
}
