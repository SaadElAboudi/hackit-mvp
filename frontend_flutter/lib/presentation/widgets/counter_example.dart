import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../core/state/app_state_manager.dart';
import '../core/hooks/use_state_stream.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class CounterExample extends HookWidget {
  const CounterExample({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useStateStream<int>('counter', initialValue: 0);
    final isEven = useDerivedState<int, bool>(
      sourceKey: 'counter',
      derivation: (value) => value % 2 == 0,
      initialValue: true,
    );

    void increment() {
      GetIt.I<AppStateManager>().updateState('counter', count + 1);
    }

    void decrement() {
      GetIt.I<AppStateManager>().updateState('counter', count - 1);
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Count: $count',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(
            'Is Even: ${isEven ? 'Yes' : 'No'}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: decrement,
                child: const Text('Decrement'),
              ),
              const SizedBox(width: 20),
              ElevatedButton(
                onPressed: increment,
                child: const Text('Increment'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}