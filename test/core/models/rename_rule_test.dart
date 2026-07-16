import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/rename_rule.dart';

void main() {
  group('RenameRule', () {
    group('构造函数', () {
      test('应使用必填参数正确创建', () {
        const rule = RenameRule(id: 'title', name: '游戏标题');
        expect(rule.id, 'title');
        expect(rule.name, '游戏标题');
        expect(rule.enabled, true);
        expect(rule.order, 0);
        expect(rule.wrapBefore, '');
        expect(rule.wrapAfter, '');
      });

      test('应正确设置所有参数', () {
        const rule = RenameRule(
          id: 'game_id',
          name: '游戏ID',
          enabled: false,
          order: 2,
          wrapBefore: '[',
          wrapAfter: ']',
        );
        expect(rule.id, 'game_id');
        expect(rule.name, '游戏ID');
        expect(rule.enabled, false);
        expect(rule.order, 2);
        expect(rule.wrapBefore, '[');
        expect(rule.wrapAfter, ']');
      });
    });

    group('defaultRules', () {
      test('应返回5条默认规则', () {
        final rules = RenameRule.defaultRules();
        expect(rules.length, 5);
      });

      test('默认规则应按顺序排列', () {
        final rules = RenameRule.defaultRules();
        expect(rules[0].id, 'game_id');
        expect(rules[0].order, 0);
        expect(rules[1].id, 'maker');
        expect(rules[1].order, 1);
        expect(rules[2].id, 'series');
        expect(rules[2].order, 2);
        expect(rules[3].id, 'title');
        expect(rules[3].order, 3);
        expect(rules[4].id, 'version');
        expect(rules[4].order, 4);
      });

      test('默认规则应有正确的包裹符号', () {
        final rules = RenameRule.defaultRules();
        expect(rules[0].wrapBefore, '[');
        expect(rules[0].wrapAfter, ']');
        expect(rules[1].wrapBefore, '[');
        expect(rules[1].wrapAfter, ']');
        expect(rules[2].wrapBefore, '[');
        expect(rules[2].wrapAfter, ']');
        expect(rules[3].wrapBefore, '');
        expect(rules[3].wrapAfter, '');
        expect(rules[4].wrapBefore, '');
        expect(rules[4].wrapAfter, '');
      });
    });

    group('JSON 序列化', () {
      test('toJson 应正确转换', () {
        const rule = RenameRule(
          id: 'title',
          name: '游戏标题',
          enabled: true,
          order: 3,
          wrapBefore: '(',
          wrapAfter: ')',
        );
        final json = rule.toJson();
        expect(json['id'], 'title');
        expect(json['name'], '游戏标题');
        expect(json['enabled'], true);
        expect(json['order'], 3);
        expect(json['wrapBefore'], '(');
        expect(json['wrapAfter'], ')');
      });

      test('fromJson 应正确解析', () {
        final json = {
          'id': 'maker',
          'name': '游戏厂商',
          'enabled': false,
          'order': 1,
          'wrapBefore': '<',
          'wrapAfter': '>',
        };
        final rule = RenameRule.fromJson(json);
        expect(rule.id, 'maker');
        expect(rule.name, '游戏厂商');
        expect(rule.enabled, false);
        expect(rule.order, 1);
        expect(rule.wrapBefore, '<');
        expect(rule.wrapAfter, '>');
      });

      test('fromJson 应使用默认值处理缺失字段', () {
        final json = {'id': 'test', 'name': '测试'};
        final rule = RenameRule.fromJson(json);
        expect(rule.enabled, true);
        expect(rule.order, 0);
        expect(rule.wrapBefore, '');
        expect(rule.wrapAfter, '');
      });

      test('toJson/fromJson 往返应保持一致', () {
        const original = RenameRule(
          id: 'series',
          name: '系列标签',
          enabled: false,
          order: 5,
          wrapBefore: '{',
          wrapAfter: '}',
        );
        final restored = RenameRule.fromJson(original.toJson());
        expect(restored.id, original.id);
        expect(restored.name, original.name);
        expect(restored.enabled, original.enabled);
        expect(restored.order, original.order);
        expect(restored.wrapBefore, original.wrapBefore);
        expect(restored.wrapAfter, original.wrapAfter);
      });
    });

    group('copyWith', () {
      test('无参数时应返回相同值的副本', () {
        const rule = RenameRule(id: 'title', name: '游戏标题', order: 3);
        final copy = rule.copyWith();
        expect(copy.id, rule.id);
        expect(copy.name, rule.name);
        expect(copy.order, rule.order);
      });

      test('应正确覆盖指定字段', () {
        const rule = RenameRule(id: 'title', name: '游戏标题');
        final copy = rule.copyWith(name: '新标题', enabled: false);
        expect(copy.id, 'title');
        expect(copy.name, '新标题');
        expect(copy.enabled, false);
      });
    });

    group('wrapContent', () {
      test('有包裹符号时应包裹内容', () {
        const rule = RenameRule(
          id: 'test',
          name: '测试',
          wrapBefore: '[',
          wrapAfter: ']',
        );
        expect(rule.wrapContent('内容'), '[内容]');
      });

      test('无包裹符号时应返回原内容', () {
        const rule = RenameRule(id: 'test', name: '测试');
        expect(rule.wrapContent('内容'), '内容');
      });

      test('仅有前包裹符号时应仅添加前缀', () {
        const rule = RenameRule(
          id: 'test',
          name: '测试',
          wrapBefore: '#',
        );
        expect(rule.wrapContent('内容'), '#内容');
      });

      test('仅有后包裹符号时应仅添加后缀', () {
        const rule = RenameRule(
          id: 'test',
          name: '测试',
          wrapAfter: '!',
        );
        expect(rule.wrapContent('内容'), '内容!');
      });
    });
  });
}
