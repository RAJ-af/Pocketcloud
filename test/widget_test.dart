import 'package:flutter_test/flutter_test.dart';
import 'package:pocketcloud/core/app_config.dart';
import 'package:pocketcloud/core/app_theme.dart';

void main() {
  test('App configuration is safely disabled without secrets', () {
    expect(AppConfig.isConfigured, isFalse);
  });

  test('PocketCloud colour palette has a distinct accent', () {
    expect(AppColors.accent, isNot(AppColors.background));
    expect(AppColors.surface, isNot(AppColors.background));
  });
}
