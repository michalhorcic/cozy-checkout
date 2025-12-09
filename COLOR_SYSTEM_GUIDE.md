# Color System Guide

## Overview
This document describes the centralized color system for the Cozy Checkout application.

## Color Palette

### Primary (#3a3a3a - Dark Gray)
**Usage:** Text, headers, primary actions, navigation elements
- `primary-50` through `primary-900`: Light to dark shades
- Main color: `primary-500` (#3a3a3a)
- Use for: Body text, headings, primary buttons, icons

### Secondary (#c8d5c4 - Sage Green)
**Usage:** Backgrounds, section accents, borders
- `secondary-50` through `secondary-900`: Light to dark shades
- Main color: `secondary-500` (#c8d5c4)
- Use for: Page backgrounds, card backgrounds, subtle borders

### Tertiary (#b8826f - Dusty Rose)
**Usage:** Active states, hover effects, info states
- `tertiary-50` through `tertiary-900`: Light to dark shades
- Main color: `tertiary-500` (#b8826f)
- Use for: Active items, selected states, info badges, interactive hover states

### Accent (#c85a3a - Terracotta)
**Usage:** Warnings, delete actions, error states, critical actions
- `accent-50` through `accent-900`: Light to dark shades
- Main color: `accent-500` (#c85a3a)
- Use for: Delete buttons, error messages, warnings, destructive actions

## Semantic Colors

### Success (Green-based)
- `success-light`: Light success background
- `success`: Main success color (oklch(70% 0.14 145))
- `success-dark`: Dark success text
- Use for: Completed states, paid status, confirmation messages

### Warning (Yellow-orange)
- `warning-light`: Light warning background
- `warning`: Main warning color (oklch(75% 0.15 70))
- `warning-dark`: Dark warning text
- Use for: Pending states, caution messages, partial payments

### Error (Terracotta-based)
- `error-light`: Light error background
- `error`: Main error color (oklch(58% 0.15 30))
- `error-dark`: Dark error text
- Use for: Error messages, failed operations, validation errors

### Info (Dusty rose-based)
- `info-light`: Light info background
- `info`: Main info color (oklch(64% 0.08 30))
- `info-dark`: Dark info text
- Use for: Informational messages, hints, tips

## Usage Examples

### Backgrounds
```html
<!-- Main page background -->
<div class="bg-secondary-50">

<!-- Card background -->
<div class="bg-white">

<!-- Section accent background -->
<div class="bg-secondary-100">
```

### Text
```html
<!-- Primary heading -->
<h1 class="text-primary-500">

<!-- Secondary text -->
<p class="text-primary-400">

<!-- Subtle text -->
<span class="text-primary-300">
```

### Buttons
```html
<!-- Primary action -->
<button class="bg-primary-500 hover:bg-primary-600 text-white">

<!-- Secondary action -->
<button class="bg-secondary-200 hover:bg-secondary-300 text-primary-500">

<!-- Active/Selected -->
<button class="bg-tertiary-500 hover:bg-tertiary-600 text-white">

<!-- Destructive action -->
<button class="bg-accent-500 hover:bg-accent-600 text-white">
```

### Status Badges
```html
<!-- Success/Completed -->
<span class="bg-success-light text-success-dark">

<!-- Warning/Pending -->
<span class="bg-warning-light text-warning-dark">

<!-- Error/Failed -->
<span class="bg-error-light text-error-dark">

<!-- Info/Active -->
<span class="bg-tertiary-100 text-tertiary-800">
```

### Borders
```html
<!-- Subtle border -->
<div class="border-secondary-200">

<!-- Active border -->
<div class="border-tertiary-500">

<!-- Error border -->
<div class="border-accent-500">
```

## Status Color Mapping

### Order Status
- **Open**: `bg-tertiary-100 text-tertiary-800`
- **Paid**: `bg-success-light text-success-dark`
- **Partially Paid**: `bg-warning-light text-warning-dark`
- **Cancelled**: `bg-accent-100 text-accent-800`

### Booking Status
- **Upcoming**: `bg-tertiary-100 text-tertiary-800`
- **Active**: `bg-success-light text-success-dark`
- **Completed**: `bg-secondary-200 text-primary-500`
- **Cancelled**: `bg-accent-100 text-accent-800`

### Invoice Status
- **Draft**: `bg-secondary-200 text-primary-500`
- **Personal**: `bg-warning-light text-warning-dark`
- **Generated**: `bg-tertiary-100 text-tertiary-800`
- **Sent**: `bg-info-light text-info-dark`
- **Paid**: `bg-success-light text-success-dark`

## Implementation Files

### Core Files
- `assets/css/app.css` - Color definitions and daisyUI theme
- `lib/cozy_checkout_web/components/core_components.ex` - Reusable components

### Updated Files
- ✅ `lib/cozy_checkout_web/live/pos_live/guest_selection.html.heex`
- ✅ `lib/cozy_checkout_web/live/pos_live/order_selection.html.heex` (partial)
- 🔲 `lib/cozy_checkout_web/live/pos_live/order_management.html.heex`
- 🔲 `lib/cozy_checkout_web/live/main_menu_live.ex`
- 🔲 `lib/cozy_checkout_web/live/dashboard_live.ex`
- 🔲 `lib/cozy_checkout_web/live/economy_live/index.html.heex`
- 🔲 `lib/cozy_checkout_web/live/booking_live/*`
- 🔲 `lib/cozy_checkout_web/live/pricelist_live/*`
- 🔲 Other admin pages

## How to Change Colors in the Future

To change the entire color scheme, you only need to modify the color definitions in `assets/css/app.css`:

1. Update the `@theme` section with your new color values
2. The changes will automatically apply throughout the application
3. No need to update individual component files

Example:
```css
@theme {
  /* Change primary color from #3a3a3a to #2c2c2c */
  --color-primary-500: oklch(25% 0 0);  /* New darker gray */
  
  /* Change secondary from #c8d5c4 to a blue tone */
  --color-secondary-500: oklch(82% 0.04 240);  /* Light blue */
}
```

## Benefits of This System

1. **Centralized Control**: Change colors in one place
2. **Semantic Naming**: Colors have meaningful names (primary, secondary, etc.)
3. **Consistency**: Same colors used throughout the app
4. **Maintainability**: Easy to update and modify
5. **Accessibility**: Carefully chosen contrast ratios
6. **Dark Mode Ready**: Structure supports theme switching if needed in future
