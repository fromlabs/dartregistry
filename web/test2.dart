import "dart:async";

@GlobalQuantifyCapability(r"^dart.async.Future$", injectable)
import 'package:reflectable/reflectable.dart';

class Injectable extends Reflectable {
  const Injectable()
/*
      : super(metadataCapability, declarationsCapability, invokingCapability,
            typeRelationsCapability);
*/
      : super.fromList(const [
    metadataCapability,
    typeRelationsCapability,
    declarationsCapability,
    invokingCapability,
    subtypeQuantifyCapability,
    superclassQuantifyCapability,
    admitSubtypeCapability,
//    typeAnnotationQuantifyCapability,

    instanceInvokeCapability,
    staticInvokeCapability,
    topLevelInvokeCapability,
    newInstanceCapability,
    nameCapability,
    classifyCapability,
    typeCapability,
    reflectedTypeCapability,
    libraryCapability,
    uriCapability,
    libraryDependenciesCapability,
    typingCapability,
    delegateCapability,
    correspondingSetterQuantifyCapability,

//    typeAnnotationDeepQuantifyCapability,
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


class B {}

@injectable
class MixinB {
}

class BB extends B with MixinB {}

class BBB extends BB {}

class BBb extends BBB {}

class C {}

@injectable
class MixinC {
}

class CC extends C with MixinC {}

class CCC extends CC {}

class CCb extends CCC {}

typedef T ProviderFunction<T>();

class A {
  @inject
  Provider<B> a1;

  @inject
  Provider<Future<C>> a2;
}

@injectable
class MixinA {
  @inject
  Provider<BBb> a3b;

  @inject
  Provider<Future<CCb>> a4b;
}

class AA extends A with MixinA {
  @inject
  Provider<BB> a3;

  @inject
  Provider<Future<CC>> a4;
}

class AAA extends AA {
  @inject
  Provider<BBB> a5;

  @inject
  Provider<Future<CCC>> a6;

  @inject
  CCCProvider a7;
}

class CCCProvider extends Provider<CCC> {

  @override
  CCC get() => new CCC();
}

main() {
  // A x = new A();
  // AA x = new AA();
  AAA x = new AAA();

  var classMirror = injectable.reflect(x).type;

  print(classMirror);

  print(classMirror.newInstance("", []));

  print(classMirror.superclass.superclass.declarations);

  while (classMirror != null) {
    classMirror.declarations.forEach((name, DeclarationMirror mirror) {
      if (mirror is VariableMirror) {
        print("Variable: $name");

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

    classMirror = classMirror.superclass;
  }
}
