import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/network_info.dart';
import 'injection.config.dart';

final GetIt getIt = GetIt.instance;

@InjectableInit(
  initializerName: 'init',
  preferRelativeImports: true,
  asExtension: true,
)
@module
abstract class RegisterModule {
  @singleton
  NetworkInfo provideNetworkInfo(Connectivity connectivity) => 
    NetworkInfoImpl(connectivity);
    
  @singleton
  http.Client provideHttpClient() => http.Client();
  @preResolve
  @singleton
  Future<SharedPreferences> get sharedPreferences => 
    SharedPreferences.getInstance();

  @singleton
  FlutterSecureStorage get secureStorage => 
    const FlutterSecureStorage();

  @preResolve
  @singleton
  Future<Connectivity> get connectivity =>
    Future.value(Connectivity());
}

Future<void> configureDependencies() => getIt.init();