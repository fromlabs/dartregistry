part of dartregistry.module;

class RegistryModuleInternal {
  static Map<Type, ProviderBinding> getBindings(RegistryModule module) =>
      module?._bindings;

  static void addProviderBinding(
          RegistryModule module, Type clazz, ProviderBinding binding) =>
      module._addProviderBinding(clazz, binding);

  static ProviderBinding getProviderBinding(
          RegistryModule module, Type clazz) =>
      module._getProviderBinding(clazz);
}

class BindingListeners {
  final Provider provider;
  final List<String> providerListeners = [];
  final List<String> instanceListeners = [];

  BindingListeners(this.provider);
}

class ProviderBinding {
  final Type clazz;
  final Scope scope;
  final Provider provider;

  ProviderBinding(this.clazz, this.scope, this.provider);
}

@injectable
class ToFunctionProvider<T> extends Provider<T> {
  final ProvideFunction<T> function;

  ToFunctionProvider(this.function);

  T get() => function();
}

@injectable
class ToClassProvider<T> extends Provider<T> {
  final Type clazz;
  final ClassMirror classMirror;

  ToClassProvider(this.clazz, this.classMirror);

  T get() => classMirror.newInstance("", []);
}

@injectable
class ToInstanceProvider<T> extends Provider<T> {
  final T instance;

  ToInstanceProvider(this.instance);

  T get() => this.instance;
}
