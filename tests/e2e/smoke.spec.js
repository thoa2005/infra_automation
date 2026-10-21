const { test, expect } = require('@playwright/test');

test('trang web tra HTTP 200', async ({ page }) => {
  const response = await page.goto('/');
  expect(response).not.toBeNull();
  expect(response.status()).toBe(200);
});
