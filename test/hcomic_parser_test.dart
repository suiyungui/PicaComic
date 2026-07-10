import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/network/hcomic_network.dart';

void main() {
  test('parses H-Comic SvelteKit comic data', () {
    const page = '''
      <input name="page" max="8">
      <script>
        kit.start(app, element, {
          data: [null,{type:"data",data:{comics:[{
            id:"123",
            tags:[{id:1,type:"tag",name:"yaoi",name_zh:"男同"}],
            title:{japanese:"日文标题",english:"English title",pretty:"Pretty",display:"Display title"},
            upload_date:1704067200,
            num_pages:3,
            media_id:"456",
            comic_source:"nh",
            thumbnail:"https://example.com/cover"
          }]}}],
          form: null
        });
      </script>
    ''';

    final data = HComicNetwork.parsePageData(page);
    final comics = HComicNetwork.parseComics(page);
    final comic = comics.single;

    expect((data['comics'] as List), hasLength(1));
    expect(comic.id, '123|Display title');
    expect(comic.title, 'Display title');
    expect(comic.subTitle, 'English title');
    expect(comic.tags, ['男同']);
    expect(comic.description, '2024-01-01');
    expect(HComicNetwork.parseMaxPage(page), 8);
  });

  test('builds H-Comic image URLs from chapter metadata', () async {
    final result = await HComicNetwork().getComicPages('nh|456|3');

    expect(result.success, isTrue);
    expect(result.data, [
      'https://h-comic.link/api/nh/456/pages/1',
      'https://h-comic.link/api/nh/456/pages/2',
      'https://h-comic.link/api/nh/456/pages/3',
    ]);
  });
}
