import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../catalog/data/catalog_api.dart';
import '../../catalog/data/catalog_repository.dart';
import '../data/coupon_api.dart';
import '../domain/cart.dart';
import '../domain/reconciliation.dart';

final cartReconcilerProvider = Provider<CartReconciler>(
  (ref) => CartReconciler(
    catalogApi: ref.watch(catalogApiProvider),
    couponApi: ref.watch(couponApiProvider),
  ),
);

/// Compares a local cart with the server's current state.
class CartReconciler {
  CartReconciler({
    required this.catalogApi,
    required this.couponApi,
  });

  final CatalogApi catalogApi;
  final CouponApi couponApi;

  /// Reconciles the local cart with the latest server data.
  ///
  /// Updates product prices and quantities, removes unavailable products,
  /// and refreshes or removes invalid coupons.
  ///
  /// Throws an ApiException if the server cannot be reached.
  /// Never returns a partially reconciled cart.
  Future<ReconciliationResult> reconcile(Cart cart) async {
    // No products and no coupon: nothing to reconcile.
    if (cart.lines.isEmpty && cart.coupon == null) {
      return ReconciliationResult(
        cart: cart,
        changes: const [],
      );
    }

    final updatedLines = <CartLine>[];
    final changes = <CartChange>[];

    // Fetch the latest product information.
    if (cart.lines.isNotEmpty) {
      final ids = cart.lines.map((line) => line.productId).toList();

      final batch = await catalogApi.getProductsByIds(ids);

      final products = {
        for (final product in batch.products) product.id: product,
      };

      final missingIds = batch.missingIds.toSet();

      // Preserve the original cart order.
      for (final oldLine in cart.lines) {
        final product = products[oldLine.productId];

        // Product is no longer available.
        if (missingIds.contains(oldLine.productId) || product == null) {
          changes.add(
            ProductUnavailable(productId: oldLine.productId),
          );
          continue;
        }

        // Product is out of stock.
        if (!product.inStock) {
          changes.add(
            OutOfStock(productId: product.id),
          );
          continue;
        }

        final available = product.purchasableQuantity;

        // Reduce quantity if it exceeds the current limit.
        if (oldLine.quantity > available) {
          changes.add(
            QuantityReduced(
              productId: product.id,
              requestedQuantity: oldLine.quantity,
              availableQuantity: available,
            ),
          );
        }

        // Record any price change.
        if (oldLine.unitPricePaise != product.pricePaise) {
          changes.add(
            PriceChanged(
              productId: product.id,
              oldPricePaise: oldLine.unitPricePaise,
              newPricePaise: product.pricePaise,
            ),
          );
        }

        final newQuantity =
            oldLine.quantity > available ? available : oldLine.quantity;

        // Create the refreshed cart line.
        updatedLines.add(
          CartLine.fromProduct(
            product,
            quantity: newQuantity,
          ),
        );
      }
    }

    // Refresh the coupon if one exists.
    var updatedCoupon = cart.coupon;

    if (updatedCoupon != null) {
      final currentCoupon = updatedCoupon;

      try {
        final latestCoupon = await couponApi.validate(
          currentCoupon.code,
        );

        // Remove a coupon that has expired.
        if (latestCoupon.isExpired(DateTime.now())) {
          changes.add(
            CouponRemoved(
              code: currentCoupon.code,
              reason: 'EXPIRED',
            ),
          );
          updatedCoupon = null;
        } else {
          // Keep the latest server-side coupon rules.
          // Do not remove it just because the minimum order
          // amount has not been reached.
          updatedCoupon = latestCoupon;
        }
      } on ClientException catch (e) {
        if (e.code == 'COUPON_EXPIRED' || e.code == 'COUPON_NOT_FOUND') {
          changes.add(
            CouponRemoved(
              code: currentCoupon.code,
              reason: e.code == 'COUPON_EXPIRED' ? 'EXPIRED' : 'NOT_FOUND',
            ),
          );

          updatedCoupon = null;
        } else {
          // Other API errors must not be silently ignored.
          rethrow;
        }
      }
    }

    // Return the fully reconciled cart.
    final updatedCart = Cart(
      lines: updatedLines,
      coupon: updatedCoupon,
    );

    return ReconciliationResult(
      cart: updatedCart,
      changes: changes,
    );
  }
}
