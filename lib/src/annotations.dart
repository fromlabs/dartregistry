library dartregistry.annotations;

import 'package:reflectable/reflectable.dart';

const Injectable injectable = const Injectable();
const Inject inject = const Inject();

const onScopeOpened = const OnScopeOpened();
const onScopeClosing = const OnScopeClosing();

const onBind = const OnBind();
const onUnbinding = const OnUnbinding();

const onProvidedBind = const OnProvidedBind();
const onProvidedUnbinding = const OnProvidedUnbinding();

class Injectable extends Reflectable {
  const Injectable()
      : super(
            metadataCapability,
            typeRelationsCapability,
            declarationsCapability,
            instanceInvokeCapability,
            newInstanceCapability);
}

@injectable
class Inject {
  final Type type;

  const Inject([this.type]);
}

@injectable
class OnScopeOpened {
  const OnScopeOpened();
}

@injectable
class OnScopeClosing {
  const OnScopeClosing();
}

@injectable
class OnBind {
  const OnBind();
}

@injectable
class OnUnbinding {
  const OnUnbinding();
}

@injectable
class OnProvidedBind {
  const OnProvidedBind();
}

@injectable
class OnProvidedUnbinding {
  const OnProvidedUnbinding();
}
