library example;

import "package:logging/logging.dart";

import "package:dartregistry/dartregistry.dart";

final Logger _libraryLogger = new Logger("example");

const Scope REQUEST_SCOPE = const Scope("REQUEST");

@injectable
class ExampleModule extends RegistryModule {
  @override
  void configure() {
    bindClass(GlobalService, Scope.ISOLATE);

    bindClass(RequestService, REQUEST_SCOPE);
  }
}

@injectable
class GlobalService {
  @inject
  RequestService service;

  @inject
  Provider<RequestService> serviceProvider;

  test() {
    service.test();
  }

  testProvider() {
    serviceProvider.get().test();
  }
}

@injectable
class RequestService {
  @inject
  GlobalService service;

  test() {
    print("request");
  }
}

main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print("*****");
    print(record);
    print(record.error);
    print(record.stackTrace);
  });

  try {
    Registry.load(new ExampleModule());

    await Registry.runInIsolateScope(() async {
      await Registry.runInScope(REQUEST_SCOPE, () {
        Registry.lookupObject(GlobalService).test();

        Registry.lookupObject(GlobalService).testProvider();
      });
    });
  } finally {
    Registry.unload();
  }
}
