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
    info("Configure module...");

    // provide a binding with a class
    bindProvider(Configuration, Scope.ISOLATE, new ConfigurationProvider());

    // bind an instance
    bindInstance(ConnectionManager, new ConnectionManager());

    // bind a class
    bindClass(ExampleService, Scope.ISOLATE, ExampleServiceImpl);

    // provide a binding with a function
    bindProvideFunction(Connection, REQUEST_SCOPE, () async {
      info("Provide a connection...");

      // simulate a delay
      await new Future.delayed(new Duration(seconds: 1));

      info("Connection provided");

      return new Connection();
    });

    info("Module configured");
  }

  @override
  void unconfigure() {
    info("Module unconfigured");
  }
}

main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print(record);
  });

  try {
    _libraryLogger.info("Begin example");

    Registry.load(new ExampleModule());

    try {
      await Registry.openScope(Scope.ISOLATE);

      await Registry.runInScope(REQUEST_SCOPE, () => request());
    } finally {
      await Registry.closeScope(Scope.ISOLATE);
    }
  } finally {
    Registry.unload();

    _libraryLogger.info("End example");
  }
}

Future request() async {
  _libraryLogger.info("Start request...");

  // static access on Registry for a lookup
  ExampleService service = Registry.lookupObject(ExampleService);

  var result = await service.execute("MY REQUEST");

  _libraryLogger.info("Request end with result: $result");
}

@injectable
class Configuration {
  final String data;

  Configuration(this.data);
}

@injectable
class ConfigurationProvider extends Loggable
    implements Provider<Future<Configuration>> {
  @override
  Future<Configuration> get() async {
    info("Provide a configuration...");

    // simulate a delay
    await new Future.delayed(new Duration(seconds: 1));

    info("Configuration provided");

    return new Configuration("CONFIGURATION");
  }

  @onBind
  void postBind() {
    info("ConfigurationProvider bound");
  }

  @onUnbinding
  void preUnbind() {
    info("Unbinding ConfigurationProvider");
  }

  @onProvidedBind
  void postProvidedBind(Future<Configuration> configurationFuture) {
    info("ConfigurationProvider postProvidedBind");

    configurationFuture.then((configuration) {
      info(
          "ConfigurationProvider postProvidedBind finish: ${configuration.data}");
    });
  }

  @onProvidedUnbinding
  void preProvidedUnbind(Future<Configuration> configurationFuture) {
    info("ConfigurationProvider preProvidedUnbind");

    configurationFuture.then((configuration) => info(
        "ConfigurationProvider preProvidedUnbind finish: ${configuration.data}"));
  }
}

@injectable
class ConnectionManager extends Loggable {
  // TODO
  @Inject(Configuration)
  Future<Configuration> configuration;

  @onScopeOpened
  Future configure() async {
    info("Configure connection manager...");

    // simulate a delay
    await new Future.delayed(new Duration(seconds: 1));

    info("Connection manager configured");
  }

  Connection createConnection() {
    info("Create connection");

    return new Connection();
  }

  @onScopeClosing
  Future close() async {
    info("Closing connection manager...");

    // simulate a delay
    await new Future.delayed(new Duration(seconds: 1));

    info("Connection manager closed");
  }
}

@injectable
class Connection extends Loggable {
  Future<String> query(String query) async {
    info("Start query");

    // simulate a delay
    await new Future.delayed(new Duration(seconds: 1));

    info("End query");

    return "RESULT OF: $query";
  }

  @onScopeClosing
  Future close() async {
    info("Closing connection...");

    // simulate a delay
    await new Future.delayed(new Duration(seconds: 1));

    info("Connection closed");
  }
}

@injectable
abstract class ExampleService {
  Future<String> execute(String request);
}

@injectable
class ExampleServiceImpl extends Loggable implements ExampleService {

  @Inject(Connection)
  Provider<Connection> connectionProvider;

  Future<String> execute(String request) async {
    info("Executing request...");

    // simulate a delay
    await new Future.delayed(new Duration(seconds: 1));

    info("Executed!");

    return request;
  }
}
