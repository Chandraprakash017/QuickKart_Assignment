import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_reconciler.dart';
import 'package:quickkart/features/cart/domain/cart.dart';

import 'helpers/test_harness.dart';

void main() {
  test('empty cart returns unchanged without errors', () async {
    final harness = TestHarness();
    addTearDown(harness.dispose);

    final reconciler = harness.read(cartReconcilerProvider);
    final cart = Cart.empty();

    final result = await reconciler.reconcile(cart);

    expect(result.cart, cart);
    expect(result.changes, isEmpty);
  });
}
