// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          backgroundColor: Colors.white,
          elevation: 3,
          centerTitle: true,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.list_alt_rounded,
                  color: Color(0xFF00C48C), size: 28),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Résultats',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Color(0xFF222B45),
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(
                          color: Color(0x22000000),
                          offset: Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 38,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Color(0xFF00C48C),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ],
          ),
          iconTheme: const IconThemeData(color: Color(0xFF222B45)),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: 10, // À remplacer par la vraie liste de résultats
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                return InkWell(
                  borderRadius: BorderRadius.circular(28),
                  splashColor: Colors.blueAccent.withValues(alpha: 0.1),
                  onTap: () {
                    // Action pour ouvrir le détail du résultat
                  },
                  child: Card(
                    elevation: 7,
                    shadowColor: Colors.blueAccent.withValues(alpha: 0.18),
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28)),
                    margin:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 18),
                      leading: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: const Icon(Icons.search_rounded,
                            color: Colors.blueAccent, size: 28),
                      ),
                      title: Text(
                        'Résultat ${index + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Color(0xFF222B45),
                        ),
                      ),
                      subtitle: const Text(
                        'Détail du résultat',
                        style:
                            TextStyle(color: Color(0xFF8F9BB3), fontSize: 14),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.open_in_new,
                            color: Color(0xFF00C48C)),
                        tooltip: 'Voir le détail',
                        onPressed: () {
                          // Action pour ouvrir le détail du résultat
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 48),
                backgroundColor: const Color(0xFF00C48C),
                foregroundColor: Colors.white,
                textStyle:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 3,
              ),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, size: 22),
              label: const Text('Nouvelle recherche'),
            ),
          ),
        ],
      ),
    );
  }
}
