class DemoUser {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final bool isDemo;

  const DemoUser({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.isDemo = false,
  });

  // Stub authentication method to avoid NoSuchMethodError
  Future<bool> authentication() async {
    // Demo users always "succeed" authentication
    return true;
  }
}
