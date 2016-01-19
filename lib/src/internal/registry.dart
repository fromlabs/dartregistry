part of dartregistry.registry;

class RegistryInternal {
  static TypeMirror getTypeMirror(Type clazz) => Registry._singleton._getTypeMirror(clazz);
}
