@GlobalQuantifyCapability(r"^dart.core.DateTime$", Injectable)
import 'package:reflectable/reflectable.dart';

import "package:dartregistry/dart_registry2.dart";

import "dart:async";

import "package:logging/logging.dart";

class TestModule extends RegistryModule {
  static const SCOPE = const Scope("NUOVO");

  @override
  Future configure(Map<String, dynamic> parameters) =>
      super.configure(parameters).then((_) {
        bindClass(LogService, Scope.ISOLATE);
        bindClass(MyService, Scope.ISOLATE, MyServiceImpl);
        bindClass(InjectService, SCOPE, InjectServiceImpl);
        bindProvider(String, Scope.ISOLATE, new StringProvider("ECCOLO"));
        bindProvider(DateTime, Scope.ISOLATE, new DateProvider());

        // bindClass(InjectService2, SCOPE, InjectService2Impl);
        // bindProviderFunction(InjectService2, Scope.ISOLATE, () => new InjectService2Impl());
      });
}

Future test() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord logRecord) {
    print('${logRecord.level.name}: ${logRecord.time}: ${logRecord.message}');
    if (logRecord.stackTrace != null) {
      print(logRecord.error);
      print(logRecord.stackTrace);
    }
  });

  print("Test");

  MyService service = Registry.lookupObject(MyService);

  Injectable.reflect(new DateProvider());

  return service.echo("Eccomi").then((msg) => print("Echo: $msg"));
}

@Injectable
abstract class Loggable {
  @Inject
  Provider<LogService> LOG_SERVICE_PROVIDER;

  LogService get LOG_SERVICE => LOG_SERVICE_PROVIDER.get();

  void info(String msg) {
    LOG_SERVICE.info(msg);
  }
}

@Injectable
class LogService {
  void info(String msg) {
    print(msg);
  }
}

class InjectServiceImpl implements InjectService {
  @OnScopeOpened
  init() {
    print("*** init ***");
    return new Future.delayed(new Duration(seconds: 1))
        .then((_) => print("*** init ok ***"));
  }

  @OnScopeClosing
  deinit() {
    print("*** deinit ***");
    return new Future.delayed(new Duration(seconds: 1))
        .then((_) => print("*** deinit ok ***"));
  }

  String echo(String msg) => msg;
}

class InjectService2Impl implements InjectService2 {}

@Injectable
abstract class InjectService {
  String echo(String msg);
}

abstract class InjectService2 {}

@Injectable
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
    future
        .then((date) => print("DateProvider preProvidedUnbind finish: $date"));
  }
}

@Injectable
class StringProvider extends Provider<String> {
  final String msg;
  StringProvider(this.msg);

  @override
  String get() => msg;

  @OnScopeOpened
  init() {
    print("*** init 2 ***");
    return new Future.delayed(new Duration(seconds: 1))
        .then((_) => print("*** init 2 ok ***"));
  }

  @OnScopeClosing
  deinit() {
    print("*** deinit 2 ***");
    return new Future.delayed(new Duration(seconds: 1))
        .then((_) => print("*** deinit 2 ok ***"));
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

@Injectable
abstract class MyService {
  Future<String> echo(String msg);
}

class MyServiceImpl extends BaseService with Loggable implements MyService {
  Future<String> echo(String msg) {
    info("-> Start");
    return super
        .echo(msg)
        .then((response) => info(response))
        .whenComplete(() => info("<- End"));
  }
}

@Injectable
abstract class BaseService {
  @Inject
  Provider<Future<DateTime>> dateProvider;

  @Inject
  Provider<String> stringProvider;

  @Inject
  Provider<InjectService> injectServiceProvider;

  // TODO provide
  // @Inject
  // ProviderFunction<InjectService> provideInjectService;

  InjectService get injectService => injectServiceProvider.get();

  @OnBind
  void postBind() => print("postBind");

  @OnUnbinding
  void preUnbind() => print("preUnbind");

  Future<String> echo(String msg) {
    // print(provideInjectService);

    // print("****************** ${provideInjectService()}");

    return dateProvider.get().then((date) => stringProvider.get() +
        ":" +
        injectService.echo(msg) +
        "@" +
        date.toString());
  }

  String asyncEcho(String msg) => injectService.echo(msg);
}

main() {
  print("Inizio");
  Registry
      .load(TestModule)
      .then((_) => Registry.openScope(Scope.ISOLATE))
      .then((_) => Registry.runInScope(TestModule.SCOPE, () => test()))
      .whenComplete(() => Registry.closeScope(Scope.ISOLATE))
      .whenComplete(() => Registry.unload())
      .whenComplete(() => print("Fine"));
}
