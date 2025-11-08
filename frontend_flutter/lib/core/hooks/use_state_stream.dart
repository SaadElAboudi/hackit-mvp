import 'package:flutter_hooks/flutter_hooks.dart';
import '../core/state/app_state_manager.dart';
import 'package:get_it/get_it.dart';

T useStateStream<T>(String key, {T? initialValue}) {
  final stateManager = GetIt.I<AppStateManager>();
  final state = useState<T?>(initialValue);

  useEffect(() {
    final subscription = stateManager
        .getStateStream<T>(key)
        .listen(
          (value) => state.value = value,
          onError: (error) => print('Error in state stream $key: $error'),
        );

    return subscription.cancel;
  }, [key]);

  return state.value ?? initialValue as T;
}

T useCombinedState<T>({
  required List<String> keys,
  required T Function(List<dynamic>) combiner,
  T? initialValue,
}) {
  final stateManager = GetIt.I<AppStateManager>();
  final state = useState<T?>(initialValue);

  useEffect(() {
    final subscription = stateManager
        .combineStates(
          keys: keys,
          combiner: combiner,
        )
        .listen(
          (value) => state.value = value,
          onError: (error) => print('Error in combined state: $error'),
        );

    return subscription.cancel;
  }, [keys.join(',')]);

  return state.value ?? initialValue as T;
}

T useDerivedState<S, T>({
  required String sourceKey,
  required T Function(S) derivation,
  T? initialValue,
}) {
  final stateManager = GetIt.I<AppStateManager>();
  final state = useState<T?>(initialValue);

  useEffect(() {
    final subscription = stateManager
        .createDerivedState<S, T>(
          sourceKey: sourceKey,
          derivation: derivation,
        )
        .listen(
          (value) => state.value = value,
          onError: (error) =>
              print('Error in derived state for $sourceKey: $error'),
        );

    return subscription.cancel;
  }, [sourceKey]);

  return state.value ?? initialValue as T;
}

T useFilteredState<T>({
  required String key,
  required bool Function(T) predicate,
  T? initialValue,
}) {
  final stateManager = GetIt.I<AppStateManager>();
  final state = useState<T?>(initialValue);

  useEffect(() {
    final subscription = stateManager
        .filterState<T>(key, predicate)
        .listen(
          (value) => state.value = value,
          onError: (error) => print('Error in filtered state for $key: $error'),
        );

    return subscription.cancel;
  }, [key]);

  return state.value ?? initialValue as T;
}