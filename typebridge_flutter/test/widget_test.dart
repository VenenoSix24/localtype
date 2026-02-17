import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:localtype/providers/local_type_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localtype/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LocalTypeProvider()),
        ],
        child: const LocalTypeApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 验证导航栏显示中文标签
    expect(find.text('输入'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
