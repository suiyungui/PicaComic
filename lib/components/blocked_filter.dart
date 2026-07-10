part of 'components.dart';

const _blockingDetailsCacheLimit = 256;

final LinkedHashMap<String, Future<_BlockingDetails?>>
    _blockingDetailsCache = LinkedHashMap();
final LinkedHashMap<String, _BlockingDetails> _resolvedBlockingDetails =
    LinkedHashMap();

class _BlockingDetails {
  const _BlockingDetails({
    required this.title,
    required this.subTitle,
    required this.description,
    required this.tags,
  });

  final String title;
  final String subTitle;
  final String description;
  final List<String> tags;
}

String? blockedWordForComic(
  BaseComic comic,
  String sourceKey, {
  Iterable<String> blockingContext = const [],
}) {
  final direct = isBlocked(comic, blockingContext: blockingContext);
  if (direct != null) {
    return direct;
  }
  final details = _resolvedBlockingDetails['$sourceKey:${comic.id}'];
  if (details == null) {
    return null;
  }
  return _findBlockedKeyword(
    title: details.title,
    subTitle: details.subTitle,
    description: details.description,
    tags: details.tags,
    blockingContext: blockingContext,
  );
}

Future<List<T>> filterBlockedComics<T extends BaseComic>(
  Iterable<T> comics,
  String sourceKey, {
  Iterable<String> blockingContext = const [],
  int maxConcurrent = 4,
  bool verifyWithDetails = false,
}) async {
  final items = comics.toList();
  if (appdata.blockingKeyword.isEmpty || items.isEmpty) {
    return items;
  }

  final fullyHide = appdata.appSettings.fullyHideBlockedWorks;
  final source = ComicSource.find(sourceKey);
  final visible = List<T?>.filled(items.length, null);
  var nextIndex = 0;

  Future<void> worker() async {
    while (nextIndex < items.length) {
      final index = nextIndex++;
      final comic = items[index];
      var blocked = blockedWordForComic(
        comic,
        sourceKey,
        blockingContext: blockingContext,
      );

      final canLoadCompleteTags =
          source?.loadComicTags != null || source?.loadComicInfo != null;
      if (blocked == null &&
          canLoadCompleteTags &&
          (verifyWithDetails || comic.tags.isEmpty)) {
        final details = await _loadBlockingDetails(source!, comic.id);
        if (details != null) {
          blocked = _findBlockedKeyword(
            title: details.title,
            subTitle: details.subTitle,
            description: details.description,
            tags: details.tags,
            blockingContext: blockingContext,
          );
        }
      }

      if (!fullyHide || blocked == null) {
        visible[index] = comic;
      }
    }
  }

  final workerCount = math.min(math.max(maxConcurrent, 1), items.length);
  await Future.wait(List.generate(workerCount, (_) => worker()));
  return visible.whereType<T>().toList();
}

Future<_BlockingDetails?> _loadBlockingDetails(
  ComicSource source,
  String comicId,
) async {
  final cacheKey = '${source.key}:$comicId';
  final resolved = _resolvedBlockingDetails.remove(cacheKey);
  if (resolved != null) {
    final cachedPending = _blockingDetailsCache.remove(cacheKey);
    if (cachedPending != null) {
      _blockingDetailsCache[cacheKey] = cachedPending;
    }
    _resolvedBlockingDetails[cacheKey] = resolved;
    return resolved;
  }
  final existing = _blockingDetailsCache.remove(cacheKey);
  if (existing != null) {
    _blockingDetailsCache[cacheKey] = existing;
    final details = await existing;
    if (details != null) {
      _resolvedBlockingDetails[cacheKey] = details;
    }
    return details;
  }

  final pending = () async {
    try {
      if (source.loadComicTags != null) {
        final tagsRes = await source.loadComicTags!(comicId);
        if (!tagsRes.error) {
          return _BlockingDetails(
            title: '',
            subTitle: '',
            description: '',
            tags: tagsRes.data,
          );
        }
      }
      if (source.loadComicInfo == null) {
        return null;
      }
      final res = await source.loadComicInfo!(comicId);
      if (res.error) {
        return null;
      }
      final info = res.data;
      final tags = <String>[];
      for (final entry in info.tags.entries) {
        for (final tag in entry.value) {
          tags.add(tag);
          if (entry.key.trim().isNotEmpty) {
            tags.add('${entry.key}:$tag');
          }
        }
      }
      return _BlockingDetails(
        title: info.title,
        subTitle: info.subTitle ?? '',
        description: info.description ?? '',
        tags: tags,
      );
    } catch (_) {
      return null;
    }
  }();

  _blockingDetailsCache[cacheKey] = pending;
  while (_blockingDetailsCache.length > _blockingDetailsCacheLimit) {
    final evictedKey = _blockingDetailsCache.keys.first;
    _blockingDetailsCache.remove(evictedKey);
    _resolvedBlockingDetails.remove(evictedKey);
  }

  final details = await pending;
  if (details == null) {
    if (identical(_blockingDetailsCache[cacheKey], pending)) {
      _blockingDetailsCache.remove(cacheKey);
    }
    return null;
  }
  _resolvedBlockingDetails[cacheKey] = details;
  return details;
}
