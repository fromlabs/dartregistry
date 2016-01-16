library dartregistry.dartregistry;

import "dart:async";

import "package:logging/logging.dart";
import "package:stack_trace/stack_trace.dart";

@GlobalQuantifyCapability(r"^dart.async.Future$", Injectable)
import 'package:reflectable/reflectable.dart';

final Logger _logger = new Logger("dartregistry");

const Injectable_ Injectable = const Injectable_();

const Module_ Module = const Module_();

const Inject_ Inject = const Inject_();

const OnScopeOpened = const OnScopeOpened_();
const OnScopeClosing = const OnScopeClosing_();

const OnBind = const OnBind_();
const OnUnbinding = const OnUnbinding_();

const OnProvidedBind = const OnProvidedBind_();
const OnProvidedUnbinding = const OnProvidedUnbinding_();

typedef T ProviderFunction<T>();

typedef ScopeRunnable();

void logReflector(Reflectable reflector) {
  _logger.finest("******************************");
  _logger.fine(
      "Annotated classes of $reflector: ${reflector.annotatedClasses.length}");
  for (var i = 0; i < reflector.annotatedClasses.length; i++) {
    try {
      var mirror = reflector.annotatedClasses.elementAt(i);

      _logger.finest(mirror.qualifiedName);
    } on NoSuchCapabilityError catch (e) {
      _logger.warning("Skip class", e);
    }
  }
  _logger.finest("******************************");
}

@Injectable
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

  void bindProviderFunction(
      Type clazz, Scope scope, ProviderFunction providerFunction) {
    _addProviderBinding(
        clazz,
        new _ProviderBinding(
            clazz, scope, new ToFunctionProvider(providerFunction)));
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

  static Map<Type, ProviderFunction> _SCOPED_PROVIDERS_CACHE;

  static Future load(Type moduleClazz,
      [Map<String, dynamic> parameters = const {}]) async {
    _logger.finest("Load registry module");

    logReflector(Injectable);

    var module =
        (Module.reflectType(moduleClazz) as ClassMirror).newInstance("", []);

    if (module is! RegistryModule) {
      throw new ArgumentError("$moduleClazz is not a registry module");
    }

    _MODULE = module;

    _SCOPED_PROVIDERS_CACHE = {};

    await _MODULE.configure(parameters);

    _injectProviders();
  }

  static Future unload() async {
    _logger.finest("Unload module");

    try {
      await _MODULE.unconfigure();
    } finally {
      _MODULE = null;
      _SCOPED_PROVIDERS_CACHE = null;
    }
  }

  static Future openScope(Scope scope) async {
    _logger.finest("Open scope $scope");

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
    _logger.finest("Close scope ${scope}");

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
            _logger.severe("Running in scope error", error, chain);
          }),
      zoneValues: {_SCOPE_CONTEXT_HOLDER: new _ScopeContextHolder()});

  static lookupObject(Type clazz) {
    ProviderFunction provider = lookupProviderFunction(clazz);
    if (provider != null) {
      return provider();
    } else {
      throw new ArgumentError("Provider not found: $clazz");
    }
  }

  static lookupProvider(Type clazz) {
    ProviderFunction provider = lookupProviderFunction(clazz);
    if (provider != null) {
      return new ToFunctionProvider(provider);
    } else {
      throw new ArgumentError("Provider not found: $clazz");
    }
  }

  static ProviderFunction lookupProviderFunction(Type clazz) {
    if (_MODULE == null) {
      throw new StateError("Registry module not loaded");
    }

    _ProviderBinding providerBinding = _MODULE._getProviderBinding(clazz);
    if (providerBinding != null) {
      ProviderFunction scopedProvider = _SCOPED_PROVIDERS_CACHE[clazz];
      if (scopedProvider == null) {
        scopedProvider = () {
          if (providerBinding.scope != Scope.NONE) {
            _ScopeContext scopeContext =
                _getScopeContext(providerBinding.scope);
            if (scopeContext != null) {
              return _provideInScope(providerBinding.provider, scopeContext);
            } else {
              _logger.warning(
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
    _logger.finest("Inject bindings on $instance");

    if (!Injectable.canReflect(instance)) {
      _logger.finest("$instance is not reflected");
      return;
    }

    var instanceMirror = Injectable.reflect(instance);
    var classMirror = instanceMirror.type;
    while (classMirror != null) {
      _logger.finest("Inject bindings on class ${classMirror.simpleName}");

      classMirror.declarations.forEach((name, DeclarationMirror mirror) {
        if (mirror is VariableMirror) {
          if (mirror.metadata.contains(Inject)) {
            _logger.finest("Inject on variable $name");

            var variableType = mirror.type;
            if (variableType is ClassMirror) {
              if (variableType.isSubclassOf(Injectable.reflectType(Provider))) {
                if (variableType.typeArguments.length == 1) {
                  var typeMirror = variableType.typeArguments[0];

                  if (typeMirror.isSubclassOf(Injectable.reflectType(Future))) {
                    if (typeMirror.typeArguments.length == 1) {
                      typeMirror = typeMirror.typeArguments[0];

                      _logger.finest(
                          "Injecting Provider<Future<${typeMirror.simpleName}>>");
                    } else {
                      throw new ArgumentError();
                    }
                  } else {
                    _logger
                        .finest("Injecting Provider<${typeMirror.simpleName}>");
                  }

                  instanceMirror.invokeSetter(
                      name, Registry.lookupProvider(typeMirror.reflectedType));
                } else {
                  throw new ArgumentError();
                }
/*
              } else if (variableType.isSubclassOf(functionTypeMirror)) {
                // TODO injection di funzioni
                print("Inject Function");


                print("UnimplementedError");
                throw new UnimplementedError();
*/
              } else if (variableType.hasReflectedType) {
                var typeMirror = variableType;

                if (typeMirror.isSubclassOf(Injectable.reflectType(Future))) {
                  if (typeMirror.typeArguments.length == 1) {
                    typeMirror = typeMirror.typeArguments[0];

                    _logger
                        .finest("Injecting Future<${typeMirror.simpleName}>");
                  } else {
                    throw new ArgumentError();
                  }
                } else {
                  _logger.finest("Injecting ${typeMirror.simpleName}");
                }

                instanceMirror.invokeSetter(
                    name, Registry.lookupProvider(typeMirror.reflectedType));
              } else {
                throw new ArgumentError();
              }
/*
            } else if (variableType is TypedefMirror &&
                variableType.isSubtypeOf(providerFunctionTypeMirror)) {
              // TODO injection di ProviderFunction
              print("Inject ProviderFunction");

              print("UnimplementedError");
              throw new UnimplementedError();
*/
            } else {
              throw new ArgumentError();
            }
          }
        }
      });

      try {
        classMirror = classMirror.superclass;
      } on NoSuchCapabilityError catch (e) {
        _logger.finest(
            "super class of ${classMirror.simpleName} is not reflected", e);

        classMirror = null;
      }
    }
  }

  static Future notifyListeners(Scope scope, bindType, bool reversed) =>
      _notifyScopeListeners(
          _getScopeListeners(scope, bindType), scope, reversed);

  static Future _notifyPostOpenedListeners(Scope scope) =>
      _notifyScopeListeners(
          _getScopeListeners(scope, OnScopeOpened), scope, false);

  static Future _notifyPreClosingListeners(Scope scope) =>
      _notifyScopeListeners(
          _getScopeListeners(scope, OnScopeClosing), scope, true);

  static void _notifyPostBindListeners(instance, Scope scope) {
    if (Injectable.canReflect(instance)) {
      _notifyListeners(Injectable.reflect(instance),
          _getInstanceListeners(instance, OnBind), scope);
    } else {
      _logger.finest("$instance not reflected");
    }
  }

  static Future _notifyPreUnbindListeners(instance, Scope scope) {
    if (Injectable.canReflect(instance)) {
      return _notifyFutureListeners(
          Injectable.reflect(instance),
          new List.from(_getInstanceListeners(instance, OnUnbinding).reversed),
          scope);
    } else {
      _logger.finest("$instance not reflected");
      return new Future.value();
    }
  }

  static void _notifyPostProvidedBindListeners(
      provider, instance, Scope scope) {
    _notifyProvidedListeners(Injectable.reflect(provider), instance,
        _getInstanceListeners(provider, OnProvidedBind), scope);
  }

  static Future _notifyPreProvidedUnbindListeners(
          provider, instance, Scope scope) =>
      _notifyFutureProvidedListeners(
          Injectable.reflect(provider),
          instance,
          new List.from(
              _getInstanceListeners(provider, OnProvidedUnbinding).reversed),
          scope);

  static List<String> _getInstanceListeners(instance, bindType) {
    // TODO eliminare utilizzo di runtimeType

    return _getTypeListeners(instance.runtimeType, bindType);
  }

  static Map<Type, _BindingListeners> _getScopeListeners(
      Scope scope, bindType) {
    var listeners = {};
    _MODULE?._bindings?.forEach((clazz, binding) {
      if (binding.scope == scope) {
        _getInstanceListeners(binding.provider, bindType).forEach((symbol) {
          _BindingListeners bindingListeners = listeners[clazz];
          if (bindingListeners == null) {
            bindingListeners = new _BindingListeners(binding.provider);
            listeners[clazz] = bindingListeners;
          }
          bindingListeners.providerListeners.add(symbol);
        });

        var target;
        if (binding.provider is ToInstanceProvider) {
          // TODO eliminare utilizzo di runtimeType
          target = binding.provider._instance.runtimeType;
        } else if (binding.provider is ToClassProvider) {
          target = binding.provider._clazz;
        } else {
          target = clazz;
        }

        _getTypeListeners(target, bindType).forEach((symbol) {
          _BindingListeners bindingListeners = listeners[clazz];
          if (bindingListeners == null) {
            bindingListeners = new _BindingListeners(binding.provider);
            listeners[clazz] = bindingListeners;
          }
          bindingListeners.instanceListeners.add(symbol);
        });
      }
    });
    return listeners;
  }

  static List<String> _getTypeListeners(Type type, bindType) {
    var listeners = [];
    var classMirror = Injectable.reflectType(type);
    while (classMirror != null) {
      classMirror.declarations.forEach((symbol, DeclarationMirror mirror) {
        if (mirror is MethodMirror) {
          if (mirror.metadata.contains(bindType)) {
            listeners.add(symbol);
          }
        }
      });

      try {
        classMirror = classMirror.superclass;

        _logger.finest("super class ${classMirror.simpleName}");
      } on NoSuchCapabilityError catch (e) {
        _logger.finest(
            "super class of ${classMirror.simpleName} is not reflected", e);

        classMirror = null;
      }
    }
    return listeners;
  }

  static void _notifyListeners(
          InstanceMirror instanceMirror, List<String> listeners, Scope scope) =>
      listeners.forEach((listener) => instanceMirror.invoke(listener, []));

  static Future _notifyFutureListeners(
          InstanceMirror instanceMirror, List<String> listeners, Scope scope) =>
      Future.forEach(
          listeners, (listener) => instanceMirror.invoke(listener, []));

  static void _notifyProvidedListeners(InstanceMirror providerMirror, instance,
          List<String> listeners, Scope scope) =>
      listeners
          .forEach((listener) => providerMirror.invoke(listener, [instance]));

  static Future _notifyFutureProvidedListeners(InstanceMirror providerMirror,
          instance, List<String> listeners, Scope scope) =>
      Future.forEach(
          listeners, (listener) => providerMirror.invoke(listener, [instance]));

  static Future _notifyScopeListeners(
      Map<Type, _BindingListeners> listeners, Scope scope, bool reversed) {
    Iterable keys = reversed
        ? new List.from(listeners.keys, growable: false).reversed
        : listeners.keys;
    return Future.forEach(keys, (clazz) {
      _BindingListeners bindingListeners = listeners[clazz];
      var providerMirror = bindingListeners.providerListeners.isNotEmpty
          ? Injectable.reflect(bindingListeners.provider)
          : null;
      var instance = bindingListeners.instanceListeners.isNotEmpty
          ? lookupObject(clazz)
          : null;

      return Future
          .forEach(bindingListeners.providerListeners,
              (listener) => providerMirror.invoke(listener, []))
          .then((_) => instance)
          .then((value) {
        var valueMirror =
            instance != null ? Injectable.reflect(instance) : null;
        return Future.forEach(bindingListeners.instanceListeners,
            (listener) => valueMirror.invoke(listener, []));
      });
    });
  }
}

class _ScopeContext {
  final Scope _scope;

  final Map<Provider, dynamic> _bindings = {};

  _ScopeContext(this._scope);

  Scope get scope => _scope;

  Map<Provider, dynamic> get bindings => _bindings;
}

class Module_ extends Reflectable {
  const Module_() : super(newInstanceCapability);
}

class Injectable_ extends Reflectable {
  const Injectable_()
      : super(
            metadataCapability,
            typeRelationsCapability,
            declarationsCapability,
            instanceInvokeCapability,
            newInstanceCapability);
}

class Inject_ {
  const Inject_();
}

class OnScopeOpened_ {
  const OnScopeOpened_();
}

class OnScopeClosing_ {
  const OnScopeClosing_();
}

class OnBind_ {
  const OnBind_();
}

class OnUnbinding_ {
  const OnUnbinding_();
}

class OnProvidedBind_ {
  const OnProvidedBind_();
}

class OnProvidedUnbinding_ {
  const OnProvidedUnbinding_();
}

@Injectable
class ToFunctionProvider<T> extends Provider<T> {
  final ProviderFunction<T> _function;

  ToFunctionProvider(this._function);

  T get() => _function();
}

@Injectable
class ToClassProvider<T> extends Provider<T> {
  final Type _clazz;

  ToClassProvider(this._clazz);

  T get() =>
      (Injectable.reflectType(_clazz) as ClassMirror).newInstance("", []);
}

@Injectable
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
