# Shopify Custom App Setup Guide

This guide explains how to configure a Shopify Custom App for product publishing from shopdata.

## Prerequisites

- Shopify store with admin access
- Custom App development enabled on the store

## Steps

### 1. Enable Custom App Development

1. Go to **Shopify Admin** > **Settings** > **Apps and sales channels**
2. Click **Develop apps**
3. If prompted, click **Allow custom app development**

### 2. Create a Custom App

1. Click **Create an app**
2. Enter an app name (e.g., "shopdata-integration")
3. Click **Create app**

### 3. Configure Admin API Scopes

1. In your new app, click **Configure Admin API scopes**
2. Enable the following scopes:
   - `write_products` — create and update products
   - `read_products` — read product data
   - `write_publications` — publish products to sales channels
   - `read_publications` — read publication data
3. Click **Save**

### 4. Install the App

1. Click **Install app**
2. Confirm by clicking **Install**

### 5. Copy the Access Token

1. After installation, click **Reveal token once** under **Admin API access token**
2. Copy the token immediately (it is only shown once)

### 6. Configure Environment Variables

Add the following to your `.env` file:

```
SHOPIFY_SHOP_DOMAIN=your-store.myshopify.com
SHOPIFY_ACCESS_TOKEN=shpat_xxxxxxxxxxxxxxxxxxxx
```

Note: `SHOPIFY_SHOP_DOMAIN` must be the `.myshopify.com` domain (not a custom domain).

## API Notes

- Authentication uses the `X-Shopify-Access-Token` header, which remains valid in 2026.
- This app uses GraphQL API version **2025-01**.
- For new installs, API version **2026-01** is recommended when available.

## Scopes Reference

| Scope | Purpose |
|-------|---------|
| `write_products` | Create/update product listings |
| `read_products` | Read existing product data |
| `write_publications` | Publish products to Online Store channel |
| `read_publications` | Check which channels products are published to |

## Troubleshooting

- **401 Unauthorized**: Check that `SHOPIFY_ACCESS_TOKEN` is correct and the app is installed.
- **403 Forbidden**: Verify the required API scopes are enabled and the app is reinstalled after scope changes.
- **404 Not Found**: Check that `SHOPIFY_SHOP_DOMAIN` uses the `.myshopify.com` format.
