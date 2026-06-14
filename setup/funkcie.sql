CREATE OR REPLACE FUNCTION sp_start_combat()
RETURNS TABLE (combat_id bigint, first_round bigint)
LANGUAGE plpgsql AS $$
DECLARE
  v_combat_log_id bigint;
BEGIN
  -- 1) Vytvori novy record v combatlog table a returne id
  INSERT INTO Combat_log DEFAULT VALUES
  RETURNING id INTO v_combat_log_id;

  -- 2) Vytvori novy round s korektnym round order
  INSERT INTO Rounds (combat_id, start, round_order) VALUES (v_combat_log_id, now(), (SELECT COALESCE(MAX(r.round_order), 0) + 1 FROM Rounds r WHERE r.combat_id = v_combat_log_id))
  RETURNING id INTO first_round;

  RETURN NEXT;
END;
$$;

--#########################################################################################################################################
CREATE OR REPLACE FUNCTION sp_enter_combat(
  p_combat_id bigint,
  p_character_id bigint
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
  v_last_leave timestamp;
  v_minutes_out integer;
  v_const integer;
  v_regen integer;
  v_max_hp integer;
  v_round_id bigint;
BEGIN
  -- 1) Kontrola ci uz nieje v boji
  IF EXISTS (
    SELECT 1 FROM Player_combat_log WHERE player_id = p_character_id AND combat_id = p_combat_id AND event_type = 'JOIN')
	THEN RAISE EXCEPTION 'Player % is already in combat %', p_character_id, p_combat_id;
  END IF;
  
  -- 2) regenerácia HP pred vstupom
  SELECT MAX(event_time) INTO v_last_leave FROM Player_combat_log WHERE player_id = p_character_id AND event_type = 'LEFT';
  IF v_last_leave IS NOT NULL THEN v_minutes_out := FLOOR(EXTRACT(EPOCH FROM (now() - v_last_leave)) / 60);
    SELECT score INTO v_const FROM Character_attributes WHERE character_id = p_character_id AND attribute_id = 'Constitution';
    SELECT score INTO v_max_hp FROM Character_attributes WHERE character_id = p_character_id AND attribute_id = 'MaxHealth';
    v_regen := FLOOR(v_minutes_out * (v_const::numeric / 5));
    UPDATE Character_attributes SET score = LEAST(v_max_hp, score + v_regen) WHERE character_id = p_character_id AND attribute_id = 'Health';
  END IF;

  -- 3) JOIN do Player_combat_log
  INSERT INTO Player_combat_log(player_id, combat_id, event_type, event_time) VALUES (p_character_id, p_combat_id, 'JOIN', now());

  -- 4) nájdi bežiace kolo alebo vytvor nové
  SELECT id INTO v_round_id FROM Rounds WHERE combat_id = p_combat_id AND "end" IS NULL
   ORDER BY start DESC
   LIMIT 1;

  IF v_round_id IS NULL THEN
    INSERT INTO Rounds(combat_id, start) VALUES (p_combat_id, now()) RETURNING id INTO v_round_id;
  END IF;

  -- 6) JOIN event do Round_events
  INSERT INTO Round_events(round_id, player1_id, event_type, success) VALUES (v_round_id, p_character_id, 'join',TRUE);
END;
$$;





--#########################################################################################################################################
CREATE OR REPLACE FUNCTION sp_log_leave_combat(
  p_combat_id    bigint,
  p_character_id bigint
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
  v_round_id bigint;
BEGIN
  -- 1) Záznam odchodu do Player_combat_log
  INSERT INTO Player_combat_log(player_id, combat_id, event_type) VALUES (p_character_id, p_combat_id, 'LEFT');

  -- 2) Nájdeme bežiace kolo
  SELECT id INTO v_round_id FROM Rounds WHERE combat_id = p_combat_id AND "end" IS NULL
   ORDER BY start DESC
   LIMIT 1;

  -- 3) Zápis odchodu do Round_events so success = TRUE
  IF v_round_id IS NOT NULL THEN
    INSERT INTO Round_events(round_id, player1_id, event_type, success) VALUES (v_round_id, p_character_id, 'left', TRUE);
  END IF;
END;
$$;









--#########################################################################################################################################
CREATE OR REPLACE FUNCTION sp_drop_loot_on_death(
  p_combat_id    bigint,
  p_character_id bigint
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
  rec_item RECORD;
  rec_spell RECORD;
BEGIN
  -- 1. Presun všetkých položiek z inventára na bojisko
  FOR rec_item IN SELECT item_id FROM Character_inventory WHERE character_id = p_character_id
  LOOP
    INSERT INTO Dropped_goods(combat_id, item_id, available, time_dropped) VALUES (p_combat_id, rec_item.item_id, TRUE, now());
  END LOOP;

  DELETE FROM Character_inventory WHERE character_id = p_character_id;
  
  -- 2. Presun všetkých kúziel z grimoára na bojisko
  FOR rec_spell IN SELECT spell_id FROM Character_grimoire WHERE owner = p_character_id
  LOOP
    INSERT INTO Dropped_goods(combat_id, spell_id, available, time_dropped) VALUES (p_combat_id, rec_spell.spell_id, TRUE, now());
  END LOOP;

  DELETE FROM Character_grimoire WHERE owner = p_character_id;
END;
$$;








--#########################################################################################################################################
CREATE OR REPLACE FUNCTION f_calculate_attack_roll(
  p_attacker_id bigint,
  p_method text    -- 'weapon' alebo 'spell'
) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_roll  integer;
  v_bonus numeric;
BEGIN
  -- 1) Hádzanie kockou d20 (1–20)
  v_roll := FLOOR(RANDOM() * 20) + 1;

  -- 2) Bonus podľa metódy
  IF p_method = 'weapon' THEN SELECT MAX(score)/2.0 INTO v_bonus FROM Character_attributes WHERE character_id = p_attacker_id AND attribute_id = 'Strength';
  ELSE
    SELECT MAX(score)/2.0 INTO v_bonus FROM Character_attributes WHERE character_id = p_attacker_id AND attribute_id = 'Intelligence';
  END IF;

  -- 3) Výsledok (zaokrúhlené na celé číslo)
  RETURN ROUND(v_roll + v_bonus);
END;
$$;


--#########################################################################################################################################
CREATE OR REPLACE FUNCTION f_effective_spell_cost(
  p_spell_id   BIGINT,
  p_caster_id  BIGINT
) RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
  v_base_cost     INT;
  v_attr_score    INT;
  v_cost_mod      FLOAT := 1;
  rec             RECORD;
BEGIN
  -- Načíta základnú cenu
  SELECT base_ap_cost INTO v_base_cost FROM Spell WHERE id = p_spell_id;

  -- Pre každý modifier (zo Spell_modifier) aplikuje multiplikátor cost
  FOR rec IN SELECT sm.attribute_id, mt.cost FROM Spell_modifier sm JOIN Modifier_type mt ON mt.name = sm.modifier_type_id WHERE sm.spell_id = p_spell_id
  LOOP
    -- skóre atribútu
    SELECT score INTO v_attr_score FROM Character_attributes WHERE character_id = p_caster_id AND attribute_id = rec.attribute_id;
	
    -- upraví modifikátor: (1 − attr/100) × cost
    v_cost_mod := v_cost_mod * (1 - (v_attr_score::FLOAT / 100)) * rec.cost;
  END LOOP;

  -- Celková cena = base_cost × všetky modifikátory
  RETURN ROUND(v_base_cost * v_cost_mod);
END;
$$;





--#########################################################################################################################################
CREATE OR REPLACE FUNCTION f_effective_item_damage(
  p_item_id  bigint,
  p_user_id  bigint
) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_base_damage numeric;
  v_attr_id varchar;
  v_attr_score numeric;
  v_mod_damage numeric;
BEGIN
  -- 1) načíta base damage a príslušný modifier
  SELECT i.damage, im.attribute_id, mt.damage INTO v_base_damage, v_attr_id, v_mod_damage
  FROM Items i 
  JOIN Item_modifier im   ON im.item_id = i.id
  JOIN Modifier_type mt   ON mt.name = im.modifier_type_id AND i.id = p_item_id
  LIMIT 1;
  
  -- 2) načíta hodnotu atribútu postavy
  SELECT score::numeric INTO v_attr_score FROM Character_attributes WHERE character_id = p_user_id AND attribute_id = v_attr_id;
  
  -- 3) vypočíta a vráti
  RETURN ROUND((v_base_damage + v_attr_score/2.0) * v_mod_damage);
END;
$$;










--########################################################################################################################################
CREATE OR REPLACE FUNCTION f_effective_item_cost(
  p_item_id     BIGINT,
  p_character_id BIGINT
) RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
  v_base_cost INT;
  v_attr_score INT;
  v_cost_mod FLOAT := 1;
  rec RECORD;
BEGIN
  -- Načíta základnú cenu
  SELECT base_ap_cost INTO v_base_cost FROM Items WHERE id = p_item_id;

  -- Pre každý modifier (zo Item_modifier) aplikuje multiplikátor cost
  FOR rec IN SELECT im.attribute_id, mt.cost FROM Item_modifier im
      JOIN Modifier_type mt ON mt.name = im.modifier_type_id WHERE im.item_id = p_item_id
  LOOP
    -- skóre atribútu
    SELECT score INTO v_attr_score FROM Character_attributes WHERE character_id = p_character_id AND attribute_id = rec.attribute_id;
	
    -- upraví modifikátor: (1 − attr/100) × cost
    v_cost_mod := v_cost_mod * (1 - (v_attr_score::FLOAT / 100)) * rec.cost;
  END LOOP;
  
  -- Celková cena = base_cost × všetky modifikátory
  RETURN ROUND(v_base_cost * v_cost_mod);
END;
$$;












--########################################################################################################################################
CREATE OR REPLACE FUNCTION f_effective_spell_damage(
  p_spell_id bigint,
  p_caster_id bigint
) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_base_damage numeric;
  v_attr_id varchar;
  v_attr_score numeric;
  v_mod_damage numeric;
BEGIN
  -- 1) Načíta base damage kúzla a prvý modifikátor
  SELECT s.power, sm.attribute_id, mt.damage INTO v_base_damage, v_attr_id, v_mod_damage
  FROM Spell s JOIN Spell_modifier sm ON sm.spell_id = s.id
  JOIN Modifier_type mt ON mt.name = sm.modifier_type_id WHERE s.id = p_spell_id
  LIMIT 1;

  -- 2) Načíta príslušný atribút postavy
  SELECT score::numeric INTO v_attr_score FROM Character_attributes WHERE character_id = p_caster_id AND attribute_id = v_attr_id;

  -- 3) Vypočíta a vráti zaokrúhlené
  RETURN ROUND((v_base_damage + v_attr_score/2.0) * v_mod_damage);
END;
$$;







--########################################################################################################################################
CREATE OR REPLACE FUNCTION sp_process_death(
  p_combat_id bigint,
  p_dead_id bigint,
  p_killer_id bigint
) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
  -- 1) presun loot z obete
  PERFORM sp_drop_loot_on_death(p_combat_id, p_dead_id);

  -- 2) forced leave bez dropu
  PERFORM sp_log_leave_combat(p_combat_id, p_dead_id);

  -- 3) level up pre toho, kto zabil
  PERFORM sp_level_up(p_killer_id);
END;
$$;







--########################################################################################################################################
CREATE OR REPLACE FUNCTION sp_level_up(
  p_winner_id bigint
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
  v_class varchar;
  v_max_hp integer;
  v_main1 varchar;
  v_main2 varchar;
BEGIN
  -- 1) Zisti class víťaza
  SELECT class_id INTO v_class FROM Characters WHERE id = p_winner_id;

  -- 2) Definuj hlavné atribúty podľa class
  CASE v_class
    WHEN 'Warrior' THEN v_main1 := 'Strength'; v_main2 := 'Constitution';
    WHEN 'Magician' THEN v_main1 := 'Intelligence'; v_main2 := 'Dexterity';
    WHEN 'Rogue' THEN v_main1 := 'Dexterity'; v_main2 := 'Strength';
    WHEN 'Archer' THEN v_main1 := 'Dexterity'; v_main2 := 'Strength';
    ELSE RAISE EXCEPTION 'Unknown class: %', v_class;
  END CASE;

  -- 3) +2 pre hlavné, cap ≤100
  UPDATE Character_attributes SET score = LEAST(100, score + 2) WHERE character_id = p_winner_id AND attribute_id IN (v_main1, v_main2);

  -- 4) +1 pre ostatné 4 atribúty, cap ≤100
  UPDATE Character_attributes SET score = LEAST(100, score + 1) WHERE character_id = p_winner_id AND attribute_id IN('Strength','Dexterity','Constitution','Intelligence') AND attribute_id NOT IN (v_main1, v_main2);

  -- 5) +5 Health, cap na MaxHealth (MaxHealth musíš udržiavať ≤500 inde)
  UPDATE Character_attributes SET score = LEAST(500, score + 5) WHERE character_id  = p_winner_id AND attribute_id  = 'MaxHealth';

    UPDATE Character_attributes SET score = LEAST(500, score + 5) WHERE character_id  = p_winner_id AND attribute_id  = 'Health';
END;
$$;








--########################################################################################################################################
CREATE OR REPLACE FUNCTION sp_reset_round(
  p_combat_id bigint
) RETURNS bigint  -- vráti ID nového kola
LANGUAGE plpgsql AS $$
DECLARE
  v_old_r bigint;
  v_new_r bigint;
  v_round_order bigint;
  r record;
BEGIN
  -- a) Ukončiť prebiehajúce kolo (nastaviť end timestamp)
  SELECT id INTO v_old_r FROM Rounds WHERE combat_id = p_combat_id AND "end" IS NULL
   LIMIT 1;

  IF v_old_r IS NOT NULL THEN UPDATE Rounds SET "end" = now() WHERE id = v_old_r;

    -- b) Zalogovať ukončenie kola
    INSERT INTO Round_events(round_id, player1_id, event_type,success, time) SELECT v_old_r, player_id, 'end_round', true, now() FROM Player_combat_log
     WHERE combat_id = p_combat_id AND event_type = 'JOIN';
  END IF;

  -- c) Vytvoriť nové kolo so správnym round_order
  -- Získame najvyšší round_order pre daný combat a priradíme +1
  SELECT COALESCE(MAX(round_order), 0) + 1 INTO v_round_order FROM Rounds WHERE combat_id = p_combat_id;

  -- Vytvárame nové kolo
  INSERT INTO Rounds(combat_id, start, round_order) VALUES (p_combat_id, now(), v_round_order)
  RETURNING id INTO v_new_r;

  -- d) JOIN všetkých aktívnych hráčov do nového kola (implicitne im zresetuje AP)
  FOR r IN
    SELECT player_id FROM Player_combat_log WHERE combat_id = p_combat_id AND event_type = 'JOIN'
  LOOP
    INSERT INTO Round_events(round_id, player1_id, event_type, success, time) VALUES (v_new_r, r.player_id, 'join_round', true, now());
  END LOOP;

  RETURN v_new_r;
END;
$$;



















--########################################################################################################################################
CREATE OR REPLACE FUNCTION sp_end_combat(
  p_combat_id bigint
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
  r RECORD;
  first_player_id bigint; -- Premenná pre ID prvého hráča
BEGIN
  -- 1) Pre každé otvorené kolo nastavíme end = now() a zapíšeme event
  FOR r IN
    SELECT id FROM Rounds WHERE combat_id = p_combat_id AND "end" IS NULL
  LOOP
    -- Ukončíme kolo, nastavíme end timestamp
    UPDATE Rounds SET "end" = now() WHERE id = r.id;

    -- Získame ID prvého hráča v boji
    SELECT player_id INTO first_player_id FROM Player_combat_log WHERE combat_id = p_combat_id
    LIMIT 1;

    -- Záznam do Round_events, že kolo bolo ukončené
    -- Nastavíme player1_id na prvého hráča
    INSERT INTO Round_events(round_id, player1_id, event_type,success, time) VALUES (r.id, first_player_id, 'end_round', true, now());
  END LOOP;

  -- 2) Opustí všetkých aktívnych hráčov zo zápasu (zápis do Player_combat_log)
  FOR r IN
    SELECT player_id FROM Player_combat_log WHERE combat_id = p_combat_id AND event_type = 'JOIN'
  LOOP
    -- Zápis do Player_combat_log o odchode hráča zo zápasu
    INSERT INTO Player_combat_log(player_id, combat_id, event_type, event_time) VALUES (r.player_id, p_combat_id, 'LEFT', now());
  END LOOP;

END;
$$;





--########################################################################################################################################
CREATE OR REPLACE FUNCTION f_get_round_status(
  p_round_id bigint
) RETURNS TABLE(
  character_id bigint,
  max_ap int,
  spent_ap int,
  ap_left int
) AS $$
BEGIN
  RETURN QUERY
    SELECT
      pc.player_id AS character_id,
      fs.max_action_points AS max_ap,
      COALESCE(SUM(re.ap_cost),0)::int AS spent_ap,
      (fs.max_action_points - COALESCE(SUM(re.ap_cost),0))::int AS ap_left
    FROM Player_combat_log pc JOIN v_character_full_stats fs ON fs.character_id = pc.player_id
    LEFT JOIN Round_events re ON re.round_id   = p_round_id AND re.player1_id = pc.player_id
    WHERE pc.combat_id = (SELECT combat_id FROM Rounds WHERE id = p_round_id) AND pc.event_type = 'JOIN'
    GROUP BY pc.player_id, fs.max_action_points;
END;
$$ LANGUAGE plpgsql;












--########################################################################################################################################
CREATE OR REPLACE FUNCTION sp_drop_item(
  p_round_id bigint,   -- id kola
  p_character_id bigint,   -- kto dropuje
  p_item_id bigint    -- čo dropuje
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
  v_combat_id bigint;
BEGIN
  -- 1) Zisti combat_id z daného kola
  SELECT combat_id INTO v_combat_id FROM Rounds WHERE id = p_round_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Round % not found', p_round_id;
  END IF;

  -- 2) Over ownership
  IF NOT EXISTS (
    SELECT 1 FROM Character_inventory WHERE character_id = p_character_id AND item_id= p_item_id
  ) THEN RAISE EXCEPTION 'Character % does not own item %', p_character_id, p_item_id;
  END IF;

  -- 3) Odstránenie z batohu
  DELETE FROM Character_inventory WHERE character_id = p_character_id AND item_id= p_item_id;

  -- 4) Vloženie do boja ako dropped_goods
  INSERT INTO Dropped_goods(combat_id,item_id,available,time_dropped) VALUES (v_combat_id,p_item_id,TRUE,now());

  -- 5) Zápis eventu do Round_events
  INSERT INTO Round_events(round_id, player1_id, player2_id, event_type, picked_item, ap_cost, damage_dealt, success) VALUES ( p_round_id, p_character_id, NULL, 'dropped_item', p_item_id, 0,0, TRUE);
END;
$$;







--########################################################################################################################################
CREATE OR REPLACE FUNCTION sp_loot_item(
  p_combat_id bigint,
  p_round_id bigint,
  p_character_id  bigint,
  p_item_id bigint
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
  v_item_weight integer;
  v_max_weight integer;
  v_current_weight integer;
  v_rows integer;
BEGIN
  -- 1) Skontroluj, že tohle item_id je naozaj droppnuté a stále dostupné
  SELECT 1 INTO v_rows FROM Dropped_goods WHERE combat_id = p_combat_id AND item_id= p_item_id AND available= TRUE;

  IF v_rows IS NULL THEN RAISE EXCEPTION 'Dropped item % is not available in combat %', p_item_id, p_combat_id;
  END IF;

  -- 2) Získaj váhu predmetu
  SELECT weight INTO v_item_weight FROM Items WHERE id = p_item_id;

  -- 3) Získaj maximálnu váhu, ktorú môže postava niesť
	SELECT (50 + (MAX(ca.score) FILTER (WHERE ca.attribute_id = 'Strength') / 2.0) * (1 + cl.inventory_bonus))::int
	INTO v_max_weight FROM Characters c
	JOIN Character_attributes ca ON c.id = ca.character_id
	JOIN Classes cl ON c.class_id = cl.name WHERE c.id = p_character_id
	GROUP BY c.id, cl.inventory_bonus;



  -- 4) Získaj aktuálnu váhu inventára
  SELECT COALESCE(SUM(i.weight), 0)
    INTO v_current_weight FROM Character_inventory ci
    JOIN Items i ON i.id = ci.item_id WHERE ci.character_id = p_character_id;

  -- 5) Skontroluj, či predmet neprekračuje maximálnu váhu inventára
  IF v_item_weight + v_current_weight > v_max_weight THEN RAISE EXCEPTION 'Character % cannot carry item % because it exceeds the maximum weight limit', p_character_id, p_item_id;
  END IF;

  -- 6) Odober ho z boja (označ ako unavailable)
  UPDATE Dropped_goods SET available = FALSE WHERE combat_id = p_combat_id AND item_id    = p_item_id;

  -- 7) Pridaj ho do inventára charaktera
  INSERT INTO Character_inventory(character_id, item_id) VALUES (p_character_id, p_item_id);

  -- 8) Záznam do Round_events
  INSERT INTO Round_events(round_id,player1_id,player2_id,event_type,picked_item,ap_cost,damage_dealt,success) VALUES (p_round_id, p_character_id,NULL,'picked_item',p_item_id,0,0,TRUE);
END;
$$;






--########################################################################################################################################
CREATE OR REPLACE FUNCTION sp_cast_spell(
  p_combat_id bigint,
  p_round_id bigint,
  p_caster_id bigint,
  p_target_id bigint,
  p_spell_id bigint,
  p_wand_id bigint DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
  v_cost integer;
  v_roll integer;
  v_ac_base integer;
  v_shield_prot integer;
  v_spell_dmg integer;
  v_wand_dmg integer := 0;
  v_raw_dmg integer;
  v_final_dmg integer;
  v_success boolean;
  v_category varchar;
  v_max_hp integer;
  v_current_hp integer;
  v_target_in_combat boolean;
BEGIN

	IF NOT EXISTS (
     SELECT 1 FROM Character_grimoire WHERE owner = p_caster_id AND spell_id = p_spell_id) 
	 THEN RAISE EXCEPTION 'Character % does not own spell %', p_caster_id, p_spell_id;
   END IF;

   
  -- 1) AP-check
  SELECT ap_left INTO v_current_hp FROM f_get_round_status(p_round_id) WHERE character_id = p_caster_id;
  v_cost := ROUND(f_effective_spell_cost(p_spell_id, p_caster_id)) + COALESCE(ROUND(f_effective_item_cost(p_wand_id, p_caster_id)), 0);
  IF v_current_hp < v_cost THEN RAISE EXCEPTION 'Not enough AP (% < %)', v_current_hp, v_cost;
  END IF;

  -- 2) Check if the target is in the combat session
  SELECT EXISTS (
    SELECT 1 FROM Player_combat_log WHERE combat_id = p_combat_id AND player_id = p_target_id) INTO v_target_in_combat;

  IF NOT v_target_in_combat THEN RAISE EXCEPTION 'Target character % is not part of the combat in round %', p_target_id, p_round_id;
  END IF;

  -- 3) Attack roll = d20 + INT/2
  v_roll := f_calculate_attack_roll(p_caster_id, 'spell');

  -- 4) Base Armor Class
  SELECT armor_class INTO v_ac_base FROM v_character_full_stats WHERE character_id = p_target_id;

  -- 5) Hit check
  IF v_roll >= v_ac_base THEN
    v_success   := TRUE;
    v_spell_dmg := f_effective_spell_damage(p_spell_id, p_caster_id);
    IF p_wand_id IS NOT NULL THEN
      v_wand_dmg := f_effective_item_damage(p_wand_id, p_caster_id);
    END IF;
    v_raw_dmg := v_spell_dmg + v_wand_dmg;
  ELSE
    v_success := FALSE;
    v_raw_dmg := 0;
  END IF;

  -- 6) Zisti kategóriu kúzla
  SELECT category_id INTO v_category FROM Spell WHERE id = p_spell_id;

  -- 7) Armor/shield reduction (len pri damage)
  IF v_success AND v_category <> 'healing' THEN
    SELECT COALESCE(SUM(i.damage),0) INTO v_shield_prot FROM Character_inventory ci
      JOIN Items i ON i.id = ci.item_id WHERE ci.character_id = p_target_id AND i.type_id IN ('Shield','Armor');
    v_final_dmg := GREATEST(0, v_raw_dmg - v_shield_prot);
  ELSE
    v_final_dmg := v_raw_dmg;
  END IF;

  -- 8) Aplikácia poškodenia alebo liečenia
  IF v_success AND v_category = 'healing' THEN
    SELECT score INTO v_max_hp FROM Character_attributes WHERE character_id = p_target_id AND attribute_id = 'MaxHealth';
    UPDATE Character_attributes SET score = LEAST(v_max_hp, score + v_final_dmg) WHERE character_id = p_target_id AND attribute_id = 'Health';
  ELSIF v_success THEN
    UPDATE Character_attributes SET score = GREATEST(0, score - v_final_dmg) WHERE character_id = p_target_id AND attribute_id = 'Health';
  END IF;

  -- 9) Log udalosti
  INSERT INTO Round_events(round_id, player1_id, player2_id,event_type, spell_used, item_used,ap_cost, damage_dealt, success)VALUES (
    p_round_id, p_caster_id, p_target_id,'attack', p_spell_id, p_wand_id,v_cost, v_final_dmg, v_success);

    --Ak cieľ zomrel, spracuj smrť
    SELECT score INTO v_current_hp FROM Character_attributes WHERE character_id = p_target_id AND attribute_id = 'Health';
    IF v_current_hp = 0 THEN PERFORM sp_process_death(p_combat_id, p_target_id, p_caster_id );
    END IF;
END;
$$;








--########################################################################################################################################
CREATE OR REPLACE FUNCTION sp_use_item(
  p_combat_id bigint,
  p_round_id bigint,
  p_user_id bigint,
  p_target_id bigint,
  p_item_id bigint
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
  v_current_ap integer;
  v_ap_cost integer;
  v_roll integer;
  v_ac_base integer;
  v_shield_prot integer;
  v_raw_val integer;
  v_final_val integer;
  v_success boolean;
  v_max_hp integer;
  v_item_type varchar;
  v_new_hp integer;
  v_target_in_combat boolean;
BEGIN
  -- 1) Overenie vlastníctva
  PERFORM 1 FROM Character_inventory WHERE character_id= p_user_id AND item_id= p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Character % does not own item %', p_user_id, p_item_id;
  END IF;

  -- 2) AP-check
  SELECT ap_left INTO v_current_ap FROM f_get_round_status(p_round_id) WHERE character_id = p_user_id;
  v_ap_cost := ROUND(f_effective_item_cost(p_item_id, p_user_id));
  IF v_current_ap < v_ap_cost THEN RAISE EXCEPTION 'Not enough AP (% < %)', v_current_ap, v_ap_cost;
  END IF;
  -- 3) Je target v combat session?
  SELECT EXISTS (
    SELECT 1 FROM Player_combat_log WHERE combat_id = p_combat_id AND player_id = p_target_id) INTO v_target_in_combat;

  IF NOT v_target_in_combat THEN RAISE EXCEPTION 'Target character % is not part of the combat in round %', p_target_id, p_round_id;
  END IF;
  -- 4) Typ itemu
  SELECT type_id INTO v_item_type FROM Items WHERE id = p_item_id;

  -- 5) Self-heal?
  IF v_item_type = 'HealingPotion' THEN
    v_success := TRUE;
    v_raw_val  := f_effective_item_damage(p_item_id, p_user_id);
  ELSE
    -- 6) Útok: roll + STR/2
    v_roll := f_calculate_attack_roll(p_user_id, 'weapon');
    SELECT armor_class INTO v_ac_base FROM v_character_full_stats WHERE character_id = p_target_id;
    IF v_roll >= v_ac_base THEN
      v_success := TRUE;
      v_raw_val  := f_effective_item_damage(p_item_id, p_user_id);
    ELSE
      v_success := FALSE;
      v_raw_val  := 0;
    END IF;
  END IF;

  -- 7) Armor/shield
  IF v_success AND v_item_type <> 'HealingPotion' THEN
    SELECT COALESCE(SUM(i.damage),0) INTO v_shield_prot
      FROM Character_inventory ci JOIN Items i ON i.id = ci.item_id WHERE ci.character_id = p_target_id AND i.type_id IN ('Shield','Armor');
    v_final_val := GREATEST(0, v_raw_val - v_shield_prot);
  ELSE
    v_final_val := v_raw_val;
  END IF;

  -- 8) Aplikácia účinku
  IF v_success AND v_item_type = 'HealingPotion' THEN
    -- heal
    SELECT score INTO v_max_hp FROM Character_attributes WHERE character_id = p_target_id AND attribute_id = 'MaxHealth';
    UPDATE Character_attributes SET score = LEAST(v_max_hp, score + v_final_val) WHERE character_id = p_target_id AND attribute_id = 'Health';

    -- 10) odstránenie spotrebovanej potion
    DELETE FROM Character_inventory WHERE character_id = p_user_id AND item_id = p_item_id;
  ELSIF v_success THEN UPDATE Character_attributes SET score = GREATEST(0, score - v_final_val) WHERE character_id = p_target_id AND attribute_id = 'Health';
  END IF;

  -- 11) Log udalosti
  INSERT INTO Round_events(round_id, player1_id, player2_id,event_type, item_used,ap_cost, damage_dealt, success) 
  VALUES (p_round_id, p_user_id, p_target_id,'attack',p_item_id,v_ap_cost,  v_final_val, v_success);

  -- 12) AK charakter po utoku umrel
  IF v_success AND v_item_type <> 'HealingPotion' THEN
    SELECT score INTO v_new_hp FROM Character_attributes WHERE character_id = p_target_id AND attribute_id = 'Health';
    IF v_new_hp = 0 THEN
      -- forced leave + drop loot + log LEFT
      PERFORM sp_process_death(p_combat_id, p_target_id, p_user_id);
    END IF;
  END IF;

END;
$$;



