CREATE TABLE Users
(
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	name varchar(255) NOT NULL,
	password varchar(255) NOT NULL
);

CREATE TABLE Classes
(
	name varchar(100) PRIMARY KEY,
	armor_bonus int NOT NULL,
	ap_bonus float NOT NULL,
	inventory_bonus float NOT NULL
);

CREATE TABLE Characters
(
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	user_id bigint  NOT NULL REFERENCES Users(id),
	name_of_character varchar(255) NOT NULL,
	class_id varchar(100) NOT NULL REFERENCES Classes(name)
);

CREATE TABLE Attribute
(
	name varchar(100) PRIMARY KEY
);

CREATE TABLE Character_attributes
(
	character_id bigint NOT NULL,
	attribute_id varchar(100) NOT NULL,
	PRIMARY KEY (character_id, attribute_id),
	FOREIGN KEY (character_id) REFERENCES Characters(id),
	FOREIGN KEY (attribute_id) REFERENCES Attribute(name),
	score int
);

CREATE TABLE Item_type
(
	name varchar(100) PRIMARY KEY
);

CREATE TABLE Items
(
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	name varchar(100) NOT NULL,
	type_id varchar(100) NOT NULL REFERENCES Item_type(name),
	weight int NOT NULL,
	damage int NOT NULL,
    base_ap_cost int NOT NULL
);

CREATE TABLE Character_inventory
(
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	character_id bigint NOT NULL REFERENCES Characters(id),
	item_id bigint REFERENCES Items(id)
);

CREATE TABLE Spell_category
(
	name varchar(100) PRIMARY KEY
);

CREATE TABLE Spell
(
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	name varchar(100) NOT NULL,
	power int,
	category_id varchar(100) NOT NULL REFERENCES Spell_category(name),
    base_ap_cost int NOT NULL
);

CREATE TABLE Character_grimoire
(
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	owner bigint NOT NULL REFERENCES Characters(id),
	spell_id bigint REFERENCES Spell(id)
);

CREATE TABLE Modifier_type
(
	name varchar(100) PRIMARY KEY,
	cost float NOT NULL,
	damage float NOT NULL
);

CREATE TABLE Item_modifier
(
	item_id bigint NOT NULL,
	attribute_id varchar(100) NOT NULL,
	modifier_type_id varchar(100) NOT NULL,
	PRIMARY KEY (item_id, attribute_id, modifier_type_id),
	FOREIGN KEY (item_id) REFERENCES Items(id),
	FOREIGN KEY (attribute_id) REFERENCES Attribute(name),
	FOREIGN KEY (modifier_type_id) REFERENCES Modifier_type(name)
);

CREATE TABLE Spell_modifier
(
	spell_id bigint NOT NULL,
	attribute_id varchar(100) NOT NULL,
	modifier_type_id varchar(100) NOT NULL,
	PRIMARY KEY (spell_id, attribute_id, modifier_type_id),
	FOREIGN KEY (spell_id) REFERENCES Spell(id),
	FOREIGN KEY (attribute_id) REFERENCES Attribute(name),
	FOREIGN KEY (modifier_type_id) REFERENCES Modifier_type(name)
);

CREATE TABLE Combat_log
(
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY
);

CREATE TABLE Player_combat_log
(
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	player_id bigint NOT NULL REFERENCES Characters(id),
	combat_id bigint NOT NULL REFERENCES Combat_log(id),
	event_time timestamp NOT NULL DEFAULT now(),
	event_type varchar(100) NOT NULL
);

CREATE TABLE Rounds
(
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	combat_id bigint NOT NULL REFERENCES Combat_log(id),
	start timestamp NOT NULL,
	"end" timestamp,
	round_order bigint NOT NULL DEFAULT 1
);

CREATE TABLE Dropped_goods
(
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	combat_id bigint NOT NULL REFERENCES Combat_log(id),
	item_id bigint REFERENCES Items(id),
	spell_id bigint REFERENCES Spell(id),
	available boolean NOT NULL DEFAULT true,
	time_dropped timestamp  NOT NULL DEFAULT now()
);

CREATE TABLE Round_events
(
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	round_id bigint	NOT NULL REFERENCES Rounds(id),
	player1_id bigint NOT NULL REFERENCES Characters(id),
	player2_id bigint REFERENCES Characters(id),
	event_type varchar(100) NOT NULL,
	picked_item bigint REFERENCES Items(id),
	item_used bigint REFERENCES Items(id),
	picked_spell bigint REFERENCES Spell(id),
	spell_used bigint REFERENCES Spell(id),
	ap_cost int,
	damage_dealt int,
	success boolean NOT NULL DEFAULT false,
	time timestamp NOT NULL DEFAULT now()
);


