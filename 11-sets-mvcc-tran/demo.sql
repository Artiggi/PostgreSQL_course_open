-- =====================================================
-- Пара 9: MVCC и транзакции
-- Демонстрационные запросы
-- =====================================================

-- =====================================================
-- 0. ВВОДНАЯ: ТРАНЗАКЦИЯ, ACID, MVCC
-- =====================================================

-- Что такое транзакция:
-- Набор операций, который выполняется как единое целое.
-- Если что-то пошло не так -> ROLLBACK, иначе COMMIT.

-- ACID:
-- A (Atomicity)    : либо все изменения, либо ни одного.
-- C (Consistency)  : ограничения целостности не нарушаются.
-- I (Isolation)    : параллельные транзакции изолированы.
-- D (Durability)   : после COMMIT изменения не теряются.

-- MVCC vs pessimistic locking:
-- - Pessimistic locking чаще опирается на ожидания из-за блокировок.
-- - MVCC хранит версии строк, поэтому чтения не блокируют записи.
-- - Конфликты остаются в основном между конкурентными писателями.

-- Проверка: по умолчанию каждая команда идет в автокоммите.
SHOW transaction_isolation;

-- =====================================================
-- 1. MVCC — ПРОСМОТР СЛУЖЕБНЫХ ПОЛЕЙ
-- =====================================================

-- Каждая строка хранит xmin (ID транзакции создания) и xmax (ID удаления)
SELECT xmin, xmax, flight_id, route_no, status
FROM flights
LIMIT 10;

-- Посмотреть текущий ID транзакции
SELECT txid_current();

-- =====================================================
-- 2. УРОВНИ ИЗОЛЯЦИИ ТРАНЗАКЦИЙ
-- =====================================================

-- Проверить текущий уровень изоляции
SHOW transaction_isolation;

-- Установить уровень изоляции для сессии
-- SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- =====================================================
-- 3. ЯВНЫЕ ТРАНЗАКЦИИ — ДЕМОНСТРАЦИЯ
-- =====================================================

-- Создадим тестовую таблицу для экспериментов
CREATE TABLE IF NOT EXISTS test_accounts (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50),
    balance NUMERIC(10, 2)
);

-- Очистим и заполним данными
TRUNCATE test_accounts;
INSERT INTO test_accounts (name, balance) VALUES
    ('Alice', 1000.00),
    ('Bob', 500.00),
    ('Charlie', 750.00);

-- Просмотр данных
SELECT * FROM test_accounts;

-- Пример транзакции: перевод средств
BEGIN;
UPDATE test_accounts SET balance = balance - 100 WHERE name = 'Alice';
UPDATE test_accounts SET balance = balance + 100 WHERE name = 'Bob';
-- Проверяем в рамках транзакции
SELECT * FROM test_accounts;
COMMIT;

-- Проверяем после коммита
SELECT * FROM test_accounts;

-- =====================================================
-- 4. ROLLBACK — ОТМЕНА ТРАНЗАКЦИИ
-- =====================================================

BEGIN;
UPDATE test_accounts SET balance = balance - 500 WHERE name = 'Bob';
-- Передумали!
ROLLBACK;

-- Проверяем — изменения не применены
SELECT * FROM test_accounts;

-- =====================================================
-- 5. SAVEPOINT — ЧАСТИЧНЫЙ ОТКАТ
-- =====================================================

BEGIN;

UPDATE test_accounts SET balance = balance + 100 WHERE name = 'Charlie';
SAVEPOINT sp1;

UPDATE test_accounts SET balance = balance - 1000 WHERE name = 'Alice';
-- Это оставит отрицательный баланс, откатим
ROLLBACK TO SAVEPOINT sp1;

-- Charlie получил +100, а Alice не тронута
SELECT * FROM test_accounts;
COMMIT;

-- =====================================================
-- 6. READ COMMITTED vs REPEATABLE READ
-- =====================================================

-- Для демонстрации нужны две сессии:

-- СЕССИЯ 1 (READ COMMITTED - по умолчанию):
/*
BEGIN;
SELECT sum(balance) FROM test_accounts;  -- например, 1350

-- [В СЕССИИ 2: INSERT INTO test_accounts VALUES (4, 'Dave', 200); COMMIT;]

SELECT sum(balance) FROM test_accounts;  -- теперь 1550!
COMMIT;
*/

-- СЕССИЯ 1 (REPEATABLE READ):
/*
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT sum(balance) FROM test_accounts;  -- например, 1350

-- [В СЕССИИ 2: INSERT INTO test_accounts VALUES (5, 'Eve', 300); COMMIT;]

SELECT sum(balance) FROM test_accounts;  -- всё ещё 1350!
COMMIT;
*/

-- =====================================================
-- 7. SERIALIZABLE — ОШИБКА СЕРИАЛИЗАЦИИ И RETRY
-- =====================================================

-- Для демонстрации нужны две сессии (аналогично блоку выше).
-- Идея: обе транзакции читают общую сумму Alice+Bob и списывают
-- с РАЗНЫХ строк. В SERIALIZABLE одна из них должна быть отменена.

-- Подготовка (один раз):
/*
UPDATE test_accounts SET balance = 1000 WHERE name = 'Alice';
UPDATE test_accounts SET balance = 500  WHERE name = 'Bob';
SELECT name, balance FROM test_accounts WHERE name IN ('Alice', 'Bob');
*/

-- СЕССИЯ 1:
/*
BEGIN ISOLATION LEVEL SERIALIZABLE;

SELECT sum(balance) AS total_ab
FROM test_accounts
WHERE name IN ('Alice', 'Bob');  -- 1500

-- Бизнес-логика: если total_ab >= 1500, списываем 900 с Alice
UPDATE test_accounts
SET balance = balance - 900
WHERE name = 'Alice';

COMMIT;  -- один из COMMIT (в сессии 1 или 2) завершится ошибкой сериализации
*/

-- СЕССИЯ 2 (запустить параллельно с СЕССИЕЙ 1):
/*
BEGIN ISOLATION LEVEL SERIALIZABLE;

SELECT sum(balance) AS total_ab
FROM test_accounts
WHERE name IN ('Alice', 'Bob');  -- тоже 1500 в своём snapshot

-- Аналогичная логика, но списание с Bob
UPDATE test_accounts
SET balance = balance - 900
WHERE name = 'Bob';

COMMIT;  -- вероятная ошибка:
-- ERROR: could not serialize access due to read/write dependencies among transactions
*/

-- Проверка после завершения:
/*
SELECT name, balance
FROM test_accounts
WHERE name IN ('Alice', 'Bob')
ORDER BY name;
*/

-- Важно: SERIALIZABLE требует retry-логики на уровне приложения.

-- =====================================================
-- 8. SELECT FOR UPDATE — БЛОКИРОВКА СТРОК
-- =====================================================

-- Для демонстрации нужны две сессии:

-- СЕССИЯ 1:
/*
BEGIN;
SELECT * FROM test_accounts WHERE name = 'Alice' FOR UPDATE;
-- Строка заблокирована, можем безопасно обновить
-- [В СЕССИИ 2 попытка UPDATE зависнет]
UPDATE test_accounts SET balance = balance - 50 WHERE name = 'Alice';
COMMIT;
*/

-- СЕССИЯ 2 (пока СЕССИЯ 1 держит блокировку):
/*
UPDATE test_accounts SET balance = balance + 1000 WHERE name = 'Alice';
-- Этот запрос будет ждать, пока СЕССИЯ 1 не сделает COMMIT
*/

-- =====================================================
-- 9. NOWAIT И SKIP LOCKED
-- =====================================================

-- NOWAIT — сразу ошибка, если строка заблокирована
BEGIN;
SELECT * FROM test_accounts WHERE name = 'Bob' FOR UPDATE NOWAIT;
-- Если заблокировано, сразу получим ошибку:
-- ERROR: could not obtain lock on row
COMMIT;

-- SKIP LOCKED — пропустить заблокированные строки
-- Полезно для очередей задач
BEGIN;
SELECT * FROM test_accounts
ORDER BY id
LIMIT 1
FOR UPDATE SKIP LOCKED;
-- Вернёт первую НЕзаблокированную строку
COMMIT;

-- =====================================================
-- 10. МОНИТОРИНГ БЛОКИРОВОК
-- =====================================================

-- Текущие активные запросы
SELECT
    pid,
    usename,
    state,
    query_start,
    LEFT(query, 50) AS query_preview
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start;

-- Запросы, ожидающие блокировки
SELECT
    pid,
    usename,
    state,
    wait_event_type,
    wait_event,
    LEFT(query, 80) AS query
FROM pg_stat_activity
WHERE wait_event_type = 'Lock';

-- Кто кого блокирует
SELECT
    blocked.pid AS blocked_pid,
    blocked.usename AS blocked_user,
    blocking.pid AS blocking_pid,
    blocking.usename AS blocking_user,
    LEFT(blocked.query, 50) AS blocked_query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking
    ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE blocked.pid != blocking.pid;

-- Просмотр блокировок на таблице
SELECT
    l.locktype,
    l.mode,
    l.granted,
    l.pid,
    a.usename,
    LEFT(a.query, 50) AS query
FROM pg_locks l
JOIN pg_stat_activity a ON l.pid = a.pid
WHERE l.relation = 'test_accounts'::regclass;

-- =====================================================
-- 11. VACUUM — ОЧИСТКА СТАРЫХ ВЕРСИЙ
-- =====================================================

-- Посмотреть статистику autovacuum
SELECT
    schemaname,
    relname,
    n_dead_tup,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables
WHERE relname = 'test_accounts';

-- Ручной запуск VACUUM
VACUUM test_accounts;

-- VACUUM с обновлением статистики
VACUUM ANALYZE test_accounts;

-- =====================================================
-- 12. ДЕМОНСТРАЦИЯ DEADLOCK
-- =====================================================

-- Для демонстрации нужны две сессии, выполняющие одновременно:

-- СЕССИЯ 1:
/*
BEGIN;
UPDATE test_accounts SET balance = balance + 1 WHERE name = 'Alice';
-- Пауза, ждём СЕССИЮ 2
UPDATE test_accounts SET balance = balance + 1 WHERE name = 'Bob';
COMMIT;
*/

-- СЕССИЯ 2:
/*
BEGIN;
UPDATE test_accounts SET balance = balance + 1 WHERE name = 'Bob';
-- Пауза, ждём СЕССИЮ 1
UPDATE test_accounts SET balance = balance + 1 WHERE name = 'Alice';
COMMIT;
*/

-- Результат: одна из сессий получит ошибку:
-- ERROR: deadlock detected

-- Решение: всегда блокировать в одном порядке
/*
BEGIN;
SELECT * FROM test_accounts WHERE name IN ('Alice', 'Bob')
ORDER BY name FOR UPDATE;  -- Всегда сначала Alice, потом Bob
-- Теперь безопасно обновлять
UPDATE test_accounts SET balance = balance + 1 WHERE name = 'Alice';
UPDATE test_accounts SET balance = balance + 1 WHERE name = 'Bob';
COMMIT;
*/
