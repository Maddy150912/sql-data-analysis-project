/*
=======================================================================================
Sales Performance Report	
=======================================================================================
Purpose:
	- Analyze overall business performance over time 
	  and identify revenue trends, growth patterns, and risks.

Highlights:
	1. Aggregates sales performance at monthly level.
	2. Measures Month-over-Month (MoM) revenue and order growth.
	3. Calculates cumulative (running) revenue over time.
	4. Evaluates order behavior through Average Order Value (AOV).
	5. Identifies each month's contribution to total revenue.
	6. Classifies monthly performance into High Growth, Moderate Growth,
	   Stable, or Decline for business monitoring.

=======================================================================================
*/

-- =============================================================================
-- Create Report: gold.report_sales_performance
-- =============================================================================
IF OBJECT_ID('gold.report_sales_performance', 'V') IS NOT NULL
    DROP VIEW gold.report_sales_performance;
GO

CREATE VIEW gold.report_sales_performance AS
WITH monthly_aggregates AS (
/*------------------------------------------------------------------------------
CTE 1: monthly_aggregates
Purpose:
	- Aggregate raw sales data into monthly level metrics
	- This acts as the foundation (base layer) for all KPIs
------------------------------------------------------------------------------*/
SELECT
	DATETRUNC(MONTH, order_date) AS month_start_date,
	SUM(sales_amount) AS total_monthly_revenue,
	COUNT(DISTINCT order_number) AS total_monthly_orders,
	SUM(quantity) AS total_monthly_quantity_sold
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(MONTH, order_date)
),

monthly_lagged AS (
/*------------------------------------------------------------------------------
CTE 2: monthly_lagged
Purpose:
	- Fetch previous month metrics using LAG()
	- Enables Month-over-Month comparison
------------------------------------------------------------------------------*/
SELECT
	month_start_date,
	total_monthly_revenue,
	LAG(total_monthly_revenue) OVER(ORDER BY month_start_date ASC) AS previous_month_revenue,
	total_monthly_quantity_sold,
	total_monthly_orders,
	LAG(total_monthly_orders) OVER(ORDER BY month_start_date ASC) AS previous_month_orders
FROM monthly_aggregates
),

monthly_kpis AS (
/*------------------------------------------------------------------------------
CTE 3: monthly_kpis
Purpose:
	- Calculate core KPIs:
		• MoM growth (revenue & orders)
		• Running revenue
------------------------------------------------------------------------------*/
SELECT
	month_start_date,
	total_monthly_quantity_sold,
	total_monthly_revenue,
	previous_month_revenue,

	-- Month-over-Month Growth (Revenue %)
	CAST(
		ROUND(
			((total_monthly_revenue - previous_month_revenue) * 1.0 
			/ NULLIF(previous_month_revenue, 0)) * 100
		, 2)
	AS DECIMAL(10,2)) AS mom_growth_revenue_pct,

	total_monthly_orders,
	previous_month_orders,

	-- Month-over-Month Growth (Orders %)
	CAST(
		ROUND(
			((total_monthly_orders - previous_month_orders) * 1.0 
			/ NULLIF(previous_month_orders, 0)) * 100
		, 2)
	AS DECIMAL(10,2)) AS mom_growth_orders_pct,

	-- Running Revenue (Cumulative)
	SUM(total_monthly_revenue) OVER(
		ORDER BY month_start_date ASC
		ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
	) AS running_revenue

FROM monthly_lagged
)

-- =============================================================================
-- Final Output
-- =============================================================================
SELECT
	month_start_date,
	total_monthly_quantity_sold,
	total_monthly_revenue,
	previous_month_revenue,
	mom_growth_revenue_pct,
	total_monthly_orders,
	previous_month_orders,
	mom_growth_orders_pct,
	running_revenue,
	
	-- Revenue Contribution %
	CAST(
		total_monthly_revenue * 100.0 
		/ NULLIF(SUM(total_monthly_revenue) OVER(),0)
	AS DECIMAL(10,2)) AS revenue_contribution_pct,

	-- Average Order Value (AOV)
	CAST(
		total_monthly_revenue * 1.0 / NULLIF(total_monthly_orders, 0)
	AS DECIMAL(10,2)) AS avg_order_value,

	-- Performance Classification
	CASE 
		WHEN previous_month_revenue IS NULL THEN 'Base Month'

		WHEN mom_growth_revenue_pct >= 20 THEN 'High Growth'
		WHEN mom_growth_revenue_pct >= 5 AND mom_growth_revenue_pct < 20 THEN 'Moderate Growth'
		WHEN mom_growth_revenue_pct >= -5 AND mom_growth_revenue_pct < 5 THEN 'Stable'
		ELSE 'Decline'
	END AS trend_label

FROM monthly_kpis;

/*====================================================
Metrics:
	 - total monthly revenue
	 - total monthly orders
	 - total monthly quantity sold
	 - previous month revenue
	 - month-over-month growth %
	 - running total revenue
	 - average order value (AOV)
	 - revenue contribution %
	 - performance trend label
=======================================================*/

--SELECT * FROM gold.report_sales_performance