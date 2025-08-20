
/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Бышин Максим Игоревич.
 * Дата: 31.03.2025
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
-- Напишите ваш запрос здесь:

-------------------------------------------------------------------------
--Создадим два СТЕ, в первом: рассчитаем общее кол-во уникальных игроков,
--во втором: общее кол-во уникальных платящих игроков.
WITH count_users AS(
	SELECT 
	count(DISTINCT id) AS total_users
	FROM fantasy.users
),
count_users_payer AS(
	SELECT 
	count(DISTINCT id) AS total_users_payer
	FROM fantasy.users
	WHERE payer = 1
)
--В основном запросе рассчитаем долю платящих игроков от 
--общего кол-ва игроков, на основе полученных результатов из СТЕ.
SELECT t1.*,
t2.*,
round((t2.total_users_payer::numeric/t1.total_users::NUMERIC*100),2) AS percent_users_payer --решил округлить для красоты
FROM count_users AS t1, count_users_payer AS t2;
---------------------------------------------------------------------------		

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
-- Напишите ваш запрос здесь

---------------------------------------------------------------------------
/*Создадим два СТЕ, в первом: рассчитаем общее кол-во уникальных игроков,
и сгрупируем их по рассам, во втором: общее кол-во уникальных платящих
игроков, также, сгрупируем результаты по рассе персонажей.
*/
WITH count_users AS(
	SELECT 
	t2.race AS race,
	count(DISTINCT t1.id) AS total_users
	FROM fantasy.users AS t1
	JOIN fantasy.race AS t2 ON t1.race_id = t2.race_id
	GROUP BY t2.race
),
count_users_payer AS(
	SELECT 
	t2.race AS race,
	count(DISTINCT t1.id) AS total_users_payer
	FROM fantasy.users AS t1
	JOIN fantasy.race AS t2 ON t1.race_id = t2.race_id
	WHERE payer = 1
	GROUP BY t2.race
)
/*В основном запросе рассчитаем долю платящих игроков от общего 
кол-ва игроков, на основе полученных результатов из СТЕ.Отсортируем 
в порядке убывания платящих игроков и общего кол-ва игроков.
*/
SELECT t1.*,
t2.total_users_payer,
round((t2.total_users_payer::numeric/t1.total_users::NUMERIC*100),2) AS percent_users_payer --решил округлить для красоты
FROM count_users AS t1
LEFT JOIN count_users_payer AS t2 ON t1.race = t2.race
ORDER BY total_users_payer desc, total_users DESC;
--------------------------------------------------------------------------------	
	
-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
-- Напишите ваш запрос здесь

-------------------------------------------------------------------------
/*Применяем по очереди аналитические функции к полю amount.
В функциях min, avg, midian, stddev решил убирать нулевые 
значения для получения корректных данных, используя CASE.
*/
SELECT 
	count(amount) AS count_amount, --общее колво покупок
	sum(amount) AS sum_amount, --общая сумма покупок
	min(CASE WHEN amount > 0 THEN amount END) AS min_amount,--минимальная поупка, исключая нулевые покупки
	max(amount) AS max_amount, --макисмальная поупка
	round(avg(CASE WHEN amount > 0 THEN amount END)::NUMERIC,2) AS avg_amount,--средняе значение покупки
	PERCENTILE_DISC(0.5)WITHIN GROUP (ORDER BY (CASE WHEN amount > 0 THEN amount END)) AS median_amount, --медианное значение покупки
	round(STDDEV((CASE WHEN amount > 0 THEN amount END))::NUMERIC,2) AS stand_dev_amount --стандартное отклонение
	FROM fantasy.events;
------------------------------------------------------------------------	
-- 2.2: Аномальные нулевые покупки:
-- Напишите ваш запрос здесь
------------------------------------------------------------------------
/*Создадим два СТЕ, в первом: рассчитаем общее кол-во нулевых покупок,
во втором: общее кол-во всех покупок.
*/
WITH t1 AS (
		SELECT 
		count(amount) AS count_null_amount
		FROM fantasy.events
		WHERE amount = 0
	),
	t2 AS (
		SELECT 
		count(amount) AS count_amount
		FROM fantasy.events
	)
/*В основном запросе рассчитаем долю нулевых покупок от общего кол-ва, 
на основе полученных результатов из СТЕ.
*/
SELECT t2.count_amount,
	t1.count_null_amount,
	round((t1.count_null_amount::numeric/t2.count_amount::NUMERIC*100),2) AS percent_null_amount 
	FROM t1,t2;
-------------------------------------------------------------------------

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
-- Напишите ваш запрос здесь
-------------------------------------------------------------------------
/*Создадим два СТЕ, в первом: рассчитаем общее кол-во уникальных не 
платящих игроков, во втором: общее кол-во уникальных платящих игроков.
*/
WITH count_users_not_payer AS(
	SELECT 
	'user_not_payer' AS users, --создаём столбец с названием категории
	count(DISTINCT t1.id) AS total_users, --вычисляем кло-во уникальных юзеров
	round(count(t2.transaction_id)/count(DISTINCT t1.id)::numeric,2) AS avg_count_trs_per_users, --вычисляем среднне количество покупок на одного пользователя
	round(sum(t2.amount)::numeric/count(DISTINCT t1.id)::numeric,2) AS avg_sum_amount_per_users --вычисляем суммарную средннюю стоимость покупоки на одного пользователя
	FROM fantasy.users AS t1
	LEFT JOIN fantasy.events AS t2 ON t1.id = t2.id
	WHERE payer = 0 AND amount > 0--фильтруем юзеров по наличию платежей
	/*
	--Корректировка решения. Комментарий был про то, что этот фильтр нужно добавить.
	ДОБАВИЛ amount > 0
	*/
),
count_users_payer AS(
	SELECT 
	'user_payer' AS users, --создаём столбец с названием категории
	count(DISTINCT t1.id) AS total_users, --вычисляем кло-во уникальных юзеров
	round(count(t2.transaction_id)/count(DISTINCT t1.id)::numeric,2) AS avg_count_trs_per_users, --вычисляем среднне количество покупок на одного пользователя
	round(sum(t2.amount)::numeric/count(DISTINCT t1.id)::numeric,2) AS avg_sum_amount_per_users --вычисляем суммарную средннюю стоимость покупоки на одного пользователя
	FROM fantasy.users AS t1
	LEFT JOIN fantasy.events AS t2 ON t1.id = t2.id
	WHERE payer = 1 AND amount > 0 --фильтруем юзеров по наличию платежей и по минимальной покупке больше нуля.
)
--В основном запросе объединяем результаты полученные в СТЕ, в общую таблицу при помощи UNION ALL для визуального удобства сравнения значений.
SELECT
	users,
	total_users,
	avg_count_trs_per_users,
	avg_sum_amount_per_users
FROM count_users_not_payer
UNION all
SELECT
	users,
	total_users,
	avg_count_trs_per_users,
	avg_sum_amount_per_users
FROM count_users_payer;
---------------------------------------------------------------------------		

-- 2.4: Популярные эпические предметы:
-------------------------------------------------------------------------
/*Формируем два СТЕ, в первом: рассчитаем общее кол-во продаж магических 
предметов и кол-во уникальных юзеров, гркперуем данные по магическим 
предметам и получем общее кол-во продаж для каждого предмета. 
Во втором, получаем значение всех продаж, для будущего расчёта доли продаж 
каждого магического предмета от общих продаж.
*/
WITH item_sales AS (
	SELECT
	t2.game_items AS item_name,
	COUNT(t1.transaction_id) AS total_sales,
	COUNT(DISTINCT t1.id) AS unique_players
	FROM fantasy.events AS t1
    JOIN fantasy.items AS t2 ON t1.item_code = t2.item_code
    WHERE amount > 0 /*Добавь, пожалуйста, фильтрацию нулевых покупок. 
    Это не будет сильно влиять на результат, но по условию задачи 
    следует провести эту фильтрацию. ДОБАВИЛ*/
    GROUP BY t2.game_items
),
total_sales AS (
    SELECT 
    sum(total_sales) AS all_sales
    FROM item_sales
)
--В основном запросе объединяем результаты полученные в СТЕ и производим расчёты долей и соритруем результаты.
    SELECT 
    t3.item_name,
    t3.total_sales,
    ROUND(t3.total_sales::numeric/t4.all_sales*100, 5) AS percentage_of_total,
    t3.unique_players,
    ROUND(t3.unique_players::numeric/(
    SELECT COUNT(DISTINCT id) FROM fantasy.events WHERE amount > 0)*100, 3) AS player_percentage --ДОБАВИЛ В ПОДЗАПРОС ЗНАЧЕНИЕ WHERE amount > 0
    FROM item_sales AS t3, total_sales AS t4
	ORDER BY total_sales DESC;
-------------------------------------------------------------------------

-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:
-------------------------------------------------------------------------
/* РЕШИЛ ПОЛНОСТЬЮ ПЕРЕПИСАТЬ ЗАПРОС.
 * НАДЕЮСЬ В ЭТОТ РАЗ ВСЁ ПРАВИЛЬНО)
 */
WITH t1  AS (
    SELECT
        race_id,
        COUNT(DISTINCT id) AS count_users  --общее количество зарегистрированных игроков
    FROM fantasy.users
    GROUP BY race_id
),
t2 AS (
    SELECT
        race_id,
        COUNT(*) AS count_users_payer, -- количество игроков совершивших покупку в разрезе каждой расы
        ROUND(SUM(payer)::numeric / COUNT(*),4) AS percentage_users  --доля платящих игроков от покупателей
    FROM fantasy.users
    WHERE id IN (SELECT id FROM fantasy.events WHERE amount > 0)
    GROUP BY race_id
),
t3 AS (
    SELECT
        t333.race_id,
        COUNT(DISTINCT t444.transaction_id) AS total_orders, --количество уникальных покупок
        COUNT(DISTINCT t444.id) AS count_items, --количество предметов
        SUM(t444.amount) AS total_amount  --общая сумма покупок
    FROM fantasy.users AS t333
    JOIN fantasy.events AS t444 ON t333.id = t444.id
    WHERE t444.amount > 0
    GROUP BY t333.race_id
)
SELECT
    t44.race, --название расы
    t11.count_users, --общее количество зарегистрированных игроков
    t22.count_users_payer, --количество игроков, совершавших покупки
    ROUND(t22.count_users_payer::numeric/t11.count_users,2) AS percentage_users_orders, --доля покупателей от общего числа игроков
    ROUND(t22.percentage_users,2) AS percentage_users_payer, --доля платящих игроков от покупателей
    ROUND(t33.total_orders::numeric/t22.count_users_payer,2) AS avg_orders_per_users, --среднее количество покупок на покупателя
    ROUND(t33.total_amount::numeric/t33.total_orders,2) AS avg_order_one_usrer, --средняя стоимость одной покупки на игрока
    ROUND(t33.total_amount::numeric/t22.count_users_payer,2) AS avg_sum_amount_users --средняя суммарная стоимость всех покупок на игрока
FROM t1 AS t11
JOIN t2 AS t22 ON t11.race_id = t22.race_id
jOIN t3 AS t33 ON t11.race_id = t33.race_id
JOIN fantasy.race AS t44 ON t11.race_id = t44.race_id
ORDER BY t11.count_users DESC;
-------------------------------------------------------------------------
-- Задача 2: Частота покупок
-- Напишите ваш запрос здесь
-------------------------------------------------------------------------
/*Формируем несколько простых СТЕ для получения необходимых данных.
*/
--рассчитаем кол-во дней между покупками, получим количество игроков, которые совершили покупки.
WITH t1 AS ( 
	SELECT      
	id,
	transaction_id,
	date::DATE - LAG(date::DATE, 1) OVER (PARTITION BY id ORDER BY date::DATE ASC) AS days_between_tr --кол-во дней между покупками
	FROM fantasy.events
	WHERE amount <> 0 --фильтруем по сумме покупок выше нуля
--получаем платящих и не платящих игроков, общее кол-во транзакций на каждого и среднее кол-во дней между покупками.
),
t2 AS(
	SELECT
	t22.payer,--значение платящих и не платящих игроков
	t11.id,
	COUNT(t11.transaction_id) AS count_tr, --общее кол-во транзакций
	ROUND(AVG(t11.days_between_tr),2) AS avg_days_between_tr --среднее значение дней для каждого игрока
	FROM t1 AS t11
	LEFT JOIN fantasy.users AS t22 ON t11.id = t22.id
	GROUP BY t22.payer, t11.id --группируем по платящим и не платящим
	HAVING COUNT(t11.transaction_id) >= 25 --фильтруем по минимальному порогу покупок
--применяем ранжирование игроков по среднему количеству дней между покупками с учётом минимального количества покупок на одного игрока
	), 
t3 AS (
	SELECT
	*,
	NTILE(3) OVER(ORDER BY avg_days_between_tr DESC) AS RANK --сортируем с минимального кол-ва
	FROM t2
--формируем финальный запрос с расчётами требуемых общих и средних значений.
)
	SELECT
    CASE WHEN rank = '1' THEN 'Низкая частота'WHEN RANK  = '2' THEN 'Умеренная частота'ELSE 'Высокая частота'
    END AS rank_users,
    COUNT(id) AS count_users, --общее кол-во игроков с покупками
    SUM(payer) AS count_payers, --сумарное кол-во платящих игроков
    round(SUM(payer)::numeric/COUNT(id),2) AS share_payers, --доля платящих
    ROUND(AVG(count_tr),2) AS avg_count_tr, --среднее кол-во покупок
    ROUND(AVG(avg_days_between_tr),2) AS avg_days_between_tr --среднее кол-во дней между покупок
FROM t3
GROUP BY rank_users --группируем по рангу
ORDER BY count_payers DESC; --сортируем для удобства
