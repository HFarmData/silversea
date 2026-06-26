WITH segs AS (
    SELECT DISTINCT 
        'left' AS side, 
        visitor_id, 
        date
    FROM `curated.visitor_segments` WHERE {{visitor_segment_left}} AND {{time_period}} AND {{market}} AND {{device_category}} AND {{visit_channel}}
    -- GROUP BY visitor_id
    UNION ALL
    SELECT DISTINCT 
        'right' AS side, 
        visitor_id, 
        date 
    FROM `curated.visitor_segments` WHERE {{visitor_segment_right}} AND {{time_period}} AND {{market}} AND {{device_category}} AND {{visit_channel}}
    -- GROUP BY visitor_id, date
),
vis AS (
    SELECT
        visitor_id,
        CAST(FORMAT_TIMESTAMP('%Y-%m-%d', visit_start_timestamp) AS TIMESTAMP) AS date,
        COUNT(DISTINCT visit_id) AS visits,
        COUNTIF(NOT is_bounce) AS non_bounce_visits,
        SUM(pageview_count) AS pageviews,
        SUM(content_interaction_count) AS interactions
    FROM `silversea-293815.curated.visits`
    GROUP BY visitor_id, date
),
moolah AS (
    SELECT
        visitor_id,
        IF(web_request_type='WEBQ', CONCAT(web_request_type, ' (', webq_source, ')' ), web_request_type) AS web_request_type,
        CAST(FORMAT_TIMESTAMP('%Y-%m-%d', event_timestamp) AS TIMESTAMP) AS date,
        SUM(net_cruise_revenue) AS total_net_cruise_revenue,
        SUM(IF(web_request_type='WBBK', net_cruise_revenue, 0)) AS wbbk_net_cruise_revenue,
        SUM(IF(web_request_type='WEBQ', net_cruise_revenue, 0)) AS webq_net_cruise_revenue,
        SUM(IF(web_request_type='WBOF.01', net_cruise_revenue, 0)) AS wbof01_net_cruise_revenue,
        SUM(IF(web_request_type='WBOF.02', net_cruise_revenue, 0)) AS wbof02_net_cruise_revenue,
        SUM(IF(web_request_type='WBOF.03', net_cruise_revenue, 0)) AS wbof03_net_cruise_revenue,
    FROM `silversea-293815.curated.visit_leads`
    WHERE booking_status='BK' AND net_cruise_revenue>0
    GROUP BY visitor_id, web_request_type, date
), pres AS (
    SELECT DISTINCT
        side,
        web_request_type,
        COUNT(moolah.visitor_id) OVER rev AS `count`,
        MIN(total_net_cruise_revenue) OVER rev AS min_booking_value,
        MAX(total_net_cruise_revenue) OVER rev AS max_booking_value,
        SUM(total_net_cruise_revenue) OVER rev / COUNT(moolah.visitor_id) OVER rev AS mean_booking_value,
        SUM(total_net_cruise_revenue) OVER rev AS total_booking_value,
        PERCENTILE_CONT(total_net_cruise_revenue, 0.5) OVER rev AS median_booking_value,

    FROM segs
    LEFT JOIN moolah ON moolah.visitor_id=segs.visitor_id AND moolah.date=segs.date
    WHERE total_net_cruise_revenue IS NOT NULL
    WINDOW rev AS (PARTITION BY side, web_request_type)
    UNION ALL
    SELECT DISTINCT
        side,
        'ALL' AS web_request_type,
        COUNT(moolah.visitor_id) OVER rev AS `count`,
        MIN(total_net_cruise_revenue) OVER rev AS min_booking_value,
        MAX(total_net_cruise_revenue) OVER rev AS max_booking_value,
        SUM(total_net_cruise_revenue) OVER rev / COUNT(moolah.visitor_id) OVER rev AS mean_booking_value,
        SUM(total_net_cruise_revenue) OVER rev AS total_booking_value,
        PERCENTILE_CONT(total_net_cruise_revenue, 0.5) OVER rev AS median_booking_value,

    FROM segs
    LEFT JOIN moolah ON moolah.visitor_id=segs.visitor_id AND moolah.date=segs.date
    WHERE total_net_cruise_revenue IS NOT NULL
    WINDOW rev AS (PARTITION BY side)
    UNION ALL
    SELECT DISTINCT
        side,
        'ALL ECOMMERCE' AS web_request_type,
        COUNT(moolah.visitor_id) OVER rev AS `count`,
        MIN(total_net_cruise_revenue) OVER rev AS min_booking_value,
        MAX(total_net_cruise_revenue) OVER rev AS max_booking_value,
        SUM(total_net_cruise_revenue) OVER rev / COUNT(moolah.visitor_id) OVER rev AS mean_booking_value,
        SUM(total_net_cruise_revenue) OVER rev AS total_booking_value,
        PERCENTILE_CONT(total_net_cruise_revenue, 0.5) OVER rev AS median_booking_value,

    FROM segs
    LEFT JOIN moolah ON moolah.visitor_id=segs.visitor_id AND moolah.date=segs.date
    WHERE total_net_cruise_revenue IS NOT NULL AND web_request_type IN ('WBBK', 'WBOF.01', 'WBOF.02', 'WBOF.03', 'WEBQ', 'WEBQ (ECommerce)', 'WEBQ (PriceConfig)')
    WINDOW rev AS (PARTITION BY side)
)
SELECT * FROM pres ORDER BY 
CASE web_request_type
    WHEN 'ALL' THEN '0'
    WHEN 'ALL ECOMMERCE' THEN '1'
    WHEN 'WBBK' THEN '2'
    WHEN 'WBOF.01' THEN '3'
    WHEN 'WBOF.02' THEN '4'
    WHEN 'WBOF.03' THEN '5'
    WHEN 'WEBQ' THEN '6'
    WHEN 'RAQ' THEN '7'
    WHEN 'RAB' THEN '8'
    WHEN 'SFO' THEN '9'
    ELSE web_request_type
END, 
side
-- SELECT 'min' AS metric, (SELECT min_booking_value FROM pres WHERE side='left') AS `left`, (SELECT min_booking_value FROM pres WHERE side='right') AS `right`
-- UNION ALL
-- SELECT 'mean' AS metric, (SELECT mean_booking_value FROM pres WHERE side='left') AS `left`, (SELECT mean_booking_value FROM pres WHERE side='right') AS `right`
-- UNION ALL
-- SELECT 'median' AS metric, (SELECT median_booking_value FROM pres WHERE side='left') AS `left`, (SELECT median_booking_value FROM pres WHERE side='right') AS `right`
-- UNION ALL
-- SELECT 'max' AS metric, (SELECT max_booking_value FROM pres WHERE side='left') AS `left`, (SELECT max_booking_value FROM pres WHERE side='right') AS `right`
-- ORDER BY metric DESC 