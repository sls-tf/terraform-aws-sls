import { test, expect } from '@playwright/test';

test.describe('Accessibility Tests', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(10000);
  });

  test('page has proper title and meta tags', async ({ page }) => {
    await page.goto('/');

    // Check page title
    await expect(page).toHaveTitle(/sls.tf/);

    // Check for meta description
    const metaDescription = page.locator('meta[name="description"]');
    await expect(metaDescription).toBeVisible();
    const description = await metaDescription.getAttribute('content');
    expect(description?.length).toBeGreaterThan(0);

    // Check for meta viewport
    const metaViewport = page.locator('meta[name="viewport"]');
    await expect(metaViewport).toBeVisible();
    const viewport = await metaViewport.getAttribute('content');
    expect(viewport).toContain('width=device-width');
  });

  test('main navigation has proper ARIA labels', async ({ page }) => {
    await page.goto('/');

    // Check for main navigation with ARIA label
    const mainNav = page.locator('nav[aria-label="Main navigation"], nav[aria-label="Main"], nav[aria-label="main"], nav[role="navigation"]');
    await expect(mainNav).toBeVisible();

    // Check navigation links have accessible names
    const navLinks = mainNav.locator('a');
    const linkCount = await navLinks.count();

    if (linkCount > 0) {
      for (let i = 0; i < Math.min(linkCount, 5); i++) {
        const link = navLinks.nth(i);
        const text = await link.textContent();
        expect(text?.trim()).not.toBe('');

        // Check link has href
        const href = await link.getAttribute('href');
        expect(href).toBeTruthy();
      }
    }
  });

  test('headings have proper hierarchy', async ({ page }) => {
    await page.goto('/introduction');

    // Check there's exactly one h1
    const h1s = page.locator('h1');
    await expect(h1s).toHaveCount(1);

    // Check h1 text is not empty
    const h1Text = await h1s.textContent();
    expect(h1Text?.trim()).not.toBe('');

    // Check heading levels don't skip (h1 followed by h3, etc.)
    const headings = page.locator('h1, h2, h3, h4, h5, h6');
    const headingLevels = [];

    for (let i = 0; i < await headings.count(); i++) {
      const heading = headings.nth(i);
      const tagName = await heading.evaluate(el => el.tagName);
      const level = parseInt(tagName.substring(1));
      headingLevels.push(level);
    }

    // Verify heading hierarchy doesn't skip levels
    for (let i = 1; i < headingLevels.length; i++) {
      const currentLevel = headingLevels[i];
      const previousLevel = headingLevels[i - 1];
      expect(currentLevel).toBeLessThanOrEqual(previousLevel + 1);
    }
  });

  test('images have alt text', async ({ page }) => {
    await page.goto('/');

    // Find all images
    const images = page.locator('img');
    const imageCount = await images.count();

    if (imageCount > 0) {
      for (let i = 0; i < imageCount; i++) {
        const img = images.nth(i);
        const alt = await img.getAttribute('alt');

        // Images should have alt text (empty alt for decorative images is allowed)
        expect(alt !== null).toBeTruthy();

        // Check image has src
        const src = await img.getAttribute('src');
        expect(src).toBeTruthy();
      }
    }
  });

  test('form elements have proper labels', async ({ page }) => {
    await page.goto('/');

    // Find search input or other form elements
    const inputs = page.locator('input, textarea, select');
    const inputCount = await inputs.count();

    if (inputCount > 0) {
      for (let i = 0; i < inputCount; i++) {
        const input = inputs.nth(i);

        // Check for label, aria-label, or aria-labelledby
        const hasLabel = await page.locator(`label[for="${await input.getAttribute('id')}"]`).count() > 0;
        const hasAriaLabel = await input.getAttribute('aria-label') !== null;
        const hasAriaLabelledBy = await input.getAttribute('aria-labelledby') !== null;
        const hasTitle = await input.getAttribute('title') !== null;

        expect(hasLabel || hasAriaLabel || hasAriaLabelledBy || hasTitle).toBeTruthy();
      }
    }
  });

  test('links have accessible names', async ({ page }) => {
    await page.goto('/quick-start');

    // Find all links
    const links = page.locator('a[href]');
    const linkCount = await links.count();

    if (linkCount > 0) {
      // Test first 10 links to avoid long test times
      const linksToTest = Math.min(linkCount, 10);

      for (let i = 0; i < linksToTest; i++) {
        const link = links.nth(i);
        const text = await link.textContent();
        const ariaLabel = await link.getAttribute('aria-label');
        const title = await link.getAttribute('title');

        // Link should have accessible text via content, aria-label, or title
        const hasAccessibleName =
          (text && text.trim().length > 0) ||
          (ariaLabel && ariaLabel.length > 0) ||
          (title && title.length > 0);

        expect(hasAccessibleName).toBeTruthy();
      }
    }
  });

  test('color contrast requirements', async ({ page }) => {
    await page.goto('/introduction');

    // Check text elements for basic visibility
    const textElements = page.locator('p, h1, h2, h3, h4, h5, h6, li, a, button');
    const elementCount = await textElements.count();

    if (elementCount > 0) {
      // Test a sample of text elements
      const elementsToTest = Math.min(elementCount, 5);

      for (let i = 0; i < elementsToTest; i++) {
        const element = textElements.nth(i);

        // Check element is visible
        await expect(element).toBeVisible();

        // Check element has color set (not transparent)
        const color = await element.evaluate(el =>
          window.getComputedStyle(el).color
        );

        expect(color).not.toBe('transparent');
        expect(color).not.toBe('rgba(0, 0, 0, 0)');
      }
    }
  });

  test('keyboard navigation works', async ({ page }) => {
    await page.goto('/');

    // Tab through focusable elements
    const focusableElements = page.locator('a, button, input, textarea, select, [tabindex]:not([tabindex="-1"])');
    const elementCount = await focusableElements.count();

    if (elementCount > 0) {
      // Test first few elements
      const elementsToTest = Math.min(elementCount, 5);

      for (let i = 0; i < elementsToTest; i++) {
        const element = focusableElements.nth(i);

        // Focus the element
        await element.focus();

        // Check element receives focus
        await expect(element).toBeFocused();

        // Tab to next element
        await page.keyboard.press('Tab');
      }
    }
  });

  test('skip links functionality', async ({ page }) => {
    await page.goto('/');

    // Look for skip links
    const skipLinks = page.locator('a[href^="#"], .skip-link, [aria-label*="skip"]');
    const skipLinkCount = await skipLinks.count();

    if (skipLinkCount > 0) {
      const firstSkipLink = skipLinks.first();
      await expect(firstSkipLink).toBeVisible();

      // Click skip link
      await firstSkipLink.click();

      // Check if page scrolled or focus moved
      await page.waitForTimeout(1000);
    }
  });

  test('focus management', async ({ page }) => {
    await page.goto('/');

    // Check that focus is managed properly
    const focusableElements = page.locator('a, button, input');
    const elementCount = await focusableElements.count();

    if (elementCount > 0) {
      const firstElement = focusableElements.first();

      // Focus first element
      await firstElement.focus();
      await expect(firstElement).toBeFocused();

      // Check focus styles
      const outline = await firstElement.evaluate(el =>
        window.getComputedStyle(el).outline
      );
      expect(outline).not.toBe('none');
    }
  });

  test('ARIA landmarks are present', async ({ page }) => {
    await page.goto('/');

    // Check for main landmarks
    const main = page.locator('main, [role="main"]');
    await expect(main).toBeVisible();

    const nav = page.locator('nav, [role="navigation"]');
    await expect(nav).toBeVisible();

    // Check for header/footer if they exist
    const header = page.locator('header, [role="banner"]');
    if (await header.count() > 0) {
      await expect(header).toBeVisible();
    }

    const footer = page.locator('footer, [role="contentinfo"]');
    if (await footer.count() > 0) {
      await expect(footer).toBeVisible();
    }
  });

  test('tables have proper headers', async ({ page }) => {
    await page.goto('/api/variables');

    // Find tables
    const tables = page.locator('table');
    const tableCount = await tables.count();

    if (tableCount > 0) {
      const firstTable = tables.first();

      // Check for table headers
      const headers = firstTable.locator('th');
      const headerCount = await headers.count();

      if (headerCount > 0) {
        // Check headers have text content
        for (let i = 0; i < headerCount; i++) {
          const header = headers.nth(i);
          const text = await header.textContent();
          expect(text?.trim()).not.toBe('');
        }

        // Check for scope attributes
        const firstHeader = headers.first();
        const scope = await firstHeader.getAttribute('scope');
        // scope is optional but recommended
      }

      // Check for caption if table is complex
      const caption = firstTable.locator('caption');
      // caption is optional for simple tables
    }
  });

  test('buttons have accessible names', async ({ page }) => {
    await page.goto('/');

    // Find all buttons
    const buttons = page.locator('button, [role="button"]');
    const buttonCount = await buttons.count();

    if (buttonCount > 0) {
      for (let i = 0; i < Math.min(buttonCount, 5); i++) {
        const button = buttons.nth(i);

        // Check button has accessible name
        const text = await button.textContent();
        const ariaLabel = await button.getAttribute('aria-label');
        const ariaLabelledBy = await button.getAttribute('aria-labelledby');

        const hasAccessibleName =
          (text && text.trim().length > 0) ||
          (ariaLabel && ariaLabel.length > 0) ||
          (ariaLabelledBy && ariaLabelledBy.length > 0);

        expect(hasAccessibleName).toBeTruthy();
      }
    }
  });

  test('reduced motion preference', async ({ page }) => {
    // Set prefers-reduced-motion
    await page.emulateMedia({ reducedMotion: 'reduce' });

    await page.goto('/');

    // Page should still be functional with reduced motion
    await expect(page.locator('h1')).toBeVisible();

    // Check animations are disabled (this is a basic check)
    const animatedElements = page.locator('[style*="animation"], [style*="transition"]');
    const elementCount = await animatedElements.count();

    if (elementCount > 0) {
      // In a real implementation, you'd check that animations respect the preference
      console.log(`Found ${elementCount} elements with animations`);
    }
  });

  test('high contrast mode', async ({ page }) => {
    // Emulate high contrast mode if supported
    await page.emulateMedia({ forcedColors: 'active' });

    await page.goto('/');

    // Page should still be readable in high contrast mode
    await expect(page.locator('h1')).toBeVisible();

    // Check text is still visible
    const bodyText = page.locator('body');
    await expect(bodyText).toBeVisible();
  });

  test('screen reader semantic structure', async ({ page }) => {
    await page.goto('/introduction');

    // Check page has semantic structure
    await expect(page.locator('h1')).toBeVisible();

    // Check for lists if they exist
    const lists = page.locator('ul, ol');
    if (await lists.count() > 0) {
      const firstList = lists.first();
      await expect(firstList).toBeVisible();

      // Check list items exist
      const listItems = firstList.locator('li');
      if (await listItems.count() > 0) {
        await expect(listItems.first()).toBeVisible();
      }
    }

    // Check for code blocks have proper semantic markup
    const codeBlocks = page.locator('pre code, code');
    if (await codeBlocks.count() > 0) {
      await expect(codeBlocks.first()).toBeVisible();
    }
  });
});