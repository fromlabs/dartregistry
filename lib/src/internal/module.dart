part of dartregistry.module;

class RegistryModuleInternal {
  Map<Type, ProviderBinding> getBindings(RegistryModule module) =>
      module._bindings;

  void addProviderBinding(
          RegistryModule module, Type clazz, ProviderBinding binding) =>
      module._addProviderBinding(clazz, binding);

  ProviderBinding getProviderBinding(RegistryModule module, Type clazz) =>
      module.getProviderBinding(clazz);
}
