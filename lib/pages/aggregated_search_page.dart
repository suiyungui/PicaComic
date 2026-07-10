import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:shimmer_animation/shimmer_animation.dart';

class AggregatedSearchPage extends StatefulWidget {
  const AggregatedSearchPage({super.key, required this.keyword});

  final String keyword;

  @override
  State<AggregatedSearchPage> createState() => _AggregatedSearchPageState();
}

class _AggregatedSearchPageState extends State<AggregatedSearchPage> {
  late final TextEditingController controller;
  late String keyword;

  List<ComicSource> get sources {
    final available = {
      for (var source in ComicSource.sources)
        if (source.searchPageData != null) source.key: source,
    };
    return appdata.appSettings.aggregatedSearchSources
        .map((key) => available[key])
        .whereType<ComicSource>()
        .toList();
  }

  @override
  void initState() {
    super.initState();
    keyword = widget.keyword;
    controller = TextEditingController(text: keyword);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void search([String? text]) {
    final value = (text ?? controller.text).trim();
    if (value.isEmpty) {
      return;
    }
    setState(() {
      keyword = value;
      controller.text = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SizedBox(height: context.padding.top),
          _AggregatedSearchBar(
            controller: controller,
            onSearch: search,
          ),
          Expanded(
            child: SmoothCustomScrollView(
              slivers: [
                if (sources.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: NetworkError(
                      message: "没有可搜索的漫画源".tl,
                      retry: () => context.pop(),
                      buttonText: "返回".tl,
                    ),
                  )
                else
                  SliverList(
                    key: ValueKey(keyword),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final source = sources[index];
                        return _AggregatedSourceResult(
                          key: ValueKey("${source.key}@$keyword"),
                          source: source,
                          keyword: keyword,
                        );
                      },
                      childCount: sources.length,
                    ),
                  ),
                SliverPadding(
                  padding: EdgeInsets.only(bottom: context.padding.bottom + 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AggregatedSearchBar extends StatelessWidget {
  const _AggregatedSearchBar({
    required this.controller,
    required this.onSearch,
  });

  final TextEditingController controller;
  final void Function(String) onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: "返回".tl,
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: "聚合搜索".tl,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: onSearch,
            ),
          ),
          IconButton(
            tooltip: "搜索".tl,
            icon: const Icon(Icons.search),
            onPressed: () => onSearch(controller.text),
          ),
        ],
      ),
    );
  }
}

class _AggregatedSourceResult extends StatefulWidget {
  const _AggregatedSourceResult({
    required this.source,
    required this.keyword,
    super.key,
  });

  final ComicSource source;
  final String keyword;

  @override
  State<_AggregatedSourceResult> createState() =>
      _AggregatedSourceResultState();
}

class _AggregatedSourceResultState extends State<_AggregatedSourceResult>
    with AutomaticKeepAliveClientMixin {
  static const _comicHeight = 168.0;
  static const _comicWidth = _comicHeight * 0.68;

  bool loading = true;
  List<BaseComic>? comics;
  String? error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final data = widget.source.searchPageData!;
    final loader = data.loadPage;
    if (loader == null) {
      setState(() {
        loading = false;
        comics = const [];
        error = "此漫画源使用自定义搜索页，点击查看完整结果".tl;
      });
      return;
    }

    try {
      final options =
          (data.searchOptions ?? []).map((e) => e.defaultValue).toList();
      final res = await loader(widget.keyword, 1, options);
      if (!mounted) {
        return;
      }
      setState(() {
        loading = false;
        if (res.error) {
          error = res.errorMessage ?? "搜索失败".tl;
        } else {
          comics = appdata.appSettings.fullyHideBlockedWorks
              ? res.data
                  .where((comic) => isBlocked(
                        comic,
                        blockingContext: [widget.keyword],
                      ) == null)
                  .toList()
              : res.data;
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return InkWell(
      onTap: () {
        context.to(
          () => SearchResultPage(
            keyword: widget.keyword,
            sourceKey: widget.source.key,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(widget.source.name.tl),
              trailing: const Icon(Icons.chevron_right),
            ),
            if (loading)
              _buildLoading(context)
            else if (error != null || comics == null || comics!.isEmpty)
              SizedBox(
                height: _comicHeight,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error ?? "无匹配结果".tl,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
              )
            else
              SizedBox(
                height: _comicHeight,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    return SizedBox(
                      width: _comicWidth,
                      child: buildComicTile(
                        context,
                        comics![index],
                        widget.source.key,
                        blockingContext: [widget.keyword],
                      ),
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemCount: comics!.length,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return SizedBox(
      height: _comicHeight,
      child: Shimmer(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) => Container(
            width: _comicWidth,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          separatorBuilder: (context, index) => const SizedBox(width: 12),
          itemCount: 6,
        ),
      ),
    );
  }
}
