# factorio-quality-control

This mod changes the quality of machines after a certain amount of processing.

Use ./package.sh to package it up into a zip file, for testing changes locally. You will need to copy that zip to your local factorio mods folder.


## Todo

Consolidate Machine Data Management

- The pattern if not storage.machine_data[unit_number] then storage.machine_data[unit_number] = {} end appears multiple times
- Create a single function to centralize data initialization
- Simplify cleanup logic by removing redundant type checking
- Merge initialization patterns that are currently duplicated

A clear function name would be good to use. Here are some proposals:
- get_or_create_machine_data()
- ensure_machine_data()
- get_machine()
- get_machine_info() <- minor preference for this

Notes:
- "_data" is a bit redundant, it's all data
- "get_" is pretty clear, but traditionally used to represent read-only operations, but I'm ok with it initializing entities that don't exist yet
- "ensure_" is ok, although "ensure_machine" isn't really enough semantic information to understand what it's doing
- "get_machine_info()" I like this, although have troulbe articulating why
- I'm open to other iterations on this if we can find something clear, concise, and user friendly (for future engineers)




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
