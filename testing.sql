-- Test #1: založenie prveho combatu vytvorenie prvého kola a pridanie hračov 1 a 2
BEGIN;
	select sp_start_combat();
	select sp_enter_combat(1,1);
	select sp_enter_combat(1,2);
COMMIT;

SELECT * FROM Combat_log;  --ocakavany výstup je combat s id = 1
SELECT * FROM Rounds WHERE combat_id = 1; --ocakavany výstup je Round s id = 1
SELECT * FROM Player_combat_log WHERE combat_id = 1;  --log joinu pre hraca 1 a 2

-- #############################################################################################################################################
-- Test #2: Hráč 1 zaútočí na hráča 2 pomocou Iron Sword (item_id = 1) v kole 1
BEGIN;
	SELECT sp_use_item(
	  1::bigint,   -- p_combat_id
	  1::bigint,   -- p_round_id
	  1::bigint,   -- p_user_id (attacker)
	  2::bigint,   -- p_target_id
	  1::bigint    -- p_item_id (Iron Sword)
	);
COMMIT;

-- Skontrolovanie či attack bol uspesny, ak nie opakujte test. Po pripade ak by bol viac krat neuspesny, tak treba pouzit toto: delete from round_events where id>3; po tomto znova opakujte test az kym nebude uspesny
select * from round_events order by time desc;
-- Skontrolovanie ci hracovi 1 sa odpocitali AP
select * from v_combat_state;
-- Skontrolovanie zivota hraca 2
select * from v_character_full_stats where character_id=2;



-- #############################################################################################################################################
-- Test #3: Magician (character_id = 2) zaútočí na hráča 1 pomocou Fireball (spell_id = 1)
BEGIN;
	SELECT sp_cast_spell(
	  1::bigint,   -- p_combat_id
	  1::bigint,   -- p_round_id
	  2::bigint,   -- p_caster_id (Magician)
	  1::bigint,   -- p_target_id  (JaniesWarrior)
	  1::bigint    -- p_spell_id   (Fireball)
	);
COMMIT;

-- Skontrolovanie či spell attack bol uspesny, ak nie tak opakujte az kym nebude uspesny, tak nebude dostatok AP, tak treba dat rollback a vymazat posledne attacky z round_events aby test bol uspesny
select * from round_events order by time DESC;
-- skontrolovanie zivota charactera 1
select * from v_character_full_stats where character_id=1;


-- #############################################################################################################################################
-- Test #4: Hráč 1 sa vylieči použitím Healing Potion (item_id = 5) na seba v kole 1
BEGIN;
	SELECT sp_use_item(
	  1::bigint,   -- p_combat_id
	  1::bigint,   -- p_round_id
	  1::bigint,   -- p_user_id (JaniesWarrior)
	  1::bigint,   -- p_target_id (self-heal)
	  5::bigint    -- p_item_id (Healing Potion)
	);
COMMIT;

-- Overenie zápisu v Round_events
select * from round_events order by time DESC;

-- Overenie aktuálneho Health u hráča 1 po healovaní
select * from v_character_full_stats where character_id=1;


-- overenie ci sa mu vymazal potion z inventara (item s id 5 tam nema byt)
select * from character_inventory where character_id=1;


-- #############################################################################################################################################
-- Test #5: Player 2 vyhodí Healing Potion (item_id = 5) na bojisko, Player 1 ho následne zoberie
BEGIN;
	SELECT sp_drop_item(
	  1::bigint,   -- p_round_id
	  2::bigint,   -- p_character_id (BartholomeusMagician)
	  5::bigint    -- p_item_id (Healing Potion)
	);
	SELECT sp_loot_item(
	  1::bigint,   -- p_combat_id
	  1::bigint,   -- roundid
	  1::bigint,   -- p_character_id (JaniesWarrior)
	  5::bigint    -- p_item_id (Healing Potion)
	);
COMMIT;

rollback;
-- Dropped_goods: položka už nie je available
SELECT
  id,
  combat_id,
  item_id,
  available,
  time_dropped
FROM Dropped_goods WHERE combat_id = 1 AND item_id = 5;

-- Character_inventory: postava 1 teraz vlastní Healing Potion
SELECT * FROM Character_inventory
WHERE character_id = 1 AND item_id = 5;

-- Character_inventory: postava 2 už nemá Healing Potion
SELECT * FROM Character_inventory
WHERE character_id = 2 AND item_id      = 5;



-- #############################################################################################################################################
-- Test #6: Player 1 sa pokúsi použiť item na ktorý nemá dostatok AP
BEGIN;
	SELECT sp_use_item(
	  1::bigint,
	  1::bigint,   -- p_round_id
	  1::bigint,   -- p_user_id (attacker)
	  2::bigint,   -- p_target_id
	  7::bigint    -- p_item_id (Excalibur)
	);
COMMIT;

ROLLBACK; -- po teste treba zapnut rollback

SELECT * FROM round_events WHERE round_id=1;   --ukazanie ze sa ani zaznam nespravil kedže je to zakazane použit item na ktorý nemá dostatok AP


-- #############################################################################################################################################
-- Test #7: Magician (player 2) zabije Warriora (player 1) Fireballom
BEGIN;
	SELECT sp_cast_spell(
	  1::bigint,   -- combat_id
	  1::bigint,   -- p_round_id
	  2::bigint,   -- p_caster_id (Magician)
	  1::bigint,   -- p_target_id  (JaniesWarrior)
	  1::bigint    -- p_spell_id   (Fireball)
	);
COMMIT;
select * from round_events order by time desc;  --skontrolovat ci bol útok uspesny, ak nie tak treba test zopakovat. Ak vypise ze uz ma nedostatok ap tak treba vymazat posledny zaznam z round_events
-- ROLLBACK; Ak napise test error ze nedostatok ap
-- DELETE FROM round_events WHERE id>6;

--Ak bol útok uspešný, tak tu sa to skontroluje

-- Health Warriora (player 1) by malo byť 0
SELECT score AS health FROM Character_attributes WHERE character_id = 1 AND attribute_id = 'Health';

-- Warrior (player 1) má v Player_combat_log najnovší event_type = 'LEFT'
SELECT event_type, event_time FROM Player_combat_log WHERE player_id  = 1 ORDER BY event_time DESC LIMIT 1;

-- Inventár Warriora je prázdny
SELECT * FROM Character_inventory WHERE character_id = 1;

-- Grimoár Warriora je prázdny
SELECT * FROM Character_grimoire WHERE owner = 1;

-- Všetky položky alebo kúzla Warriora sú v Dropped_goods pre combat_id = 1 a available = TRUE
SELECT * FROM Dropped_goods WHERE combat_id = 1 AND (item_id IS NOT NULL OR spell_id IS NOT NULL) AND available = TRUE;

-- Magician (player 2) sa vyleveloval: hlavné atribúty +2, ostatné +1, MaxHealth +5
SELECT attribute_id, score FROM Character_attributes WHERE character_id = 2 AND attribute_id IN ('Strength','Dexterity','Constitution','Intelligence','MaxHealth') ORDER BY attribute_id;



-- #############################################################################################################################################
-- Test #8: Reset kola – nové kolo vytvorené, AP pre hráča 2 resetované
select * from v_combat_state; -- skonrolovanie kolko AP left ma hrač 2

BEGIN;
	SELECT sp_reset_round(1);
COMMIT;

-- V Rounds by mal byť nový záznam (id = 2) pre combat_id = 1
SELECT * FROM Rounds WHERE combat_id = 1;

-- hrac 2 by mal mat plne AP left
select * from v_combat_state;



-- #############################################################################################################################################
-- Test #9: Insert tazkeho itemu do dropped_goods, pokus hrača 2 o zobranie itemu ktorý je moc tažký pre jeho inventár
BEGIN;
	INSERT INTO Dropped_goods (combat_id, item_id, available, time_dropped) VALUES (1, 6, TRUE, now());
	SELECT sp_loot_item(
	  1::bigint,   -- p_combat_id
	  1::bigint,   -- round id
	  2::bigint,   -- p_character_id (JaniesWarrior)
	  6::bigint    -- p_item_id (excalibur)
	);
COMMIT;

ROLLBACK; -- po teste treba spustit rollback

select * from character_inventory where character_id=2; -- kontrola či hráč 2 má daný item s id=7 v inventár (nemal by mat)

select * from v_character_full_stats;

-- #############################################################################################################################################
-- Test #10: Pokus hráča 2 zaútočiť na hráča 3 ktorý nieje v aktívnom combate 
BEGIN;
	SELECT sp_cast_spell(
	  1::bigint,   -- p_combat_id
	  2::bigint,   -- p_round_id
	  2::bigint,   -- p_caster_id (Magician)
	  3::bigint,   -- p_target_id  (JaniesWarrior)
	  1::bigint    -- p_spell_id   (Fireball)
	);
COMMIT;

ROLLBACK; -- po teste treba spustit rollback
SELECT * FROM round_events;  -- kontrola v round_events, nemal by tam byt zaznam kedže hrač 2 sa pokusil porušit pravidlá a systém mu to nedovolil



-- #############################################################################################################################################
-- Test #11: Pokus hráča 2 sa pridat do aktívneho kola, ale hráč 2 už je v aktívnom kole
BEGIN;
	select sp_enter_combat(1,2);
COMMIT;

ROLLBACK; -- po teste treba spustit rollback
SELECT * FROM round_events;  -- kontrola v round_events, nemal by tam byt zaznam kedže hrač 2 sa pokusil porušit pravidlá a systém mu to nedovolil



-- #############################################################################################################################################
-- Test #12: Vytvorenie nového combatu, pridanie hráča 1 do combatu, kontrola či sa zregeneroval kým nebol v boji
BEGIN;
 SELECT sp_start_combat();
 SELECT sp_enter_combat(2,1);
COMMIT;

SELECT score AS current_hp
FROM Character_attributes
WHERE character_id = 1
  AND attribute_id = 'Health';



-- #############################################################################################################################################
-- Test #13: Ukončenie combatu, premiestnenie hráča 2 preč z aktívneho combatu
BEGIN;
   SELECT sp_end_combat(2); 
COMMIT;

SELECT * FROM Rounds;  -- end timestamp by mal byt pre round 2
SELECT * FROM round_events WHERE round_id = 2;  -- mal by tam byt zaznam o ukončení
SELECT * FROM player_combat_log order by event_time desc;  -- hrač 2 by tam mal mat LEFT



-- #############################################################################################################################################
-- Test Views:
select * from v_combat_state;
select * from v_most_damage;
select * from v_spell_statistics;
select * from v_strongest_characters;
select * from v_combat_damage;
select * from v_character_full_stats;
