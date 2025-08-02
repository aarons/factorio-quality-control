# factorio-quality-control

This mod changes the quality of machines after a certain amount of processing.

Use ./package.sh to package it up into a zip file, for testing changes locally. You will need to copy that zip to your local factorio mods folder.


## Todo

Consolidate Machine Data Management

- Create a single get_or_create_machine_data() function to centralize data
 initialization
- Simplify cleanup logic by removing redundant type checking
- Merge initialization patterns that are currently duplicated

 1. Consolidate Machine Data Management

  - Create a single ensure_machine_data(unit_number) function to reduce duplication
  - The pattern if not storage.machine_data[unit_number] then
  storage.machine_data[unit_number] = {} end appears multiple times

  2. Simplify Entity Selection Logic

  - The randomly_select_entities() function could use Lua's simpler math.random(1,
  #entities) approach instead of Fisher-Yates for small selections
  - Reduce complexity in apply_ratio_based_quality_changes() by extracting the entity
  processing logic

  3. Streamline Notification System

  - Combine the alert creation and console message loops in
  handle_quality_change_notifications()
  - The entity type name mapping could be moved to a module-level constant

  4. Minor Code Structure Improvements

  - Combine related variable declarations
  - Reduce some function parameter passing by restructuring local scope
