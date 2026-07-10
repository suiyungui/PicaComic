part of pica_settings;

class ComicSourceSettings extends StatefulWidget {
  const ComicSourceSettings({super.key});

  @override
  State<ComicSourceSettings> createState() => _ComicSourceSettingsState();

  static Future<void> checkCustomComicSourceUpdate(
      [bool showLoading = false]) async {
    final customSources =
        ComicSource.sources.where((source) => !source.isBuiltIn).toList();
    if (customSources.isEmpty) {
      if (showLoading) {
        showToast(message: "没有已安装的自定义漫画源".tl);
      }
      return;
    }

    final controller =
        showLoading ? showLoadingDialog(App.globalContext!) : null;
    try {
      final res = await logDio().get<String>(
        appdata.appSettings.comicSourceListUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final list = jsonDecode(res.data!) as List;
      final versions = <String, String>{};
      for (var item in list.whereType<Map>()) {
        final key = item['key']?.toString();
        final version = item['version']?.toString();
        if (key != null && version != null) {
          versions[key] = version;
        }
      }

      final updates = <ComicSource, String>{};
      for (var source in customSources) {
        final version = versions[source.key];
        if (version == null) {
          continue;
        }
        try {
          if (compareSemVer(version, source.version)) {
            updates[source] = version;
          }
        } catch (_) {}
      }

      controller?.close();
      if (updates.isEmpty) {
        if (showLoading) {
          showToast(message: "已是最新版本".tl);
        }
        return;
      }

      final message = updates.entries
          .map((entry) => "${entry.key.name}: ${entry.key.version} -> ${entry.value}")
          .join("\n");
      showConfirmDialog(App.globalContext!, "有可用更新".tl, message, () async {
        final failures = <String>[];
        for (var source in updates.keys) {
          final currentSource = ComicSource.find(source.key);
          if (currentSource != null) {
            try {
              await _ComicSourceSettingsState.update(currentSource, false);
            } catch (_) {
              failures.add(source.name);
            }
          }
        }
        if (failures.isEmpty) {
          showToast(message: "漫画源更新完成".tl);
        } else {
          showToast(message: "更新失败: ${failures.join(', ')}".tl);
        }
      });
    } catch (e) {
      controller?.close();
      if (showLoading) {
        showToast(message: e.toString());
      }
    }
  }
}

extension _WidgetExt on Widget {
  Widget withDivider() {
    return Column(
      children: [
        this,
        const Divider(),
      ],
    );
  }
}

class _ComicSourceSettingsState extends State<ComicSourceSettings> {
  var url = "";

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchSetting(
          title: "启动时检查漫画源更新".tl,
          settingsIndex: 80,
          icon: const Icon(Icons.security_update),
        ),
        buildCard(context),
        const _BuiltInSources(),
        if(appdata.appSettings.isComicSourceEnabled("picacg"))
          const PicacgSettings(false).withDivider(),
        if(appdata.appSettings.isComicSourceEnabled("ehentai"))
          const EhSettings(false).withDivider(),
        if(appdata.appSettings.isComicSourceEnabled("nhentai"))
          const NhSettings(false).withDivider(),
        if(appdata.appSettings.isComicSourceEnabled("jm"))
          const JmSettings(false).withDivider(),
        if(appdata.appSettings.isComicSourceEnabled("hitomi"))
          const HitomiSettings(false).withDivider(),
        if(appdata.appSettings.isComicSourceEnabled("htmanga"))
          // const HtSettings(false).withDivider(),
          const HtSettings(false),
        // buildCustomSettings(),
        for (var source in ComicSource.sources.where((e) => !e.isBuiltIn))
          buildCustom(context, source),
        Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom))
      ],
    );
  }

  // Widget buildCustomSettings() {
  //   return Column(
  //     children: [
  //       ListTile(
  //         title: Text("自定义漫画源".tl),
  //       ),
  //       ListTile(
  //         leading: const Icon(Icons.update_outlined),
  //         title: Text("检查更新".tl),
  //         onTap: () => ComicSourceSettings.checkCustomComicSourceUpdate(true),
  //         trailing: const Icon(Icons.arrow_right),
  //       ),
  //       SwitchSetting(
  //         title: "启动时检查更新".tl,
  //         icon: const Icon(Icons.security_update),
  //         settingsIndex: 80,
  //       )
  //     ],
  //   );
  // }

  Widget buildCustom(BuildContext context, ComicSource source) {
    return Column(
      children: [
        const Divider(),
        ListTile(
          title: Text(source.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (App.isDesktop)
                Tooltip(
                  message: "Edit",
                  child: IconButton(
                      onPressed: () => edit(source),
                      icon: const Icon(Icons.edit_note)),
                ),
              Tooltip(
                message: "Update",
                child: IconButton(
                    onPressed: () => update(source),
                    icon: const Icon(Icons.update)),
              ),
              Tooltip(
                message: "Delete",
                child: IconButton(
                    onPressed: () => delete(source),
                    icon: const Icon(Icons.delete)),
              ),
            ],
          ),
        ),
        ListTile(
          title: const Text("Version"),
          subtitle: Text(source.version),
        )
      ],
    );
  }

  void delete(ComicSource source) {
    showConfirmDialog(App.globalContext!, "删除".tl, "要删除此漫画源吗?".tl, () {
      var file = File(source.filePath);
      file.delete();
      ComicSource.sources.remove(source);
      _validatePages();
      MyApp.updater?.call();
    });
  }

  void edit(ComicSource source) async {
    try {
      await Process.run("code", [source.filePath], runInShell: true);
      await showDialog(
          context: App.globalContext!,
          builder: (context) => AlertDialog(
                title: const Text("Reload Configs"),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("cancel")),
                  TextButton(
                      onPressed: () async {
                        await ComicSource.reload();
                        MyApp.updater?.call();
                      },
                      child: const Text("continue")),
                ],
              ));
    } catch (e) {
      showToast(message: "Failed to launch vscode");
    }
  }

  static Future<void> update(ComicSource source,
      [bool showLoading = true]) async {
    if (!source.url.isURL) {
      if (showLoading) {
        showToast(message: "Invalid url config");
        return;
      }
      throw "Invalid url config";
    }
    bool cancel = false;
    final controller = showLoading
        ? showLoadingDialog(App.globalContext!,
            onCancel: () => cancel = true, barrierDismissible: false)
        : null;
    try {
      var res = await logDio().get<String>(source.url,
          options: Options(responseType: ResponseType.plain));
      if (cancel) return;
      ComicSource.sources.remove(source);
      await ComicSourceParser().parse(res.data!, source.filePath);
      await File(source.filePath).writeAsString(res.data!);
      controller?.close();
      await ComicSource.reload();
      MyApp.updater?.call();
    } catch (e) {
      if (cancel) return;
      controller?.close();
      if (!ComicSource.sources.contains(source)) {
        await ComicSource.reload();
      }
      if (showLoading) {
        showToast(message: e.toString());
        return;
      }
      rethrow;
    }
  }

  Widget buildCard(BuildContext context) {
    return Card.outlined(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text("添加漫画源".tl),
              leading: const Icon(Icons.dashboard_customize),
            ),
            TextField(
                    decoration: InputDecoration(
                        hintText: "JS URL / index.json URL",
                        border: const UnderlineInputBorder(),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        suffix: IconButton(
                            onPressed: () => handleAddSource(url),
                            icon: const Icon(Icons.check))),
                    onChanged: (value) {
                      url = value;
                    },
                    onSubmitted: handleAddSource)
                .paddingHorizontal(16)
                .paddingBottom(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: chooseFile,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text("选择文件".tl),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => showPopUpWidget(
                    context,
                    _ComicSourceList(handleAddSource),
                  ),
                  icon: const Icon(Icons.list_alt),
                  label: Text("浏览列表".tl),
                ),
                FilledButton.tonalIcon(
                  onPressed: () =>
                      ComicSourceSettings.checkCustomComicSourceUpdate(true),
                  icon: const Icon(Icons.update),
                  label: Text("检查更新".tl),
                ),
                FilledButton.tonalIcon(
                  onPressed: help,
                  icon: const Icon(Icons.help_outline),
                  label: Text("查看帮助".tl),
                ),
              ],
            ).paddingHorizontal(12).paddingVertical(8),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ).paddingHorizontal(12);
  }

  void chooseFile() async {
    const XTypeGroup typeGroup = XTypeGroup(
      extensions: <String>['js'],
    );
    final XFile? file =
        await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (file == null) return;
    try {
      var fileName = file.name;
      // file.readAsString 会导致中文乱码
      var bytes = await file.readAsBytes();
      var content = utf8.decode(bytes);
      await addSource(content, fileName);
    } catch (e) {
      showToast(message: e.toString());
    }
  }

  void help() {
    launchUrlString(
      "https://github.com/Pacalini/PicaComic/blob/master/doc/comic_source.md",
    );
  }

  Future<void> handleAddSource(String url) async {
    url = url.trim();
    if (url.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.isScheme("http") || uri.isScheme("https"))) {
      showToast(message: "无效的 URL".tl);
      return;
    }
    final fileName =
        uri.pathSegments.isEmpty ? "comic_source.js" : uri.pathSegments.last;
    bool cancel = false;
    var controller = showLoadingDialog(App.globalContext!,
        onCancel: () => cancel = true, barrierDismissible: false);
    try {
      var res = await logDio()
          .get<String>(url, options: Options(responseType: ResponseType.plain));
      if (cancel) return;
      if (_isComicSourceIndex(res.data!)) {
        appdata.appSettings.comicSourceListUrl = url;
        await appdata.updateSettings();
        controller.close();
        if (mounted) {
          showPopUpWidget(
            context,
            _ComicSourceList(handleAddSource),
          );
        }
        return;
      }
      await addSource(res.data!, fileName);
      controller.close();
    } catch (e) {
      if (cancel) return;
      controller.close();
      showToast(message: e.toString());
    }
  }

  bool _isComicSourceIndex(String content) {
    try {
      final data = jsonDecode(content);
      return data is List &&
          data.isNotEmpty &&
          data.every((item) =>
              item is Map &&
              item["key"] != null &&
              (item["fileName"] != null || item["url"] != null));
    } catch (_) {
      return false;
    }
  }

  Future<void> addSource(String js, String fileName) async {
    var comicSource = await ComicSourceParser().createAndParse(js, fileName);
    ComicSource.sources.add(comicSource);
    _addAllPagesWithComicSource(comicSource);
    appdata.updateSettings();
    MyApp.updater?.call();
  }
}

class _ComicSourceList extends StatefulWidget {
  const _ComicSourceList(this.onAdd);

  final Future<void> Function(String) onAdd;

  @override
  State<_ComicSourceList> createState() => _ComicSourceListState();
}

class _ComicSourceListState extends State<_ComicSourceList> {
  bool loading = false;
  List? json;
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(
      text: appdata.appSettings.comicSourceListUrl,
    );
    load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final url = controller.text.trim();
    if (url.isEmpty) {
      setState(() {
        json = const [];
        loading = false;
      });
      return;
    }
    setState(() => loading = true);
    try {
      final res = await logDio().get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final data = jsonDecode(res.data!);
      if (data is! List) {
        throw "漫画源列表格式无效".tl;
      }
      appdata.appSettings.comicSourceListUrl = url;
      await appdata.updateSettings();
      if (mounted) {
        setState(() {
          json = data;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          json = const [];
          loading = false;
        });
      }
      showToast(message: e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(title: "漫画源".tl, body: buildBody());
  }

  Widget buildBody() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final items = json ?? const [];
    final currentKeys = ComicSource.sources.map((source) => source.key).toSet();
    return ListView.builder(
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: const Icon(Icons.source_outlined),
                title: Text("漫画源仓库地址".tl),
              ),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: "index.json URL",
                  border: const UnderlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  suffixIcon: IconButton(
                    tooltip: "刷新".tl,
                    onPressed: load,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => load(),
              ).paddingHorizontal(16).paddingBottom(12),
              const Divider(),
            ],
          );
        }

        final item = Map<String, dynamic>.from(items[index - 1] as Map);
        final key = item["key"]?.toString() ?? "";
        final installed = currentKeys.contains(key);
        final action = installed
            ? const Icon(Icons.check)
            : IconButton(
                tooltip: "添加".tl,
                icon: const Icon(Icons.add),
                onPressed: () async {
                  await widget.onAdd(_resolveSourceUrl(item));
                  if (mounted) {
                    setState(() {});
                  }
                },
              );
        final description = [
          item["version"]?.toString(),
          item["description"]?.toString(),
        ].whereType<String>().where((text) => text.isNotEmpty).join("\n");

        return ListTile(
          title: Text(item["name"]?.toString() ?? key),
          subtitle: description.isEmpty ? null : Text(description),
          trailing: action,
        );
      },
    );
  }

  String _resolveSourceUrl(Map<String, dynamic> item) {
    final directUrl = item["url"]?.toString();
    if (directUrl != null && directUrl.isURL) {
      return directUrl;
    }
    final fileName = item["fileName"]?.toString();
    if (fileName == null || fileName.isEmpty) {
      throw "漫画源条目缺少 fileName".tl;
    }
    return Uri.parse(controller.text.trim()).resolve(fileName).toString();
  }
}

class _BuiltInSources extends StatefulWidget {
  const _BuiltInSources();

  @override
  State<_BuiltInSources> createState() => _BuiltInSourcesState();
}

class _BuiltInSourcesState extends State<_BuiltInSources> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(),
        ListTile(
          title: Text("内置漫画源".tl),
        ),
        for(int index = 0; index < builtInSources.length; index++)
          buildTile(index),
        const Divider(),
      ],
    );
  }

  bool isLoading = false;

  Widget buildTile(int index) {
    var key = builtInSources[index];
    return ListTile(
      title: Text(
          ComicSource.builtIn.firstWhere((e) => e.key == key).name.tl),
      trailing: Switch(
        value: appdata.appSettings.isComicSourceEnabled(key),
        onChanged: (v) async {
          if (isLoading) return;
          isLoading = true;
          appdata.appSettings.setComicSourceEnabled(key, v);
          await appdata.updateSettings();
          if(!v) {
            ComicSource.sources.removeWhere((e) => e.key == key);
            _validatePages();
          } else {
            var source = ComicSource.builtIn.firstWhere((e) => e.key == key);
            ComicSource.sources.add(source);
            source.loadData();
            _addAllPagesWithComicSource(source);
          }
          isLoading = false;
          if (mounted) {
            setState(() {});
            context.findAncestorStateOfType<_ComicSourceSettingsState>()
                ?.setState(() {});
          }
        },
      ),
    );
  }
}

void _validatePages() {
  var explorePages = appdata.appSettings.explorePages;
  var categoryPages = appdata.appSettings.categoryPages;
  var networkFavorites = appdata.appSettings.networkFavorites;
  var searchSources = appdata.appSettings.aggregatedSearchSources;

  var totalExplorePages = ComicSource.sources
      .map((e) => e.explorePages.map((e) => e.title))
      .expand((element) => element)
      .toList();
  var totalCategoryPages = ComicSource.sources
      .map((e) => e.categoryData?.key)
      .where((element) => element != null)
      .map((e) => e!)
      .toList();
  var totalNetworkFavorites = ComicSource.sources
      .map((e) => e.favoriteData?.key)
      .where((element) => element != null)
      .map((e) => e!)
      .toList();

  var totalSearchSources = ComicSource.sources
      .where((source) => source.searchPageData != null)
      .map((source) => source.key)
      .toList();
  for (var page in List.from(explorePages)) {
    if (!totalExplorePages.contains(page)) {
      explorePages.remove(page);
    }
  }
  for (var page in List.from(categoryPages)) {
    if (!totalCategoryPages.contains(page)) {
      categoryPages.remove(page);
    }
  }
  for (var page in List.from(networkFavorites)) {
    if (!totalNetworkFavorites.contains(page)) {
      networkFavorites.remove(page);
    }
  }
  for (var source in List.from(searchSources)) {
    if (!totalSearchSources.contains(source)) {
      searchSources.remove(source);
    }
  }

  appdata.appSettings.explorePages = explorePages;
  appdata.appSettings.categoryPages = categoryPages;
  appdata.appSettings.networkFavorites = networkFavorites;
  appdata.appSettings.aggregatedSearchSources = searchSources;

  appdata.updateSettings();
}

void _addAllPagesWithComicSource(ComicSource source) {
  var explorePages = appdata.appSettings.explorePages;
  var categoryPages = appdata.appSettings.categoryPages;
  var networkFavorites = appdata.appSettings.networkFavorites;
  var searchSources = appdata.appSettings.aggregatedSearchSources;

  if (source.explorePages.isNotEmpty) {
    for (var page in source.explorePages) {
      if (!explorePages.contains(page.title)) {
        explorePages.add(page.title);
      }
    }
  }
  if (source.categoryData != null &&
      !categoryPages.contains(source.categoryData!.key)) {
    categoryPages.add(source.categoryData!.key);
  }
  if (source.favoriteData != null &&
      !networkFavorites.contains(source.favoriteData!.key)) {
    networkFavorites.add(source.favoriteData!.key);
  }
  if (source.searchPageData != null && !searchSources.contains(source.key)) {
    searchSources.add(source.key);
  }

  appdata.appSettings.explorePages = explorePages.toSet().toList();
  appdata.appSettings.categoryPages = categoryPages.toSet().toList();
  appdata.appSettings.networkFavorites = networkFavorites.toSet().toList();
  appdata.appSettings.aggregatedSearchSources = searchSources.toSet().toList();

  appdata.updateSettings();
}
