import "package:dartregistry/dart_registry.dart";

import "dart:async";

class TestModule extends RegistryModule {

	static const SCOPE = const Scope("NUOVO");

	@override
	Future configure(Map<String, dynamic> parameters) => super.configure(parameters).then((_) {
		bindClass(LogService, Scope.ISOLATE);
		bindClass(MyService, Scope.ISOLATE, MyServiceImpl);
		bindClass(InjectService, SCOPE, InjectServiceImpl);
		bindProvider(String, Scope.ISOLATE, new StringProvider("ECCOLO"));
		bindProvider(DateTime, Scope.ISOLATE, new DateProvider());
	});
}

Future test() {
	print("Test");

	MyService service = Registry.lookupObject(MyService);

	return service.echo("Eccomi").then((msg) => print("Echo: $msg"));
}

abstract class Loggable {

	@Inject
	Provider<LogService> _LOG_SERVICE_PROVIDER;

	LogService get LOG_SERVICE => _LOG_SERVICE_PROVIDER.get();

	void info(String msg) {
		LOG_SERVICE.info(msg);
	}
}

class LogService {
	void info(String msg) {
    		print(msg);
    	}
}

class InjectServiceImpl implements InjectService {

	@OnScopeOpened
	init() {
		print("*** init ***");
		return new Future.delayed(new Duration(seconds: 1)).then((_) => print("*** init ok ***"));
	}

	@OnScopeClosing
	deinit() {
		print("*** deinit ***");
		return new Future.delayed(new Duration(seconds: 1)).then((_) => print("*** deinit ok ***"));
	}

	String echo(String msg) => msg;

}

abstract class InjectService {

	String echo(String msg);
}

class DateProvider extends Provider<Future<DateTime>> {

	@override
	Future<DateTime> get() => new Future.value(new DateTime.now());

	@OnBind
	void postBind1() {
		print("DateProvider postBind");
	}

	@OnUnbinding
	void preUnbind1() {
		print("DateProvider preUnbind");
	}

	@OnProvidedBind
	void postProvidedBind(Future future) {
		print("DateProvider postProvidedBind");
		future.then((date) => print("DateProvider postProvidedBind finish: $date"));
	}

	@OnProvidedUnbinding
	void preProvidedUnbind(Future future) {
		print("DateProvider preProvidedUnbind");
		future.then((date) => print("DateProvider preProvidedUnbind finish: $date"));
	}
}

class StringProvider extends Provider<String> {

	final String msg;
	StringProvider(this.msg);

	@override
	String get() => msg;

	@OnScopeOpened
    	init() {
    		print("*** init 2 ***");
    		return new Future.delayed(new Duration(seconds: 1)).then((_) => print("*** init 2 ok ***"));
    	}

    	@OnScopeClosing
    	deinit() {
    		print("*** deinit 2 ***");
    		return new Future.delayed(new Duration(seconds: 1)).then((_) => print("*** deinit 2 ok ***"));
    	}

	@OnBind
	void postBind() {
		print("StringProvider postBind");
	}

	@OnUnbinding
	void preUnbind() {
		print("StringProvider preUnbind");
	}

	@OnProvidedBind
	void postProvidedBind(instance) {
		print("StringProvider postProvidedBind: $instance");
	}

	@OnProvidedUnbinding
	void preProvidedUnbind(instance) {
		print("StringProvider preProvidedUnbind: $instance");
	}
}

abstract class MyService {
	Future<String> echo(String msg);
}

class MyServiceImpl extends BaseService with Loggable implements MyService {
	Future<String> echo(String msg) {
		info("-> Start");
		return super.echo(msg).whenComplete(() => info("<- End"));
	}
}

abstract class BaseService {

	@Inject
	Provider<Future<DateTime>> dateProvider;

	@Inject
	Provider<String> stringProvider;

	@Inject
	Provider<InjectService> injectServiceProvider;

	InjectService get injectService => injectServiceProvider.get();

	@OnBind
	void postBind() => print("postBind");

	@OnUnbinding
	void preUnbind() => print("preUnbind");

	Future<String> echo(String msg) {
		return dateProvider.get().then((date) => stringProvider.get() + ":" + injectService.echo(msg) + "@" + date.toString());
	}

	String asyncEcho(String msg) => injectService.echo(msg);
}

main() {
	print("Inizio");
	Registry.load(TestModule)
	.then((_) => Registry.openScope(Scope.ISOLATE))
	.then((_) => Registry.runInScope(TestModule.SCOPE, () => test()))
	.whenComplete(() => Registry.closeScope(Scope.ISOLATE))
	.whenComplete(() => Registry.unload())
	.whenComplete(() => print("Fine"));
}
