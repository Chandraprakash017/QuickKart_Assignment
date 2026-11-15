import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_reconciler.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/reconciliation.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/cart/data/coupon_api.dart';

import 'helpers/test_harness.dart';

void main() {
  test('empty cart returns unchanged without errors', () async {
    final h = TestHarness();
    addTearDown(h.dispose);

    final result = await h.read(cartReconcilerProvider).reconcile(Cart.empty());

    expect(result.cart, Cart.empty());
    expect(result.changes, isEmpty);
  });

  test('reconciles price, stock, out-of-stock and unavailable products',
      () async {
    final h = TestHarness();
    addTearDown(h.dispose);

    final ids = h.server.productIds.take(4).toList();
    final batch = await h.read(catalogApiProvider).getProductsByIds(ids);
    final products = batch.products;

    expect(products.length, 4);

    final cart = Cart(lines: [
      CartLine.fromProduct(products[0], quantity: 1),
      CartLine.fromProduct(products[1], quantity: 1),
      CartLine.fromProduct(products[2], quantity: 3),
      CartLine.fromProduct(products[3], quantity: 1),
    ]);

    h.server.simulateCartConflicts(ids);

    final result = await h.read(cartReconcilerProvider).reconcile(cart);

    expect(
        result.cart.lines.map((e) => e.productId).toList(), [ids[0], ids[2]]);

    expect(result.cart.lines[0].unitPricePaise, isNot(products[0].pricePaise));

    expect(result.cart.lines[1].quantity, 1);

    expect(result.changes.whereType<PriceChanged>(), hasLength(1));
    expect(result.changes.whereType<OutOfStock>(), hasLength(1));
    expect(result.changes.whereType<QuantityReduced>(), hasLength(1));
    expect(result.changes.whereType<ProductUnavailable>(), hasLength(1));
    expect(result.requiresUserReview, isTrue);
  });

  test('removes expired coupon and keeps coupon below minimum order', () async {
    final h = TestHarness();
    addTearDown(h.dispose);

    final couponApi = h.read(couponApiProvider);
    final expiredCoupon = await couponApi.validate('FLAT50');

    h.server.expireCoupon('FLAT50');

    final expiredResult = await h
        .read(cartReconcilerProvider)
        .reconcile(Cart(lines: const [], coupon: expiredCoupon));

    expect(expiredResult.cart.coupon, isNull);
    expect(expiredResult.changes.whereType<CouponRemoved>(), hasLength(1));

    final belowMinimumCoupon = await couponApi.validate('SAVE10');

    final result = await h.read(cartReconcilerProvider).reconcile(
          Cart(lines: const [], coupon: belowMinimumCoupon),
        );

    expect(result.cart.coupon, isNotNull);
    expect(result.cart.coupon!.code, 'SAVE10');
  });
}
