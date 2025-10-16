---
description: AI rules derived by SpecStory from the project AI interaction history
globs: *
---

## PROJECT RULES & CODING STANDARDS

*   When designing databases, implement soft deletes using a `deleted_at` column of type `:utc_datetime` and create an index on this column.
*   Capture the price and VAT rate at the time of purchase in the `order_items` table to ensure accurate historical records.
*   Ensure all tables include `inserted_at` and `updated_at` timestamps.
*   When creating a database table, every table with soft deletes should also have an index on the `deleted_at` column.
*   When designing a database related to financial transactions, capture the VAT rate at the time of purchase to ensure accurate historical records.
*   When creating a database table, use `binary_id` for primary key and foreign key columns.
*   When creating a database table, create unique index for columns with unique values.
*   When creating a database table, name indexes for foreign keys according to `[:column_name]` convention.

## TECH STACK

*   Ecto (with Elixir) for database interactions and migrations.
*   daisyUI (with Phoenix 1.8) for UI components.

## PROJECT DOCUMENTATION & CONTEXT SYSTEM

## WORKFLOW & RELEASE RULES

*   When building CRUD interfaces, create full CRUD for all tables.
*   When building an application with multiple sections, create a main menu to access all sections.

## DEBUGGING

*   When using Phoenix 1.8 with daisyUI, utilize `<.form>` from `Phoenix.Component` and existing `.input` components directly, instead of creating custom `<.simple_form>` components.