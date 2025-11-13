import { test, expect, devices } from '@playwright/test';

test.describe('Responsive Design Tests', () => {
  const viewports = [
    { name: 'Desktop', width: 1200, height: 800 },
    { name: 'Laptop', width: 1024, height: 768 },
    { name: 'Tablet', width: 768, height: 1024 },
    { name: 'Mobile Large', width: 414, height: 896 },
    { name: 'Mobile Small', width: 375, height: 667 }
  ];

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(10000);
  });

  test.describe('Desktop Viewport', () => {
    test.use({ viewport: { width: 1200, height: 800 } });

    test('desktop layout displays correctly', async ({ page }) => {
      await page.goto('/');

      // Check main navigation is visible
      const mainNav = page.locator('nav[aria-label="Main"]');
      await expect(mainNav).toBeVisible();

      // Check sidebar is visible on desktop
      const sidebar = page.locator('.starlight-sidebar');
      await expect(sidebar).toBeVisible();

      // Check content area takes appropriate width
      const content = page.locator('main, .starlight-page');
      await expect(content).toBeVisible();

      // Check page is not showing mobile navigation button
      const mobileNavButton = page.locator('button[aria-label*="menu" i], button[aria-label*="navigation" i]');
      await expect(mobileNavButton).not.toBeVisible();
    });

    test('desktop navigation works', async ({ page }) => {
      await page.goto('/');

      // Test sidebar navigation
      const sidebarLinks = page.locator('.starlight-sidebar a');
      const linkCount = await sidebarLinks.count();

      if (linkCount > 0) {
        // Click first link
        await sidebarLinks.first().click();
        await expect(page.locator('h1')).toBeVisible();
      }
    });

    test('desktop tables display correctly', async ({ page }) => {
      await page.goto('/api/variables');

      // Check if tables exist and are readable
      const tables = page.locator('table');
      if (await tables.count() > 0) {
        await expect(tables.first()).toBeVisible();

        // Check table is not scrollable on desktop (should fit)
        const tableWrapper = tables.first().locator('..');
        const overflow = await tableWrapper.evaluate(el =>
          window.getComputedStyle(el).overflowX
        );

        // Table should not have horizontal overflow on desktop
        expect(overflow).not.toBe('auto');
        expect(overflow).not.toBe('scroll');
      }
    });
  });

  test.describe('Tablet Viewport', () => {
    test.use({ viewport: { width: 768, height: 1024 } });

    test('tablet layout adapts correctly', async ({ page }) => {
      await page.goto('/');

      // Check main navigation is still visible
      const mainNav = page.locator('nav[aria-label="Main"]');
      await expect(mainNav).toBeVisible();

      // Check sidebar behavior on tablet
      const sidebar = page.locator('.starlight-sidebar');
      await expect(sidebar).toBeVisible();

      // Check content area adjusts
      const content = page.locator('main, .starlight-page');
      await expect(content).toBeVisible();
    });

    test('tablet navigation works', async ({ page }) => {
      await page.goto('/introduction');

      // Test navigation still works on tablet
      const sidebarLinks = page.locator('.starlight-sidebar a');
      const linkCount = await sidebarLinks.count();

      if (linkCount > 0) {
        // Test clicking a navigation link
        await sidebarLinks.first().click();
        await expect(page.locator('h1')).toBeVisible();
      }
    });
  });

  test.describe('Mobile Viewport', () => {
    test.use({ viewport: { width: 375, height: 667 } });

    test('mobile layout works correctly', async ({ page }) => {
      await page.goto('/');

      // Check main navigation is visible
      const mainNav = page.locator('nav[aria-label="Main"]');
      await expect(mainNav).toBeVisible();

      // Check mobile navigation button is visible
      const mobileNavButton = page.locator('button[aria-label*="menu" i], button[aria-label*="navigation" i]');

      // Wait a bit for mobile elements to potentially appear
      await page.waitForTimeout(1000);

      // Check if sidebar is hidden by default on mobile
      const sidebar = page.locator('.starlight-sidebar');
      const sidebarVisible = await sidebar.isVisible();

      // On mobile, sidebar might be hidden or transformed
      if (sidebarVisible) {
        // If visible, check if it's properly styled for mobile
        const sidebarPosition = await sidebar.evaluate(el =>
          window.getComputedStyle(el).position
        );
        console.log(`Mobile sidebar position: ${sidebarPosition}`);
      }
    });

    test('mobile navigation functionality', async ({ page }) => {
      await page.goto('/');

      // Look for mobile navigation button
      const mobileNavButton = page.locator('button[aria-label*="menu" i], button[aria-label*="navigation" i], .mobile-nav-toggle');

      if (await mobileNavButton.isVisible()) {
        // Click to open mobile menu
        await mobileNavButton.click();
        await page.waitForTimeout(500);

        // Check if navigation appears
        const mobileNav = page.locator('.mobile-nav, .starlight-sidebar[aria-expanded="true"], .navigation-menu');

        if (await mobileNav.isVisible()) {
          // Test clicking a navigation link
          const navLink = mobileNav.locator('a').first();
          if (await navLink.isVisible()) {
            await navLink.click();
            await expect(page.locator('h1')).toBeVisible();
          }
        }
      }
    });

    test('mobile content readability', async ({ page }) => {
      await page.goto('/introduction');

      // Check main content is readable
      const mainContent = page.locator('main, .starlight-page, article');
      await expect(mainContent).toBeVisible();

      // Check text is not too small on mobile
      const bodyText = page.locator('body');
      const fontSize = await bodyText.evaluate(el =>
        window.getComputedStyle(el).fontSize
      );
      const fontSizeValue = parseInt(fontSize);
      expect(fontSizeValue).toBeGreaterThanOrEqual(14); // Minimum readable font size

      // Check content width is appropriate for mobile
      const contentWidth = await mainContent.evaluate(el =>
        el.offsetWidth
      );
      const viewportWidth = page.viewportSize()?.width || 375;

      // Content should use most of the viewport width on mobile
      const contentRatio = contentWidth / viewportWidth;
      expect(contentRatio).toBeGreaterThan(0.8);
    });

    test('mobile code blocks are scrollable', async ({ page }) => {
      await page.goto('/installation');

      // Find code blocks
      const codeBlocks = page.locator('pre');
      const codeCount = await codeBlocks.count();

      if (codeCount > 0) {
        const firstCodeBlock = codeBlocks.first();
        await expect(firstCodeBlock).toBeVisible();

        // Check code block width on mobile
        const codeBlockWidth = await firstCodeBlock.evaluate(el =>
          el.scrollWidth > el.offsetWidth
        );

        // Code blocks that are too wide should be horizontally scrollable
        if (codeBlockWidth) {
          const overflowX = await firstCodeBlock.evaluate(el =>
            window.getComputedStyle(el).overflowX
          );
          expect(overflowX === 'auto' || overflowX === 'scroll').toBeTruthy();
        }
      }
    });

    test('mobile tables are scrollable', async ({ page }) => {
      await page.goto('/api/variables');

      // Find tables
      const tables = page.locator('table');
      const tableCount = await tables.count();

      if (tableCount > 0) {
        const firstTable = tables.first();
        await expect(firstTable).toBeVisible();

        // Check if table needs scrolling on mobile
        const tableContainer = firstTable.locator('..');
        const overflowX = await tableContainer.evaluate(el =>
          window.getComputedStyle(el).overflowX
        );

        // Tables should be scrollable on mobile if they overflow
        if (overflowX === 'auto' || overflowX === 'scroll') {
          // Test horizontal scrolling
          const maxScroll = await tableContainer.evaluate(el => el.scrollWidth - el.offsetWidth);
          expect(maxScroll).toBeGreaterThan(0);

          // Test scrolling functionality
          await tableContainer.scrollRight(maxScroll);
          await page.waitForTimeout(500);
        }
      }
    });
  });

  test.describe('Cross-Device Consistency', () => {
    const pages = ['/', '/introduction', '/quick-start', '/installation'];

    pages.forEach(pagePath => {
      test(`content consistency across devices for ${pagePath}`, async ({ page }) => {
        // Test on desktop
        await page.setViewportSize({ width: 1200, height: 800 });
        await page.goto(pagePath);
        const desktopH1 = await page.locator('h1').textContent();

        // Test on mobile
        await page.setViewportSize({ width: 375, height: 667 });
        await page.reload();
        const mobileH1 = await page.locator('h1').textContent();

        // Main heading should be consistent
        expect(desktopH1).toBe(mobileH1);
      });
    });
  });

  test.describe('Orientation Changes', () => {
    test('mobile orientation change works', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 }); // Portrait
      await page.goto('/');

      // Check page loads in portrait
      await expect(page.locator('h1')).toBeVisible();

      // Change to landscape
      await page.setViewportSize({ width: 667, height: 375 }); // Landscape
      await page.waitForTimeout(500);

      // Check page still works in landscape
      await expect(page.locator('h1')).toBeVisible();

      // Change back to portrait
      await page.setViewportSize({ width: 375, height: 667 });
      await page.waitForTimeout(500);

      // Check page still works after orientation change
      await expect(page.locator('h1')).toBeVisible();
    });
  });

  test.describe('Touch Interactions', () => {
    test.use({ viewport: { width: 375, height: 667 } });

    test('mobile touch interactions work', async ({ page }) => {
      await page.goto('/');

      // Test swipe gestures (basic implementation)
      const mainContent = page.locator('main, .starlight-page');
      await expect(mainContent).toBeVisible();

      // Test touch events on navigation
      const navLinks = page.locator('nav a, .starlight-sidebar a');
      const linkCount = await navLinks.count();

      if (linkCount > 0) {
        const firstLink = navLinks.first();

        // Touch/click the link
        await firstLink.tap();
        await expect(page.locator('h1')).toBeVisible();
      }
    });
  });

  test.describe('Performance on Mobile', () => {
    test.use({ viewport: { width: 375, height: 667 } });

    test('mobile page load performance', async ({ page }) => {
      const startTime = Date.now();

      await page.goto('/quick-start');

      // Wait for page to be fully loaded
      await page.waitForLoadState('networkidle');
      await expect(page.locator('h1')).toBeVisible();

      const loadTime = Date.now() - startTime;

      // Page should load within reasonable time on mobile
      expect(loadTime).toBeLessThan(5000); // 5 seconds max
    });

    test('mobile scroll performance', async ({ page }) => {
      await page.goto('/installation');

      // Scroll to bottom of page
      await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
      await page.waitForTimeout(1000);

      // Scroll back to top
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.waitForTimeout(1000);

      // Check page is still functional
      await expect(page.locator('h1')).toBeVisible();
    });
  });
});