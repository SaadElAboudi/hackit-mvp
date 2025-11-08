class AppState {
  final Map<String, dynamic> _state = {};

  T? get<T>(String key) => _state[key] as T?;
  
  void set<T>(String key, T value) {
    _state[key] = value;
  }

  void remove(String key) {
    _state.remove(key);
  }

  void clear() {
    _state.clear();
  }

  bool contains(String key) => _state.containsKey(key);
  
  Map<String, dynamic> getAll() => Map.from(_state);
}