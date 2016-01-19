library dartregistry.module;

import "package:reflectable/reflectable.dart";

import "common.dart";
import "annotations.dart";
import "logging.dart";
import "registry.dart";

part "internal/module.dart";

@injectable
abstract class RegistryModule extends Loggable {
  Map<Type, ProviderBinding> _bindings;

  void configure();

  void unconfigure() {}

  void onBindingAdded(Type clazz) {}

  void bindInstance(Type clazz, instance) {
    _addProviderBinding(
        clazz,
        new ProviderBinding(
            clazz, Scope.ISOLATE, new ToInstanceProvider(instance)));
  }

  void bindClass(Type clazz, Scope scope, [Type clazzImpl]) {
    clazzImpl = clazzImpl != null ? clazzImpl : clazz;
    _addProviderBinding(
        clazz,
        new ProviderBinding(
            clazz,
            scope,
            new ToClassProvider(clazzImpl,
                (RegistryInternal.getTypeMirror(clazzImpl) as ClassMirror))));
  }

  void bindProvideFunction(
      Type clazz, Scope scope, ProvideFunction provideFunction) {
    _addProviderBinding(
        clazz,
        new ProviderBinding(
            clazz, scope, new ToFunctionProvider(provideFunction)));
  }

  void bindProvider(Type clazz, Scope scope, Provider provider) {
    _addProviderBinding(clazz, new ProviderBinding(clazz, scope, provider));
  }

  void _configure() {
    _bindings = {};

    configure();
  }

  void _unconfigure() {
    unconfigure();

    _bindings.clear();
    _bindings = null;
  }

  void _addProviderBinding(Type clazz, ProviderBinding binding) {
    _bindings[clazz] = binding;

    onBindingAdded(clazz);
  }

  ProviderBinding _getProviderBinding(Type clazz) => _bindings[clazz];
}
