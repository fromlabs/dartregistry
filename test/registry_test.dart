library test;

@GlobalQuantifyCapability(r"^dart.core.(String|DateTime)$", injectable)
import 'package:reflectable/reflectable.dart';

import "package:dartregistry/dart_registry.dart";

import "dart:async";

import "package:logging/logging.dart";

final _libraryLogger = new Logger("test");

class TestModule extends RegistryModule {
  static const SCOPE = const Scope("NUOVO");

  @override
  Future configure() async {
    _libraryLogger.info("Configure");
    await super.configure();

    bindClass(LogService, Scope.ISOLATE);
    bindClass(MyService, Scope.ISOLATE, MyServiceImpl);
    bindClass(InjectService, SCOPE, InjectServiceImpl);
    bindProvider(String, Scope.ISOLATE, new StringProvider("ECCOLO"));
    bindProvider(DateTime, Scope.ISOLATE, new DateProvider());
  }
}

test() async {
  _libraryLogger.info("Test");

  var logService = Registry.lookupObject(LogService) as LogService;
  logService.info("Ciao a tutti");

  MyService service = Registry.lookupObject(MyService);

  return service.echo("Eccomi").then((msg) => print("Echo: $msg"));
}

@injectable
abstract class Loggable {
  @Inject(LogService)
  Provider<LogService> LOG_SERVICE_PROVIDER;

  LogService get LOG_SERVICE => LOG_SERVICE_PROVIDER.get();

  void info(String msg) {
    LOG_SERVICE.info(msg);
  }
}

@injectable
class LogService {
  void info(String msg) {
    _libraryLogger.info(msg);
  }
}

@injectable
class InjectServiceImpl implements InjectService {
  @onScopeOpened
  init() async {
    _libraryLogger.info("*** init InjectServiceImpl ***");

    await new Future.delayed(new Duration(seconds: 1));

    _libraryLogger.info("*** init InjectServiceImpl ok ***");
  }

  @onScopeClosing
  deinit() async {
    _libraryLogger.info("*** deinit InjectServiceImpl ***");

    await new Future.delayed(new Duration(seconds: 1));

    _libraryLogger.info("*** deinit InjectServiceImpl ok ***");
  }

  String echo(String msg) => msg;
}

@injectable
abstract class InjectService {
  String echo(String msg);
}

@injectable
class DateProvider extends Provider<Future<DateTime>> {
  @override
  Future<DateTime> get() async => new DateTime.now();

  @onBind
  void postBind1() {
    _libraryLogger.info("DateProvider postBind");
  }

  @onUnbinding
  void preUnbind1() {
    _libraryLogger.info("DateProvider preUnbind");
  }

  @onProvidedBind
  void postProvidedBind(Future future) {
    _libraryLogger.info("DateProvider postProvidedBind");

    future.then((date) =>
        _libraryLogger.info("DateProvider postProvidedBind finish: $date"));
  }

  @onProvidedUnbinding
  void preProvidedUnbind(Future future) {
    _libraryLogger.info("DateProvider preProvidedUnbind");

    future.then((date) =>
        _libraryLogger.info("DateProvider preProvidedUnbind finish: $date"));
  }
}

@injectable
class StringProvider extends Provider<String> {
  final String msg;

  StringProvider(this.msg);

  @override
  String get() => msg;

  @onScopeOpened
  init() async {
    _libraryLogger.info("*** init StringProvider ***");

    await new Future.delayed(new Duration(seconds: 1));

    _libraryLogger.info("*** init StringProvider ok ***");
  }

  @onScopeClosing
  deinit() async {
    _libraryLogger.info("*** deinit StringProvider ***");

    await new Future.delayed(new Duration(seconds: 1));

    _libraryLogger.info("*** deinit StringProvider ok ***");
  }

  @onBind
  void postBind() {
    _libraryLogger.info("StringProvider postBind");
  }

  @onUnbinding
  void preUnbind() {
    _libraryLogger.info("StringProvider preUnbind");
  }

  @onProvidedBind
  void postProvidedBind(instance) {
    _libraryLogger.info("StringProvider postProvidedBind: $instance");
  }

  @onProvidedUnbinding
  void preProvidedUnbind(instance) {
    _libraryLogger.info("StringProvider preProvidedUnbind: $instance");
  }
}

@injectable
abstract class MyService {
  Future<String> echo(String msg);
}

@injectable
class MyServiceImpl extends BaseService with Loggable implements MyService {
  Future<String> echo(String msg) async {
    info("-> Start");

    info("##################");
    info(injectService.toString());
    info(injectServiceProvider.get().toString());
    info((await dateProvider.get()).toString());
    info((await dateFuture).toString());
    info("##################");

    var response = await super.echo(msg);

    info(response);

    info("<- End");

    return response;
  }
}

@injectable
abstract class BaseService {
  @Inject(DateTime)
  Provider<Future<DateTime>> dateProvider;

  @Inject(String)
  Provider<String> stringProvider;

  @inject
  InjectService injectService;

  @Inject(InjectService)
  Provider<InjectService> injectServiceProvider;

  @Inject(DateTime)
  Future<DateTime> dateFuture;

  @onBind
  void postBind() => _libraryLogger.info("postBind");

  @onUnbinding
  void preUnbind() => _libraryLogger.info("preUnbind");

  Future<String> echo(String msg) async {
    var date = await dateProvider.get();

    return "${stringProvider.get()}:${injectService.echo(msg)}@$date";
  }

  String asyncEcho(String msg) => injectService.echo(msg);
}

main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen(new LogPrintHandler());

  _libraryLogger.info("Inizio");

  await Registry.load(new TestModule());

  await Registry.openScope(Scope.ISOLATE);

  await Registry.runInScope(TestModule.SCOPE, () => test());

  await Registry.closeScope(Scope.ISOLATE);

  await Registry.unload();

  _libraryLogger.info("Fine");
}
