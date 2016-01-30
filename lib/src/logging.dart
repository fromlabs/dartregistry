library dartregistry.logging;

import "package:logging/logging.dart";

import "annotations.dart";
import "registry.dart";

@injectable
abstract class Loggable {
  Logger _logger;

  Logger get logger {
    if (_logger == null) {
      _logger = createLogger();
      if (_logger == null) {
        _logger = new Logger("dartregistry.logging.Loggable");

        _logger.warning(
            "Can't find a logger for $this. Annotate the class ${this.runtimeType} with @injectable annotation or override createLogger() method and provide a Logger");
      }
    }
    return _logger;
  }

  Logger createLogger() {
    var classDescriptor = Registry.getInstanceClass(this);
    return classDescriptor != null
        ? new Logger(classDescriptor.qualifiedName)
        : null;
  }

  bool isLoggable(Level value) => logger.isLoggable(value);

  void shout(message, [Object error, StackTrace stackTrace]) =>
      logger.shout(message, error, stackTrace);

  void severe(message, [Object error, StackTrace stackTrace]) =>
      logger.severe(message, error, stackTrace);

  void warning(message, [Object error, StackTrace stackTrace]) =>
      logger.warning(message, error, stackTrace);

  void info(message, [Object error, StackTrace stackTrace]) =>
      logger.info(message, error, stackTrace);

  void config(message, [Object error, StackTrace stackTrace]) =>
      logger.config(message, error, stackTrace);

  void fine(message, [Object error, StackTrace stackTrace]) =>
      logger.fine(message, error, stackTrace);

  void finer(message, [Object error, StackTrace stackTrace]) =>
      logger.finer(message, error, stackTrace);

  void finest(message, [Object error, StackTrace stackTrace]) =>
      logger.finest(message, error, stackTrace);
}