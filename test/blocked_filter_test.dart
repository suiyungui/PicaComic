import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/res.dart';

void main() {
  late List<String> originalBlockingKeywords;
  late String originalFullyHideSetting;
  late List<ComicSource> originalSources;

  setUp(() {
    originalBlockingKeywords = List.of(appdata.blockingKeyword);
    originalFullyHideSetting = appdata.settings[83];
    originalSources = List.of(ComicSource.sources);
    appdata.blockingKeyword = ['yaoi'];
    appdata.appSettings.fullyHideBlockedWorks = true;
  });

  tearDown(() {
    appdata.blockingKeyword = originalBlockingKeywords;
    appdata.settings[83] = originalFullyHideSetting;
    ComicSource.sources = originalSources;
  });

  test('search filtering verifies complete tags for partial list metadata',
      () async {
    var tagLoads = 0;
    ComicSource.sources = [
      ComicSource.named(
        name: 'Test source',
        key: 'complete_tags_test',
        filePath: 'built-in',
        loadComicTags: (id) async {
          tagLoads++;
          return const Res(['romance', 'yaoi']);
        },
      ),
    ];
    const comic = CustomComic(
      'Title',
      '',
      '',
      'partial-tags',
      ['romance'],
      '',
      'complete_tags_test',
    );

    final withoutVerification = await filterBlockedComics(
      const [comic],
      'complete_tags_test',
    );
    final withVerification = await filterBlockedComics(
      const [comic],
      'complete_tags_test',
      verifyWithDetails: true,
    );

    expect(withoutVerification, const [comic]);
    expect(withVerification, isEmpty);
    expect(tagLoads, 1);
  });

  test('complete tag loading falls back to comic details after an error',
      () async {
    var infoLoads = 0;
    ComicSource.sources = [
      ComicSource.named(
        name: 'Fallback source',
        key: 'tag_fallback_test',
        filePath: 'built-in',
        loadComicTags: (id) async => const Res.error('Unavailable'),
        loadComicInfo: (id) async {
          infoLoads++;
          return Res(ComicInfoData(
            'Title',
            null,
            '',
            null,
            const {
              'Tags': ['yaoi'],
            },
            null,
            null,
            null,
            0,
            null,
            'tag_fallback_test',
            id,
          ));
        },
      ),
    ];
    const comic = CustomComic(
      'Title',
      '',
      '',
      'fallback-tags',
      const [],
      '',
      'tag_fallback_test',
    );

    final result = await filterBlockedComics(
      const [comic],
      'tag_fallback_test',
      verifyWithDetails: true,
    );

    expect(result, isEmpty);
    expect(infoLoads, 1);
  });
}
