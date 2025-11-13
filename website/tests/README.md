# Playwright Test Suite

This directory contains a comprehensive Playwright test suite for the sls.tf documentation website.

## Test Coverage

### 1. Basic Navigation Tests (`basic-navigation.spec.ts`)
- Homepage loading verification
- All documentation pages accessibility (200 status codes)
- Sidebar navigation functionality
- Collapsible sidebar sections
- Breadcrumbs navigation
- Search functionality
- Theme toggle (dark/light mode)
- External links validation

### 2. Content Verification Tests (`content-verification.spec.ts`)
- Homepage key content verification
- Introduction page content validation
- Installation and quick start guides
- API reference technical content
- Feature documentation details
- Example page practical implementations
- Code block formatting validation
- Table and structured data rendering
- Internal link functionality
- Heading structure verification
- Image and media loading

### 3. Responsive Design Tests (`responsive-design.spec.ts`)
- Desktop layout validation
- Tablet adaptation testing
- Mobile layout functionality
- Cross-device content consistency
- Orientation change handling
- Touch interaction support
- Mobile performance testing
- Mobile scroll performance
- Code block scrollability on mobile
- Table scrollability on mobile

### 4. Accessibility Tests (`accessibility.spec.ts`)
- Page titles and meta tags
- ARIA labels and landmarks
- Heading hierarchy validation
- Image alt text verification
- Form element labeling
- Link accessible names
- Color contrast requirements
- Keyboard navigation
- Focus management
- Skip links functionality
- Reduced motion preference
- High contrast mode
- Screen reader semantic structure

### 5. Basic Functionality Tests (`basic-functionality.spec.ts`)
- Page loading status codes
- Navigation element presence
- Content readability and structure
- Code block presence on technical pages
- Link functionality
- Responsive layout testing
- Console error monitoring
- Image loading verification
- Form and input functionality

## Current Status

### ✅ Working Features
- All documentation pages load with 200 status codes
- Navigation and routing work correctly
- Content is properly structured and readable
- Responsive design adapts to different viewports
- Basic accessibility features are implemented

### ⚠️ Known Issues
- **Starlight Head Utility Error**: There's a known issue with Starlight's head utility (`Cannot read properties of undefined (reading 'some')` at `utils/head.ts:43:14`) that affects:
  - Page title generation
  - Some meta tag processing
  - Some dynamic head element creation

**Impact**: This error does not prevent the documentation from functioning, but it affects some of the Playwright tests that specifically check for page titles and certain head elements.

## Running Tests

### Prerequisites
- Node.js installed
- Playwright browsers installed

### Install Dependencies
```bash
npm install
npm run test:install  # Install Playwright browsers
```

### Run Tests

#### Run all tests
```bash
npm test
```

#### Run specific test files
```bash
# Basic navigation tests
npx playwright test basic-navigation.spec.ts

# Content verification tests
npx playwright test content-verification.spec.ts

# Responsive design tests
npx playwright test responsive-design.spec.ts

# Accessibility tests
npx playwright test accessibility.spec.ts

# Basic functionality tests
npx playwright test basic-functionality.spec.ts
```

#### Run tests on specific browsers
```bash
# Chrome only
npx playwright test --project=chromium

# Firefox only
npx playwright test --project=firefox

# Safari only
npx playwright test --project=webkit

# Mobile devices
npx playwright test --project="Mobile Chrome"
npx playwright test --project="Mobile Safari"
```

#### Test with different reporters
```bash
# HTML reporter (default)
npm test

# List reporter
npx playwright test --reporter=list

# JUnit reporter (for CI)
npx playwright test --reporter=junit

# Multiple reporters
npx playwright test --reporter=list --reporter=html
```

#### Test specific functionality
```bash
# Run tests matching a pattern
npx playwright test --grep "navigation"

# Run tests excluding a pattern
npx playwright test --grep-invert "mobile"

# Run tests with specific timeout
npx playwright test --timeout=60000
```

### Development and Debugging

#### Interactive UI mode
```bash
npm run test:ui
```

#### Debug mode
```bash
npm run test:debug
```

#### Generate tests with codegen
```bash
npm run test:codegen
```

#### Run tests with traces
```bash
npx playwright test --trace on
```

#### Run tests with video recording
```bash
npx playwright test --video on
```

## Test Configuration

### Base Configuration
- **Base URL**: `http://localhost:4321`
- **Default timeout**: 10 seconds
- **Retry on CI**: 2 times
- **Parallel execution**: Enabled
- **Screenshots**: On failure
- **Video recording**: On failure
- **Trace collection**: On first retry

### Browsers Tested
- Chromium (Chrome/Edge)
- Firefox
- WebKit (Safari)
- Mobile Chrome (Android)
- Mobile Safari (iPhone)

### Viewports Tested
- Desktop: 1200x800, 1024x768
- Tablet: 768x1024
- Mobile: 414x896, 375x667

## CI/CD Integration

### GitHub Actions
The tests are designed to run in CI/CD environments. Add to your workflow:

```yaml
- name: Install dependencies
  run: npm ci

- name: Install Playwright browsers
  run: npx playwright install --with-deps

- name: Run Playwright tests
  run: npm test

- name: Upload test results
  if: always()
  uses: actions/upload-artifact@v3
  with:
    name: playwright-report
    path: playwright-report/
```

### Environment Variables
- `CI`: Set to true in CI environments
- `PLAYWRIGHT_BROWSERS_PATH`: Override browser installation path

## Troubleshooting

### Common Issues

1. **Connection Refused Error**
   - Ensure development server is running on port 4321
   - Check if another service is using the port

2. **Timeout Errors**
   - Increase timeout with `--timeout` flag
   - Check server performance and network connectivity

3. **Browser Installation Issues**
   - Run `npx playwright install`
   - Clear browser cache with `npx playwright install --force`

4. **Test Failures Due to Starlight Error**
   - The Starlight head utility error is known but doesn't affect functionality
   - Focus tests on functionality rather than specific head elements
   - See "Known Issues" section above

### Debugging Failed Tests

1. **View screenshots and videos**
   ```bash
   # Screenshots are saved in test-results/
   # Videos are saved alongside screenshots
   ```

2. **Use HTML reporter**
   ```bash
   npx playwright test --reporter=html
   # Open playwright-report/index.html
   ```

3. **Run in debug mode**
   ```bash
   npx playwright test --debug
   ```

4. **Generate traces**
   ```bash
   npx playwright test --trace on
   # View traces with npx playwright show-trace
   ```

## Writing New Tests

### Test Structure
```typescript
import { test, expect } from '@playwright/test';

test.describe('Test Suite Name', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(10000);
  });

  test('test description', async ({ page }) => {
    await page.goto('/some-page');
    await expect(page.locator('h1')).toBeVisible();
  });
});
```

### Best Practices
1. Use descriptive test names
2. Group related tests in describe blocks
3. Use `beforeEach` for common setup
4. Use explicit waits instead of fixed timeouts
5. Test for user-visible behavior, not implementation details
6. Use semantic selectors over CSS selectors when possible
7. Include accessibility testing
8. Test responsive behavior

## Coverage Report

To generate a coverage report:

```bash
# Install coverage dependencies
npm install --save-dev @playwright/test-expect

# Run tests with coverage
npx playwright test --coverage
```

## Contributing

When adding new tests:

1. Follow the existing test structure and naming conventions
2. Test both happy path and edge cases
3. Include accessibility considerations
4. Test on multiple viewports when relevant
5. Update this README with new test descriptions
6. Ensure tests are deterministic and don't rely on external factors

## Future Improvements

- [ ] Fix Starlight head utility error
- [ ] Add visual regression testing
- [ ] Add performance testing
- [ ] Add internationalization testing
- [ ] Add component-level testing
- [ ] Add API endpoint testing (if applicable)