CREATE OR REPLACE VIEW v_character_full_stats AS
SELECT c.id AS character_id,
  -- základné staty
  MAX(ca.score) FILTER (WHERE ca.attribute_id = 'Strength') AS str,
  MAX(ca.score) FILTER (WHERE ca.attribute_id = 'Dexterity') AS dex,
  MAX(ca.score) FILTER (WHERE ca.attribute_id = 'Constitution') AS con,
  MAX(ca.score) FILTER (WHERE ca.attribute_id = 'Intelligence') AS int,
  -- uložené maximum HP
  MAX(ca.score) FILTER (WHERE ca.attribute_id = 'MaxHealth') AS max_hp,
  -- aktuálny HP priamo zo stavu health (už bez subquery na damage)
  MAX(ca.score) FILTER (WHERE ca.attribute_id = 'Health') AS current_hp,
  -- Armor Class = 10 + (Dexterity/2) + class armor_bonus
  ROUND(10 + (MAX(ca.score) FILTER (WHERE ca.attribute_id = 'Dexterity') / 2.0) + cl.armor_bonus)::int AS armor_class,
  -- max_action_points = ROUND((dex + int) * (1 + ap_bonus))
  ROUND(((MAX(ca.score) FILTER (WHERE ca.attribute_id = 'Dexterity') + MAX(ca.score) FILTER (WHERE ca.attribute_id = 'Intelligence')) * (1 + cl.ap_bonus)))::int AS max_action_points,
  -- max_inventory_weight = 50 + (strength/2) * (1 + inventory_bonus)
  (50 + (MAX(ca.score) FILTER (WHERE ca.attribute_id = 'Strength') / 2.0) * (1 + cl.inventory_bonus))::int AS max_inventory_weight,
  -- current_inventory_weight = súčet váh všetkých položiek v inventári
  COALESCE((SELECT SUM(i.weight) FROM Character_inventory ci 
  JOIN Items i ON i.id = ci.item_id WHERE ci.character_id = c.id), 0)::int AS current_inventory_weight
  
FROM Characters c
JOIN Character_attributes ca ON ca.character_id = c.id
JOIN Classes cl ON cl.name = c.class_id
GROUP BY c.id, cl.ap_bonus, cl.inventory_bonus, cl.armor_bonus;










CREATE OR REPLACE VIEW v_most_damage AS
SELECT c.id AS character_id, c.name_of_character AS character_name, COALESCE(SUM(re.damage_dealt),0) AS total_damage
FROM characters c
LEFT JOIN round_events re ON re.player1_id  = c.id AND re.event_type  = 'attack' AND re.success     = TRUE AND re.damage_dealt > 0
GROUP BY c.id, c.name_of_character
ORDER BY total_damage DESC;








CREATE OR REPLACE VIEW v_strongest_characters AS
SELECT c.id AS character_id, c.name_of_character AS character_name, COALESCE(d.total_damage, 0) AS total_damage, s.current_hp AS current_hp
FROM Characters c
-- pripojíme súčet damage pre každú postavu
LEFT JOIN (
  SELECT player1_id AS character_id, SUM(damage_dealt) AS total_damage FROM Round_events 
  WHERE event_type = 'attack' AND success = TRUE AND damage_dealt > 0
  GROUP BY player1_id
) d ON d.character_id = c.id
-- pripojíme aktuálne HP z view
JOIN v_character_full_stats s ON s.character_id = c.id
-- zoradíme podľa damage, potom podľa zostávajúceho HP
ORDER BY d.total_damage DESC NULLS LAST, s.current_hp DESC NULLS LAST;




CREATE OR REPLACE VIEW v_combat_damage AS
SELECT r.combat_id, COALESCE(SUM(re.damage_dealt), 0) AS total_damage FROM Rounds r
LEFT JOIN Round_events re ON re.round_id   = r.id AND re.event_type = 'attack' AND re.success = TRUE AND re.damage_dealt > 0
GROUP BY r.combat_id
ORDER BY r.combat_id;



CREATE OR REPLACE VIEW v_spell_statistics AS
SELECT s.id AS spell_id, s.name AS spell_name,
  -- Koľkokrát bolo kúzlo použité
  COUNT(re.id) FILTER (WHERE re.spell_used = s.id) AS times_cast,
  -- Koľko zásahov bolo úspešných
  COUNT(re.id) FILTER (WHERE re.spell_used = s.id AND re.success = TRUE) AS hits,
  -- Koľko zásahov zlyhalo
  COUNT(re.id) FILTER (WHERE re.spell_used = s.id AND re.success = FALSE) AS misses,
  -- Celkové poškodenie (len úspešné použitia)
  COALESCE(SUM(re.damage_dealt) FILTER (WHERE re.spell_used = s.id AND re.success = TRUE), 0) AS total_damage,
  -- Priemerné poškodenie na úspešný zásah
  COALESCE(ROUND(AVG(re.damage_dealt) FILTER (WHERE re.spell_used = s.id AND re.success = TRUE))::int, 0) AS avg_damage
FROM Spell s
LEFT JOIN Round_events re ON re.spell_used = s.id
GROUP BY s.id, s.name
ORDER BY total_damage DESC;




CREATE OR REPLACE VIEW v_combat_state AS
WITH active_combat AS (
  -- Získame všetky aktívne boje (boje, ktoré majú aspoň jedno otvorené kolo)
  SELECT c.id AS combat_id FROM Combat_log c WHERE EXISTS (
     -- Skontrolujeme, či existuje aspoň jedno otvorené kolo v boji
   SELECT 1 FROM Rounds r WHERE r.combat_id = c.id AND r."end" IS NULL)),
all_rounds AS (
  -- Získame všetky kolá v rámci aktívnych bojoch, pričom vyberieme len neukončené kolá
  SELECT r.id AS round_id, r.combat_id FROM Rounds r JOIN active_combat ac ON r.combat_id = ac.combat_id WHERE r."end" IS NULL)  -- Zabezpečujeme, že vyberieme len kolá, ktoré ešte nie sú ukončené

SELECT ar.round_id, pc.player_id AS character_id, fs.max_action_points AS max_ap,
  -- spočítame, koľko AP už bolo minuté v tomto kole
  COALESCE(SUM(re.ap_cost), 0) AS spent_ap,
  -- ostávajúce AP
  fs.max_action_points - COALESCE(SUM(re.ap_cost), 0) AS ap_left
FROM all_rounds ar
  -- Zobrazíme všetkých hráčov pripojených k boju, bez ohľadu na kolo
  JOIN Player_combat_log pc ON pc.combat_id = ar.combat_id AND pc.event_type = 'JOIN' AND NOT EXISTS (
     -- Vylúčime hráčov, ktorí opustili boj
     SELECT 1 FROM Player_combat_log pl WHERE pl.combat_id = pc.combat_id AND pl.player_id = pc.player_id AND pl.event_type = 'LEFT')
  -- Pripojíme štatistiky hráčov
  JOIN v_character_full_stats fs ON fs.character_id = pc.player_id
  -- Pripojíme všetky udalosti v kole
  LEFT JOIN Round_events re ON re.round_id = ar.round_id AND re.player1_id = pc.player_id
GROUP BY ar.round_id,pc.player_id,fs.max_action_points;

-- Indexes
-- 1) Rýchle vyhľadanie eventov podľa kola
CREATE INDEX idx_round_events_round_id
  ON round_events(round_id);

-- 2) Rýchly súčet úspešného damage podľa cieľa
CREATE INDEX idx_round_events_player2_success
  ON round_events(player2_id, success);

-- 3) Priamy prístup k hodnote konkrétneho atribútu postavy
CREATE INDEX idx_character_attributes_char_attr
  ON character_attributes(character_id, attribute_id);

-- 4) Rýchle vyhľadanie účastníkov podľa combatu
CREATE INDEX idx_player_combat_log_combat_id
  ON player_combat_log(combat_id);

-- 5) Rýchly prístup na všetky kolá v rámci daneho boja
CREATE INDEX idx_rounds_combat_id
  ON rounds(combat_id);

