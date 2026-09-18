import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/db/db.dart';

import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/data/profile_data_source.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:uuid/uuid.dart';

abstract interface class ProfileRepository {
  TaskEither<ProfileFailure, Unit> init();
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id);
  TaskEither<ProfileFailure, Unit> setAsActive(String id);
  TaskEither<ProfileFailure, Unit> deleteById(String id, bool isActive);
  Stream<Either<ProfileFailure, ProfileEntity?>> watchActiveProfile();
  Stream<Either<ProfileFailure, bool>> watchHasAnyProfile();
  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  });
  TaskEither<ProfileFailure, Unit> upsertRemote(String url, {UserOverride? userOverride, CancelToken? cancelToken});
  TaskEither<ProfileFailure, Unit> addLocal(String content, {UserOverride? userOverride});
  TaskEither<ProfileFailure, Unit> offlineUpdate(ProfileEntity nProfile, String nContent);
  TaskEither<ProfileFailure, Unit> validateConfig(String path, String tempPath, String? profileOverride, bool debug);
  TaskEither<ProfileFailure, String> generateConfig(String id);
  TaskEither<ProfileFailure, String> getRawConfig(String id);
}

class ProfileRepositoryImpl with ExceptionHandler, InfraLogger implements ProfileRepository {
  ProfileRepositoryImpl({
    required ProfileDataSource profileDataSource,
    required ProfilePathResolver profilePathResolver,
    required HiddifyCoreService singbox,
    required ConfigOptionRepository configOptionRepository,
    required ProfileParser profileParser,
  }) : _profileParser = profileParser,
       _configOptionRepo = configOptionRepository,
       _singbox = singbox,
       _profilePathResolver = profilePathResolver,
       _profileDataSource = profileDataSource;

  final ProfileDataSource _profileDataSource;
  final ProfilePathResolver _profilePathResolver;
  final HiddifyCoreService _singbox;
  final ConfigOptionRepository _configOptionRepo;
  final ProfileParser _profileParser;

  // --- لیست کانفیگ‌های پیش‌فرض که خودت دادی ---
  final List<String> _defaultConfigs = [
    'vless://d3b7c9a2-1234-5678-9abc-def012345678@proxy-1555869700.ghost109test.workers.dev:443?encryption=none&security=tls&sni=proxy-1555869700.ghost109test.workers.dev&fp=randomized&type=ws&host=proxy-1555869700.ghost109test.workers.dev&path=%2F%3Fed%3D2048#server_1',
    'vless://d3b7c9a2-1234-5678-9abc-def012345678@proxy-1555hfne12.kmxgamer01.workers.dev:443?encryption=none&security=tls&sni=proxy-1555hfne12.kmxgamer01.workers.dev&fp=randomized&type=ws&host=proxy-1555hfne12.kmxgamer01.workers.dev&path=%2F%3Fed%3D2048#server_2',
    'vless://d3b7c9a2-1234-5678-9abc-def012345678@proxybehsj2789.infinityfreew3.workers.dev:443?encryption=none&security=tls&sni=proxybehsj2789.infinityfreew3.workers.dev&fp=randomized&type=ws&host=proxybehsj2789.infinityfreew3.workers.dev&path=%2F%3Fed%3D2048#server_3',
    'vless://d3b7c9a2-1234-5678-9abc-def012345678@proxykoojbbbb45.gggfjosoz.workers.dev:443?encryption=none&security=tls&sni=proxykoojbbbb45.gggfjosoz.workers.dev&fp=randomized&type=ws&host=proxykoojbbbb45.gggfjosoz.workers.dev&path=%2F%3Fed%3D2048#server_4',
    'vless://d3b7c9a2-1234-5678-9abc-def012345678@proxyviivigigviivv.gxgxhg56.workers.dev:443?encryption=none&security=tls&sni=proxyviivigigviivv.gxgxhg56.workers.dev&fp=randomized&type=ws&host=proxyviivigigviivv.gxgxhg56.workers.dev&path=%2F%3Fed%3D2048#server_5',
  ];

  // متدی برای اضافه کردن خودکار کانفیگ‌ها
  Future<void> _addDefaultConfigs() async {
    try {
      // گرفتن لیست پروفایل‌های موجود برای جلوگیری از تکراری شدن
      final existingProfilesResult = await _profileDataSource.watchAll(
        sort: ProfilesSort.lastUpdate, 
        sortMode: SortMode.ascending
      ).first;

      // ⚠️ اصلاح خط ۷۹: استفاده از add به جای addAll و map
      final existingNames = existingProfilesResult.fold<List<String>>(
        [], 
        (prev, element) => prev..add(element.toEntity().name)
      );

      for (final config in _defaultConfigs) {
        // استخراج اسم از انتهای کانفیگ (بعد از #)
        final name = config.split('#').last;
        if (!existingNames.contains(name)) {
          // --- استفاده از UserOverride ---
          final userOverride = UserOverride(name: name);
          await addLocal(config, userOverride: userOverride).run();
          loggy.info('Default config $name added successfully.');
        }
      }
    } catch (e, stackTrace) {
      loggy.error('Error adding default configs', e, stackTrace);
    }
  }

  @override
  TaskEither<ProfileFailure, Unit> init() {
    return exceptionHandler(() async {
      if (!kIsWeb) {
        if (!await _profilePathResolver.directory.exists()) {
          await _profilePathResolver.directory.create(recursive: true);
        }
      }

      // --- فراخوانی متد اضافه کردن کانفیگ‌های پیش‌فرض ---
      await _addDefaultConfigs();

      return right(unit);
    }, ProfileUnexpectedFailure.new);
  }

  @override
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id) {
    return TaskEither.tryCatch(
      () => _profileDataSource.getById(id).then((value) => value?.toEntity()),
      ProfileUnexpectedFailure.new,
    );
  }

  @override
  TaskEither<ProfileFailure, Unit> setAsActive(String id) {
    return TaskEither.tryCatch(() async {
      await _profileDataSource.edit(id, const ProfileEntriesCompanion(active: Value(true)));
      return unit;
    }, ProfileUnexpectedFailure.new);
  }

  @override
  TaskEither<ProfileFailure, Unit> deleteById(String id, bool isActive) {
    return TaskEither.tryCatch(() async {
      await _profileDataSource.deleteById(id, isActive);
      await _profilePathResolver.file(id).delete();
      return unit;
    }, ProfileUnexpectedFailure.new);
  }

  @override
  Stream<Either<ProfileFailure, ProfileEntity?>> watchActiveProfile() {
    return _profileDataSource.watchActiveProfile().map((event) => event?.toEntity()).handleExceptions((
      error,
      stackTrace,
    ) {
      loggy.error("error watching active profile", error, stackTrace);
      return ProfileUnexpectedFailure(error, stackTrace);
    });
  }

  @override
  Stream<Either<ProfileFailure, bool>> watchHasAnyProfile() {
    return _profileDataSource
        .watchProfilesCount()
        .map((event) => event != 0)
        .handleExceptions(ProfileUnexpectedFailure.new);
  }

  @override
  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  }) {
    return _profileDataSource
        .watchAll(sort: sort, sortMode: sortMode)
        .map((event) => event.map((e) => e.toEntity()).toList())
        .handleExceptions(ProfileUnexpectedFailure.new);
  }

  @override
  TaskEither<ProfileFailure, Unit> upsertRemote(String url, {UserOverride? userOverride, CancelToken? cancelToken}) =>
      TaskEither.tryCatch(
        () async => await _profileDataSource.getByUrl(url).then((profEntry) => profEntry?.toEntity()),
        ProfileFailure.unexpected,
      ).flatMap((profEntity) {
        // if profile is null, generate id
        final id = profEntity?.id ?? const Uuid().v4();
        final file = _profilePathResolver.file(id);
        final tempFile = _profilePathResolver.tempFile(id);
        try {
          if (profEntity != null && profEntity is RemoteProfileEntity) {
            // Update
            if (userOverride != null) {
              profEntity = profEntity.copyWith(userOverride: userOverride);
            }
            return _profileParser
                .updateRemote(rp: profEntity, tempFilePath: tempFile.path, cancelToken: cancelToken)
                .flatMap(
                  (profEntity) =>
                      validateConfig(
                        file.path,
                        tempFile.path,
                        ProfileParser.profileOverrideHelper(profile: profEntity),
                        false,
                      ).flatMap(
                        (unit) => TaskEither.tryCatch(() async {
                          await _profileDataSource.edit(id, profEntity);
                          return unit;
                        }, ProfileFailure.unexpected),
                      ),
                );
          } else {
            // Add
            return _profileParser
                .addRemote(
                  id: id,
                  url: url,
                  tempFilePath: tempFile.path,
                  userOverride: userOverride,
                  cancelToken: cancelToken,
                )
                .flatMap(
                  (profEntity) =>
                      validateConfig(
                        file.path,
                        tempFile.path,
                        ProfileParser.profileOverrideHelper(profile: profEntity),
                        false,
                      ).flatMap(
                        (unit) => TaskEither.tryCatch(() async {
                          await _profileDataSource.insert(profEntity);
                          return unit;
                        }, ProfileFailure.unexpected),
                      ),
                );
          }
        } finally {
          if (tempFile.existsSync()) tempFile.deleteSync();
        }
      });

  @override
  TaskEither<ProfileFailure, Unit> addLocal(String content, {UserOverride? userOverride}) =>
      TaskEither.tryCatch(() async {
        final id = const Uuid().v4();
        final file = _profilePathResolver.file(id);
        final tempFile = _profilePathResolver.tempFile(id);
        try {
          await tempFile.writeAsString(content);
          final task = _profileParser
              .addLocal(id: id, content: content, tempFilePath: tempFile.path, userOverride: userOverride)
              .flatMap(
                (profEntity) =>
                    validateConfig(
                      file.path,
                      tempFile.path,
                      ProfileParser.profileOverrideHelper(profile: profEntity),
                      false,
                    ).flatMap(
                      (unit) => TaskEither.tryCatch(() async {
                        await _profileDataSource.insert(profEntity);
                        return unit;
                      }, ProfileFailure.unexpected),
                    ),
              );
          return (await task.run()).getOrElse((l) => throw l);
        } finally {
          if (tempFile.existsSync()) tempFile.deleteSync();
        }
      }, ProfileFailure.unexpected);

  @override
  TaskEither<ProfileFailure, Unit> offlineUpdate(ProfileEntity profile, String nContent) =>
      TaskEither.tryCatch(
        () async => await _profileDataSource.getById(profile.id).then((profEntry) => profEntry?.toEntity()),
        ProfileFailure.unexpected,
      ).flatMap((oProfile) {
        if (oProfile == null || oProfile.runtimeType != profile.runtimeType) throw const ProfileFailure.notFound();
        if (profile.userOverride == null) loggy.warning('Updaing profile content with "userOverride" == null');
        final id = oProfile.id;
        final file = _profilePathResolver.file(id);
        final tempFile = _profilePathResolver.tempFile(id);
        try {
          return TaskEither.tryCatch(
            () async => await tempFile.writeAsString(nContent),
            ProfileFailure.unexpected,
          ).flatMap(
            (_) =>
                TaskEither.fromEither(
                  _profileParser.offlineUpdate(
                    profile: oProfile.copyWith(userOverride: profile.userOverride),
                    tempFilePath: tempFile.path,
                  ),
                ).flatMap(
                  (profEntity) =>
                      validateConfig(
                        file.path,
                        tempFile.path,
                        ProfileParser.profileOverrideHelper(profile: profEntity),
                        false,
                      ).flatMap(
                        (unit) => TaskEither.tryCatch(() async {
                          await _profileDataSource.edit(id, profEntity);
                          return unit;
                        }, ProfileFailure.unexpected),
                      ),
                ),
          );
        } finally {
          if (tempFile.existsSync()) tempFile.deleteSync();
        }
      });

  @override
  TaskEither<ProfileFailure, Unit> validateConfig(String path, String tempPath, String? profileOverride, bool debug) =>
      TaskEither.fromEither(_configOptionRepo.fullOptionsOverrided(profileOverride))
          .mapLeft((configOptionFailure) => ProfileFailure.invalidConfig(null, configOptionFailure))
          .flatMap(
            (overridedOptions) => _singbox
                .changeOptions(overridedOptions)
                .mapLeft(ProfileFailure.invalidConfig)
                .flatMap(
                  (_) => _singbox.validateConfigByPath(path, tempPath, debug).mapLeft(ProfileFailure.invalidConfig),
                ),
          );

  @override
  TaskEither<ProfileFailure, String> generateConfig(String id) => TaskEither.fromEither(
    Either.tryCatch(() => _profilePathResolver.file(id), ProfileFailure.unexpected),
  ).flatMap((configFile) => _singbox.generateFullConfigByPath(configFile.path).mapLeft(ProfileFailure.unexpected));

  @override
  TaskEither<ProfileFailure, String> getRawConfig(String id) {
    return TaskEither.fromEither(
      Either.tryCatch(() => _profilePathResolver.file(id), ProfileFailure.unexpected),
    ).flatMap((configFile) => TaskEither.tryCatch(() => configFile.readAsString(), ProfileFailure.unexpected));
  }
}
