library test;

@GlobalQuantifyCapability(r"^dart.core.(String|DateTime)$", injectable)
import 'package:reflectable/reflectable.dart';

import "package:dartregistry/dartregistry.dart";

import "dart:async";

import "package:logging/logging.dart";

class TestModule extends RegistryModule {
  static const SCOPE = const Scope("NUOVO");

  @override
  void configure() {
    bindClass(PrintService, Scope.ISOLATE);
    bindClass(MyService, Scope.ISOLATE, MyServiceImpl);
    bindClass(InjectService, SCOPE, InjectServiceImpl);
    bindProvider(String, Scope.ISOLATE, new StringProvider("ECCOLO"));
    bindProvider(DateTime, Scope.ISOLATE, new DateProvider());
  }
}

test() async {
  var logService = Registry.lookupObject(PrintService) as PrintService;
  logService.print("Ciao a tutti");

  MyService service = Registry.lookupObject(MyService);
  return service.echo("Eccomi").then((msg) => print("Echo: $msg"));
}

@injectable
class PrintService extends Loggable {
  void print(String msg) {
    info(msg);
  }
}

@injectable
abstract class Printable {
  @inject
  Provider<PrintService> printServiceProvider;

  PrintService get printService => printServiceProvider.get();

  void print(String msg) {
    printService.print(msg);
  }
}

@injectable
class InjectServiceImpl extends Loggable implements InjectService {
  @onScopeOpened
  init() async {
    info("*** init InjectServiceImpl ***");

    await new Future.delayed(new Duration(seconds: 1));

    info("*** init InjectServiceImpl ok ***");
  }

  @onScopeClosing
  deinit() async {
    info("*** deinit InjectServiceImpl ***");

    await new Future.delayed(new Duration(seconds: 1));

    info("*** deinit InjectServiceImpl ok ***");
  }

  String echo(String msg) => msg;
}

@injectable
abstract class InjectService {
  String echo(String msg);
}

@injectable
class DateProvider extends Loggable implements Provider<Future<DateTime>> {
  @override
  Future<DateTime> get() async => new DateTime.now();

  @onBind
  void postBind1() {
    info("DateProvider postBind");
  }

  @onUnbinding
  void preUnbind1() {
    info("DateProvider preUnbind");
  }

  @onProvidedBind
  void postProvidedBind(Future future) {
    info("DateProvider postProvidedBind");

    future.then((date) => info("DateProvider postProvidedBind finish: $date"));
  }

  @onProvidedUnbinding
  void preProvidedUnbind(Future future) {
    info("DateProvider preProvidedUnbind");

    future.then((date) => info("DateProvider preProvidedUnbind finish: $date"));
  }
}

@injectable
class StringProvider extends Loggable implements Provider<String> {
  final String msg;

  StringProvider(this.msg);

  @override
  String get() => msg;

  @onScopeOpened
  init() async {
    info("*** init StringProvider ***");

    await new Future.delayed(new Duration(seconds: 1));

    info("*** init StringProvider ok ***");
  }

  @onScopeClosing
  deinit() async {
    info("*** deinit StringProvider ***");

    await new Future.delayed(new Duration(seconds: 1));

    info("*** deinit StringProvider ok ***");
  }

  @onBind
  void postBind() {
    info("StringProvider postBind");
  }

  @onUnbinding
  void preUnbind() {
    info("StringProvider preUnbind");
  }

  @onProvidedBind
  void postProvidedBind(instance) {
    info("StringProvider postProvidedBind: $instance");
  }

  @onProvidedUnbinding
  void preProvidedUnbind(instance) {
    info("StringProvider preProvidedUnbind: $instance");
  }
}

@injectable
abstract class MyService {
  Future<String> echo(String msg);
}

@injectable
class MyServiceImpl extends BaseService with Printable implements MyService {
  Future<String> echo(String msg) async {
    print("-> Start");

    print("##################");
    print(injectService.toString());
    print(injectServiceProvider.get().toString());
    print((await dateProvider.get()).toString());
    print((await dateFuture).toString());
    // TODO not supported in Dart2JS
    print(provideInjectService().toString());
    print((await provideDate()).toString());
    print("##################");

    var response = await super.echo(msg);

    print(response);

    print("<- End");

    return response;
  }
}

@injectable
abstract class BaseService extends Loggable {
  @inject
  Provider<Future<DateTime>> dateProvider;

  // TODO not supported in Dart2JS
  @inject
  ProvideFunction<Future<DateTime>> provideDate;

  @inject
  Provider<String> stringProvider;

  @inject
  InjectService injectService;

  @inject
  Provider<InjectService> injectServiceProvider;

  @inject
  Future<DateTime> dateFuture;

  // TODO not supported in Dart2JS
  @inject
  ProvideFunction<InjectService> provideInjectService;

  @onBind
  void postBind() => info("postBind");

  @onUnbinding
  void preUnbind() => info("preUnbind");

  Future<String> echo(String msg) async {
    var date = await dateProvider.get();

    return "${stringProvider.get()}:${injectService.echo(msg)}@$date";
  }

  String asyncEcho(String msg) => injectService.echo(msg);
}

main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print(record);
  });

  Logger.root.info("Inizio");

  Registry.load(new TestModule());
  await Registry.openScope(Scope.ISOLATE);
  await Registry.runInScope(TestModule.SCOPE, () => test());
  await Registry.closeScope(Scope.ISOLATE);
  Registry.unload();

  Logger.root.info("Fine");
}
