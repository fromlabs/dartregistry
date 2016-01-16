@GlobalQuantifyCapability(r"^dart.core.(String|DateTime)$", injectable)
import 'package:reflectable/reflectable.dart';

import "package:dartregistry/dart_registry.dart";

import "dart:async";

import "package:logging/logging.dart";
import "package:stack_trace/stack_trace.dart";

final _logger = Logger.root;

@injectionModule
class TestModule extends RegistryModule {
  static const SCOPE = const Scope("NUOVO");

  @override
  Future configure(Map<String, dynamic> parameters) =>
      super.configure(parameters).then((_) {
        _logger.info("Configure");

        bindClass(LogService, Scope.ISOLATE);
        bindClass(MyService, Scope.ISOLATE, MyServiceImpl);
        bindClass(InjectService, SCOPE, InjectServiceImpl);
        bindProvider(String, Scope.ISOLATE, new StringProvider("ECCOLO"));
        bindProvider(DateTime, Scope.ISOLATE, new DateProvider());
      });
}

test() async {
  _logger.info("Test");

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
    _logger.info(msg);
  }
}

@injectable
class InjectServiceImpl implements InjectService {
  @onScopeOpened
  init() async {
    _logger.info("*** init InjectServiceImpl ***");

    await new Future.delayed(new Duration(seconds: 1));

    _logger.info("*** init InjectServiceImpl ok ***");
  }

  @onScopeClosing
  deinit() async {
    _logger.info("*** deinit InjectServiceImpl ***");

    await new Future.delayed(new Duration(seconds: 1));

    _logger.info("*** deinit InjectServiceImpl ok ***");
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
    _logger.info("DateProvider postBind");
  }

  @onUnbinding
  void preUnbind1() {
    _logger.info("DateProvider preUnbind");
  }

  @onProvidedBind
  void postProvidedBind(Future future) {
    _logger.info("DateProvider postProvidedBind");

    future.then(
        (date) => _logger.info("DateProvider postProvidedBind finish: $date"));
  }

  @onProvidedUnbinding
  void preProvidedUnbind(Future future) {
    _logger.info("DateProvider preProvidedUnbind");

    future.then(
        (date) => _logger.info("DateProvider preProvidedUnbind finish: $date"));
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
    _logger.info("*** init StringProvider ***");

    await new Future.delayed(new Duration(seconds: 1));

    _logger.info("*** init StringProvider ok ***");
  }

  @onScopeClosing
  deinit() async {
    _logger.info("*** deinit StringProvider ***");

    await new Future.delayed(new Duration(seconds: 1));

    _logger.info("*** deinit StringProvider ok ***");
  }

  @onBind
  void postBind() {
    _logger.info("StringProvider postBind");
  }

  @onUnbinding
  void preUnbind() {
    _logger.info("StringProvider preUnbind");
  }

  @onProvidedBind
  void postProvidedBind(instance) {
    _logger.info("StringProvider postProvidedBind: $instance");
  }

  @onProvidedUnbinding
  void preProvidedUnbind(instance) {
    _logger.info("StringProvider preProvidedUnbind: $instance");
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

  @Inject(InjectService)
  InjectService injectService;

  @Inject(InjectService)
  Provider<InjectService> injectServiceProvider;

  @Inject(InjectService)
  ProvideFunction<InjectService> provideInjectService;

  InjectService get injectService3 => provideInjectService();

  InjectService get injectService2 => injectServiceProvider.get();

  @onBind
  void postBind() => _logger.info("postBind");

  @onUnbinding
  void preUnbind() => _logger.info("preUnbind");

  Future<String> echo(String msg) async {
    var date = await dateProvider.get();

    return "${stringProvider.get()}:${injectService.echo(msg)}@$date";
  }

  String asyncEcho(String msg) => injectService.echo(msg);
}

main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord logRecord) {
    print('${logRecord.level.name}: ${logRecord.time}: ${logRecord.message}');
    if (logRecord.error != null) {
      print(logRecord.error);
    }
    if (logRecord.stackTrace != null) {
      print(Trace.format(logRecord.stackTrace));
    }
  });

  _logger.info("Inizio");

  await Registry.load(TestModule);

  await Registry.openScope(Scope.ISOLATE);

  await Registry.runInScope(TestModule.SCOPE, () => test());

  await Registry.closeScope(Scope.ISOLATE);

  await Registry.unload();

  _logger.info("Fine");
}
