part of dartregistry;

const Object Inject = const _Inject();

const Object OnScopeOpened = const _OnScopeOpened();
const Object OnScopeClosing = const _OnScopeClosing();

const Object OnBind = const _OnBind();
const Object OnUnbinding = const _OnUnbinding();

const Object OnProvidedBind = const _OnProvidedBind();
const Object OnProvidedUnbinding = const _OnProvidedUnbinding();

typedef T ProviderFunction<T>();

typedef ScopeRunnable();

abstract class Provider<T> {
	T get();
}

abstract class RegistryModule {

	Map<Type, _ProviderBinding> _bindings;

	Future configure(Map<String, dynamic> parameters) {
		_bindings = {};

		return new Future.value();
	}

	Future unconfigure() {
		_bindings.clear();
		_bindings = null;

		return new Future.value();
	}

	void bindInstance(Type clazz, instance) {
		_addProviderBinding(clazz, new _ProviderBinding(clazz, Scope.ISOLATE, new _ToInstanceProvider(instance)));
	}

	void bindClass(Type clazz, Scope scope, [Type clazzImpl]) {
		clazzImpl = clazzImpl != null ? clazzImpl : clazz;
		_addProviderBinding(clazz, new _ProviderBinding(clazz, scope, new _ToClassProvider(clazzImpl)));
	}

	void bindProviderFunction(Type clazz, Scope scope, ProviderFunction providerFunction) {
		_addProviderBinding(clazz, new _ProviderBinding(clazz, scope, new _ToFunctionProvider(providerFunction)));
	}

	void bindProvider(Type clazz, Scope scope, Provider provider) {
		_addProviderBinding(clazz, new _ProviderBinding(clazz, scope, provider));
	}

	void _addProviderBinding(Type clazz, _ProviderBinding binding) {
		_bindings[clazz] = binding;

		onBindingAdded(clazz);
	}

	void onBindingAdded(Type clazz) {}

	_getProviderBinding(Type clazz) => _bindings[clazz];
}

class Scope {
	static const Scope NONE = const Scope("NONE");
	static const Scope ISOLATE = const Scope("ISOLATE");

	final String id;

	const Scope(this.id);

	String toString() => this.id;
}

class Registry {

	static const _SCOPE_CONTEXT_HOLDER = "_SCOPE_CONTEXT_HOLDER";

	static RegistryModule _MODULE;

	static _ScopeContext _ISOLATE_SCOPE_CONTEXT;

	static Map<Type, ProviderFunction> _SCOPED_PROVIDERS_CACHE;

	static Map<Scope, _ScopeContext> _CONTEXTS;

	static Future load(Type moduleClazz, [Map<String, dynamic> parameters = const {}]) {
		print("Load module");

		var module = _newInstanceFromClass(moduleClazz);
		if (module is! RegistryModule) {
			throw new ArgumentError("$moduleClazz is not a registry module");
		}
		_MODULE = module;

		_SCOPED_PROVIDERS_CACHE = {};
		_CONTEXTS = {};
		return _MODULE.configure(parameters).then((_) {
			_injectProviders();
		});
	}

	static Future unload() {
		print("Unload module");

		return _MODULE.unconfigure().then((_) {
			_MODULE = null;
			_SCOPED_PROVIDERS_CACHE = null;
		});
	}

	static Future openScope(Scope scope) {
		print("Open scope $scope");

		if (scope == Scope.NONE) {
			throw new ArgumentError("Can't open scope context ${Scope.NONE}");
		}

		var scopeContext = new _ScopeContext(scope);

		if (_ISOLATE_SCOPE_CONTEXT != null) {
			if (scope == Scope.ISOLATE) {
				throw new ArgumentError("Scope context already opened ${Scope.ISOLATE}");
			}

			Zone.current[_SCOPE_CONTEXT_HOLDER].hold(scopeContext);
		} else {
			if (scope != Scope.ISOLATE) {
				throw new ArgumentError("Scope context not opened yet ${Scope.ISOLATE}");
			}

			_ISOLATE_SCOPE_CONTEXT = scopeContext;
		}

		return _notifyPostOpenedListeners(scope).then((_) => scopeContext);
	}

	static Future closeScope(Scope scope) {
		print("Close scope ${scope}");

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
		return Future.forEach(providers.keys, (provider) {
			var instance = providers[provider];
			return _notifyPreUnbindListeners(instance, scope)
					.then((_) => _notifyPreProvidedUnbindListeners(provider, instance, scope))
					.then((_) => _notifyPreUnbindListeners(provider, scope));
		})
		.then((_) => _notifyPreClosingListeners(scopeContext._scope))
		.then((_) {
			if (holder != null && holder.isHolding) {
				holder.unhold();
			} else {
				_ISOLATE_SCOPE_CONTEXT = null;
			}
		});
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

	static runInScope(Scope scope, ScopeRunnable runnable) {
		return runZoned(() {
			return openScope(scope).then((_) => runnable()).whenComplete(() => closeScope(scope));
		}, zoneValues: {
			_SCOPE_CONTEXT_HOLDER: new _ScopeContextHolder()
		}, onError: (error) {
			print(error);
			if (error is Error) {
				print(error.stackTrace);
			}
		});
	}

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
			return new _ToFunctionProvider(provider);
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
						_ScopeContext scopeContext = _getScopeContext(providerBinding.scope);
						if (scopeContext != null) {
							return _provideInScope(providerBinding.provider, scopeContext);
						} else {
							print("Scope context not found for provider binding: $clazz");

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

	static void _injectProviders() {
		_MODULE._bindings.values.forEach((providerBinding) => _injectBindings(providerBinding.provider));
	}

	static void _injectBindings(instance) {
		var classMirror = reflect(instance).type;
		while (classMirror != null) {
			classMirror.declarations.forEach((symbol, DeclarationMirror mirror) {
				if (mirror is VariableMirror) {
					if (mirror.metadata.contains(reflect(Inject))) {
						var variableType = mirror.type;
						if (variableType is ClassMirror && variableType.isSubclassOf(reflectClass(Provider))) {
							if (variableType.typeArguments.length == 1) {
								var typeMirror = variableType.typeArguments[0];

								if (typeMirror.isSubclassOf(reflectClass(Future))) {
									if (typeMirror.typeArguments.length == 1) {
										typeMirror = typeMirror.typeArguments[0];
									} else {
										throw new ArgumentError();
									}
								}

								reflect(instance).setField(symbol, Registry.lookupProvider(typeMirror.reflectedType));
							} else {
								throw new ArgumentError();
							}
						} else if (variableType is ClassMirror && variableType.reflectedType == Function) {
							throw new UnimplementedError();
						} else if (variableType is ClassMirror) {
							var typeMirror = variableType;

							if (typeMirror.isSubclassOf(reflectClass(Future))) {
								if (typeMirror.typeArguments.length == 1) {
									typeMirror = typeMirror.typeArguments[0];
								} else {
									throw new ArgumentError();
								}
							}

							reflect(instance).setField(symbol, Registry.lookupObject(typeMirror.reflectedType));
						} else if (variableType is TypedefMirror && variableType.isSubtypeOf(reflectClass(ProviderFunction))) {
							if (variableType.typeArguments.length == 1) {
								var typeMirror = variableType.typeArguments[0];

								if (typeMirror.isSubclassOf(reflectClass(Future))) {
									if (typeMirror.typeArguments.length == 1) {
										typeMirror = typeMirror.typeArguments[0];
									} else {
										throw new ArgumentError();
									}
								}

								reflect(instance).setField(symbol, Registry.lookupProviderFunction(typeMirror.reflectedType));
							} else {
								throw new ArgumentError();
							}
						} else {
							throw new ArgumentError();
						}
					}
				}
			});

			classMirror = classMirror.superclass;
		}
	}

	static Future _notifyPostOpenedListeners(Scope scope) => _notifyScopeListeners(_getScopeListeners(scope,
			OnScopeOpened), scope, false);

	static Future _notifyPreClosingListeners(Scope scope) => _notifyScopeListeners(_getScopeListeners(scope,
			OnScopeClosing), scope, true);

	static void _notifyPostBindListeners(instance, Scope scope) {
		_notifyListeners(reflect(instance), _getInstanceListeners(instance, OnBind), scope);
	}

	static Future _notifyPreUnbindListeners(instance, Scope scope) =>
		_notifyFutureListeners(reflect(instance), new List.from(_getInstanceListeners(instance, OnUnbinding).reversed), scope);

	static void _notifyPostProvidedBindListeners(provider, instance, Scope scope) {
		_notifyProvidedListeners(reflect(provider), instance, _getInstanceListeners(provider, OnProvidedBind), scope);
	}

	static Future _notifyPreProvidedUnbindListeners(provider, instance, Scope scope) =>
		_notifyFutureProvidedListeners(reflect(provider), instance, new List.from(_getInstanceListeners(provider,
				OnProvidedUnbinding).reversed), scope);

	static List<Symbol> _getInstanceListeners(instance, bindType) => _getTypeListeners(instance.runtimeType, bindType);

	static Map<Type, _BindingListeners> _getScopeListeners(Scope scope, bindType) {
		var listeners = {};
		_MODULE._bindings.forEach((clazz, binding) {
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
				if (binding.provider is _ToInstanceProvider) {
					target = binding.provider._instance.runtimeType;
				} else if (binding.provider is _ToClassProvider) {
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

	static List<Symbol> _getTypeListeners(type, bindType) {
		var listeners = [];
		var classMirror = reflectType(type);
		while (classMirror != null) {
			classMirror.declarations.forEach((symbol, DeclarationMirror mirror) {
				if (mirror is MethodMirror) {
					if (mirror.metadata.contains(reflect(bindType))) {
						listeners.add(symbol);
					}
				}
			});

			classMirror = classMirror.superclass;
		}
		return listeners;
	}

	static void _notifyListeners(InstanceMirror instanceMirror, List<Symbol> listeners, Scope scope) => listeners.forEach(
			(listener) => instanceMirror.invoke(listener, []));

	static Future _notifyFutureListeners(InstanceMirror instanceMirror, List<Symbol> listeners, Scope scope) =>
		Future.forEach(listeners, (listener) => instanceMirror.invoke(listener, []).reflectee);

	static void _notifyProvidedListeners(InstanceMirror providerMirror, instance, List<Symbol> listeners, Scope scope) =>
			listeners.forEach((listener) => providerMirror.invoke(listener, [instance]));

	static Future _notifyFutureProvidedListeners(InstanceMirror providerMirror, instance, List<Symbol> listeners, Scope scope) =>
			Future.forEach(listeners, (listener) => providerMirror.invoke(listener, [instance]).reflectee);

	static Future _notifyScopeListeners(Map<Type, _BindingListeners> listeners, Scope scope, bool reversed) {
		Iterable keys = reversed ? new List.from(listeners.keys, growable: false).reversed : listeners.keys;
		return Future.forEach(keys, (clazz) {
			_BindingListeners bindingListeners = listeners[clazz];
			var providerMirror = bindingListeners.providerListeners.isNotEmpty ? reflect(bindingListeners.provider) : null;
			var instance = bindingListeners.instanceListeners.isNotEmpty ? lookupObject(clazz) : null;
			return Future.forEach(bindingListeners.providerListeners, (listener) => providerMirror.invoke(listener,
					[]).reflectee).then((_) => instance).then((value) {
				var valueMirror = reflect(instance);
				return Future.forEach(bindingListeners.instanceListeners, (listener) => valueMirror.invoke(listener, []).reflectee);
			});
		});
	}
}

_newInstanceFromClass(Type clazz) {
	ClassMirror mirror = reflectClass(clazz);
	var object = mirror.newInstance(MirrorSystem.getSymbol(""), []);
	return object.reflectee;
}

class _ScopeContext {

	final Scope _scope;

	final Map<Provider, dynamic> _bindings = {};

	_ScopeContext(this._scope);

	Scope get scope => _scope;

	Map<Provider, dynamic> get bindings => _bindings;
}

class _Inject {
	const _Inject();
}

class _OnScopeOpened {
	const _OnScopeOpened();
}

class _OnScopeClosing {
	const _OnScopeClosing();
}

class _OnBind {
	const _OnBind();
}

class _OnUnbinding {
	const _OnUnbinding();
}

class _OnProvidedBind {
	const _OnProvidedBind();
}

class _OnProvidedUnbinding {
	const _OnProvidedUnbinding();
}

class _ToFunctionProvider<T> extends Provider<T> {

	final ProviderFunction<T> _function;

	_ToFunctionProvider(this._function);

	T get() => _function();
}

class _ToClassProvider<T> extends Provider<T> {

	final Type _clazz;

	_ToClassProvider(this._clazz);

	T get() => _newInstanceFromClass(this._clazz);
}

class _ToInstanceProvider<T> extends Provider<T> {

	final T _instance;

	_ToInstanceProvider(this._instance);

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
	final List<Symbol> providerListeners = [];
	final List<Symbol> instanceListeners = [];
	_BindingListeners(this.provider);
}
