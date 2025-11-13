import { test, expect } from '@playwright/test';

test.describe('Content Verification Tests', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(10000);
  });

  test('homepage contains key content', async ({ page }) => {
    await page.goto('/');

    // Check for main title
    await expect(page.locator('h1')).toContainText('sls.tf');

    // Check for key sections
    await expect(page.locator('body')).toContainText('Serverless Framework');
    await expect(page.locator('body')).toContainText('Terraform');
    await expect(page.locator('body')).toContainText('AWS infrastructure');

    // Check for navigation elements
    const mainNav = page.locator('nav[aria-label="Main"]');
    await expect(mainNav).toBeVisible();
  });

  test('introduction page has proper content', async ({ page }) => {
    await page.goto('/introduction');

    // Check page title
    await expect(page.locator('h1')).toContainText('Welcome to sls.tf');

    // Check for key content sections
    await expect(page.locator('body')).toContainText('comprehensive Terraform module');
    await expect(page.locator('body')).toContainText('Serverless Framework configurations');
    await expect(page.locator('body')).toContainText('production-ready AWS infrastructure');

    // Check for feature list
    await expect(page.locator('body')).toContainText('Lambda Functions');
    await expect(page.locator('body')).toContainText('API Gateway');
    await expect(page.locator('body')).toContainText('DynamoDB');
  });

  test('quick start page has installation steps', async ({ page }) => {
    await page.goto('/quick-start');

    // Check page title
    await expect(page.locator('h1')).toContainText('Quick Start');

    // Check for prerequisites section
    await expect(page.locator('body')).toContainText('Prerequisites');

    // Check for installation steps
    await expect(page.locator('body')).toContainText('Terraform');
    await expect(page.locator('body')).toContainText('git submodule');

    // Check for code examples
    const codeBlocks = page.locator('code, pre');
    await expect(codeBlocks.first()).toBeVisible();
  });

  test('installation page has detailed instructions', async ({ page }) => {
    await page.goto('/installation');

    // Check page title
    await expect(page.locator('h1')).toContainText('Installation');

    // Check for required tools section
    await expect(page.locator('body')).toContainText('Prerequisites');
    await expect(page.locator('body')).toContainText('Terraform');
    await expect(page.locator('body')).toContainText('Node.js');
    await expect(page.locator('body')).toContainText('AWS CLI');

    // Check for installation methods
    await expect(page.locator('body')).toContainText('Git Submodule');
  });

  test('configuration page has proper documentation', async ({ page }) => {
    await page.goto('/configuration');

    // Check page title
    await expect(page.locator('h1')).toContainText('Configuration Guide');

    // Check for basic configuration section
    await expect(page.locator('body')).toContainText('Required Variables');
    await expect(page.locator('body')).toContainText('config_path');
    await expect(page.locator('body')).toContainText('lambda_code_path');

    // Check for configuration examples
    const codeBlocks = page.locator('code:has-text("module")');
    await expect(codeBlocks.first()).toBeVisible();
  });

  test('API reference pages have technical content', async ({ page }) => {
    const apiPages = [
      { path: '/api/variables', title: 'Input Variables', content: ['config_path', 'lambda_code_path'] },
      { path: '/api/outputs', title: 'Outputs', content: ['api_gateway_invoke_url', 'function_names'] },
      { path: '/api/resource-types', title: 'Resource Types', content: ['Lambda', 'API Gateway', 'DynamoDB'] }
    ];

    for (const apiPage of apiPages) {
      await page.goto(apiPage.path);

      // Check page title
      await expect(page.locator('h1')).toContainText(apiPage.title);

      // Check for key content
      for (const content of apiPage.content) {
        await expect(page.locator('body')).toContainText(content);
      }

      // Check for technical documentation
      const codeBlocks = page.locator('code, pre');
      await expect(codeBlocks.first()).toBeVisible();
    }
  });

  test('feature pages contain detailed information', async ({ page }) => {
    const featurePages = [
      { path: '/features/lambda-functions', content: ['Lambda', 'IAM roles', 'memorySize', 'timeout'] },
      { path: '/features/typescript', content: ['TypeScript', 'async exports', 'ts-node'] }
    ];

    for (const featurePage of featurePages) {
      await page.goto(featurePage.path);

      // Check for key content
      for (const content of featurePage.content) {
        await expect(page.locator('body')).toContainText(content);
      }

      // Check for code examples
      const codeBlocks = page.locator('code, pre');
      await expect(codeBlocks.first()).toBeVisible();
    }
  });

  test('example pages have practical implementations', async ({ page }) => {
    const examplePages = [
      { path: '/examples/basic-service', content: ['serverless.yml', 'main.tf', 'handler.js'] },
      { path: '/examples/typescript-config', content: ['serverless.ts', 'TypeScript', 'export default'] }
    ];

    for (const examplePage of examplePages) {
      await page.goto(examplePage.path);

      // Check for key content
      for (const content of examplePage.content) {
        await expect(page.locator('body')).toContainText(content);
      }

      // Check for code examples
      const codeBlocks = page.locator('pre code');
      expect(await codeBlocks.count()).toBeGreaterThan(0);
    }
  });

  test('code blocks are properly formatted', async ({ page }) => {
    await page.goto('/installation');

    // Find code blocks
    const codeBlocks = page.locator('pre code');
    const count = await codeBlocks.count();

    if (count > 0) {
      // Check first code block has syntax highlighting or proper structure
      const firstCodeBlock = codeBlocks.first();
      await expect(firstCodeBlock).toBeVisible();

      // Check code block content is not empty
      const textContent = await firstCodeBlock.textContent();
      expect(textContent?.trim()).not.toBe('');
    }
  });

  test('tables and structured data render correctly', async ({ page }) => {
    await page.goto('/api/variables');

    // Check for tables if they exist
    const tables = page.locator('table');
    if (await tables.count() > 0) {
      await expect(tables.first()).toBeVisible();

      // Check table headers
      const headers = page.locator('th');
      if (await headers.count() > 0) {
        await expect(headers.first()).toBeVisible();
      }

      // Check table cells
      const cells = page.locator('td');
      if (await cells.count() > 0) {
        await expect(cells.first()).toBeVisible();
      }
    }
  });

  test('links within content work', async ({ page }) => {
    await page.goto('/quick-start');

    // Find internal links
    const internalLinks = page.locator('a[href^="/"], a[href^="./"], a[href^="../"]');
    const count = await internalLinks.count();

    if (count > 0) {
      // Test first few internal links
      const linksToTest = Math.min(count, 3);
      for (let i = 0; i < linksToTest; i++) {
        const link = internalLinks.nth(i);
        const href = await link.getAttribute('href');

        if (href && !href.includes('#')) { // Skip anchor links
          // Click the link
          await link.click();

          // Check that navigation worked (no 404)
          await expect(page.locator('h1')).toBeVisible();

          // Go back
          await page.goBack();
        }
      }
    }
  });

  test('headings are properly structured', async ({ page }) => {
    await page.goto('/introduction');

    // Check for h1 heading
    const h1 = page.locator('h1');
    await expect(h1).toBeVisible();
    expect(await h1.count()).toBe(1); // Should be exactly one h1

    // Check for h2 headings
    const h2s = page.locator('h2');
    if (await h2s.count() > 0) {
      await expect(h2s.first()).toBeVisible();
    }

    // Check heading hierarchy (h2s should come after h1, etc.)
    const headings = page.locator('h1, h2, h3, h4, h5, h6');
    const headingCount = await headings.count();

    if (headingCount > 1) {
      // Get text content of headings
      const headingTexts = [];
      for (let i = 0; i < Math.min(headingCount, 5); i++) {
        const text = await headings.nth(i).textContent();
        if (text) headingTexts.push(text.trim());
      }

      expect(headingTexts.length).toBeGreaterThan(0);
    }
  });

  test('images and media load correctly', async ({ page }) => {
    await page.goto('/');

    // Find images
    const images = page.locator('img');
    const count = await images.count();

    if (count > 0) {
      // Check first image loads
      const firstImage = images.first();
      await expect(firstImage).toBeVisible();

      // Check image has src attribute
      const src = await firstImage.getAttribute('src');
      expect(src).toBeTruthy();
    }
  });

  test('no broken internal links', async ({ page }) => {
    await page.goto('/');

    // Find all internal links
    const internalLinks = page.locator('a[href^="/"], a[href^="./"], a[href^="../"]');
    const count = await internalLinks.count();

    if (count > 0) {
      // Test up to 5 links to avoid long test times
      const linksToTest = Math.min(count, 5);
      for (let i = 0; i < linksToTest; i++) {
        const link = internalLinks.nth(i);
        const href = await link.getAttribute('href');

        if (href && !href.includes('#')) { // Skip anchor links
          console.log(`Testing link: ${href}`);

          // Navigate to link
          const response = await page.goto(href);
          expect(response?.status()).toBeLessThan(400);

          // Check page loaded successfully
          await expect(page.locator('h1')).toBeVisible();

          // Go back to continue testing
          await page.goBack();
        }
      }
    }
  });
});