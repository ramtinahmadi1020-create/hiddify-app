import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/bootstrap.dart';
import 'package:hiddify/core/model/environment.dart';

// 🆕 ایمپورت‌های جدید برای صفحه لایسنس و ذخیره‌سازی
import 'package:hiddify/features/license/presentation/license_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // final widgetsBinding = SentryWidgetsFlutterBinding.ensureInitialized();
  // debugPaintSizeEnabled = true;

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
  );

  // 🆕 چک کردن وضعیت لایسنس قبل از بالا آوردن اپ
  final prefs = await SharedPreferences.getInstance();
  final isActivated = prefs.getBool('license_activated') ?? false;

  if (isActivated) {
    // اگه قبلاً لایسنس وارد شده بود، اپ اصلی رو لود کن
    return await lazyBootstrap(widgetsBinding, Environment.dev);
  } else {
    // اگه لایسنس وارد نشده بود، اول صفحه لایسنس رو نشون بده
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
        home: LicenseScreen(
          onActivated: () {
            // وقتی لایسنس درست وارد شد، اپ اصلی رو لود کن
            lazyBootstrap(widgetsBinding, Environment.dev);
          },
        ),
      ),
    );
  }
}
