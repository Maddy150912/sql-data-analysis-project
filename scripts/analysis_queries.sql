-- Analyze Sales Performance Over Time.
SELECT
YEAR(order_date) AS order_year,
SUM(sales_amount) AS total_sales,
COUNT(DISTINCT customer_key) AS total_customers,
SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date)
ORDER BY YEAR(order_date)

SELECT
MONTH(order_date) AS order_month,
SUM(sales_amount) AS total_sales,
COUNT(DISTINCT customer_key) AS total_customers,
SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY MONTH(order_date)
ORDER BY MONTH(order_date)

SELECT
YEAR(order_date) AS order_year,
MONTH(order_date) AS order_month,
SUM(sales_amount) AS total_sales,
COUNT(DISTINCT customer_key) AS total_customers,
SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date), MONTH(order_date)
ORDER BY YEAR(order_date), MONTH(order_date)

SELECT
DATETRUNC(month,order_date) AS order_date,
SUM(sales_amount) AS total_sales,
COUNT(DISTINCT customer_key) AS total_customers,
SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(month,order_date)
ORDER BY DATETRUNC(month,order_date)

SELECT
FORMAT(order_date, 'yyyy-MMM') AS order_date,
SUM(sales_amount) AS total_sales,
COUNT(DISTINCT customer_key) AS total_customers,
SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY FORMAT(order_date, 'yyyy-MMM')
ORDER BY FORMAT(order_date, 'yyyy-MMM')

-- **** Cumulative analysis - Window fuction ****
-- Calculate the total sales per month and the running total sales over time
SELECT 
order_date,
total_sales,
SUM(total_sales) OVER(ORDER BY order_date) AS running_total_sales,
AVG(avg_price) OVER(ORDER BY order_date) AS moving_average_price
FROM (
SELECT
DATETRUNC( month, order_date) AS order_date,
SUM(sales_amount) AS total_sales,
AVG(price) AS avg_price
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC( month, order_date)
)t

-- **** Performance analysis ****
/*  Analyze the yearly performance of products by comparing each product's 
	sales to both its average sales performance and the previous year's sales.
*/
WITH yearly_product_sales AS (
SELECT 
YEAR(s.order_date) AS order_year,
p.product_name,
SUM(s.sales_amount) AS current_sales
FROM gold.fact_sales s
LEFT JOIN gold.dim_products p
ON s.product_key = p.product_key
WHERE s.order_date IS NOT NULL
GROUP BY YEAR(s.order_date),
p.product_name
)

SELECT 
order_year,
product_name,
current_sales,
AVG(current_sales) OVER(PARTITION BY product_name) AS avg_sales,
current_sales - AVG(current_sales) OVER(PARTITION BY product_name) AS diff_avg,
CASE 
	WHEN current_sales - AVG(current_sales) OVER(PARTITION BY product_name) > 0 THEN 'Above Avg' 
	WHEN current_sales - AVG(current_sales) OVER(PARTITION BY product_name) < 0 THEN 'Below Avg'
	ELSE 'AVG'
END AS avg_change,
-- Year-over-year analysis 
LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) AS previous_year_sales,
current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) AS diff_previous_years,
CASE 
	WHEN current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Increase' 
	WHEN current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Decrease'
	ELSE 'No change'
END AS previous_year_change
FROM yearly_product_sales
ORDER BY product_name,order_year

-- Which categories contribute the most to overall sales?
WITH category_sales AS (
SELECT 
p.category,
SUM(s.sales_amount) AS total_sales
FROM gold.fact_sales s
LEFT JOIN gold.dim_products p
ON p.product_key = s.product_key
GROUP BY p.category
)

SELECT 
category,
total_sales,
SUM(total_sales) OVER() AS overall_sales, 
CONCAT(ROUND((CAST(total_sales AS float) / SUM(total_sales) OVER()) * 100,2), '%') AS percentage_of_total
FROM category_sales
ORDER BY total_sales DESC

-- **** Data segmentation ****
-- Segment projects into cost ranges and count how many products fall into each segment.
WITH product_category AS (
	SELECT
	product_key,
	product_name,
	cost,
	CASE 
		WHEN cost < 100 THEN 'Below 100'
		WHEN cost BETWEEN 100 AND 500 THEN '100 - 500'
		WHEN cost BETWEEN 500 AND 1000 THEN '500 - 1000'
		ELSE 'Above 1000'
	END AS cost_range
	FROM gold.dim_products
)

SELECT
cost_range,
COUNT(product_key) AS total_products
FROM product_category
GROUP BY cost_range
ORDER BY total_products DESC



-- Group customers into three segments based on their spending behavior 
-- VIP: at least 12 months of history and spending more than 5000.
-- Regular: at least 12 months of history but spending 5000 or less.
-- New: lifespan less than 12 months.
-- And find the total number of customers by each group.

WITH sales_history AS (
	SELECT
	c.customer_key,
	c.first_name,
	c.last_name,
	SUM(s.sales_amount) AS total_spending,
	MIN(s.order_date) AS first_order,
	MAX(s.order_date) AS last_order,
	DATEDIFF(MONTH, MIN(s.order_date), MAX(s.order_date)) AS lifespan
	FROM gold.fact_sales s
	JOIN gold.dim_customers c
	ON s.customer_key = c.customer_key
	GROUP BY c.customer_key,
	c.first_name,
	c.last_name
), 
customer_category AS (
	SELECT
	customer_key,
	first_name,
	last_name,
	total_spending,
	lifespan,
	CASE
		WHEN lifespan >= 12 AND total_spending > 5000 THEN 'VIP' 
		WHEN lifespan >= 12 and total_spending <= 5000 THEN 'Regular'
		ELSE 'New'
	END AS customer_group
	FROM sales_history
)

SELECT
customer_group,
COUNT(*) AS total_number_of_customers
FROM customer_category
GROUP BY customer_group
ORDER BY total_number_of_customers DESC
