# dartregistry

A simple dependency injection library inspired by [Google Guice]. 
Currently the library supports advanced futures as providers, provider functions, custom scope contexts, binding listeners, scope listeners.

## Usage

A simple usage example:

    import "package:dartregistry/dartregistry.dart";
    
    @injectable
    class ExampleModule extends RegistryModule {
      @override
      void configure() {
        // bind an instance
        bindInstance(Manager, new Manager());
    
        // bind a class implementation
        bindClass(Worker, Scope.ISOLATE, WorkerImpl);
    
        // bind a provider instance
        // bindProvider(Worker, Scope.ISOLATE, new WorkerProvider());
    
        // bind a provider function
        // bindProvideFunction(Worker, Scope.ISOLATE, () => new WorkerImpl());
      }
    }
    
    @injectable
    class Manager {
      @inject
      Worker worker;
    
      // @inject
      @Inject(Worker)
      Provider<Worker> workerProvider;
    
      void test() {
        print("Manager test");
    
        // accessing directly
        worker.run();
    
        // accessing through a provider
        workerProvider.get().run();
      }
    }
    
    @injectable
    abstract class Worker {
      void run();
    }
    
    @injectable
    class WorkerImpl implements Worker {
    
      @onBind
      void init() {
        print("Worker bind");
      }
    
      @onUnbinding
      void deinit() {
        print("Worker unbind");
      }
    
      @override
      void run() {
        print("Worker run");
      }
    }
    
    @injectable
    class WorkerProvider implements Provider<Worker> {
      @override
      Worker get() => new WorkerImpl();
    }
    
    main() async {
      // load the configuration
      Registry.load(new ExampleModule());
    
      // run inside the isolate scope context
      await Registry.runInIsolateScope(() {
        // lookup an object by its interface
        var manager = Registry.lookupObject(Manager) as Manager;
        manager.test();
    
        // lookups from in-scope bindings return the same instances
        var worker1 = Registry.lookupObject(Worker);
        var worker2 = Registry.lookupObject(Worker);
        assert(identical(worker1, worker2));
      });
    
      // unload the configuration
      Registry.unload();
    }


## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[Google Guice]: https://github.com/google/guice
[tracker]: https://github.com/fromlabs/dartregistry/issues