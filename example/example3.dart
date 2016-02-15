library example;

import "dart:async";

import "package:logging/logging.dart";

import "package:dartregistry/dartregistry.dart";

final Logger _libraryLogger = new Logger("example");

const Scope REQUEST_SCOPE = const Scope("REQUEST");

@injectable
class ExampleModule extends RegistryModule {
  @override
  void configure() {
    bindClass(Service, Scope.ISOLATE);

    bindProvideFunction(
        Connection,
        REQUEST_SCOPE,
        () => new Future.delayed(new Duration(seconds: 1))
            .then((_) => new ConnectionImpl()));
  }
}

@injectable
class Service {
  @Inject(Connection)
  Provider<Future<Connection>> connectionProvider;

  Future run() async {
    var connection = await connectionProvider.get();
    await connection.query();
  }
}

@injectable
abstract class Connection {
  Future query();
}

@injectable
class ConnectionImpl implements Connection {
  Future query() async {
    print("Query execution...");
    await new Future.delayed(new Duration(seconds: 1));
    print("Query executed!");
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
      print("Request begin");
      await Registry.runInScope(REQUEST_SCOPE, () async {
        var service = Registry.lookupObject(Service) as Service;
        await service.run();
      });
      print("Request end");
    });
  } finally {
    Registry.unload();
  }
}
