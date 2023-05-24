--SQL Project Solution, 04.02.2023
--E-Commerce Data and Customer Retention Analysis with SQL


--////////////////////////////////////////////////////////////////////////////////////
-- Analysis of Data
--************************************************************

SELECT * FROM e_commerce_data
ORDER BY Cust_ID

-- order ids are not compatible with order dates

----------------------------------------------------------------------------
-- 1. Find the top 3 customers who have the maximum count of orders.

SELECT TOP 3 Cust_ID, 
	   COUNT(DISTINCT Ord_ID) cnt_orders
FROM e_commerce_data
GROUP BY Cust_ID
ORDER BY cnt_orders DESC;


----------------------------------------------------------------------------
-- 2. Find the customer whose order took the maximum time to get shipping.

SELECT TOP 1 Cust_ID, Customer_Name, Order_Date, DaysTakenForShipping
FROM e_commerce_data
ORDER BY DaysTakenForShipping DESC;

-------

SELECT Cust_ID, Customer_Name, Order_Date, DaysTakenForShipping
FROM e_commerce_data
WHERE DaysTakenForShipping = (SELECT MAX(DaysTakenForShipping)
							  FROM e_commerce_data)


----------------------------------------------------------------------------
-- 3. Count the total number of unique customers in January and 
-- how many of them came back every month over the entire year in 2011.

SELECT COUNT(DISTINCT Cust_ID) cnt_cust
FROM e_commerce_data
WHERE YEAR(Order_Date)=2011
AND MONTH(Order_Date)=1

-----------------------

SELECT MONTH(Order_Date) ord_month,
	COUNT(DISTINCT Cust_ID) numofcust
FROM e_commerce_data
WHERE YEAR(Order_Date)=2011
AND Cust_ID IN(SELECT DISTINCT Cust_ID cnt_cust
			  FROM e_commerce_data
			  WHERE YEAR(Order_Date)=2011
			  AND MONTH(Order_Date)=1)
GROUP BY MONTH(Order_Date)

-----------------------
--with correlated subquery

SELECT MONTH(Order_Date) ord_month,
	COUNT(DISTINCT Cust_ID) numofcust
FROM e_commerce_data A
WHERE YEAR(Order_Date)=2011
AND EXISTS (SELECT 1
			  FROM e_commerce_data B
			  WHERE YEAR(Order_Date)=2011
			  AND MONTH(Order_Date)=1
			  AND B.Cust_ID=A.Cust_ID)
GROUP BY MONTH(Order_Date)


----------------------------------------------------------------------------
-- 4. Write a query to return for each user the time elapsed between the first purchasing 
-- and the third purchasing, in ascending order by Customer ID.

--Pay attention to the orders of customers with id 431, 799, 1445, 1680, 1730

SELECT Cust_ID, first_order, Order_Date as third_order,
		DATEDIFF(DD, first_order, Order_Date) day_elapsed
FROM (
		SELECT DISTINCT Cust_ID, Ord_ID, Order_Date,
			MIN(Order_Date) OVER(PARTITION BY Cust_ID) first_order,
			DENSE_RANK() OVER(PARTITION BY Cust_ID ORDER BY Order_Date, Ord_ID) sales_order
		FROM e_commerce_data) subq
WHERE sales_order=3


--- solution with LEAD()

SELECT Cust_ID,
	DATEDIFF(DD, MIN(Order_Date), MIN(next_two_order)) day_elapsed
FROM(SELECT Cust_ID, Ord_ID, Order_Date,
		LEAD(Order_Date, 2) OVER(PARTITION BY Cust_ID ORDER BY Order_Date, Ord_ID) next_two_order 
	FROM e_commerce_data
	GROUP BY Cust_ID, Ord_ID, Order_Date)subq
WHERE next_two_order IS NOT NULL
GROUP BY Cust_ID
GO

----------------------------------------------------------------------------
-- 5. Write a query that returns customers who purchased both product 11 and product 14, 
-- as well as the ratio of these products to the total quantity of products purchased by the customer.

WITH t1 AS
(
	SELECT Cust_ID,
		SUM(CASE WHEN Prod_ID='Prod_11' THEN Order_Quantity ELSE 0 END) AS prod_11,
		SUM(CASE WHEN Prod_ID='Prod_14' THEN Order_Quantity ELSE 0 END) AS prod_14,
		SUM(Order_Quantity) total_quantity
	FROM e_commerce_data
	GROUP BY Cust_ID
	HAVING
		SUM(CASE WHEN Prod_ID='Prod_11' THEN Order_Quantity ELSE 0 END) > 0
		AND
		SUM(CASE WHEN Prod_ID='Prod_14' THEN Order_Quantity ELSE 0 END) > 0
)
SELECT *,
	CAST(1.0*prod_11 / total_quantity AS DEC(3,2)) p11_ratio,
	CAST(1.0*prod_14 / total_quantity AS DEC(3,2)) p14_ratio
FROM t1
GO


--////////////////////////////////////////////////////////////////////////////////////

-- Customer Segmentation
--************************************************************

-- Categorize customers based on their frequency of visits.

-- 1. Create a “view” that keeps visit logs of customers on a monthly basis. 
-- (For each log, three field is kept: Cust_id, Year, Month)


CREATE VIEW cust_visit_logs AS
SELECT Cust_ID, Year(Order_Date) AS Year, Month(Order_Date) AS Month
FROM e_commerce_data;
GO

-- 2. Create a “view” that keeps the number of monthly visits by users. 
--(Show separately all months from the beginning business)

CREATE VIEW monthly_visits AS
SELECT Cust_ID, 
		YEAR(Order_Date) AS ord_year, 
		Month(Order_Date) AS ord_month,
		COUNT(DISTINCT Ord_ID) AS num_of_visits
FROM e_commerce_data
GROUP BY 
	Cust_ID, 
	Year(Order_Date), 
	Month(Order_Date)
GO

SELECT * FROM monthly_visits


-- 3. For each visit of customers, create the next month of the visit as a separate column.

SELECT *,
	LEAD(current_month) OVER(PARTITION BY Cust_ID ORDER BY current_month) next_month_visit
FROM(SELECT *,
		DENSE_RANK() OVER(ORDER BY ord_year, ord_month) current_month
	FROM monthly_visits) subq
GO

-- 4. Calculate the monthly time gap between two consecutive visits by each customer.

CREATE VIEW monthly_time_gaps AS
SELECT *,
	LEAD(current_month) OVER(PARTITION BY Cust_ID ORDER BY current_month) next_month_visit,
	LEAD(current_month) OVER(PARTITION BY Cust_ID ORDER BY current_month)-current_month time_gap
FROM(SELECT *,
		DENSE_RANK() OVER(ORDER BY ord_year, ord_month) current_month
	FROM monthly_visits) subq


-- 5. Categorise customers using average time gaps. Choose the most fitted labeling model for you.

-- For example:
-- Labeled as "churn" if the customer hasn't made another purchase in the months 
-- since they made their first purchase.
-- Labeled as "regular" if the customer has made a purchase every month.


SELECT Cust_ID, AVG(1.0*time_gap) avg_time_gap,
	CASE	
		WHEN AVG(1.0*time_gap) IS NULL THEN 'churn'
		WHEN AVG(1.0*time_gap) <=3 AND COUNT(*) >= 4 THEN 'regular'
		WHEN AVG(1.0*time_gap) <=3 AND COUNT(*) < 4 THEN 'need attention'
		ELSE 'irregular' 
	END cust_segment
FROM monthly_time_gaps
GROUP BY Cust_ID
ORDER BY cust_segment


--////////////////////////////////////////////////////////////////////////////////////

-- Month-Wise Retention Rate
--************************************************************

-- Find month-by-month customer retention rate since the start of the business.

SELECT * FROM monthly_time_gaps
GO


WITH t1 AS
(
	SELECT current_month,
		COUNT(Cust_ID) total_cust,
		SUM(CASE WHEN time_gap=1 THEN 1 END) cnt_retained_cust
	FROM monthly_time_gaps
	GROUP BY current_month
)
SELECT current_month,
	LAG(retention_rate) OVER(ORDER BY current_month) ret_rate
FROM
	(SELECT current_month, CAST(1.0*cnt_retained_cust / total_cust AS DEC(3,2)) retention_rate
	 FROM t1) subq


