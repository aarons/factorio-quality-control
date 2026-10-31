# Independent module upgrades

Add an opt-in module upgrade mode in which installed modules receive separate quality
upgrade rolls using secondary progression. A max-quality host can continue improving its
modules, including lower-quality modules inserted later. Hosts remain the queue entries;
each module slot owns its failure bonus.

Status: implementation added, with behavioral coverage through `./validate.sh`.
Real-engine verification and large-save profiling remain outstanding. The replacement
policy below incorporates the implementation discussion: ordinary upgrade-planner
replacements may start fresh; only Quality Control replacements transfer slot bonuses.

## Agreed behavior

- Add `independent` to the existing `change-modules-with-entity` startup dropdown. Preserve
  `disabled`, `enabled`, `extra-enabled`, and the default of `disabled`.
- Independent mode replaces automatic module upgrades on host upgrades. Combining it with
  Enabled or Extra Enabled is outside this feature.
- Every installed module uses its surface's secondary progression, including modules in
  primary machines. The host's own production credits are not the module's credits.
- Module rolls, failure bonuses, and target qualities are independent of the host's roll
  and quality. Each slot has its own bonus, stored in a numeric array on the host record.
- A host type whose configured upgrade limit is Common disables both host and module
  upgrades. This is the initial policy and may be revisited after player feedback.
- Other host limits apply only to the host. A host capped at Rare can contain modules that
  independently advance beyond Rare. The module's own quality path determines eligibility.
- Empty slots retain their earned failure bonuses but do not earn additional progress.
  A newly inserted module inherits the destination slot's bonus.
- Eligible secondary hosts with module slots stay in the queue indefinitely, even when the
  host and all modules are at maximum quality, or every module slot is empty.
- The batch budget counts hosts and inspected module slots. Complete a host and all its
  slots once that group has started, even if doing so exceeds the budget.

Existing force, surface, and entity exclusions remain in effect. A Common limit does not
change the existing rule that depositing primaries remain tracked to generate surface
credits; it prevents upgrade attempts in those hosts.

## Settings and player expectations

Rename the displayed setting to **Module upgrades**, retaining its internal key for saved
settings compatibility. Keep it a startup setting for this implementation.

Suggested Independent description:

> Installed modules receive their own upgrade chances from their surface's secondary
> progression, even when their machine is at maximum quality. Each module slot retains its
> accumulated failure bonus while empty, but earns no additional progress until occupied.
> Setting a machine type's upgrade limit to Common disables its module upgrades too.

Explain in the batch setting description that Independent counts each inspected module
slot, including empty slots, and finishes the current machine before stopping. Existing
module modes keep their current behavior and do not gain independent inventory polling.

## Progression and slot state

Modules are inventory items, not separate world entities. Their identity for this feature
is the host record plus inventory slot index. No module entries are added to `entity_list`,
and no persistent object is allocated for each module.

Suggested fields on an eligible host's existing tracking record:

```lua
module_last_seen_meter = current_surface_meter,
module_failure_bonuses = {0, 0, 0, 0}
```

Each numeric bonus is measured in percentage points above the configured base chance.
Zero means a new slot has the base chance. Keep the array contiguous through its highest
historically available index; its length is not the current inventory size.

The module meter bookmark is separate from the host's existing progression fields. A
primary host needs both manufacturing-hour state and a module meter bookmark; a secondary
host must not consume its meter delta before the modules can receive theirs.

### Credit calculation

On a module processing visit, read the current surface meter and advance the bookmark:

```text
credits = (surface_meter - module_last_seen_meter)
          * secondary_progression_rate / 100
module_last_seen_meter = surface_meter
```

Each occupied, eligible slot receives the full `credits` value. Do not divide it by the
number of modules, withdraw it from a finite pool, or add modules to primary counts.
Modules neither generate surface credits nor change the surface meter's divisor.

Use the existing secondary credit semantics: these are already normalized credits. Do
not divide again by the host's or module's quality multiplier. The module's current quality
is used to determine its own upgrade path and target, using `quality_selector` and its
hidden-quality rules. This avoids introducing a new module-specific progression curve.

For base chance `B`, slot bonus `F`, accumulation percentage `A`, and positive credits `C`:

```text
success probability = min(1, ((B + F) / 100) * C)
on random failure: F = F + B * (A / 100) * C
on successful module replacement: F = 0
```

Each slot gets a separate random roll. A success or failure affects only that slot. Use
the existing quality selection distribution; one successful attempt can skip quality
tiers, but there is at most one attempt per occupied eligible slot per visit. Do not add
catch-up loops for large credit deltas. Technical failures to replace an item must not
be reported as successful upgrades or erase its earned bonus.

No positive credits means no roll or bonus increase. `secondary-progression-rate = 0`
halts module progression. A surface whose meter does not advance grants no progression,
even if the host itself has another source of upgrade attempts.

### Empty slots and item changes

Advance the host's module bookmark even when all slots are empty or ineligible. Preserve
their bonuses without incrementing them. Banking means retaining earned failure bonuses,
not accumulating meter credits during empty visits.

Do not reset a slot's bonus when its module is removed, changes type or quality, or is
replaced by an identical module. Progress belongs to the slot and does not follow items
between machines. A module moved elsewhere inherits the destination slot's bonus; its
source slot retains its own bonus. This preserves progress in existing slots, not a
globally conserved balance attached to physical modules.

Polling cannot identify the exact insertion time between visits. Treat occupancy observed
at the visit as applying to that visit's credit delta. Consequently, a newly inserted
module can receive some credits from before insertion within that interval. No complete
module-transfer event tracking is required for this feature.

### Changing slot counts

Always use the current module inventory size to bound processing.

| Change | Required treatment |
| --- | --- |
| Existing slot remains available | Preserve its bonus by index. |
| A never-before-seen index becomes available | Initialize its bonus to zero. |
| Inventory shrinks | Retain trailing bonuses as dormant entries; do not process them. |
| Inventory grows into dormant indices | Resume their retained bonuses. |
| An index is unavailable or empty | No roll and no bonus increase. |

For example, bonuses `[0.2, 0.4, 0.6, 0.8]` remain stored when a four-slot host becomes a
two-slot host. Only indices 1 and 2 participate. If four slots become available later,
indices 3 and 4 resume at 0.6 and 0.8. Module reordering does not reorder the bonuses.

## Batch accounting and host retention

Keep one queue entry per host. In Independent mode, check the remaining budget before
starting a group, then finish that host and its current module inventory:

```text
checked = 0
while checked < configured_budget and current_queue_pass_has_work:
    visit next host
    checked += 1
    if host is eligible for independent module inspection:
        for each current module inventory slot:
            inspect and process slot
            checked += 1
```

Every inspected slot costs one unit, including empty, maximum-quality, or otherwise
ineligible slots. Dormant array entries cost nothing because they are not inspected.
A host with no module inventory costs one unit. Invalid queue entries consume a host
visit and are removed using the existing queue cleanup rules.

Examples with a budget of 10:

- Two hosts with four slots each use exactly 10 units.
- Three hosts with three slots each use 12 units: the third group starts at 8 and finishes.
- Starting a four-slot host at 9 uses 14 units total, then stops.

Do not begin another group after reaching or exceeding the budget. Preserve the existing
end-of-pass stop; a small queue must not wrap repeatedly within a single batch. Preserve
correct indexing when host removal or replacement uses swap-with-last removal.

The budget applies per processing callback; `batch-ticks-between-processing` continues
to control callback frequency. A host with many modded slots can produce a large final
overshoot. This is accepted under the whole-group rule, not a hard CPU-time guarantee.

Both initial registration and ongoing retention must recognize independent module hosts.
An eligible secondary host must not be rejected or removed because its own quality path
has ended or its configured non-Common limit has been reached. Do not apply this retention
rule to unrelated capped secondary entities with no module capability.

Defer queue skipping and exponential backoff. Future backoff must guarantee revisits and
account for the fact that preserving total credits does not guarantee identical outcomes
when the same credits are combined into fewer rolls.

## Host lifecycle and persistence

### Replacement and movement

Process modules against a valid host and transfer their state across an identified host
replacement. Preserve the numeric array, including dormant entries, and the meter
bookmark on same-surface replacement. Do not copy the host's own failure chance into the
module array or initialize modules from its lifetime manufacturing hours.

A practical ordering is to process host credit generation, then modules, then attempt the
host upgrade. Capture the updated module state before the old host record is removed and
attach it to the replacement record. Event callbacks may register the replacement during
this operation; avoid duplicate queue entries and duplicate module attempts. Independent
mode must bypass the legacy `update_module_quality` behavior.

Ordinary replacements, including upgrade planners, start with fresh module bonuses.
No robot mine/build pairing is required. Quality Control replacements transfer state
using the returned replacement entity, including when quality changes module capacity.
The saved array length is historical state, never the current number of available slots;
processing, batch costs, and inspection use the current module inventory exclusively.

When an existing tracked host moves to another surface, retain bonuses but rebase its
module bookmark to the destination meter. Never subtract readings from different surfaces.
A true clone gets fresh module state so cloning does not duplicate accumulated bonuses.
Arbitrary mining followed by rebuilding has no guaranteed identity relationship and is
not required to preserve bonuses. Destruction and surface deletion clean up host state.

Retain the existing guard against processing hosts marked for deconstruction or upgrade.
Suspended visits advance the module bookmark without rolls or bonus increases. Like
occupancy, suspension is sampled at visits; exact transition-time tracking is not required.

### Initialization and configuration changes

Initialize new module bookmarks to the current surface meter, never historical zero on
an existing surface. Existing saves begin with zero module bonuses, without retroactive
attempts. Preserve state through ordinary save/load; `on_load` must remain read-only.

`reinitialize_quality_control_storage` currently resets tracking records and surface
meters on configuration changes and runtime limit changes. These rebuilds may also reset
module bonuses to zero, including dormant entries. Losing accumulated module progress
during configuration changes is acceptable; no snapshot, restoration, or special
preservation mechanism is required. Mode changes, Common disabling and re-enabling, and
the explicit `quality-control-init` reset command may use the same reset behavior.

Initialize module bookmarks against the rebuilt surface meters. Never carry an old
bookmark into a newly reset meter or grant credits for an interval in which module
upgrades were disabled. This reset policy applies to configuration and explicit tracking
rebuilds; ordinary save/load and identified host replacements still preserve module state
as described above.

## Inventory operations and API constraints

Use the host's current [module inventory](https://lua-api.factorio.com/latest/classes/LuaEntity.html#get_module_inventory)
and validate each stack. Inventory references identify slots; ordinary modules have no
guaranteed persistent per-item ID. This supports the slot-owned design.

The [event catalog](https://lua-api.factorio.com/latest/events.html) provides some player
interaction events but no universal module-inventory-change event. Batched inspection is
the source of truth, including changes made by robots and scripts.

[`LuaItemStack.set_stack`](https://lua-api.factorio.com/latest/classes/LuaItemStack.html#set_stack)
accepts an item definition containing quality. Validate the intended replacement and
check success. Preserve item name and count, and any applicable item data. Avoid clearing
the stack first and assuming reinsertion succeeds. Verify effect recalculation and
inventory restrictions in Factorio 2.1, the repository's target version.

Do not assume every modded module stack has count one. Verify supported stack behavior
before deciding whether an exceptional multi-item slot is a single upgrade unit or needs
special handling; the agreed state and budget model is indexed by slot.

## Implementation touchpoints

| File or function | Work |
| --- | --- |
| `settings.lua` | Add the new dropdown value without changing existing defaults. |
| `control.lua` configuration and initialization | Wire the mode, discover eligible hosts, initialize or migrate module state, and handle rebuilds. |
| `core.get_entity_info` | Retain capped eligible module hosts; initialize module state independently of host hours and chance. |
| `core.batch_process_entities` | Account for whole groups, process module meter deltas, and separate host and module upgrade eligibility. |
| `attempt_upgrade_normal` and lifecycle handlers | Transfer module state across identified replacements and handle changing inventories. |
| `scripts/quality_selector.lua` | Reuse current selection and hidden-quality behavior for the module's quality. |
| `scripts/notifications.lua` | Distinguish module upgrades from host upgrades in alerts and summaries; expose slot progression in inspection. |
| `locale/en/locale.cfg` and `README.md` | Explain Independent, Common disabling, slot-owned bonuses, and the soft batch budget. |

Only update English localization. Non-English additions are handled separately. Module
alerts should identify the module and use the host as a location; they must not claim the
host changed quality. Avoid adding a new notification subsystem for this feature.

## Implementation decisions and remaining checks

These decisions preserve the agreed progression and budget rules:

1. Ordinary upgrade-planner replacements reset bonuses; Quality Control replacements
   preserve them using the returned entity. No inferred replacement pairing is used.
2. Suspended visits retain bonuses and discard their observed surface-meter delta.
3. A multi-item module slot upgrades as one unit, retaining count, health, and applicable
   spoilage. Preflight and replacement success checks guard bonus resets and notifications.
   Real-engine inventory restrictions, effect recalculation, and failure behavior still
   need verification; Lua test doubles do not establish engine guarantees.

## Acceptance criteria

Automated validation: 15 Lua behavioral scenarios pass, including current-inventory
resizing, dormant bonuses, replacement queue fairness, failed replacements, and legacy
modes. `./validate.sh` reports 166 passing tests and 30 expected missing non-English
translation failures. Production lint and static access checks remain unchanged.
The checklist below still requires real-engine verification and profiling.

Run repository validation only through `./validate.sh`; do not invoke luacheck or pytest
directly. The existing suite is mainly static validation, so verify runtime behavior in
Factorio and add meaningful behavioral coverage where supported.

- [ ] Disabled, Enabled, and Extra Enabled retain their previous behavior and defaults.
- [ ] Modules in primary and secondary hosts receive the same surface-meter credits for
      the same interval and rate, regardless of host quality or the host's own roll.
- [ ] Each slot accumulates its own failure bonus; a success resets only that slot.
- [ ] Empty slots retain bonuses without increasing them; refilling inherits the bonus
      without receiving credits for prior visits observed empty.
- [ ] Swapping module type or quality does not reset or transfer slot bonuses.
- [ ] Capped and empty eligible secondary hosts stay discoverable. Newly inserted modules
      are processed on a subsequent visit without requiring an insertion event.
- [ ] Common disables module upgrades. A non-Common host cap does not cap module quality.
- [ ] Module processing leaves primary counts and surface-credit generation unchanged.
- [ ] Rate zero, idle meters, separate surfaces, and surface moves obey the meter rules.
- [ ] Mixed module qualities, terminal qualities, and hidden/modded qualities are handled
      using each module's own path. Ineligible slots do not gain bonuses.
- [ ] Batch accounting includes empty and ineligible slots, finishes the last group, and
      never starts another group once the budget is exhausted. Test budgets of 1 and 10.
- [ ] Queue mutation cannot skip permanently, double-process, or loop repeatedly over a
      small queue within a callback.
- [ ] Four-to-two-to-four slot transitions preserve overlapping and dormant bonuses.
      Brand-new slot indices begin with zero bonus.
- [ ] Quality Control replacements preserve slot bonuses across capacity changes; ordinary
      replacements, including upgrade planners, start fresh.
- [ ] Save/load retains state. First adoption has no historical payout. Configuration and
      explicit tracking rebuilds may reset bonuses, including dormant entries, but must
      initialize fresh meter bookmarks and cannot create disabled-period credit windfalls.
- [ ] Module replacement preserves items and count, updates effects, and reports only
      applied upgrades. Technical failures preserve the earned bonus.
- [ ] Alerts and inspection distinguish host upgrades from module upgrades.
- [ ] `./validate.sh` passes, apart from expected missing non-English translations for
      newly added locale keys.

Profile a representative large save with Independent disabled and enabled, including
empty inventories, capped modules, many capped secondary hosts, and a host with many
modded slots. Record script time, queue revisit interval, and save-state growth. The budget
controls inspected work units; no fixed UPS improvement is promised. Retaining capped
hosts and counting modules will lengthen queue cycles, and larger intervals can change
roll outcomes even when the underlying earned credits are preserved.
