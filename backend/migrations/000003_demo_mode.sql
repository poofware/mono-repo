ALTER TABLE properties
ADD COLUMN is_demo BOOLEAN NOT NULL DEFAULT FALSE;

---- create above / drop below ----

ALTER TABLE properties
DROP COLUMN is_demo;
