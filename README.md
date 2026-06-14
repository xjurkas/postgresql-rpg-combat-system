# PostgreSQL RPG Combat System

A database-driven role-playing game combat system implemented in **PostgreSQL** and **PL/pgSQL**.

The project models users, playable characters, classes, attributes, inventories, items, spells, modifiers, combat sessions, rounds, combat events, dropped loot, action points, damage, healing, death processing, and character progression.

It was created as a university database assignment at the Faculty of Informatics and Information Technologies, Slovak University of Technology in Bratislava.

## Features

- Users with one or more playable characters
- Character classes with armor, action-point, and inventory bonuses
- Character attributes such as:
  - Strength
  - Dexterity
  - Constitution
  - Intelligence
  - Health
  - Maximum health
  - Action points
- Items, item categories, spells, and spell categories
- Character inventories and grimoires
- Attribute-based item and spell modifiers
- Turn-based combat sessions and rounds
- Dynamic action-point consumption
- D20-style attack rolls
- Armor Class calculations
- Weapon and spell attacks
- Healing items and healing spells
- Inventory weight limits
- Dropping and looting items
- Death processing and automatic loot drops
- Character removal from combat after death
- Class-dependent level-up logic
- Health regeneration before re-entering combat
- Combat statistics through database views
- Manual integration tests covering valid and invalid scenarios

## Repository structure

```text
.
├── modely/
│   ├── ermodel.pdf
│   ├── logickymodel.pdf
│   └── fyzickymodel.pdf
├── setup/
│   ├── create_alltables.sql
│   ├── insertUdajov.sql
│   ├── ViewsAndIndexes.sql
│   ├── funkcie.sql
│   └── cleanup.sql
├── dokumentacia.pdf
├── testing.sql
└── README.md
```

| File | Description |
| --- | --- |
| `setup/create_alltables.sql` | Creates the complete relational schema |
| `setup/insertUdajov.sql` | Inserts demonstration classes, users, characters, items, spells, attributes, and modifiers |
| `setup/ViewsAndIndexes.sql` | Creates analytical views and performance indexes |
| `setup/funkcie.sql` | Creates the PL/pgSQL combat functions |
| `setup/cleanup.sql` | Removes all stored data and resets generated identities |
| `testing.sql` | Contains 13 manually executed integration-test scenarios |
| `modely/ermodel.pdf` | Entity-relationship model |
| `modely/logickymodel.pdf` | Logical database model |
| `modely/fyzickymodel.pdf` | Physical database model |
| `dokumentacia.pdf` | Detailed Slovak-language implementation documentation |

## Technology

- PostgreSQL
- PL/pgSQL
- SQL views
- B-tree indexes
- Transactions
- Referential integrity through primary and foreign keys
- Identity columns
- Aggregate and filtered aggregate queries

PostgreSQL 14 or newer is recommended.

## Database model

The implementation contains 19 tables.

### Users and characters

| Table | Purpose |
| --- | --- |
| `Users` | Stores application users |
| `Classes` | Stores character classes and their bonuses |
| `Characters` | Stores playable characters owned by users |
| `Attribute` | Dictionary of character attributes |
| `Character_attributes` | Stores attribute values for each character |

A user can own multiple characters. Every character belongs to a class and has a set of attribute values.

### Items and inventory

| Table | Purpose |
| --- | --- |
| `Item_type` | Dictionary of item categories |
| `Items` | Stores item properties, weight, damage, and base AP cost |
| `Character_inventory` | Assigns items to characters |
| `Modifier_type` | Defines cost and damage multipliers |
| `Item_modifier` | Connects items, attributes, and modifier types |

### Spells and grimoires

| Table | Purpose |
| --- | --- |
| `Spell_category` | Dictionary of spell categories |
| `Spell` | Stores spell power, category, and base AP cost |
| `Character_grimoire` | Assigns known spells to characters |
| `Spell_modifier` | Connects spells, attributes, and modifier types |

### Combat

| Table | Purpose |
| --- | --- |
| `Combat_log` | Represents a combat session |
| `Player_combat_log` | Records characters joining and leaving combat |
| `Rounds` | Stores individual rounds within a combat |
| `Round_events` | Stores attacks, spell casts, item use, loot, joins, and departures |
| `Dropped_goods` | Stores items and spells available on the battlefield |

## Derived character statistics

The `v_character_full_stats` view derives important combat values from stored attributes and class bonuses.

### Armor Class

```text
Armor Class = 10 + Dexterity / 2 + class armor bonus
```

### Maximum action points

```text
Maximum AP = round((Dexterity + Intelligence) × (1 + class AP bonus))
```

### Maximum inventory weight

```text
Maximum inventory weight =
50 + Strength / 2 × (1 + class inventory bonus)
```

The view also provides:

- current and maximum health,
- base character attributes,
- current inventory weight,
- maximum inventory weight.

## Combat workflow

A typical combat session follows this process:

```text
Start combat
    ↓
Create first round
    ↓
Characters enter combat
    ↓
Use items or cast spells
    ↓
Consume action points
    ↓
Apply damage or healing
    ↓
Log the event
    ↓
Process death and dropped loot when necessary
    ↓
Reset the round or end combat
```

## PL/pgSQL functions

The project contains 18 PL/pgSQL routines. Although several names use the `sp_` prefix, they are implemented using PostgreSQL `FUNCTION` declarations.

### Combat lifecycle

| Function | Purpose |
| --- | --- |
| `sp_start_combat()` | Creates a new combat and its first round |
| `sp_enter_combat(...)` | Adds a character to combat and applies out-of-combat health regeneration |
| `sp_log_leave_combat(...)` | Records a character leaving combat |
| `sp_reset_round(...)` | Closes the current round and starts the next one |
| `sp_end_combat(...)` | Closes all active rounds in a combat |

### Attacks and resource calculations

| Function | Purpose |
| --- | --- |
| `f_calculate_attack_roll(...)` | Calculates a D20 attack roll with a Strength or Intelligence bonus |
| `f_effective_item_cost(...)` | Calculates the effective AP cost of an item |
| `f_effective_item_damage(...)` | Calculates item damage using attributes and modifiers |
| `f_effective_spell_cost(...)` | Calculates the effective AP cost of a spell |
| `f_effective_spell_damage(...)` | Calculates spell damage using attributes and modifiers |
| `f_get_round_status(...)` | Returns maximum, spent, and remaining AP for characters in a round |
| `sp_use_item(...)` | Uses an item for an attack or healing |
| `sp_cast_spell(...)` | Casts a spell, optionally with a wand |

### Loot, death, and progression

| Function | Purpose |
| --- | --- |
| `sp_drop_item(...)` | Drops an owned item onto the battlefield |
| `sp_loot_item(...)` | Picks up an available item when the inventory limit permits it |
| `sp_drop_loot_on_death(...)` | Moves all inventory and grimoire contents to the battlefield |
| `sp_process_death(...)` | Processes death, loot, combat departure, and the killer's level-up |
| `sp_level_up(...)` | Increases attributes according to the winner's character class |

## Views

The project defines six views.

| View | Description |
| --- | --- |
| `v_character_full_stats` | Complete derived character statistics |
| `v_combat_state` | Remaining AP for every active character in an open round |
| `v_most_damage` | Characters ordered by total successful damage |
| `v_strongest_characters` | Characters ordered by damage and remaining health |
| `v_combat_damage` | Total damage dealt in each combat |
| `v_spell_statistics` | Spell usage, hit, miss, total-damage, and average-damage statistics |

Example:

```sql
SELECT *
FROM v_character_full_stats
ORDER BY character_id;
```

```sql
SELECT *
FROM v_spell_statistics;
```

## Indexes

Five indexes optimize frequently used combat queries.

| Index | Indexed columns | Purpose |
| --- | --- | --- |
| `idx_round_events_round_id` | `round_events(round_id)` | Finds events from a specific round |
| `idx_round_events_player2_success` | `round_events(player2_id, success)` | Supports successful-hit analysis by target |
| `idx_character_attributes_char_attr` | `character_attributes(character_id, attribute_id)` | Retrieves a specific character attribute |
| `idx_player_combat_log_combat_id` | `player_combat_log(combat_id)` | Retrieves participants of a combat |
| `idx_rounds_combat_id` | `rounds(combat_id)` | Retrieves all rounds belonging to a combat |

## Requirements

- PostgreSQL 14 or newer
- `psql`, pgAdmin, DBeaver, DataGrip, or another PostgreSQL-compatible client
- Permission to create tables, views, indexes, and PL/pgSQL functions

No application server or external programming language is required.

## Installation

Create an empty PostgreSQL database.

Example:

```sql
CREATE DATABASE rpg_combat;
```

Connect to the database and execute the scripts in this exact order:

1. `setup/create_alltables.sql`
2. `setup/insertUdajov.sql`
3. `setup/ViewsAndIndexes.sql`
4. `setup/funkcie.sql`

### Using psql

```bash
createdb rpg_combat

psql -d rpg_combat -f setup/create_alltables.sql
psql -d rpg_combat -f setup/insertUdajov.sql
psql -d rpg_combat -f setup/ViewsAndIndexes.sql
psql -d rpg_combat -f setup/funkcie.sql
```

Specify a PostgreSQL user when necessary:

```bash
psql -U postgres -d rpg_combat -f setup/create_alltables.sql
```

## Demonstration data

The seed script inserts:

- four character classes,
- five users,
- four characters,
- seven character-attribute types,
- seven items,
- four spells,
- item and spell modifiers,
- initial inventories,
- initial grimoires.

Examples include:

- `JaniesWarrior`
- `BartholomeusMagician`
- `MinniesArcher`
- `Iron Sword`
- `Healing Potion`
- `Excalibur`
- `Fireball`
- `Heal`
- `Ice Spike`
- `Lightning Bolt`

## Usage examples

### Start a combat

```sql
SELECT *
FROM sp_start_combat();
```

### Add characters to combat

```sql
SELECT sp_enter_combat(1, 1);
SELECT sp_enter_combat(1, 2);
```

### Attack using an item

```sql
SELECT sp_use_item(
    1, -- combat ID
    1, -- round ID
    1, -- attacker character ID
    2, -- target character ID
    1  -- item ID
);
```

### Cast a spell

```sql
SELECT sp_cast_spell(
    1,    -- combat ID
    1,    -- round ID
    2,    -- caster character ID
    1,    -- target character ID
    1,    -- spell ID
    NULL  -- optional wand ID
);
```

### Inspect the current combat state

```sql
SELECT *
FROM v_combat_state;
```

### Reset the round

```sql
SELECT sp_reset_round(1);
```

### End the combat

```sql
SELECT sp_end_combat(1);
```

## Testing

The `testing.sql` file contains 13 integration scenarios.

They cover:

1. combat creation and participant entry,
2. weapon attacks,
3. spell attacks,
4. healing with a potion,
5. dropping and looting an item,
6. rejection of an action with insufficient AP,
7. death processing, dropped loot, and level-up,
8. round reset and AP restoration,
9. rejection of loot exceeding inventory capacity,
10. rejection of attacks against characters outside combat,
11. rejection of duplicate combat entry,
12. health regeneration after time outside combat,
13. combat termination.

The file also queries all six views.

> [!IMPORTANT]
> Execute `testing.sql` section by section rather than as one script. Several tests depend on the state created by previous tests, and attack success contains a randomized D20 roll.

Recommended process:

1. Execute the setup scripts.
2. Open `testing.sql`.
3. Run one transaction block at a time.
4. Inspect the verification queries beneath the test.
5. Use `ROLLBACK` where the test instructions require it.
6. Reset the database before repeating the complete test sequence.

## Resetting the database data

To remove all data and reset generated identities:

```bash
psql -d rpg_combat -f setup/cleanup.sql
```

The cleanup script uses `TRUNCATE ... RESTART IDENTITY CASCADE`.

It removes data but does not drop the database objects.

To rebuild the sample environment after cleanup:

```bash
psql -d rpg_combat -f setup/insertUdajov.sql
```

## Models and documentation

The repository includes:

- an ER model,
- a logical model,
- a physical model,
- detailed implementation documentation,
- explanations of views, indexes, functions, setup, and tests.

See:

- [`modely/ermodel.pdf`](modely/ermodel.pdf)
- [`modely/logickymodel.pdf`](modely/logickymodel.pdf)
- [`modely/fyzickymodel.pdf`](modely/fyzickymodel.pdf)
- [`dokumentacia.pdf`](dokumentacia.pdf)

## Known limitations

- User passwords are stored as plaintext demonstration values.
- The project is a database implementation and does not include a graphical or web client.
- Event types and several dictionary values are stored as unrestricted text instead of PostgreSQL enums or reference tables.
- Some rules are enforced in PL/pgSQL rather than with database constraints.
- Randomized attack rolls make exact test results nondeterministic.
- `testing.sql` is stateful and is not designed to run automatically from beginning to end.
- The setup scripts do not use `IF NOT EXISTS`, so they should be executed on a clean schema.
- `ViewsAndIndexes.sql` creates indexes without first dropping existing indexes.
- The project does not include automated unit testing or a CI pipeline.
- The SQL scripts were prepared specifically for PostgreSQL and are not portable to MySQL or SQLite.
- Demonstration credentials and data must not be used in a production system.

## Possible improvements

- Hash passwords using a secure application-level authentication layer.
- Add check constraints or enums for event types and categories.
- Add uniqueness constraints where duplicate inventory or grimoire records are not intended.
- Convert the manual test script into repeatable pgTAP tests.
- Add migrations with Flyway or Liquibase.
- Add Docker Compose for a reproducible PostgreSQL environment.
- Add schema-qualified object names.
- Add transactional setup and teardown scripts.
- Add explicit combat lifecycle states.
- Add concurrency protection for simultaneous loot and combat actions.
- Add audit metadata and role-based database permissions.
- Benchmark the indexes using `EXPLAIN ANALYZE`.

## Author

**Dominik Jurkas**

Faculty of Informatics and Information Technologies  
Slovak University of Technology in Bratislava
