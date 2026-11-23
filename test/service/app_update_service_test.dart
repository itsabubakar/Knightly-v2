import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/service/app_update_service.dart';

Map<String, dynamic> _release(String tag, {List<String> assets = const ['knightly.apk']}) => {
  'tag_name': tag,
  'body': 'Openings trainer',
  'assets': [
    for (final name in assets)
      {'name': name, 'browser_download_url': 'https://github.com/x/releases/download/$tag/$name'},
  ],
};

void main() {
  test('the build number of a tag', () {
    expect(releaseBuildNumber('v1.0.1+010001'), 10001);
    expect(releaseBuildNumber('v1.0.1'), isNull);
  });

  test('a newer release with an APK is offered', () {
    final release = newerRelease(_release('v1.0.1+010001'), 10000);
    expect(release?.version, '1.0.1');
    expect(release?.buildNumber, 10001);
    expect(release?.apkUrl, endsWith('knightly.apk'));
    expect(release?.notes, 'Openings trainer');
  });

  test('the same or an older release is not', () {
    expect(newerRelease(_release('v1.0.0+010000'), 10000), isNull);
    expect(newerRelease(_release('v0.9.0+000900'), 10000), isNull);
  });

  test('a release without an APK is not', () {
    expect(newerRelease(_release('v1.0.1+010001', assets: ['notes.txt']), 10000), isNull);
  });
}
