import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llsif_local_admin/api.dart';
import 'package:llsif_local_admin/pages/cards_page.dart';
import 'package:llsif_local_admin/pages/lives_page.dart';
import 'package:llsif_local_admin/pages/overview_page.dart';
import 'package:llsif_local_admin/pages/player_detail_page.dart';
import 'package:llsif_local_admin/pages/players_page.dart';
import 'package:llsif_local_admin/pages/tools_page.dart';
import 'package:llsif_local_admin/state.dart';

/// 夹具来自运行中的 honoka-chan `/local/*` 接口（test/fixtures/*.json），
/// 保证 JSON 形状与线上一致；用 MockClient 回放，绕开测试环境的网络隔离。
String _fixture(String name) =>
    File('test/fixtures/$name.json').readAsStringSync();

String? _bodyFor(Uri uri) {
  final path = uri.path;
  if (path == '/local/ping') return _fixture('ping');
  if (path == '/local/admin/overview') return _fixture('overview');
  if (path == '/local/accounts') return _fixture('accounts');
  if (path.endsWith('/backups')) return _fixture('backups');
  if (path.startsWith('/local/admin/players/')) return _fixture('player');
  if (path.startsWith('/local/admin/master/units')) return _fixture('units');
  if (path.startsWith('/local/admin/master/accessories')) {
    return _fixture('accessories');
  }
  if (path.startsWith('/local/admin/master/lives')) return _fixture('lives');
  if (path.startsWith('/local/admin/lives/tracks')) return _fixture('live_tracks');
  if (path == '/local/admin/unlock') {
    return '{"ok":true,"lives_unlocked":972,"scenarios_marked":0}';
  }
  if (path == '/local/admin/server') return _fixture('server');
  if (path == '/local/admin/cardart') {
    return '{"ok":true,"dir":"D:\\\\LLSIFLocal\\\\honoka-chan-dev\\\\static\\\\custom\\\\cardart",'
        '"total":1,"items":[{"name":"cardart_1","png_path":"D:\\\\a.png",'
        '"size":1234,"width":128,"height":128,"updated_at":"2026-10-22 07:00:00"}]}';
  }
  if (path == '/local/admin/logs') {
    return '{"lines":[],"next":0}';
  }
  return null;
}

LocalApi _api({String prefix = ''}) {
  final client = MockClient((request) async {
    final body = _bodyFor(request.url);
    if (body == null) {
      return http.Response(
        '{"ok":false,"message":"not found"}',
        404,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response.bytes(
      utf8.encode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  return LocalApi(baseUrl: 'http://127.0.0.1:8080$prefix', client: client);
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  test('API 客户端能解析 ping 与 overview', () async {
    final api = _api();
    final ping = await api.ping();
    expect(ping['ok'], true);
    expect(ping['version'], '97.4.6');

    final overview = await api.overview();
    expect(overview.unitMaster, 3963);
    expect(overview.liveTotal, greaterThan(0));
    expect(overview.missing, contains('event'));
  });

  test('分页与查询参数能正确拼接', () async {
    final api = _api();
    final units = await api.units(page: 1, size: 3, query: '穗乃果');
    expect(units.total, greaterThan(0));
    expect(units.units.length, lessThanOrEqualTo(3));

    final lives = await api.lives(page: 1, size: 3);
    expect(lives.lives.first.notesAsset, startsWith('Live_'));
  });

  test('中文不乱码', () async {
    final accounts = await _api().accounts();
    expect(accounts, isNotEmpty);
    expect(accounts.any((a) => a.name == '音乃木坂学生'), true);
  });

  test('404 与业务失败都会抛 ApiException', () async {
    await expectLater(
        _api(prefix: '/nope').ping(), throwsA(isA<ApiException>()));

    // ok:false 的响应（如密码错误）必须转成异常，不能静默通过。
    final failing = LocalApi(
      baseUrl: 'http://127.0.0.1:8080',
      client: MockClient((_) async => http.Response.bytes(
            utf8.encode('{"ok":false,"message":"密码有误"}'),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    );
    await expectLater(failing.patchPlayer(1, {'level': 2}),
        throwsA(isA<ApiException>()));
  });

  testWidgets('总览页展示服务端状态与数据规模', (tester) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = AppState.forTest(api: _api());
    await tester.pumpWidget(_wrap(OverviewPage(state: state)));
    // 页面里有 2 秒轮询，不能用 pumpAndSettle，否则永远不 settle。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('服务端'), findsOneWidget);
    expect(find.text('运行中 · 外部进程'), findsOneWidget);
    expect(find.text('12345'), findsOneWidget);
    expect(find.text('数据规模'), findsOneWidget);
    expect(find.text('97.4.6'), findsOneWidget);
    expect(find.text('部员模板'), findsOneWidget);
    expect(find.text('3963'), findsOneWidget);
    expect(find.text('能力清单'), findsOneWidget);
    expect(find.textContaining('缺少主数据'), findsOneWidget);

    // 卸载页面以取消轮询 Timer。
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('账号页列出账号并可进入详情', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(PlayersPage(api: _api())));
    await tester.pumpAndSettle();

    expect(find.textContaining('手机号'), findsWidgets);

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.byType(PlayerDetailPage), findsOneWidget);
  });

  testWidgets('玩家详情展示等级与保存入口', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
        home: PlayerDetailPage(api: _api(), userId: 1792563557)));
    await tester.pumpAndSettle();

    expect(find.text('属性修改'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('1028'), findsWidgets);
  });

  testWidgets('卡池页展示稀有度筛选与卡牌', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(CardsPage(api: _api())));
    await tester.pumpAndSettle();

    expect(find.text('全部稀有度'), findsOneWidget);
    expect(find.textContaining('桜坂しずく'), findsWidgets);
    expect(find.textContaining('共 '), findsOneWidget);
  });

  testWidgets('乐曲页按曲目聚合展示曲名与难度', (tester) async {
    tester.view.physicalSize = const Size(1100, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(LivesPage(api: _api())));
    await tester.pumpAndSettle();

    // 有曲名的显示曲名，没曲名的回退成「曲目 #id」，不再一律显示曲目号。
    expect(find.text('Snow halation'), findsOneWidget);
    expect(find.text('曲目 #5'), findsOneWidget);
    // 一首曲一张卡，三个难度在卡片里，不是三行。
    expect(find.textContaining('3 个难度'), findsOneWidget);
    expect(find.text('导入曲名'), findsOneWidget);
    expect(find.text('解锁全部'), findsOneWidget);
  });

  testWidgets('工具页展示卡面库与转换命令入口', (tester) async {
    tester.view.physicalSize = const Size(1100, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
        _wrap(ToolsPage(state: AppState.forTest(api: _api()))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('自定义卡面库'), findsOneWidget);
    expect(find.text('扫描卡面目录'), findsOneWidget);
    expect(find.text('复制 texb 转换命令'), findsOneWidget);
    expect(find.text('cardart_1'), findsOneWidget);
  });
}
