// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:connectivity_plus/connectivity_plus.dart' as _i6;
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as _i8;
import 'package:get_it/get_it.dart' as _i1;
import 'package:http/http.dart' as _i5;
import 'package:injectable/injectable.dart' as _i2;
import 'package:shared_preferences/shared_preferences.dart' as _i17;

import '../../cache/cache_manager.dart' as _i3;
import '../../data/cache/cache_manager.dart' as _i4;
import '../../data/core/network_info.dart' as _i13;
import '../../data/offline/offline_manager.dart' as _i14;
import '../../data/repositories/video_repository_impl.dart' as _i20;
import '../../domain/repositories/video_repository.dart' as _i19;
import '../../features/search/data/repositories/search_repository_impl.dart'
    as _i27;
import '../../features/search/data/repository/search_repository_impl.dart'
    as _i26;
import '../../features/search/domain/repository/search_repository.dart' as _i25;
import '../../features/search/domain/usecases/search_usecase.dart' as _i28;
import '../../features/search/presentation/bloc/search_bloc.dart' as _i29;
import '../../presentation/blocs/search_bloc.dart' as _i24;
import '../../services/api_service.dart' as _i21;
import '../../services/deep_link_service.dart' as _i7;
import '../../services/localization_service.dart' as _i10;
import '../../services/security_service.dart' as _i15;
import '../../services/share_service.dart' as _i16;
import '../../services/theme_service.dart' as _i18;
import '../../state/state_manager.dart' as _i22;
import '../error/global_error_handler.dart' as _i9;
import '../network/network_client.dart' as _i11;
import '../network/network_info.dart' as _i12;
import '../state/app_state_manager.dart' as _i23;
import 'injection.dart' as _i30;

extension GetItInjectableX on _i1.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  Future<_i1.GetIt> init({
    String? environment,
    _i2.EnvironmentFilter? environmentFilter,
  }) async {
    final gh = _i2.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    final registerModule = _$RegisterModule();
    gh.singleton<_i3.CacheManager>(() => _i3.CacheManager());
    gh.singletonAsync<_i4.CacheManager>(() {
      final i = _i4.CacheManager();
      return i.init().then((_) => i);
    });
    gh.singleton<_i5.Client>(() => registerModule.provideHttpClient());
    await gh.singletonAsync<_i6.Connectivity>(
      () => registerModule.connectivity,
      preResolve: true,
    );
    gh.singleton<_i7.DeepLinkService>(() => _i7.DeepLinkService());
    gh.singleton<_i8.FlutterSecureStorage>(() => registerModule.secureStorage);
    gh.singleton<_i9.GlobalErrorHandler>(
        () => _i9.GlobalErrorHandler(gh<InvalidType>()));
    gh.singleton<_i10.LocalizationService>(() => _i10.LocalizationService());
    gh.singleton<_i11.NetworkClient>(() => _i11.NetworkClient());
    gh.singleton<_i12.NetworkInfo>(
        () => registerModule.provideNetworkInfo(gh<_i6.Connectivity>()));
    gh.singleton<_i13.NetworkInfo>(
        () => _i13.NetworkInfoImpl(gh<_i6.Connectivity>()));
    gh.singleton<_i12.NetworkInfoImpl>(
        () => _i12.NetworkInfoImpl(gh<_i6.Connectivity>()));
    gh.singletonAsync<_i14.OfflineManager>(() async => _i14.OfflineManager(
          gh<_i13.NetworkInfo>(),
          await getAsync<_i4.CacheManager>(),
        ));
    gh.singleton<_i15.SecurityService>(
        () => _i15.SecurityService(gh<_i8.FlutterSecureStorage>()));
    gh.singleton<_i16.ShareService>(
        () => _i16.ShareService(gh<_i7.DeepLinkService>()));
    await gh.singletonAsync<_i17.SharedPreferences>(
      () => registerModule.sharedPreferences,
      preResolve: true,
    );
    gh.singleton<_i18.ThemeService>(() => _i18.ThemeService(gh<InvalidType>()));
    gh.singletonAsync<_i19.VideoRepository>(
        () async => _i20.VideoRepositoryImpl(
              gh<InvalidType>(),
              await getAsync<_i4.CacheManager>(),
              gh<_i13.NetworkInfo>(),
            ));
    gh.singleton<_i21.ApiService>(() => _i21.ApiService(gh<_i5.Client>()));
    gh.singleton<_i22.AppStateManager>(
        () => _i22.AppStateManager(gh<_i17.SharedPreferences>()));
    gh.singleton<_i23.AppStateManager>(
        () => _i23.AppStateManager(gh<_i17.SharedPreferences>()));
    gh.factoryAsync<_i24.SearchBloc>(
        () async => _i24.SearchBloc(await getAsync<_i19.VideoRepository>()));
    gh.singletonAsync<_i25.SearchRepository>(
        () async => _i26.SearchRepositoryImpl(
              gh<_i21.ApiService>(),
              await getAsync<_i4.CacheManager>(),
              gh<_i12.NetworkInfo>(),
            ));
    gh.singletonAsync<_i27.SearchRepositoryImpl>(
        () async => _i27.SearchRepositoryImpl(
              gh<_i21.ApiService>(),
              await getAsync<_i4.CacheManager>(),
              gh<_i12.NetworkInfo>(),
            ));
    gh.factoryAsync<_i28.SearchUseCase>(() async =>
        _i28.SearchUseCase(await getAsync<_i25.SearchRepository>()));
    gh.factoryAsync<_i29.SearchBloc>(
        () async => _i29.SearchBloc(await getAsync<_i28.SearchUseCase>()));
    return this;
  }
}

class _$RegisterModule extends _i30.RegisterModule {}
