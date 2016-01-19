part of dartregistry.common;

class CommonInternal {
  static ClassDescriptor newClassDescriptor(Type type, String simpleName,
          String qualifiedName, List annotations) =>
      new ClassDescriptor._(type, simpleName, qualifiedName, annotations);

  static MethodDescriptor newMethodDescriptor(
          ClassDescriptor classDescriptor, String name, int parameterCount, List annotations) =>
      new MethodDescriptor._(classDescriptor, name, parameterCount, annotations);
}
