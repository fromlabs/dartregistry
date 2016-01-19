library dartregistry.module;

import "dart:async";

import "package:reflectable/reflectable.dart";

import "common.dart";
import "annotations.dart";
import "logging.dart";
import "registry.dart";

part "internal/module.dart";

@injectable
abstract class RegistryModule extends Loggable {
  Map<Type, ProviderBinding> _bindings;

  Future configure() async {
    _bindings = {};
  }

  Future unconfigure() async {
    _bindings.clear();
    _bindings = null;
  }

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

  void _addProviderBinding(Type clazz, ProviderBinding binding) {
    _bindings[clazz] = binding;

    onBindingAdded(clazz);
  }

  ProviderBinding _getProviderBinding(Type clazz) => _bindings[clazz];
}
