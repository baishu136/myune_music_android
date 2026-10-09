import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/optional_shader_mask.dart';

void main() {
  testWidgets(
    'bypass avoids shader creation/layer and retains child State and geometry',
    (tester) async {
      var calls = 0;
      Widget host(bool active) => MaterialApp(
        home: OptionalShaderMask(
          active: active,
          shaderCallback: (bounds) {
            calls++;
            return const LinearGradient(
              colors: [Colors.white, Colors.transparent],
            ).createShader(bounds);
          },
          child: const SizedBox(
            key: ValueKey('child'),
            height: 100,
            width: 200,
            child: Text('text'),
          ),
        ),
      );
      await tester.pumpWidget(host(false));
      final element = tester.element(find.byKey(const ValueKey('child')));
      final rect = tester.getRect(find.byKey(const ValueKey('child')));
      final render = tester.renderObject<RenderShaderMask>(
        find.byType(OptionalShaderMask),
      );
      expect(calls, 0);
      expect(render.layer, isNull);
      for (final active in [true, false, true, false]) {
        final before = calls;
        await tester.pumpWidget(host(active));
        expect(
          tester.element(find.byKey(const ValueKey('child'))),
          same(element),
        );
        expect(tester.getRect(find.byKey(const ValueKey('child'))), rect);
        expect(calls, active ? greaterThan(before) : before);
        expect(render.layer, active ? isA<ShaderMaskLayer>() : isNull);
      }
    },
  );
}
