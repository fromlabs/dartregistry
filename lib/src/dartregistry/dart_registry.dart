library dartregistry.dartregistry;

import "dart:async";

import "package:logging/logging.dart";
import "package:stack_trace/stack_trace.dart";

@GlobalQuantifyCapability(r"^dart.async.Future$", injectable)
import 'package:reflectable/reflectable.dart';

final Logger _libraryLogger = new Logger("dartregistry");

const String _FUTURE_TYPE_NAME = "dart.core.Future";
const String _PROVIDER_TYPE_NAME = "dartregistry.dartregistry.Provider";
const String _FUNCTION_PROVIDER_TYPE_NAME =
    "dartregistry.dartregistry.ProvideFunction";

const InjectionModule injectionModule = const InjectionModule();
const Injectable injectable = const Injectable();
const Inject inject = const Inject();

class InjectionModule extends Reflectable {
  const InjectionModule() : super(newInstanceCapability);
}

class Injectable extends Reflectable {
  const Injectable()
      : super(
            metadataCapability,
            typeRelationsCapability,
            declarationsCapability,
            instanceInvokeCapability,
            newInstanceCapability);
}

@injectable
class Inject {
  final Type type;

  const Inject([this.type]);
}

const onScopeOpened = const OnScopeOpened();
const onScopeClosing = const OnScopeClosing();

@injectable
class OnScopeOpened {
  const OnScopeOpened();
}

@injectable
class OnScopeClosing {
  const OnScopeClosing();
}

const onBind = const OnBind();
const onUnbinding = const OnUnbinding();

@injectable
class OnBind {
  const OnBind();
}

@injectable
class OnUnbinding {
  const OnUnbinding();
}

const onProvidedBind = const OnProvidedBind();
const onProvidedUnbinding = const OnProvidedUnbinding();

@injectable
class OnProvidedBind {
  const OnProvidedBind();
}

@injectable
class OnProvidedUnbinding {
  const OnProvidedUnbinding();
}

typedef T ProvideFunction<T>();

typedef ScopeRunnable();

void logReflector(Reflectable reflector) {
  _libraryLogger.finest("******************************");
  _libraryLogger.fine(
      "Annotated classes of $reflector: ${reflector.annotatedClasses.length}");
  for (var i = 0; i < reflector.annotatedClasses.length; i++) {
    try {
      var mirror = reflector.annotatedClasses.elementAt(i);

      _libraryLogger.finest(mirror.qualifiedName);
    } on NoSuchCapabilityError catch (e) {
      _libraryLogger.warning("Skip class", e);
    }
  }
  _libraryLogger.finest("******************************");
}

@injectable
abstract class Provider<T> {
  T get();
}

class Scope {
  static const Scope NONE = const Scope("NONE");
  static const Scope ISOLATE = const Scope("ISOLATE");

  final String id;

  const Scope(this.id);

  String toString() => this.id;
}

@injectionModule
abstract class RegistryModule {
  Map<Type, _ProviderBinding> _bindings;

  Future configure(Map<String, dynamic> parameters) async {
    _bindings = {};
  }

  Future unconfigure() async {
    _bindings.clear();
    _bindings = null;
  }

  void bindInstance(Type clazz, instance) {
    _addProviderBinding(
        clazz,
        new _ProviderBinding(
            clazz, Scope.ISOLATE, new ToInstanceProvider(instance)));
  }

  void bindClass(Type clazz, Scope scope, [Type clazzImpl]) {
    clazzImpl = clazzImpl != null ? clazzImpl : clazz;
    _addProviderBinding(clazz,
        new _ProviderBinding(clazz, scope, new ToClassProvider(clazzImpl)));
  }

  void bindProvideFunction(
      Type clazz, Scope scope, ProvideFunction provideFunction) {
    _addProviderBinding(
        clazz,
        new _ProviderBinding(
            clazz, scope, new ToFunctionProvider(provideFunction)));
  }

  void bindProvider(Type clazz, Scope scope, Provider provider) {
    _addProviderBinding(clazz, new _ProviderBinding(clazz, scope, provider));
  }

  void _addProviderBinding(Type clazz, _ProviderBinding binding) {
    _bindings[clazz] = binding;

    onBindingAdded(clazz);
  }

  void onBindingAdded(Type clazz) {}

  _ProviderBinding _getProviderBinding(Type clazz) => _bindings[clazz];
}

class Registry {
  static const _SCOPE_CONTEXT_HOLDER = "_SCOPE_CONTEXT_HOLDER";

  static RegistryModule _MODULE;

  static _ScopeContext _ISOLATE_SCOPE_CONTEXT;

  static Map<Type, ProvideFunction> _SCOPED_PROVIDERS_CACHE;

  static Future load(Type moduleClazz,
      [Map<String, dynamic> parameters = const {}]) async {
    _libraryLogger.finest("Load registry module");

    logReflector(injectable);

    var module = (injectionModule.reflectType(moduleClazz) as ClassMirror)
        .newInstance("", []);

    if (module is! RegistryModule) {
      throw new ArgumentError("$moduleClazz is not a registry module");
    }

    _MODULE = module;

    _SCOPED_PROVIDERS_CACHE = {};

    await _MODULE.configure(parameters);

    _injectProviders();
  }

  static Future unload() async {
    _libraryLogger.finest("Unload module");

    try {
      await _MODULE.unconfigure();
    } finally {
      _MODULE = null;
      _SCOPED_PROVIDERS_CACHE = null;
    }
  }

  static Future openScope(Scope scope) async {
    _libraryLogger.finest("Open scope $scope");

    if (scope == Scope.NONE) {
      throw new ArgumentError("Can't open scope context ${Scope.NONE}");
    }

    var scopeContext = new _ScopeContext(scope);

    if (_ISOLATE_SCOPE_CONTEXT != null) {
      if (scope == Scope.ISOLATE) {
        throw new ArgumentError(
            "Scope context already opened ${Scope.ISOLATE}");
      }

      Zone.current[_SCOPE_CONTEXT_HOLDER].hold(scopeContext);
    } else {
      if (scope != Scope.ISOLATE) {
        throw new ArgumentError(
            "Scope context not opened yet ${Scope.ISOLATE}");
      }

      _ISOLATE_SCOPE_CONTEXT = scopeContext;
    }

    await _notifyPostOpenedListeners(scope);
  }

  static Future closeScope(Scope scope) async {
    _libraryLogger.finest("Close scope ${scope}");

    _ScopeContext scopeContext;

    _ScopeContextHolder holder = Zone.current[_SCOPE_CONTEXT_HOLDER];
    if (holder != null && holder.isHolding) {
      scopeContext = holder.held;
    } else {
      scopeContext = _ISOLATE_SCOPE_CONTEXT;
    }

    if (scopeContext.scope != scope) {
      throw new StateError("Can't close not current scope: $scope");
    }

    Map<Provider, dynamic> providers = scopeContext.bindings;

    await Future.forEach(providers.keys, (provider) async {
      var instance = providers[provider];

      await _notifyPreUnbindListeners(instance, scope);
      await _notifyPreProvidedUnbindListeners(provider, instance, scope);
      await _notifyPreUnbindListeners(provider, scope);
    });

    await _notifyPreClosingListeners(scopeContext._scope);

    if (holder != null && holder.isHolding) {
      holder.unhold();
    } else {
      _ISOLATE_SCOPE_CONTEXT = null;
    }
  }

  static _ScopeContext _getScopeContext(Scope scope) {
    if (scope == Scope.ISOLATE) {
      return _ISOLATE_SCOPE_CONTEXT;
    } else {
      _ScopeContextHolder holder = Zone.current[_SCOPE_CONTEXT_HOLDER];
      if (holder != null && holder.isHolding && holder.held.scope == scope) {
        return holder.held;
      } else {
        throw new ArgumentError("Scope context not found for scope: $scope");
      }
    }
  }

  static runInScope(Scope scope, ScopeRunnable runnable) => runZoned(
      () => Chain.capture(() async {
            await openScope(scope);
            await runnable();
            await closeScope(scope);
          }, onError: (error, Chain chain) {
            _libraryLogger.severe("Running in scope error", error, chain);
          }),
      zoneValues: {_SCOPE_CONTEXT_HOLDER: new _ScopeContextHolder()});

  static lookupObject(Type clazz) {
    ProvideFunction provide = lookupProvideFunction(clazz);
    if (provide != null) {
      return provide();
    } else {
      throw new ArgumentError("Provider not found: $clazz");
    }
  }

  static lookupProvider(Type clazz) {
    ProvideFunction provider = lookupProvideFunction(clazz);
    if (provider != null) {
      return new ToFunctionProvider(provider);
    } else {
      throw new ArgumentError("Provider not found: $clazz");
    }
  }

  static ProvideFunction lookupProvideFunction(Type clazz) {
    if (_MODULE == null) {
      throw new StateError("Registry module not loaded");
    }

    _ProviderBinding providerBinding = _MODULE._getProviderBinding(clazz);
    if (providerBinding != null) {
      ProvideFunction scopedProvider = _SCOPED_PROVIDERS_CACHE[clazz];
      if (scopedProvider == null) {
        scopedProvider = () {
          if (providerBinding.scope != Scope.NONE) {
            _ScopeContext scopeContext =
                _getScopeContext(providerBinding.scope);
            if (scopeContext != null) {
              return _provideInScope(providerBinding.provider, scopeContext);
            } else {
              _libraryLogger.warning(
                  "Scope context not found for provider binding: $clazz");

              return null;
            }
          } else {
            return providerBinding.provider.get();
          }
        };

        _SCOPED_PROVIDERS_CACHE[clazz] = scopedProvider;
      }

      return scopedProvider;
    } else {
      throw new ArgumentError("Provider binding not found: $clazz");
    }
  }

  static _provideInScope(Provider provider, _ScopeContext scopeContext) {
    Map<Provider, dynamic> providers = scopeContext.bindings;

    var instance = providers[provider];
    bool newInstance = (instance == null);

    if (newInstance) {
      _notifyPostBindListeners(provider, scopeContext.scope);

      instance = provider.get();

      providers[provider] = instance;

      _injectBindings(instance);

      _notifyPostProvidedBindListeners(provider, instance, scopeContext.scope);

      _notifyPostBindListeners(instance, scopeContext.scope);
    }

    return instance;
  }

  static void injectMembers(instance) {
    _injectBindings(instance);
  }

  static void _injectProviders() {
    for (var providerBinding in _MODULE._bindings.values) {
      _injectBindings(providerBinding.provider);
    }
  }

  static void _injectBindings(instance) {
    _libraryLogger.finest("Inject bindings on $instance");

    if (!injectable.canReflect(instance)) {
      _libraryLogger.finest("$instance is not reflected");
      return;
    }

    var instanceMirror = injectable.reflect(instance);
    var classMirror = instanceMirror.type;
    while (classMirror != null) {
      _libraryLogger
          .finest("Inject bindings on class ${classMirror.simpleName}");

      classMirror.declarations.forEach((name, DeclarationMirror mirror) {
        if (mirror is VariableMirror) {
          Inject injectInstance =
              _lookupMetadataOfType(mirror.metadata, Inject);
          if (injectInstance != null) {
            var boundType = injectInstance.type;

            _libraryLogger
                .finest("Inject on variable $name bound to ${boundType ??
                    "unspecified"}");

            var variableType = mirror.type;
            if (_isGenericTypeOf(variableType, _PROVIDER_TYPE_NAME)) {
              _libraryLogger.finest("Provider injection");

              if (boundType != null) {
                _libraryLogger.finest("Injecting $boundType");

                instanceMirror.invokeSetter(
                    name, Registry.lookupProvider(boundType));
              } else {
                throw new ArgumentError();
              }
            } else if (_isGenericTypeOf(variableType, _FUTURE_TYPE_NAME)) {
              _libraryLogger.finest("Future injection");

              if (boundType != null) {
                _libraryLogger.finest("Injecting $boundType");

                instanceMirror.invokeSetter(
                    name, Registry.lookupProvider(boundType));
              } else {
                throw new ArgumentError();
              }
            } else if (_isGenericTypeOf(
                variableType, _FUNCTION_PROVIDER_TYPE_NAME)) {
              _libraryLogger.finest("Provide function injection");

              if (boundType != null) {
                _libraryLogger.finest("Injecting $boundType");

                instanceMirror.invokeSetter(
                    name, Registry.lookupProvideFunction(boundType));
              } else {
                throw new ArgumentError();
              }
            } else if (variableType is ClassMirror &&
                variableType.hasReflectedType) {
              _libraryLogger.finest("Injecting ${variableType.simpleName}");

              instanceMirror.invokeSetter(
                  name, Registry.lookupObject(variableType.reflectedType));
            } else {
              throw new ArgumentError();
            }
          }
        }
      });

      try {
        classMirror = classMirror.superclass;
      } on NoSuchCapabilityError catch (e) {
        _libraryLogger.finest(
            "super class of ${classMirror.simpleName} is not reflected", e);

        classMirror = null;
      }
    }
  }

  static Future notifyListeners(Scope scope, Type bindType, bool reversed) =>
      _notifyScopeListeners(
          _getScopeListeners(scope, bindType), scope, reversed);

  static Future _notifyPostOpenedListeners(Scope scope) =>
      _notifyScopeListeners(
          _getScopeListeners(scope, OnScopeOpened), scope, false);

  static Future _notifyPreClosingListeners(Scope scope) {
    return _notifyScopeListeners(
        _getScopeListeners(scope, OnScopeClosing), scope, true);
  }

  static void _notifyPostBindListeners(instance, Scope scope) =>
      _notifyListeners(
          instance, _getInstanceListeners(instance, OnBind), scope);

  static Future _notifyPreUnbindListeners(instance, Scope scope) =>
      _notifyFutureListeners(
          instance,
          new List.from(_getInstanceListeners(instance, OnUnbinding).reversed),
          scope);

  static void _notifyPostProvidedBindListeners(
          Provider provider, instance, Scope scope) =>
      _notifyProvidedListeners(provider, instance,
          _getInstanceListeners(provider, OnProvidedBind), scope);

  static Future _notifyPreProvidedUnbindListeners(
          Provider provider, instance, Scope scope) =>
      _notifyFutureProvidedListeners(
          provider,
          instance,
          new List.from(
              _getInstanceListeners(provider, OnProvidedUnbinding).reversed),
          scope);

  static List<String> _getInstanceListeners(instance, Type bindType) {
    _libraryLogger.finest("Get $bindType listeners on instance $instance");

    if (injectable.canReflect(instance)) {
      var typeMirror = injectable.reflect(instance).type;
      if (typeMirror.hasReflectedType) {
        return _getTypeListeners(typeMirror.reflectedType, bindType);
      }
    }

    _libraryLogger.finest("$instance is not reflected");

    return [];
  }

  static Map<Type, _BindingListeners> _getScopeListeners(
      Scope scope, Type bindType) {
    _libraryLogger.finest("Get $bindType listeners on scope $scope");

    var listeners = {};
    _MODULE?._bindings?.forEach((clazz, binding) {
      if (binding.scope == scope) {
        var instanceListeners =
            _getInstanceListeners(binding.provider, bindType);
        for (var symbol in instanceListeners) {
          _BindingListeners bindingListeners = listeners[clazz];
          if (bindingListeners == null) {
            bindingListeners = new _BindingListeners(binding.provider);
            listeners[clazz] = bindingListeners;
          }
          bindingListeners.providerListeners.add(symbol);
        }

        var target;
        if (binding.provider is ToInstanceProvider) {
          target =
              injectable.reflect(binding.provider._instance).type.reflectedType;
        } else if (binding.provider is ToClassProvider) {
          target = binding.provider._clazz;
        } else {
          target = clazz;
        }

        var typeListeners = _getTypeListeners(target, bindType);
        for (var symbol in typeListeners) {
          _BindingListeners bindingListeners = listeners[clazz];
          if (bindingListeners == null) {
            bindingListeners = new _BindingListeners(binding.provider);
            listeners[clazz] = bindingListeners;
          }
          bindingListeners.instanceListeners.add(symbol);
        }
      }
    });

    return listeners;
  }

  static List<String> _getTypeListeners(Type type, Type bindType) {
    _libraryLogger.finest("Get $bindType listeners on type $type");

    var listeners = [];
    if (injectable.canReflectType(type)) {
      var classMirror = injectable.reflectType(type);
      while (classMirror != null) {
        classMirror.declarations.forEach((symbol, DeclarationMirror mirror) {
          if (mirror is MethodMirror) {
            var bindInstance = _lookupMetadataOfType(mirror.metadata, bindType);
            if (bindInstance != null) {
              listeners.add(symbol);
            }
          }
        });

        try {
          classMirror = classMirror.superclass;

          _libraryLogger.finest("super class ${classMirror.simpleName}");
        } on NoSuchCapabilityError catch (e) {
          _libraryLogger.finest(
              "super class of ${classMirror.simpleName} is not reflected", e);

          classMirror = null;
        }
      }
    } else {
      _libraryLogger.finest("$type is not reflected");
    }
    return listeners;
  }

  static void _notifyListeners(instance, List<String> listeners, Scope scope) {
    _libraryLogger.finest(
        "Notify ${listeners.length} listeners on instance $instance in scope $scope");

    if (injectable.canReflect(instance)) {
      var instanceMirror = injectable.reflect(instance);

      for (var listener in listeners) {
        instanceMirror.invoke(listener, []);
      }
    } else {
      _libraryLogger.finest("$instance not reflected");
    }
  }

  static Future _notifyFutureListeners(
      instance, List<String> listeners, Scope scope) async {
    _libraryLogger.finest(
        "Notify ${listeners.length} listeners on future of instance $instance in scope $scope");

    if (injectable.canReflect(instance)) {
      var instanceMirror = injectable.reflect(instance);

      await Future.forEach(
          listeners, (listener) => instanceMirror.invoke(listener, []));
    } else {
      _libraryLogger.finest("$instance not reflected");
    }
  }

  static void _notifyProvidedListeners(
      Provider provider, instance, List<String> listeners, Scope scope) {
    _libraryLogger.finest(
        "Notify ${listeners.length} listeners on provider $provider of instance $instance in scope $scope");

    if (injectable.canReflect(provider)) {
      var providerMirror = injectable.reflect(provider);

      for (var listener in listeners) {
        providerMirror.invoke(listener, [instance]);
      }
    } else {
      _libraryLogger.finest("$provider not reflected");
    }
  }

  static Future _notifyFutureProvidedListeners(
      Provider provider, instance, List<String> listeners, Scope scope) async {
    _libraryLogger.finest(
        "Notify ${listeners.length} listeners on provider $provider of future instance $instance in scope $scope");

    if (injectable.canReflect(provider)) {
      var providerMirror = injectable.reflect(provider);

      await Future.forEach(
          listeners, (listener) => providerMirror.invoke(listener, [instance]));
    } else {
      _libraryLogger.finest("$provider not reflected");
    }
  }

  static Future _notifyScopeListeners(Map<Type, _BindingListeners> listeners,
      Scope scope, bool reversed) async {
    _libraryLogger
        .finest("Notify ${listeners.length} scope listeners on scope $scope");

    Iterable keys = reversed
        ? new List.from(listeners.keys, growable: false).reversed
        : listeners.keys;

    await Future.forEach(keys, (clazz) async {
      _BindingListeners bindingListeners = listeners[clazz];

      var providerMirror = bindingListeners.providerListeners.isNotEmpty
          ? injectable.reflect(bindingListeners.provider)
          : null;

      await Future.forEach(bindingListeners.providerListeners,
          (listener) => providerMirror.invoke(listener, []));

      var instance = bindingListeners.instanceListeners.isNotEmpty
          ? lookupObject(clazz)
          : null;

      var instanceMirror =
          instance != null ? injectable.reflect(instance) : null;

      await Future.forEach(bindingListeners.instanceListeners,
          (listener) => instanceMirror.invoke(listener, []));
    });
  }

  // TODO per semplicità vado puntuale sui nodi (c'erano problemi con reflectable in dart2js)
  static bool _isGenericTypeOf(TypeMirror typeMirror, String genericType) =>
      typeMirror.qualifiedName == genericType;

  static _lookupMetadataOfType(List metadata, Type type) {
    if (injectable.canReflectType(type)) {
      var typeMirror = injectable.reflectType(type);
      var list = metadata.where((annotation) {
        if (injectable.canReflect(annotation)) {
          var annotationMirror = injectable.reflect(annotation);
          var annotationTypeMirror = annotationMirror.type;

          // TODO per semplicità vado puntuale sui nodi (c'erano problemi con reflectable in dart2js)
          return annotationTypeMirror.qualifiedName == typeMirror.qualifiedName;
        } else {
          return false;
        }
      }).toList(growable: false);

      return list.isNotEmpty ? list.single : null;
    } else {
      _libraryLogger.finest("Annotation $type is not reflected");

      return null;
    }
  }
}

class _ScopeContext {
  final Scope _scope;

  final Map<Provider, dynamic> _bindings = {};

  _ScopeContext(this._scope);

  Scope get scope => _scope;

  Map<Provider, dynamic> get bindings => _bindings;
}

@injectable
class ToFunctionProvider<T> extends Provider<T> {
  final ProvideFunction<T> _function;

  ToFunctionProvider(this._function);

  T get() => _function();
}

@injectable
class ToClassProvider<T> extends Provider<T> {
  final Type _clazz;

  ToClassProvider(this._clazz);

  T get() =>
      (injectable.reflectType(_clazz) as ClassMirror).newInstance("", []);
}

@injectable
class ToInstanceProvider<T> extends Provider<T> {
  final T _instance;

  ToInstanceProvider(this._instance);

  T get() => this._instance;
}

class _ProviderBinding {
  final Type clazz;

  final Scope scope;

  final Provider provider;

  _ProviderBinding(this.clazz, this.scope, this.provider);
}

class _ScopeContextHolder {
  _ScopeContext _scopeContext;

  bool get isHolding => _scopeContext != null;

  _ScopeContext get held => _scopeContext;

  void hold(_ScopeContext scopeContext) {
    if (scopeContext == null) {
      throw new ArgumentError("Null scope context");
    }
    _scopeContext = scopeContext;
  }

  void unhold() {
    _scopeContext = null;
  }
}

class _BindingListeners {
  final Provider provider;
  final List<String> providerListeners = [];
  final List<String> instanceListeners = [];
  _BindingListeners(this.provider);
}
