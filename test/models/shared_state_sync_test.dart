import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// syncState 把 needSyncSharedState 的 JSON 发给原生侧（快捷磁贴、通知栏读它），
/// 所以「要不要同步」必须按这份 JSON 判断。
///
/// 这里锁住的行为是：换节点必须触发同步。freezed 的 == 逐字段比较（含
/// currentNodeName），原本就能触发；这些用例的价值是防止以后往 SharedState
/// 加字段时漏掉同步条件，以及确认 setupParams 确实被剥离。
void main() {
  SharedState base({String? nodeName}) => SharedState(
    stopTip: 'Stopping',
    startTip: 'Starting',
    localNetworkTip: 'Local network denied',
    currentProfileName: 'Work',
    currentNodeName: nodeName,
    stopText: 'Stop',
    onlyStatisticsProxy: false,
    crashlytics: true,
  );

  String payload(SharedState state) =>
      state.needSyncSharedState.toJson().toString();

  test('changing only the node name changes what gets synced', () {
    final before = base(nodeName: 'HK 01');
    final after = base(nodeName: 'JP 02');

    // 两个断言都要成立：换节点必须让「发送内容」发生变化，否则磁贴不会更新。
    expect(
      after.needSyncSharedState,
      isNot(equals(before.needSyncSharedState)),
    );
    expect(payload(after), isNot(equals(payload(before))));
  });

  test('an unchanged node name keeps the payload identical', () {
    expect(payload(base(nodeName: 'HK 01')), payload(base(nodeName: 'HK 01')));
  });

  test('the node name survives into the synced payload', () {
    expect(payload(base(nodeName: 'HK 01')), contains('HK 01'));
  });

  test('a null node name is still represented in the payload', () {
    expect(payload(base(nodeName: null)), contains('currentNodeName'));
  });

  test('setup params are stripped from the synced payload', () {
    // needSyncSharedState 去掉 setupParams：它只用于启动时的一次性握手。
    const state = SharedState(
      stopTip: 'Stopping',
      startTip: 'Starting',
      localNetworkTip: 'Local network denied',
      currentProfileName: 'Work',
      currentNodeName: 'HK 01',
      stopText: 'Stop',
      onlyStatisticsProxy: false,
      crashlytics: true,
      setupParams: SetupParams(
        testUrl: 'https://example.test/204',
        selectedMap: {'GLOBAL': 'HK 01'},
      ),
    );

    final synced = state.needSyncSharedState;
    expect(synced.setupParams, isNull);
    expect(synced.currentNodeName, 'HK 01');
    expect(payload(state), isNot(contains('example.test')));
  });
}
