import 'dart:collection';

import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/network/hcomic_network.dart';
import 'package:pica_comic/network/res.dart';

final hcomic = ComicSource.named(
  name: 'H-Comic',
  key: 'hcomic',
  filePath: 'built-in',
  explorePages: [
    ExplorePageData.named(
      title: 'H-Comic',
      type: ExplorePageType.singlePageWithMultiPart,
      loadMultiPart: () async {
        final result = await HComicNetwork().getHomePage();
        if (result.error) {
          return Res.fromErrorRes(result);
        }
        return Res([
          ExplorePagePart('随机漫画', result.data, null),
        ]);
      },
    ),
  ],
  categoryData: const CategoryData(
    title: 'H-Comic',
    key: 'hcomic',
    enableRankingPage: false,
    categories: [
      FixedCategoryPart(
        '热门TAG',
        [
          '全部',
          '全彩',
          '無修正',
          '蘿莉',
          '制服',
          '巨乳',
          '黑絲 / 白襪',
          'NTR',
          '足交 / 腳交',
          '女學生',
          '眼鏡控',
          '口交',
          '正太控',
          '年上',
          '亂倫',
          '熟女 / 人妻',
          '同志 BL',
          '黑肉',
          '泳裝',
          '手淫',
          '肌肉',
          '姐姐 / 妹妹',
          '捆綁',
          '調教',
          '催眠',
          '露出',
          '群交',
          '肛交',
          '獸交',
        ],
        'category',
        [
          '',
          '全彩',
          '無修正',
          '蘿莉',
          '制服',
          '巨乳',
          '黑絲 / 白襪',
          'netorare',
          'footjob',
          '女學生',
          '眼鏡控',
          '口交',
          '正太控',
          '年上',
          '亂倫',
          '熟女 / 人妻',
          '同志 BL',
          '黑肉',
          '泳裝',
          '手淫',
          '肌肉',
          '姐姐 / 妹妹',
          '捆綁',
          '調教',
          '催眠',
          '露出',
          '群交',
          '肛交',
          '獸交',
        ],
      ),
    ],
  ),
  categoryComicsData: CategoryComicsData.named(
    options: [
      CategoryComicsOptions.named(
        options: LinkedHashMap.of({
          'latest': '最近更新',
          'random': '随机刷新',
        }),
      ),
    ],
    load: (category, param, options, page) {
      return HComicNetwork().getComics(
        page: page,
        tag: param ?? '',
        random: options.isNotEmpty && options.first == 'random',
      );
    },
  ),
  searchPageData: SearchPageData.named(
    loadPage: (keyword, page, options) {
      return HComicNetwork().getComics(
        page: page,
        query: keyword,
      );
    },
  ),
  loadComicInfo: (id) async {
    final result = await HComicNetwork().getComicDetails(id);
    if (result.error) {
      return Res.fromErrorRes(result);
    }
    final comic = result.data;
    return Res(ComicInfoData(
      comic.title,
      comic.subTitle,
      comic.cover,
      comic.description,
      comic.tags,
      {comic.chapterId: '全一话'},
      null,
      null,
      1,
      null,
      'hcomic',
      comic.id,
    ));
  },
  loadComicTags: (id) async {
    final result = await HComicNetwork().getComicDetails(id);
    if (result.error) {
      return Res.fromErrorRes(result);
    }
    return Res(result.data.tags.values.expand((tags) => tags).toList());
  },
  loadComicPages: (id, chapterId) {
    return HComicNetwork().getComicPages(chapterId);
  },
  getImageLoadingConfig: (imageKey, comicId, epId) => {
    'headers': {
      'User-Agent': webUA,
      'Referer': '${HComicNetwork.baseUrl}/',
    },
  },
  getThumbnailLoadingConfig: (imageKey) => {
    'headers': {
      'User-Agent': webUA,
      'Referer': '${HComicNetwork.baseUrl}/',
    },
  },
);
