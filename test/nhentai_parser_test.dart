import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';

void main() {
  test('parses nhentai embedded search tag ids', () {
    final apiBody = jsonEncode({
      'result': [
        {
          'id': 663076,
          'tag_ids': [12227, 23895],
        },
      ],
      'num_pages': 12,
    });
    final embeddedResponse = jsonEncode({
      'status': 200,
      'body': apiBody,
    });
    final document = html.parse('''
      <div class="gallery">
        <a href="/g/663076/">
          <img src="https://t4.nhentai.net/galleries/4040753/thumb.webp">
        </a>
        <div class="caption">Test comic</div>
      </div>
      <script type="application/json" data-sveltekit-fetched>
        $embeddedResponse
      </script>
    ''');

    final network = NhentaiNetwork();
    final embedded = network.parseEmbeddedGalleryData(document);
    final comic = network.parseComicWithTagIds(
      document.querySelector('div.gallery')!,
      (embedded!['result'] as List).first['tag_ids'],
    );

    expect(embedded['num_pages'], 12);
    expect(comic.id, '663076');
    expect(comic.lang, 'English');
    expect(comic.tags, contains('yaoi'));
  });
}
