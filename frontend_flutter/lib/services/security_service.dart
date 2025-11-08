import 'package:injectable/injectable.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

@singleton
class SecurityService {
  static const _keyPrefix = 'hackit_mvp_';
  final FlutterSecureStorage _secureStorage;
  late final Encrypter _encrypter;
  late final IV _iv;

  SecurityService(this._secureStorage) {
    _initializeEncryption();
  }

  Future<void> _initializeEncryption() async {
    // Récupérer ou générer la clé de chiffrement
    String? encryptionKey = await _secureStorage.read(key: '${_keyPrefix}encryption_key');
    if (encryptionKey == null) {
      // Générer une nouvelle clé si elle n'existe pas
      final key = Key.fromSecureRandom(32);
      encryptionKey = base64Encode(key.bytes);
      await _secureStorage.write(
        key: '${_keyPrefix}encryption_key',
        value: encryptionKey,
      );
    }

    // Initialiser l'encrypter avec la clé
    final key = Key.fromBase64(encryptionKey);
    _encrypter = Encrypter(AES(key));
    _iv = IV.fromSecureRandom(16);
  }

  // Chiffrement des données sensibles
  String encryptData(String data) {
    return _encrypter.encrypt(data, iv: _iv).base64;
  }

  // Déchiffrement des données
  String decryptData(String encryptedData) {
    final encrypted = Encrypted.fromBase64(encryptedData);
    return _encrypter.decrypt(encrypted, iv: _iv);
  }

  // Gestion sécurisée des tokens
  Future<void> saveToken(String token) async {
    final hashedToken = _hashToken(token);
    await _secureStorage.write(
      key: '${_keyPrefix}auth_token',
      value: hashedToken,
    );
  }

  Future<String?> getToken() async {
    return await _secureStorage.read(key: '${_keyPrefix}auth_token');
  }

  Future<void> deleteToken() async {
    await _secureStorage.delete(key: '${_keyPrefix}auth_token');
  }

  // Protection contre les injections et XSS
  String sanitizeInput(String input) {
    // Échapper les caractères spéciaux HTML
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;')
        .replaceAll('/', '&#x2F;');
  }

  // Génération de noms de fichiers sécurisés
  String generateSecureFilename(String originalFilename) {
    final uuid = const Uuid().v4();
    final extension = originalFilename.split('.').last;
    return '$uuid.$extension';
  }

  // Validation des données
  bool isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  bool isValidPassword(String password) {
    // Au moins 8 caractères, une majuscule, une minuscule, un chiffre et un caractère spécial
    return RegExp(
      r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$',
    ).hasMatch(password);
  }

  // Hachage sécurisé des tokens
  String _hashToken(String token) {
    final bytes = utf8.encode(token);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Protection contre les attaques par force brute
  final Map<String, int> _failedAttempts = {};
  final Map<String, DateTime> _lockoutUntil = {};

  bool isAccountLocked(String userId) {
    final lockoutTime = _lockoutUntil[userId];
    if (lockoutTime != null && lockoutTime.isAfter(DateTime.now())) {
      return true;
    }
    _lockoutUntil.remove(userId);
    return false;
  }

  void recordFailedAttempt(String userId) {
    _failedAttempts[userId] = (_failedAttempts[userId] ?? 0) + 1;
    if (_failedAttempts[userId]! >= 5) {
      // Verrouiller le compte pendant 15 minutes après 5 tentatives échouées
      _lockoutUntil[userId] = DateTime.now().add(const Duration(minutes: 15));
    }
  }

  void resetFailedAttempts(String userId) {
    _failedAttempts.remove(userId);
    _lockoutUntil.remove(userId);
  }

  // Nettoyage périodique des données sensibles
  Future<void> cleanupSensitiveData() async {
    final keys = await _secureStorage.readAll();
    final now = DateTime.now();

    for (final entry in keys.entries) {
      if (entry.key.startsWith('${_keyPrefix}temp_')) {
        // Supprimer les données temporaires après 24h
        final timestamp = int.tryParse(entry.value.split('_').last);
        if (timestamp != null) {
          final creationTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
          if (now.difference(creationTime).inHours >= 24) {
            await _secureStorage.delete(key: entry.key);
          }
        }
      }
    }
  }
}