-- =====================================================
-- Пара 11: DDL, DML и временные таблицы
-- Демонстрационные запросы
-- =====================================================

-- =====================================================
-- 1. DDL — DATA DEFINITION LANGUAGE
-- =====================================================

-- DDL управляет структурой объектов базы данных:
-- CREATE, ALTER, DROP, TRUNCATE

-- На время демонстрации используем отдельную таблицу-песочницу
DROP TABLE IF EXISTS dml_playground;

CREATE TABLE dml_playground (
    id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        text NOT NULL UNIQUE,
    title       text NOT NULL,
    amount      numeric(10, 2) NOT NULL DEFAULT 0,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- Проверим структуру созданной таблицы
SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'dml_playground'
ORDER BY ordinal_position;

-- ALTER TABLE — меняем структуру таблицы
ALTER TABLE dml_playground
ADD COLUMN status text NOT NULL DEFAULT 'new';

ALTER TABLE dml_playground
ADD COLUMN note text;

-- Проверка после ALTER
SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'dml_playground'
ORDER BY ordinal_position;

-- TRUNCATE — быстрая очистка таблицы
TRUNCATE TABLE dml_playground;

-- =====================================================
-- 2. DML — DATA MANIPULATION LANGUAGE
-- =====================================================

-- INSERT — вставка одной строки
INSERT INTO dml_playground (code, title, amount)
VALUES ('ROW001', 'Первая запись', 1000);

SELECT * FROM dml_playground;

-- INSERT — вставка нескольких строк
INSERT INTO dml_playground (code, title, amount, status)
VALUES
    ('ROW002', 'Вторая запись', 1500, 'draft'),
    ('ROW003', 'Третья запись', 2200, 'draft'),
    ('ROW004', 'Четвёртая запись', 800, 'approved');

SELECT * FROM dml_playground ORDER BY id;

-- INSERT ... SELECT — загрузка данных из запроса
INSERT INTO dml_playground (code, title, amount, status, note)
SELECT
    'FLT-' || flight_id,
    route_no,
    0,
    'imported',
    status
FROM flights
ORDER BY flight_id
LIMIT 5;

SELECT * FROM dml_playground ORDER BY id;

-- UPDATE — изменение строк
UPDATE dml_playground
SET amount = amount * 1.1
WHERE status = 'draft';

-- UPDATE с вычислением и условием
UPDATE dml_playground
SET
    status = 'review',
    note = 'Обновлено на демонстрации'
WHERE amount >= 1500
  AND status IN ('draft', 'imported');

SELECT * FROM dml_playground ORDER BY id;

-- DELETE — удаление строк
DELETE FROM dml_playground
WHERE status = 'new';

SELECT * FROM dml_playground ORDER BY id;

-- RETURNING — получаем результат DML сразу
INSERT INTO dml_playground (code, title, amount, status)
VALUES ('ROW999', 'Запись с RETURNING', 9999, 'final')
RETURNING id, code, status, amount;

UPDATE dml_playground
SET amount = amount + 500
WHERE code = 'ROW999'
RETURNING id, code, amount;

DELETE FROM dml_playground
WHERE code = 'ROW999'
RETURNING id, code, status;

-- =====================================================
-- 3. ВРЕМЕННЫЕ ТАБЛИЦЫ
-- =====================================================

-- TEMP TABLE живёт только в рамках текущей сессии
DROP TABLE IF EXISTS temp_route_stats;

CREATE TEMP TABLE temp_route_stats (
    route_no         text,
    flights_count    integer,
    cancelled_count  integer,
    total_revenue    numeric(12, 2)
);

-- Наполняем временную таблицу агрегатами
INSERT INTO temp_route_stats
SELECT
    t.route_no,
    count(*) AS flights_count,
    count(*) FILTER (WHERE t.status = 'Cancelled') AS cancelled_count,
    COALESCE(sum(s.price), 0) AS total_revenue
FROM timetable t
LEFT JOIN segments s ON s.flight_id = t.flight_id
GROUP BY t.route_no
ORDER BY total_revenue DESC
LIMIT 20;

SELECT *
FROM temp_route_stats
ORDER BY total_revenue DESC, route_no;

-- Временная таблица может быть создана сразу из SELECT
DROP TABLE IF EXISTS temp_cancelled_flights;

CREATE TEMP TABLE temp_cancelled_flights AS
SELECT
    t.flight_id,
    t.route_no,
    dep.city AS departure_city,
    arr.city AS arrival_city,
    t.scheduled_departure
FROM timetable t
JOIN airports dep ON dep.airport_code = t.departure_airport
JOIN airports arr ON arr.airport_code = t.arrival_airport
WHERE t.status = 'Cancelled';

SELECT count(*) AS cancelled_flights_count
FROM temp_cancelled_flights;

-- На TEMP TABLE можно создавать индексы
CREATE INDEX ON temp_cancelled_flights (route_no);

-- ON COMMIT DELETE ROWS — структура остаётся, строки очищаются
DROP TABLE IF EXISTS temp_session_buffer;

CREATE TEMP TABLE temp_session_buffer (
    id      integer GENERATED ALWAYS AS IDENTITY,
    payload text
) ON COMMIT DELETE ROWS;

BEGIN;

INSERT INTO temp_session_buffer (payload)
VALUES ('one'), ('two'), ('three');

SELECT count(*) AS rows_inside_tx
FROM temp_session_buffer;

COMMIT;

SELECT count(*) AS rows_after_commit
FROM temp_session_buffer;
