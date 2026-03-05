/*
=======================================================================================
Product Report	
=======================================================================================
Purpose:
	-  This report consolidates key product metrics and behaviors

Highlights:
	1. Gathers essential fields such as product names, category, subcategory and cost.
	2. Segments product by revenue to identify High-Performers, Mid-Range or Low-Performers.
	3. Aggregates product-level metrics:
	 - total orders
	 - total sales
	 - total quantity sold
	 - total customers (unique)
	 - lifespan (in months)
	4. Calculates valuable KPIs:
	 - recency (months since last sale)
	 - average order revenue (AOR)
	 - average monthly revenue
=======================================================================================
*/
-- =============================================================================
-- Create Report: gold.report_products
-- =============================================================================
IF OBJECT_ID('gold.report_products', 'V') IS NOT NULL
    DROP VIEW gold.report_products;
GO

CREATE VIEW gold.report_products AS
WITH base_query AS (
/*---------------------------------------------------------------------------
1) Base Query: Retrieves core columns from fact_sales and dim_products
---------------------------------------------------------------------------*/
	SELECT
		s.order_number,
		s.customer_key,
		s.order_date,
		s.sales_amount,
		s.quantity,
		p.product_key,
		p.product_name,
		p.category,
		p.subcategory,
		p.cost
	FROM gold.fact_sales s
	JOIN gold.dim_products p
	ON p.product_key = s.product_key
	WHERE order_date IS NOT NULL
)
, product_aggregation AS(
/*---------------------------------------------------------------------------
2) Product Aggregations: Summarizes key metrics at the product level
---------------------------------------------------------------------------*/
SELECT
	product_key,
	product_name,
	category,
	subcategory,
	cost,
	SUM(sales_amount) AS total_sales,
	COUNT(DISTINCT order_number) AS total_orders,
	SUM(quantity) AS total_quantity,
	COUNT(DISTINCT customer_key) AS total_customers,
	MAX(order_date) AS last_sale_date,
	DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan,
	ROUND(AVG(CAST(sales_amount AS FLOAT) / NULLIF(quantity,0)),1) AS avg_selling_price
FROM base_query
GROUP BY
	product_key,
	product_name,
	category,
	subcategory,
	cost
), final_product_aggregation AS (
/*---------------------------------------------------------------------------
 3) Product Segmentation: Dynamically segments products into performance tiers
   - Uses NTILE(3) to divide products into three groups based on total sales
   - Ensures scalable and distribution-based categorization
   - Replaces static revenue thresholds with data-driven segmentation
---------------------------------------------------------------------------*/
SELECT 
	*,
	NTILE(3) OVER(ORDER BY total_sales DESC) AS product_category
	FROM product_aggregation
)

/*---------------------------------------------------------------------------
  4) Final Query: Combines all product results into one output
---------------------------------------------------------------------------*/
SELECT
	product_key,
	product_name,
	category,
	subcategory,
	cost,
	last_sale_date,
	DATEDIFF(MONTH, last_sale_date, GETDATE()) AS recency_months,
	total_sales,
	CASE
		WHEN product_category = 1 THEN 'High-Performer'
		WHEN product_category = 2 THEN 'Mid-Range'
		ELSE 'Low-Performer'
	END AS product_segment,
	lifespan,
	total_orders,
	total_quantity,
	total_customers,
	avg_selling_price,
	-- Average Order Revenue (AOR)
	CASE 
		WHEN total_orders = 0 THEN 0
		ELSE ROUND(CAST(total_sales AS float) / total_orders, 2)
	END AS avg_order_revenue,
	-- Average Monthly Revenue
	CASE 
		WHEN lifespan = 0 THEN total_sales
		ELSE ROUND(CAST(total_sales AS float) / lifespan, 2)
	END AS avg_monthly_revenue
FROM final_product_aggregation