INSERT INTO Classes(name, armor_bonus, ap_bonus, inventory_bonus) VALUES ('Warrior', 5,  0.10, 0.15),('Magician',2,  0.12, 0.10),('Rogue',3, 0.08, 0.12), ('Archer',2, 0.09, 0.08);

INSERT INTO Attribute(name) VALUES ('Strength'), ('Dexterity'), ('Constitution'), ('Intelligence'), ('Health'), ('MaxHealth'), ('ActionPoints');

INSERT INTO Spell_category(name) VALUES ('fire'),('healing'),('ice'),('lightning'),('Earth'),('Water');

INSERT INTO Item_type(name) VALUES ('Sword'),('Shield'),('Bow'),('Wand'),('HealingPotion');

INSERT INTO Spell(name, power, category_id, base_ap_cost) VALUES ('Fireball',50,'fire',10),('Heal',30, 'healing',8),('Ice Spike',40, 'ice',9),('Lightning Bolt',45, 'lightning', 12);


INSERT INTO Items(name,type_id, weight, damage, base_ap_cost) VALUES ('Iron Sword','Sword',35,15,2),('Wooden Shield', 'Shield',20,5,1),('Long Bow','Bow',25,12,3),('Magic Wand','Wand',25,8,4),('Healing Potion', 'HealingPotion',1,20,2),('Excalibur', 'Sword', 50, 80, 50),('GodSlayer', 'Sword',1,200,100);
  
insert into Users (name, password) values ('Janie', 'yD2{wn''cqO`M%f.'),('Bartholomeus', 'sV8)lV/Aj'),('Minnie', 'cL1?V4HK3+&jncgn'),('Miguel', 'aG4&H)A|1xkQOgf'),('Holt', 'gQ8,USvvvjhx%ZD');


INSERT INTO Characters (user_id, name_of_character, class_id) VALUES (1, 'JaniesWarrior' , 'Warrior' ), (2, 'BartholomeusMagician'  , 'Magician'),(3,'MinniesArcher','Archer'), (1, 'JaniesWarrior2' , 'Warrior' );

INSERT INTO Character_attributes (character_id, attribute_id, score) VALUES 
(1,'Strength',15), (1,'Dexterity',8), (1,'Constitution',20), (1,'Intelligence',6), (1,'Health',100), (1,'MaxHealth',100),
(2,'Strength',2), (2,'Dexterity',15), (2,'Constitution',10), (2,'Intelligence',15), (2,'Health',110), (2,'MaxHealth',110),
(3,'Strength',12), (3,'Dexterity',12), (3,'Constitution',15), (3,'Intelligence',6), (3,'Health',80), (3,'MaxHealth',80),
(4,'Strength',8), (4,'Dexterity',4), (4,'Constitution',10), (4,'Intelligence',3), (4,'Health',50), (4,'MaxHealth',50);

INSERT INTO Character_attributes (character_id, attribute_id, score)
SELECT c.id AS character_id,'ActionPoints' AS attribute_id,
  FLOOR((dex.score + intl.score)*(1 + cl.ap_bonus))::int AS score
FROM Characters c
JOIN Classes cl ON cl.name = c.class_id
JOIN Character_attributes dex ON dex.character_id = c.id AND dex.attribute_id = 'Dexterity'
JOIN Character_attributes intl ON intl.character_id = c.id AND intl.attribute_id = 'Intelligence';

INSERT INTO Modifier_type(name, cost, damage) VALUES
  ('BasicDamage', 1.0, 1.2),    -- +20 % damage
  ('BasicApCost', 1.2, 1.0),    -- +20 % AP cost
  ('MidDamage', 1.0, 1.4),
  ('MidApCost', 1.4, 1.0);



INSERT INTO Item_modifier(item_id, attribute_id, modifier_type_id) VALUES
  (1, 'Strength', 'BasicDamage'),
  (3, 'Dexterity', 'MidDamage'),
  (4, 'Intelligence', 'MidApCost'),
  (5, 'Intelligence', 'BasicApCost');


INSERT INTO Spell_modifier(spell_id, attribute_id, modifier_type_id) VALUES
  (1, 'Intelligence', 'BasicDamage'),
  (1, 'Intelligence', 'MidApCost'),
  (2, 'Intelligence', 'BasicApCost'),
  (3, 'Intelligence', 'MidDamage'),
  (4, 'Intelligence', 'BasicApCost');


INSERT INTO Character_inventory(character_id, item_id) VALUES
  (1,1),(1,2),(1,5),(1,7),  -- JaniesWarrior: Iron Sword, Wooden Shield, healingpotion, excalibur
  (2,4),(2,5),  -- BartholomeusMagician: Magic Wand, Healing Potion
  (3,3),(3,5),  -- MinniesArcher: Long Bow, Healing Potion
  (4,1);  -- JaniesWarrior2: Iron Sword

INSERT INTO Character_grimoire(owner, spell_id) VALUES
  (1,1),(1,2),  
  (2,1),(2,3),
  (3,3),(3,4),
  (4,1),(4,2);


