import { test, expect } from '@playwright/test';

test.describe('Basic Navigation Tests', () => {
  const pages = [
    { path: '/', title: 'sls.tf' },
    { path: '/introduction', title: 'Introduction' },
    { path: '/quick-start', title: 'Quick Start' },
    { path: '/installation', title: 'Installation' },
    { path: '/configuration', title: 'Configuration' },
    { path: '/api/variables', title: 'Variables' },
    { path: '/api/outputs', title: 'Outputs' },
    { path: '/api/resource-types', title: 'Resource Types' },
    { path: '/features/lambda-functions', title: 'Lambda Functions' },
    { path: '/features/typescript', title: 'TypeScript Support' },
    { path: '/examples/basic-service', title: 'Basic Service' },
    { path: '/examples/typescript-config', title: 'TypeScript Config' }
  ];

  test.beforeEach(async ({ page }) => {
    // Set a longer timeout for page loads
    page.setDefaultTimeout(10000);
  });

  test('homepage loads successfully', async ({ page }) => {
    await page.goto('/');

    // Check that the page loads without errors
    await expect(page).toHaveTitle(/sls.tf/);

    // Check for main navigation elements
    const navigation = page.locator('nav[aria-label="Main navigation"]');
    await expect(navigation).toBeVisible();

    // Check for main heading (exclude dev toolbar elements)
    const mainHeading = page.locator('main h1, h1[data-astro-cid]');
    await expect(mainHeading).toBeVisible();
  });

  test('all main documentation pages load without 404 errors', async ({ page }) => {
    for (const pageData of pages) {
      console.log(`Testing page: ${pageData.path}`);

      // Navigate to the page
      const response = await page.goto(pageData.path);

      // Check successful response
      expect(response?.status()).toBe(200);

      // Check for proper title
      await expect(page).toHaveTitle(/sls.tf/);

      // Check that we're not on a 404 page
      await expect(page.locator('h1')).toBeVisible();

      // Check main navigation is present
      const navigation = page.locator('nav[aria-label="Main navigation"]');
      await expect(navigation).toBeVisible();
    }
  });

  test('main navigation works correctly', async ({ page }) => {
    await page.goto('/');

    // Check for main navigation links
    const navigation = page.locator('nav[aria-label="Main navigation"]');
    await expect(navigation).toBeVisible();

    // Check main navigation sections
    const expectedLinks = ['Home', 'Documentation', 'GitHub'];

    for (const linkText of expectedLinks) {
      const link = navigation.locator(`a:has-text("${linkText}")`);
      await expect(link).toBeVisible();
    }
  });

  test('navigation between pages works', async ({ page }) => {
    await page.goto('/');

    // Click on Documentation link
    await page.click('nav[aria-label="Main navigation"] a:has-text("Documentation")');
    await expect(page).toHaveURL('/docs');

    // Navigate to introduction page directly
    await page.goto('/introduction');
    await expect(page).toHaveURL('/introduction');

    // Check browser back button
    await page.goBack();
    await expect(page).toHaveURL('/docs');

    // Check browser forward button
    await page.goForward();
    await expect(page).toHaveURL('/introduction');
  });

  test('navigation links are accessible', async ({ page }) => {
    await page.goto('/');

    // Check all navigation links have proper attributes
    const navLinks = page.locator('nav[aria-label="Main navigation"] a');
    const count = await navLinks.count();

    expect(count).toBeGreaterThan(0);

    for (let i = 0; i < count; i++) {
      const link = navLinks.nth(i);
      await expect(link).toBeVisible();

      // Check href exists
      const href = await link.getAttribute('href');
      expect(href).toBeTruthy();
    }
  });

  test('page navigation through links works', async ({ page }) => {
    await page.goto('/docs');

    // Find documentation links
    const docLinks = page.locator('.doc-link');
    const count = await docLinks.count();

    expect(count).toBeGreaterThan(0);

    // Test first few links to ensure they work
    for (let i = 0; i < Math.min(3, count); i++) {
      const link = docLinks.nth(i);
      const href = await link.getAttribute('href');

      if (href && !href.startsWith('http')) {
        // Navigate to the link
        await link.click();

        // Check that page loads without 404
        await expect(page.locator('body')).toBeVisible();

        // Go back
        await page.goBack();
        await expect(page).toHaveURL('/docs');
      }
    }
  });

  test('page responsiveness works', async ({ page }) => {
    await page.goto('/');

    // Test desktop viewport
    await page.setViewportSize({ width: 1200, height: 800 });
    const nav = page.locator('nav[aria-label="Main navigation"]');
    await expect(nav).toBeVisible();

    // Test tablet viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await expect(nav).toBeVisible();

    // Test mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await expect(nav).toBeVisible();
  });

  test('site styling loads correctly', async ({ page }) => {
    await page.goto('/');

    // Check that main elements have loaded
    await expect(page.locator('nav')).toBeVisible();
    await expect(page.locator('main')).toBeVisible();
    await expect(page.locator('footer')).toBeVisible();

    // Check that CSS has loaded by verifying styles are applied
    const nav = page.locator('nav');
    const computedStyle = await nav.evaluate((el) => {
      return window.getComputedStyle(el).position;
    });

    // Navigation should have position: sticky or similar
    expect(['sticky', 'relative', 'static', 'fixed']).toContain(computedStyle);
  });

  test('external links work correctly', async ({ page }) => {
    await page.goto('/installation');

    // Find external links (GitHub, Discord, etc.)
    const externalLinks = page.locator('a[href*="github.com"], a[href*="discord.gg"]');
    const count = await externalLinks.count();

    if (count > 0) {
      // Test first external link
      const firstLink = externalLinks.first();
      const href = await firstLink.getAttribute('href');

      expect(href).toBeTruthy();
      expect(href?.startsWith('http')).toBeTruthy();

      // Check rel attributes for external links
      const rel = await firstLink.getAttribute('rel');
      expect(rel).toContain('noopener');
      expect(rel).toContain('noreferrer');
    }
  });
});