import 'package:flutter/material.dart';
import '../bloc/connectivity_bloc.dart';
import '../offline/offline_manager.dart';

class OfflineBanner extends StatelessWidget {
  final OfflineManager offlineManager;

  const OfflineBanner({
    super.key,
    required this.offlineManager,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: offlineManager.isOnline,
      builder: (context, snapshot) {
        if (snapshot.hasData && !snapshot.data!) {
          return Container(
            color: Colors.orange,
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.cloud_off,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Mode hors ligne - Les modifications seront synchronisées plus tard',
                  style: TextStyle(color: Colors.white),
                ),
                StreamBuilder<List<PendingAction>>(
                  stream: offlineManager.pendingActions,
                  builder: (context, actionSnapshot) {
                    if (actionSnapshot.hasData && 
                        actionSnapshot.data!.isNotEmpty) {
                      return Chip(
                        label: Text(
                          '${actionSnapshot.data!.length}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        backgroundColor: Colors.orange[700],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}