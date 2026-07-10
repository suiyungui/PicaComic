import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/app_dio.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/res.dart';

class HComicNetwork {
  factory HComicNetwork() => _instance;

  HComicNetwork._();

  static final HComicNetwork _instance = HComicNetwork._();

  static const baseUrl = 'https://h-comic.com';
  static const imageBaseUrl = 'https://h-comic.link/api';

  static const _headers = {
    'User-Agent': webUA,
    'Referer': '$baseUrl/',
  };

  Future<Res<String>> _getHtml(Uri uri) async {
    try {
      final response = await logDio(BaseOptions(headers: _headers)).get<String>(
        uri.toString(),
        options: Options(responseType: ResponseType.plain),
      );
      if (response.statusCode != 200 || response.data == null) {
        return Res.error('Invalid status: ${response.statusCode}');
      }
      return Res(response.data!);
    } on DioException catch (e) {
      return Res.error(e.message ?? e.toString());
    } catch (e, stackTrace) {
      LogManager.addLog(
        LogLevel.error,
        'H-Comic Network',
        '$e\n$stackTrace',
      );
      return Res.error(e.toString());
    }
  }

  Future<Res<List<BaseComic>>> getHomePage() async {
    final response = await _getHtml(Uri.parse(baseUrl));
    if (response.error) {
      return Res.fromErrorRes(response);
    }
    try {
      return Res(parseComics(response.data), subData: 1);
    } catch (e, stackTrace) {
      LogManager.addLog(
        LogLevel.error,
        'H-Comic Parser',
        '$e\n$stackTrace',
      );
      return Res.error('解析失败: $e');
    }
  }

  Future<Res<List<BaseComic>>> getComics({
    required int page,
    String query = '',
    String tag = '',
    bool random = false,
  }) async {
    final uri = Uri(
      scheme: 'https',
      host: 'h-comic.com',
      path: random ? '/random' : '/',
      queryParameters: {
        'page': page.toString(),
        'q': query,
        'tag': tag,
      },
    );
    final response = await _getHtml(uri);
    if (response.error) {
      return Res.fromErrorRes(response);
    }
    try {
      return Res(
        parseComics(response.data),
        subData: random ? null : parseMaxPage(response.data),
      );
    } catch (e, stackTrace) {
      LogManager.addLog(
        LogLevel.error,
        'H-Comic Parser',
        '$e\n$stackTrace',
      );
      return Res.error('解析失败: $e');
    }
  }

  Future<Res<HComicDetails>> getComicDetails(String encodedId) async {
    final parts = encodedId.split('|');
    final id = parts.removeAt(0);
    final title = parts.isEmpty ? 'view' : parts.join('|');
    final encodedPath = [
      'comics',
      Uri.encodeComponent(title),
      '1',
    ].join('/');
    final uri = Uri.parse('$baseUrl/$encodedPath').replace(
      queryParameters: {'id': id},
    );
    final response = await _getHtml(uri);
    if (response.error) {
      return Res.fromErrorRes(response);
    }
    try {
      final data = parsePageData(response.data);
      final comic = data['comic'];
      if (comic is! Map) {
        return const Res.error('Failed to load comic info');
      }
      return Res(HComicDetails.fromJson(Map<String, dynamic>.from(comic)));
    } catch (e, stackTrace) {
      LogManager.addLog(
        LogLevel.error,
        'H-Comic Parser',
        '$e\n$stackTrace',
      );
      return Res.error('解析失败: $e');
    }
  }

  Future<Res<List<String>>> getComicPages(String? chapterId) async {
    if (chapterId == null) {
      return const Res.error('Chapter not found');
    }
    final parts = chapterId.split('|');
    if (parts.length != 3) {
      return const Res.error('Invalid chapter id');
    }
    final pageCount = int.tryParse(parts[2]);
    if (pageCount == null || pageCount < 1) {
      return const Res.error('Invalid page count');
    }
    return Res([
      for (var page = 1; page <= pageCount; page++)
        '$imageBaseUrl/${parts[0]}/${parts[1]}/pages/$page',
    ]);
  }

  static Map<String, dynamic> parsePageData(String pageHtml) {
    final match = RegExp(
      r'data:\s*\[null,\s*(\{[\s\S]*?\})\s*\]\s*,\s*form:',
    ).firstMatch(pageHtml);
    if (match == null) {
      throw const FormatException('SvelteKit data not found');
    }
    final jsonText = match.group(1)!.replaceAllMapped(
      RegExp(r'([{,]\s*)([a-zA-Z_][a-zA-Z0-9_]*)\s*:'),
      (match) => '${match.group(1)}"${match.group(2)}":',
    );
    final root = jsonDecode(jsonText);
    if (root is! Map || root['data'] is! Map) {
      throw const FormatException('Invalid SvelteKit data');
    }
    return Map<String, dynamic>.from(root['data'] as Map);
  }

  static List<BaseComic> parseComics(String pageHtml) {
    final data = parsePageData(pageHtml);
    final comics = data['comics'];
    if (comics is! List) {
      return const [];
    }
    return comics
        .whereType<Map>()
        .map((comic) => HComicBrief.fromJson(
              Map<String, dynamic>.from(comic),
            ))
        .toList();
  }

  static int parseMaxPage(String pageHtml) {
    final document = html_parser.parse(pageHtml);
    return int.tryParse(
          document.querySelector('[name="page"]')?.attributes['max'] ?? '',
        ) ??
        1;
  }
}

class HComicBrief extends BaseComic {
  const HComicBrief({
    required this.id,
    required this.title,
    required this.subTitle,
    required this.cover,
    required this.tags,
    required this.description,
  });

  factory HComicBrief.fromJson(Map<String, dynamic> json) {
    final titleData = Map<String, dynamic>.from(json['title'] as Map? ?? {});
    final title = _firstText([
      titleData['display'],
      titleData['pretty'],
      titleData['japanese'],
      titleData['english'],
    ]);
    return HComicBrief(
      id: '${json['id']}|$title',
      title: title,
      subTitle: titleData['english']?.toString() ?? '',
      cover: json['thumbnail']?.toString() ?? '',
      tags: _parseTags(json['tags']),
      description: _parseDate(json['upload_date']),
    );
  }

  @override
  final String id;

  @override
  final String title;

  @override
  final String subTitle;

  @override
  final String cover;

  @override
  final List<String> tags;

  @override
  final String description;
}

class HComicDetails {
  const HComicDetails({
    required this.id,
    required this.title,
    required this.subTitle,
    required this.cover,
    required this.description,
    required this.tags,
    required this.chapterId,
  });

  factory HComicDetails.fromJson(Map<String, dynamic> json) {
    final titleData = Map<String, dynamic>.from(json['title'] as Map? ?? {});
    final title = _firstText([
      titleData['display'],
      titleData['pretty'],
      titleData['japanese'],
      titleData['english'],
    ]);
    final source = json['comic_source']?.toString() ?? '';
    final mediaId = json['media_id']?.toString() ?? '';
    final pageCount = (json['num_pages'] as num?)?.toInt() ?? 0;
    var cover = json['thumbnail']?.toString() ?? '';
    if (cover.isEmpty && source.isNotEmpty && mediaId.isNotEmpty) {
      cover = '${HComicNetwork.imageBaseUrl}/$source/$mediaId/pages/1';
    }
    final tags = _parseTags(json['tags']);
    final date = _parseDate(json['upload_date']);
    return HComicDetails(
      id: '${json['id']}|$title',
      title: title,
      subTitle: titleData['english']?.toString() ?? '',
      cover: cover,
      description: titleData['japanese']?.toString() ?? '',
      tags: {
        '标签': tags,
        if (date.isNotEmpty) '日期': [date],
      },
      chapterId: '$source|$mediaId|$pageCount',
    );
  }

  final String id;
  final String title;
  final String subTitle;
  final String cover;
  final String description;
  final Map<String, List<String>> tags;
  final String chapterId;
}

String _firstText(Iterable<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) {
      return text;
    }
  }
  return 'Untitled';
}

List<String> _parseTags(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.whereType<Map>().map((tag) {
    final name = tag['name_zh']?.toString().trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return tag['name']?.toString().trim() ?? '';
  }).where((tag) => tag.isNotEmpty).toList();
}

String _parseDate(Object? value) {
  final timestamp = value is num ? value.toInt() : int.tryParse('$value');
  if (timestamp == null) {
    return '';
  }
  return DateTime.fromMillisecondsSinceEpoch(
    timestamp * 1000,
    isUtc: true,
  ).toIso8601String().split('T').first;
}
