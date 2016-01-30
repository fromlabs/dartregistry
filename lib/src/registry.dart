library dartregistry.registry;

import "dart:async";

import "package:logging/logging.dart";

@GlobalQuantifyCapability(r"^(dart.async.Future|logging.Logger)$", injectable)
import 'package:reflectable/reflectable.dart';

import "annotations.dart";
import "common.dart";
import "module.dart";

part "internal/registry.dart";

const String _FUTURE_TYPE_NAME = "dart.async.Future";
const String _PROVIDER_TYPE_NAME = "dartregistry.common.Provider";
const String _FUNCTION_PROVIDER_TYPE_NAME =
    "dartregistry.common.ProvideFunction";

class Registry {
  static const _SCOPE_CONTEXT_HOLDER = "_SCOPE_CONTEXT_HOLDER";

  static final Registry _singleton = new Registry();

  Logger _logger = new Logger("dartregistry.registry.Registry");

  RegistryModule _MODULE;

  _ScopeContext _ISOLATE_SCOPE_CONTEXT;

  Map<Type, ProvideFunction> _SCOPED_PROVIDERS_CACHE;

  final Map<TypeMirror, Type> _reflectedTypes = new Map.identity();

  final Map<Type, TypeMirror> _reflectedTypeMirrors = new Map.identity();

  final Map<Type, List<ClassMirror>> _reflectedClassMirrorHierarchies =
      new Map.identity();

  final Map<Scope, Map<Type, Map<Type, BindingListeners>>> _scopeListeners =
      new Map.identity();

  final Map<Type,
          Map<Type, List<DeclarationMirror>>> _allAnnotatedDeclarations =
      new Map.identity();

  static void load(RegistryModule module) => _singleton._load(module);
  static void unload() => _singleton._unload();

  static Future openScope(Scope scope) => _singleton._openScope(scope);
  static Future closeScope(Scope scope) => _singleton._closeScope(scope);
  static runInScope(Scope scope, ScopeRunnable runnable) =>
      _singleton._runInScope(scope, runnable);

  static Future openIsolateScope() => _singleton._openScope(Scope.ISOLATE);
  static Future closeIsolateScope() => _singleton._closeScope(Scope.ISOLATE);
  static runInIsolateScope(ScopeRunnable runnable) =>
      _singleton._runInScope(Scope.ISOLATE, runnable);

  static lookupObject(Type clazz) => _singleton._lookupObject(clazz);
  static lookupProvider(Type clazz) => _singleton._lookupProvider(clazz);
  static ProvideFunction lookupProvideFunction(Type clazz) =>
      _singleton._lookupProvideFunction(clazz);

  static void injectMembers(instance) => _singleton._injectMembers(instance);
  static Future notifyListeners(Scope scope, Type bindType, bool reversed) =>
      _singleton._notifyListeners(scope, bindType, reversed);

  static ClassDescriptor getInstanceClass(instance) =>
      _singleton._getInstanceClass(instance);
  static ClassDescriptor getClass(Type type) => _singleton._getClass(type);
  static List<MethodDescriptor> getAllMethodsAnnotatedWith(
          ClassDescriptor classDescriptor, Type annotationType) =>
      _singleton._getAllMethodsAnnotatedWith(classDescriptor, annotationType);

  static bool isClassAnnotatedWith(
          ClassDescriptor descriptor, Type annotationType) =>
      _singleton._isClassAnnotatedWith(descriptor, annotationType);
  static List getClassAnnotationsWith(
          ClassDescriptor descriptor, Type annotationType) =>
      _singleton._getClassAnnotationsWith(descriptor, annotationType);
  static bool isMethodAnnotatedWith(
          MethodDescriptor descriptor, Type annotationType) =>
      _singleton._isMethodAnnotatedWith(descriptor, annotationType);
  static List getMethodAnnotationsWith(
          MethodDescriptor descriptor, Type annotationType) =>
      _singleton._getMethodAnnotationsWith(descriptor, annotationType);
  static Object invokeMethod(
          instance, MethodDescriptor method, List positionalArguments,
          [Map<Symbol, dynamic> namedArguments]) =>
      _singleton._invokeMethod(
          instance, method, positionalArguments, namedArguments);

  void _load(RegistryModule module) {
    _logger.finest("Load registry module: $module");

    _logReflector(injectable);

    _MODULE = module;

    _SCOPED_PROVIDERS_CACHE = {};

    RegistryModuleInternal.configure(_MODULE);

    _injectProviders();
  }

  void _unload() {
    _logger.finest("Unload module");

    try {
      RegistryModuleInternal.unconfigure(_MODULE);
    } finally {
      _MODULE = null;
      _SCOPED_PROVIDERS_CACHE = null;
    }
  }

  Future _openScope(Scope scope) async {
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

  Future _closeScope(Scope scope) async {
    _logger.finest("Close scope ${scope}");

    _ScopeContextHolder holder = Zone.current[_SCOPE_CONTEXT_HOLDER];

    _ScopeContext scopeContext = holder != null && holder.isHolding
        ? holder.held
        : _ISOLATE_SCOPE_CONTEXT;

    if (scopeContext.scope != scope) {
      throw new StateError("Can't close not current scope: $scope");
    }

    try {
      Map<Provider, dynamic> providers = scopeContext.bindings;

      await Future.forEach(providers.keys, (provider) async {
        var instance = providers[provider];

        await _notifyPreUnbindListeners(instance, scope);
        await _notifyPreProvidedUnbindListeners(provider, instance, scope);
        await _notifyPreUnbindListeners(provider, scope);
      });

      await _notifyPreClosingListeners(scopeContext.scope);
    } finally {
      if (holder != null && holder.isHolding) {
        holder.unhold();
      } else {
        _ISOLATE_SCOPE_CONTEXT = null;
      }
    }
  }

  Future _runInScope(Scope scope, ScopeRunnable runnable) {
    return runZoned(() async {
      var isAlreadyInError = false;
      try {
        await openScope(scope);

        return await runnable();
      } catch (e) {
        isAlreadyInError = true;

        rethrow;
      } finally {
        try {
          await closeScope(scope);
        } catch (e, s) {
          if (isAlreadyInError) {
            _logger.warning("Catched a close scope error", e, s);
          } else {
            rethrow;
          }
        }
      }
    }, zoneValues: {_SCOPE_CONTEXT_HOLDER: new _ScopeContextHolder()});
  }

  _lookupObject(Type clazz) {
    ProvideFunction provide = lookupProvideFunction(clazz);
    if (provide != null) {
      return provide();
    } else {
      throw new ArgumentError("Provider not found: $clazz");
    }
  }

  _lookupProvider(Type clazz) {
    ProvideFunction provider = lookupProvideFunction(clazz);
    if (provider != null) {
      return new ToFunctionProvider(provider);
    } else {
      throw new ArgumentError("Provider not found: $clazz");
    }
  }

  ProvideFunction _lookupProvideFunction(Type clazz) {
    if (_MODULE == null) {
      throw new StateError("Registry module not loaded");
    }

    ProviderBinding providerBinding =
        RegistryModuleInternal.getProviderBinding(_MODULE, clazz);
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

  void _injectMembers(instance) => instance._injectBindings(instance);

  Future _notifyListeners(Scope scope, Type bindType, bool reversed) =>
      _notifyScopeListeners(
          _getScopeListeners(scope, bindType), scope, reversed);

  ClassDescriptor _getInstanceClass(instance) {
    var instanceMirror = _getInstanceMirror(instance);

    if (instanceMirror != null) {
      return _getClassInternal(instanceMirror.type);
    } else {
      return null;
    }
  }

  ClassDescriptor _getClass(Type type) {
    var typeMirror = _getTypeMirror(type);

    if (typeMirror != null) {
      return _getClassInternal(typeMirror);
    } else {
      return null;
    }
  }

  List<MethodDescriptor> _getAllMethodsAnnotatedWith(
      ClassDescriptor classDescriptor, Type annotationType) {
    var methods = {};

    _getAllMethodsAnnotatedWithInternal(classDescriptor.type, annotationType)
        .forEach(
            (methodMirror) => methods.putIfAbsent(methodMirror.simpleName, () {
                  var annotations = _getMethodAnnotations(
                      classDescriptor.type, methodMirror.simpleName);

                  return CommonInternal.newMethodDescriptor(
                      classDescriptor,
                      methodMirror.simpleName,
                      methodMirror.parameters.length,
                      annotations);
                }));

    return methods.values.toList(growable: false);
  }

  bool _isClassAnnotatedWith(ClassDescriptor descriptor, Type annotationType) =>
      getClassAnnotationsWith(descriptor, annotationType).isNotEmpty;

  List _getClassAnnotationsWith(
          ClassDescriptor descriptor, Type annotationType) =>
      _getMetadataOfType(descriptor.annotations, annotationType);

  bool _isMethodAnnotatedWith(
          MethodDescriptor descriptor, Type annotationType) =>
      getMethodAnnotationsWith(descriptor, annotationType).isNotEmpty;

  List _getMethodAnnotationsWith(
          MethodDescriptor descriptor, Type annotationType) =>
      _getMetadataOfType(descriptor.annotations, annotationType);

  Object _invokeMethod(
          instance, MethodDescriptor method, List positionalArguments,
          [Map<Symbol, dynamic> namedArguments]) =>
      _getInstanceMirror(instance)
          .invoke(method.name, positionalArguments, namedArguments);

  List _getTypeAnnotations(Type clazz) {
    var mirrors = _getClassMirrorHierarchy(clazz);

    var annotations = [];

    for (var mirror in mirrors) {
      annotations.addAll(_getMetadataOfType(mirror.metadata));
    }

    return annotations;
  }

  List _getMethodAnnotations(Type clazz, String method, [Type annotationType]) {
    var mirrors = _getClassMirrorHierarchy(clazz);

    var annotations = [];

    for (var mirror in mirrors) {
      var methodMirror = mirror.declarations[method];
      if (methodMirror != null) {
        annotations.addAll(_getMetadataOfType(methodMirror.metadata));
      }
    }

    return annotations;
  }

  _ScopeContext _getScopeContext(Scope scope) {
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

  _provideInScope(Provider provider, _ScopeContext scopeContext) {
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

  void _injectProviders() {
    for (var providerBinding
        in RegistryModuleInternal.getBindings(_MODULE).values) {
      _injectBindings(providerBinding.provider);
    }
  }

  void _injectBindings(instance) {
    _logger.finest("Inject bindings on $instance");

    var instanceMirror = _getInstanceMirror(instance);

    if (instanceMirror != null) {
      var declarations =
          _getAllVariablesAnnotatedWith(_getInstanceType(instance), Inject);

      for (VariableMirror declaration in declarations) {
        var injectAnnotations = _getDeclarationAnnotations(declaration, Inject);

        var injectInstance =
            injectAnnotations.isNotEmpty ? injectAnnotations.first : null;

        var name = declaration.simpleName;
        var boundType = injectInstance.type;

        _logger.finest(
            "Inject on variable $name bound to ${boundType ?? "unspecified"}");

        var variabileTypeMirror = declaration.type;

        if (_isGenericTypeOf(variabileTypeMirror, _PROVIDER_TYPE_NAME)) {
          _logger.finest("Provider injection");

          if (boundType != null) {
            _logger.finest("Injecting $boundType");

            instanceMirror.invokeSetter(
                name, Registry.lookupProvider(boundType));
          } else {
            throw new ArgumentError();
          }
        } else if (_isGenericTypeOf(variabileTypeMirror, _FUTURE_TYPE_NAME)) {
          _logger.finest("Future injection");

          if (boundType != null) {
            _logger.finest("Injecting $boundType");

            instanceMirror.invokeSetter(name, Registry.lookupObject(boundType));
          } else {
            throw new ArgumentError();
          }
        } else if (_isGenericTypeOf(
            variabileTypeMirror, _FUNCTION_PROVIDER_TYPE_NAME)) {
          _logger.finest("Provide function injection");

          if (boundType != null) {
            _logger.finest("Injecting $boundType");

            // TODO verificare quando dart2js offrirà il supporto ai typedef con generici
            // throw new UnsupportedError("Provide function injection");

            _logger.warning(
                "*******************************************************************");
            _logger.warning(
                "*** Provide function injection is not supported yet in Dart2JS! ***");
            _logger.warning(
                "*******************************************************************");

            instanceMirror.invokeSetter(
                name, Registry.lookupProvideFunction(boundType));
          } else {
            throw new ArgumentError();
          }
        } else if (variabileTypeMirror is ClassMirror) {
          _logger.finest("Injecting ${variabileTypeMirror.simpleName}");

          instanceMirror.invokeSetter(
              name, Registry.lookupObject(variabileTypeMirror.reflectedType));
        } else {
          throw new ArgumentError();
        }
      }
    }
  }

  Future _notifyPostOpenedListeners(Scope scope) => _notifyScopeListeners(
      _getScopeListeners(scope, OnScopeOpened), scope, false);

  Future _notifyPreClosingListeners(Scope scope) {
    return _notifyScopeListeners(
        _getScopeListeners(scope, OnScopeClosing), scope, true);
  }

  void _notifyPostBindListeners(instance, Scope scope) =>
      _notifyListenersInternal(
          instance, _getInstanceListeners(instance, OnBind), scope);

  Future _notifyPreUnbindListeners(instance, Scope scope) =>
      _notifyFutureListeners(
          instance,
          new List.from(_getInstanceListeners(instance, OnUnbinding).reversed),
          scope);

  void _notifyPostProvidedBindListeners(
          Provider provider, instance, Scope scope) =>
      _notifyProvidedListeners(provider, instance,
          _getInstanceListeners(provider, OnProvidedBind), scope);

  Future _notifyPreProvidedUnbindListeners(
          Provider provider, instance, Scope scope) =>
      _notifyFutureProvidedListeners(
          provider,
          instance,
          new List.from(
              _getInstanceListeners(provider, OnProvidedUnbinding).reversed),
          scope);

  void _notifyListenersInternal(instance, List<String> listeners, Scope scope) {
    var instanceMirror = _getInstanceMirror(instance);
    for (var listener in listeners) {
      instanceMirror.invoke(listener, []);
    }
  }

  Future _notifyFutureListeners(
      instance, List<String> listeners, Scope scope) async {
    var instanceMirror = _getInstanceMirror(instance);

    await Future.forEach(
        listeners, (listener) => instanceMirror.invoke(listener, []));
  }

  void _notifyProvidedListeners(
      Provider provider, instance, List<String> listeners, Scope scope) {
    var providerMirror = _getInstanceMirror(provider);

    for (var listener in listeners) {
      providerMirror.invoke(listener, [instance]);
    }
  }

  Future _notifyFutureProvidedListeners(
      Provider provider, instance, List<String> listeners, Scope scope) async {
    var providerMirror = _getInstanceMirror(provider);

    await Future.forEach(
        listeners, (listener) => providerMirror.invoke(listener, [instance]));
  }

  Future _notifyScopeListeners(
      Map<Type, BindingListeners> listeners, Scope scope, bool reversed) async {
    Iterable keys = reversed
        ? new List.from(listeners.keys, growable: false).reversed
        : listeners.keys;

    await Future.forEach(keys, (clazz) async {
      BindingListeners bindingListeners = listeners[clazz];

      if (bindingListeners.providerListeners.isNotEmpty) {
        var providerMirror = _getInstanceMirror(bindingListeners.provider);

        await Future.forEach(bindingListeners.providerListeners,
            (listener) => providerMirror.invoke(listener, []));
      }

      if (bindingListeners.instanceListeners.isNotEmpty) {
        var instanceMirror = _getInstanceMirror(lookupObject(clazz));

        if (instanceMirror != null) {
          await Future.forEach(bindingListeners.instanceListeners,
              (listener) => instanceMirror.invoke(listener, []));
        }
      }
    });
  }

  List<String> _getInstanceListeners(instance, Type bindType) {
    var instanceType = _getInstanceType(instance);

    return instanceType != null
        ? _getTypeListeners(instanceType, bindType)
        : [];
  }

  Map<Type, BindingListeners> _getScopeListeners(Scope scope, Type bindType) {
    var bindListeners = _scopeListeners[scope];
    if (bindListeners == null) {
      bindListeners = new Map.identity();
      _scopeListeners[scope] = bindListeners;
    }

    var listeners;
    if (bindListeners.containsKey(bindType)) {
      listeners = bindListeners[bindType];
    } else {
      _logger.finest("Get $bindType listeners on scope $scope");

      listeners = {};
      RegistryModuleInternal.getBindings(_MODULE)?.forEach((clazz, binding) {
        if (binding.scope == scope) {
          var instanceListeners =
              _getInstanceListeners(binding.provider, bindType);
          for (var symbol in instanceListeners) {
            BindingListeners bindingListeners = listeners[clazz];
            if (bindingListeners == null) {
              bindingListeners = new BindingListeners(binding.provider);
              listeners[clazz] = bindingListeners;
            }
            bindingListeners.providerListeners.add(symbol);
          }

          var target;
          if (binding.provider is ToInstanceProvider) {
            target = _getInstanceType(binding.provider.instance);
          } else if (binding.provider is ToClassProvider) {
            target = binding.provider.clazz;
          } else {
            target = clazz;
          }

          var typeListeners = _getTypeListeners(target, bindType);
          for (var symbol in typeListeners) {
            BindingListeners bindingListeners = listeners[clazz];
            if (bindingListeners == null) {
              bindingListeners = new BindingListeners(binding.provider);
              listeners[clazz] = bindingListeners;
            }
            bindingListeners.instanceListeners.add(symbol);
          }
        }
      });

      bindListeners[bindType] = listeners;
    }
    return listeners;
  }

  List<String> _getTypeListeners(Type type, Type bindType) {
    return _getAllMethodsAnnotatedWithInternal(type, bindType)
        .map((mirror) => mirror.simpleName)
        .toList(growable: false);
  }

  ClassDescriptor _getClassInternal(TypeMirror typeMirror) {
    var type = _getReflectedType(typeMirror);

    if (type != null) {
      var annotations = _getTypeAnnotations(type);

      return CommonInternal.newClassDescriptor(
          type, typeMirror.simpleName, typeMirror.qualifiedName, annotations);
    } else {
      return null;
    }
  }

  Type _getInstanceType(instance) {
    var instanceMirror = _getInstanceMirror(instance);
    return instanceMirror != null
        ? _getReflectedType(instanceMirror.type)
        : null;
  }

  Type _getReflectedType(TypeMirror typeMirror) {
    var type;
    if (_reflectedTypes.containsKey(typeMirror)) {
      type = _reflectedTypes[typeMirror];
    } else {
      if (typeMirror.hasReflectedType) {
        type = typeMirror.reflectedType;
      } else {
        _logger.finest("Type mirror $typeMirror is not reflected");
        type = null;
      }
      _reflectedTypes[typeMirror] = type;
    }
    return type;
  }

  InstanceMirror _getInstanceMirror(instance) {
    if (injectable.canReflect(instance)) {
      return injectable.reflect(instance);
    } else {
      _logger.finest("Instance $instance not reflected");
      return null;
    }
  }

  TypeMirror _getTypeMirror(Type type) {
    var typeMirror;
    if (_reflectedTypeMirrors.containsKey(type)) {
      typeMirror = _reflectedTypeMirrors[type];
    } else {
      if (injectable.canReflectType(type)) {
        typeMirror = injectable.reflectType(type);
      } else {
        _logger.finest("Type $type not reflected");
        typeMirror = null;
      }
      _reflectedTypeMirrors[typeMirror] = typeMirror;
    }
    return typeMirror;
  }

  List<ClassMirror> _getClassMirrorHierarchy(Type clazz) {
    var classMirrors;
    if (_reflectedClassMirrorHierarchies.containsKey(clazz)) {
      classMirrors = _reflectedClassMirrorHierarchies[clazz];
    } else {
      classMirrors = [];

      var classMirror = _getTypeMirror(clazz);
      while (classMirror != null) {
        classMirrors.add(classMirror);

        try {
          classMirror = classMirror.superclass;
        } on NoSuchCapabilityError catch (e) {
          _logger.finest(
              "Super class of ${classMirror.simpleName} is not reflected", e);

          classMirror = null;
        }
      }

      _reflectedClassMirrorHierarchies[clazz] = classMirrors;
    }
    return classMirrors;
  }

  bool _isGenericTypeOf(TypeMirror typeMirror, String genericType) {
    // TODO per semplicità vado puntuale sui nodi (ci sono problemi con reflectable in dart2js nel recupero del reflectedType di tipi con generici)
    return typeMirror.qualifiedName == genericType;
  }

  List<MethodMirror> _getAllMethodsAnnotatedWithInternal(
      Type clazz, Type annotationType) {
    return _getAllDeclarationsAnnotatedWith(clazz, annotationType)
        .where((declaration) => declaration is MethodMirror)
        .toList(growable: false);
  }

  List<VariableMirror> _getAllVariablesAnnotatedWith(
      Type clazz, Type annotationType) {
    return _getAllDeclarationsAnnotatedWith(clazz, annotationType)
        .where((declaration) => declaration is VariableMirror)
        .toList(growable: false);
  }

  List<DeclarationMirror> _getAllDeclarationsAnnotatedWith(
      Type clazz, Type annotationType) {
    var typeDeclarations = _allAnnotatedDeclarations[clazz];
    if (typeDeclarations == null) {
      typeDeclarations = new Map.identity();
      _allAnnotatedDeclarations[clazz] = typeDeclarations;
    }

    var declarations;
    if (typeDeclarations.containsKey(annotationType)) {
      declarations = typeDeclarations[annotationType];
    } else {
      _logger.finest("Get $annotationType declarations on class $clazz");

      declarations = [];
      var classMirrors = _getClassMirrorHierarchy(clazz);
      for (var classMirror in classMirrors) {
        classMirror.declarations.forEach((name, DeclarationMirror mirror) {
          if (_isDeclarationAnnotatedWith(mirror, annotationType)) {
            declarations.add(mirror);
          }
        });
      }

      typeDeclarations[annotationType] = declarations;
    }
    return declarations;
  }

  bool _isDeclarationAnnotatedWith(
      DeclarationMirror mirror, Type annotationType) {
    return _getDeclarationAnnotations(mirror, annotationType).isNotEmpty;
  }

  List _getDeclarationAnnotations(DeclarationMirror mirror,
      [Type annotationType]) {
    return _getMetadataOfType(mirror.metadata, annotationType);
  }

  List _getMetadataOfType(List metadata, [Type annotationType]) {
    var filterTypeMirror =
        annotationType != null ? _getTypeMirror(annotationType) : null;

    if (filterTypeMirror != null) {
      return metadata.where((annotation) {
        if (injectable.canReflect(annotation)) {
          var annotationMirror = injectable.reflect(annotation);
          var annotationTypeMirror = annotationMirror.type;

          return _isGenericTypeOf(
              annotationTypeMirror, filterTypeMirror.qualifiedName);
        } else {
          return false;
        }
      }).toList(growable: false);
    } else if (annotationType == null) {
      return metadata;
    } else {
      return [];
    }
  }

  void _logReflector(Reflectable reflector) {
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

class _ScopeContext {
  final Scope _scope;

  final Map<Provider, dynamic> _bindings = {};

  _ScopeContext(this._scope);

  Scope get scope => _scope;

  Map<Provider, dynamic> get bindings => _bindings;
}
