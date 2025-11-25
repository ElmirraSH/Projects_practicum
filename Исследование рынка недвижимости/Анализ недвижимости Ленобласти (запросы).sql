* Анализ данных для агентства недвижимости
  
Задача 1. Время активности объявлений


WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_id AS (
    -- Найдём id объявлений, которые не содержат выбросы
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND (
            (ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
             AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits))
            OR ceiling_height IS NULL
        )
),
by_city AS (
    -- Категоризируем объявления по времени активности и отфильтруем объявления только по городам
    SELECT
        CASE 
            WHEN city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'ЛенОбл'
        END AS city_category,
        CASE 
            WHEN days_exposition > 0 AND days_exposition <= 30 THEN 'sold_in_month'
            WHEN days_exposition > 30 AND days_exposition <= 90 THEN 'sold_in_three_months'
            WHEN days_exposition > 90 AND days_exposition <= 180 THEN 'sold_in_six_months'
            WHEN days_exposition > 180 THEN 'sold_in_more_then_six'
        END AS act_category,
        last_price / total_area AS square,
        total_area,
        rooms,
        balcony,
        "floor",
        id
    FROM real_estate.flats 
    JOIN real_estate.city USING (city_id)
    JOIN real_estate.type USING (type_id)
    JOIN real_estate.advertisement USING (id)
    WHERE "type" = 'город'
)
SELECT 
    city_category,
    act_category,
    ROUND(AVG(square)::numeric, 2) AS avg_sum_per_square,
    ROUND(AVG(total_area)::numeric, 2) AS avg_total_area,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY rooms) AS mediana_rooms,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY balcony) AS mediana_balcony,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY "floor") AS mediana_floor,
    COUNT(id) AS total_ads
FROM by_city
WHERE id IN (SELECT * FROM filtered_id)
  AND act_category IS NOT NULL
GROUP BY city_category, act_category
ORDER BY city_category;




Задача 2 Сезонность объявлений

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY last_price) AS last_price_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY last_price) AS last_price_limit_l
    FROM real_estate.flats
    JOIN real_estate.advertisement USING(id)
),
filtered_id AS (
    -- Найдём id объявлений, которые не содержат выбросы по площади и цене
    SELECT id
    FROM real_estate.flats f
    JOIN real_estate.type t USING(type_id)
    JOIN real_estate.advertisement a USING(id)
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (
            (a.last_price < (SELECT last_price_limit_h FROM limits)
             AND a.last_price > (SELECT last_price_limit_l FROM limits))
            OR a.last_price IS NULL
        )
        AND "type" = 'город'
),
first_day AS (
    SELECT
        EXTRACT(MONTH FROM first_day_exposition) AS month_first_day,
        ROUND(AVG(last_price / total_area)::NUMERIC, 2) AS avg_meter_cost,
        ROUND(AVG(total_area)::NUMERIC, 2) AS avg_total_area,
        COUNT(id) AS count_ads
    FROM real_estate.advertisement a
    JOIN real_estate.flats f USING(id)
    WHERE days_exposition IS NOT NULL
      AND first_day_exposition BETWEEN '2015-01-01' AND '2019-01-01'
      AND id IN (SELECT * FROM filtered_id)
    GROUP BY month_first_day
),
last_day AS (
    SELECT
        EXTRACT(MONTH FROM (first_day_exposition + days_exposition * INTERVAL '1 day')::DATE) AS month_last_day,
        ROUND(AVG(last_price / total_area)::NUMERIC, 2) AS avg_meter_cost,
        ROUND(AVG(total_area)::NUMERIC, 2) AS avg_total_area,
        COUNT(id) AS count_ads
    FROM real_estate.advertisement a
    JOIN real_estate.flats f USING(id)
    WHERE days_exposition IS NOT NULL
      AND first_day_exposition BETWEEN '2015-01-01' AND '2019-01-01'
      AND id IN (SELECT * FROM filtered_id)
    GROUP BY month_last_day
)
SELECT
    'публикация' AS type,
    *,
    RANK() OVER (ORDER BY count_ads DESC) AS month_rank
FROM first_day
UNION ALL
SELECT
    'снятие' AS type,
    *,
    RANK() OVER (ORDER BY count_ads DESC) AS month_rank
FROM last_day;


Задача 3: Анализ рынка недвижимости Ленобласти


При расчете показателей количества объявлений по населенным пунктам, получила большой разброс и разницу более, чем в 5 раз между медианой и средним.
Значит выборка смещена в сторону больших значений. 

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY last_price) AS last_price_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY last_price) AS last_price_limit_l
    FROM real_estate.flats
    JOIN real_estate.advertisement USING(id)
),
filtered_id AS (
    -- Найдём id объявлений, которые не содержат выбросы по площади и цене
    SELECT id
    FROM real_estate.flats f
    JOIN real_estate.advertisement a USING(id)
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (
            (a.last_price < (SELECT last_price_limit_h FROM limits)
             AND a.last_price > (SELECT last_price_limit_l FROM limits))
            OR a.last_price IS NULL
        )
),
request AS (
    -- Подсчёт количества объявлений по городам, кроме Санкт-Петербурга
    SELECT DISTINCT 
        c.city,
        COUNT(id) OVER(PARTITION BY city) AS amount_ids
    FROM real_estate.flats f
    JOIN real_estate.city c USING(city_id) 
    WHERE city != 'Санкт-Петербург' 
      AND id IN (SELECT * FROM filtered_id)
),
city_rank AS (
    -- Ранжирование городов по количеству объявлений и выбор топ-15
    SELECT *,
           DENSE_RANK() OVER (ORDER BY amount_ids DESC) AS city_rank
    FROM request
    LIMIT 15
)
-- Основной запрос с отбором топ-15 городов по количеству объявлений
SELECT 
    city, 
    COUNT(id) AS amount_ids, 
    ROUND((COUNT(id) FILTER (WHERE days_exposition IS NOT NULL))::NUMERIC / COUNT(id), 2) AS selled_share,
    ROUND(AVG(last_price / total_area)::NUMERIC, 2) AS avg_cost_per_square_meter,
    ROUND(AVG(total_area)::NUMERIC, 2) AS avg_total_area, 
    ROUND(COUNT(id) FILTER (WHERE days_exposition < 30)::NUMERIC / COUNT(id) FILTER (WHERE days_exposition IS NOT NULL), 2) AS share_of_selled_in_month,
    ROUND(COUNT(id) FILTER (WHERE days_exposition >= 30 AND days_exposition < 90)::NUMERIC / COUNT(id) FILTER (WHERE days_exposition IS NOT NULL), 2) AS share_of_selled_in_three_month,
    ROUND(COUNT(id) FILTER (WHERE days_exposition >= 90 AND days_exposition < 180)::NUMERIC / COUNT(id) FILTER (WHERE days_exposition IS NOT NULL), 2) AS share_of_selled_in_six_month,
    ROUND(COUNT(id) FILTER (WHERE days_exposition >= 180)::NUMERIC / COUNT(id) FILTER (WHERE days_exposition IS NOT NULL), 2) AS share_of_selled_in_morethansix
FROM real_estate.flats f
JOIN real_estate.advertisement a USING(id)
JOIN real_estate.city c USING(city_id)
WHERE city IN (SELECT city FROM city_rank WHERE city_rank <= 15)
  AND id IN (SELECT * FROM filtered_id)
GROUP BY city
ORDER BY selled_share DESC, amount_ids DESC;








