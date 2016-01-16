@GlobalQuantifyCapability(r"^dart.core.(String|DateTime)$", Injectable)
import 'package:reflectable/reflectable.dart';

import "package:dartregistry/dart_registry.dart";

import "dart:async";

import "package:logging/logging.dart";
import "package:stack_trace/stack_trace.dart";

final _logger = Logger.root;

@Module
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
    _logger.info(msg);
  }
}

@Injectable
class InjectServiceImpl implements InjectService {
  @OnScopeOpened
  init() async {
    _logger.info("*** init InjectServiceImpl ***");

    await new Future.delayed(new Duration(seconds: 1));

    _logger.info("*** init InjectServiceImpl ok ***");
  }

  @OnScopeClosing
  deinit() async {
    _logger.info("*** deinit InjectServiceImpl ***");

    await new Future.delayed(new Duration(seconds: 1));

    _logger.info("*** deinit InjectServiceImpl ok ***");
  }

  String echo(String msg) => msg;
}

@Injectable
abstract class InjectService {
  String echo(String msg);
}

@Injectable
class DateProvider extends Provider<Future<DateTime>> {
  @override
  Future<DateTime> get() async => new DateTime.now();

  @OnBind
  void postBind1() {
    _logger.info("DateProvider postBind");
  }

  @OnUnbinding
  void preUnbind1() {
    _logger.info("DateProvider preUnbind");
  }

  @OnProvidedBind
  void postProvidedBind(Future future) {
    _logger.info("DateProvider postProvidedBind");

    future.then(
        (date) => _logger.info("DateProvider postProvidedBind finish: $date"));
  }

  @OnProvidedUnbinding
  void preProvidedUnbind(Future future) {
    _logger.info("DateProvider preProvidedUnbind");

    future.then(
        (date) => _logger.info("DateProvider preProvidedUnbind finish: $date"));
  }
}

@Injectable
class StringProvider extends Provider<String> {
  final String msg;

  StringProvider(this.msg);

  @override
  String get() => msg;

  @OnScopeOpened
  init() async {
    _logger.info("*** init StringProvider ***");

    await new Future.delayed(new Duration(seconds: 1));

    _logger.info("*** init StringProvider ok ***");
  }

  @OnScopeClosing
  deinit() async {
    _logger.info("*** deinit StringProvider ***");

    await new Future.delayed(new Duration(seconds: 1));

    _logger.info("*** deinit StringProvider ok ***");
  }

  @OnBind
  void postBind() {
    _logger.info("StringProvider postBind");
  }

  @OnUnbinding
  void preUnbind() {
    _logger.info("StringProvider preUnbind");
  }

  @OnProvidedBind
  void postProvidedBind(instance) {
    _logger.info("StringProvider postProvidedBind: $instance");
  }

  @OnProvidedUnbinding
  void preProvidedUnbind(instance) {
    _logger.info("StringProvider preProvidedUnbind: $instance");
  }
}

@Injectable
abstract class MyService {
  Future<String> echo(String msg);
}

@Injectable
class MyServiceImpl extends BaseService with Loggable implements MyService {
  Future<String> echo(String msg) async {
    info("-> Start");

    var response = await super.echo(msg);

    info(response);

    info("<- End");

    return response;
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

  InjectService get injectService => injectServiceProvider.get();

  @OnBind
  void postBind() => _logger.info("postBind");

  @OnUnbinding
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
