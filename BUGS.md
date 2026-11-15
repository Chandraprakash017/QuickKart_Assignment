# Bugs found & fixed

## BUG-1: Cart reconciliation was not implemented (QK-101)

- **Symptom:** Calling `CartReconciler.reconcile()` always threw `UnimplementedError`, preventing the cart from being checked against current server data.
- **Steps to reproduce:**
  1. Create an empty cart.
  2. Call `CartReconciler.reconcile(cart)`.
  3. Observe the `UnimplementedError`.
- **Root cause:** `lib/features/cart/application/cart_reconciler.dart`, `CartReconciler.reconcile()`, contained only a TODO and an `UnimplementedError`.
- **Fix:** Implemented server-side product and coupon refresh, price and quantity reconciliation, removal of unavailable products and invalid coupons, and preservation of cart line order.
- **Test:** `test/cart_reconciler_test.dart` → `empty cart returns unchanged without errors`
- **Commits:** test `ece1b1a` → fix `d0c95d2`
- **Additional coverage:** `d4719b7` adds tests for price changes, stock conflicts, unavailable products, and coupon handling.

---

## Suspicious but NOT a bug

- Flutter analyzer reports 13 informational deprecation notices for `package:flutter/material.dart`. These are framework migration notices, not test failures or errors introduced by the cart reconciliation change.
